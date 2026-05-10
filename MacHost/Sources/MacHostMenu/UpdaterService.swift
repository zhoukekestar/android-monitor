import AppKit
import CryptoKit
import Foundation

/// Self-update service that polls GitHub Releases and replaces the running
/// `.app` bundle in-place. Designed for the ad-hoc-signed CI artifact:
///
///   1. Query `/repos/<owner>/<repo>/releases/latest`.
///   2. Pick the first `.zip` asset and the matching `.zip.sha256` asset.
///   3. Download the zip, verify the checksum, unzip via `ditto`.
///   4. Spawn a detached shell helper that waits for this process to exit,
///      moves the new `.app` over the existing bundle, strips quarantine,
///      then re-launches the freshly installed app.
///   5. Quit ourselves so the helper can take over.
///
/// No third-party dependencies and no signing key needed; the trade-off is
/// that the trust boundary is "I trust GitHub Releases under this repo."
/// Asset integrity is checked against the `.sha256` published alongside the
/// zip by the same workflow run, so a tampered zip alone won't be accepted.
final class UpdaterService {
    static let shared = UpdaterService()

    // Source repository. Hardcoded so users on a stale Info.plist still find
    // the right place; bump these if the repo moves.
    private let repoOwner = "zhoukekestar"
    private let repoName  = "android-monitor"

    /// Called on the main thread whenever the updater wants to surface a
    /// short status string (used to drive the menubar `operationMessage`).
    var onStatusMessage: ((String?) -> Void)?

    private var isBusy = false

    // MARK: - Public entry points

    /// Run a release check. `silent == true` swallows all dialogs except the
    /// "update available" prompt — used for the on-launch background check.
    func checkForUpdates(silent: Bool) {
        guard !isBusy else { return }
        guard isRunningFromAppBundle else {
            if !silent {
                presentInfo(title: "无法检查更新", message: "当前不是从 .app 启动，自动更新仅在打包后的 Android Monitor Host.app 中可用。")
            }
            return
        }
        guard let current = currentVersion else {
            if !silent {
                presentInfo(title: "无法检查更新", message: "未能从 Info.plist 读取当前版本号。")
            }
            return
        }
        isBusy = true
        emitStatus("正在检查更新…")
        fetchLatestRelease { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.emitStatus(nil)
                switch result {
                case .failure(let error):
                    if !silent {
                        self.presentInfo(title: "检查更新失败", message: error.localizedDescription)
                    }
                case .success(let release):
                    guard let latest = SemVer(parsing: release.tag_name) else {
                        if !silent {
                            self.presentInfo(title: "检查更新失败", message: "无法解析最新版本号：\(release.tag_name)")
                        }
                        return
                    }
                    if latest > current {
                        self.presentUpdateAvailable(release: release, current: current, latest: latest)
                    } else if !silent {
                        self.presentInfo(title: "已是最新版本", message: "你正在使用 v\(current.description)，没有可用的更新。")
                    }
                }
            }
        }
    }

    // MARK: - GitHub fetch

    private struct ReleaseInfo: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int
        }
    }

    private func fetchLatestRelease(completion: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AndroidMonitorHostUpdater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(UpdaterError.message("没有收到来自 GitHub 的响应。")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(UpdaterError.message("GitHub 返回 HTTP \(http.statusCode)。")))
                return
            }
            guard let data else {
                completion(.failure(UpdaterError.message("GitHub 响应为空。")))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Update prompt

    private func presentUpdateAvailable(release: ReleaseInfo, current: SemVer, latest: SemVer) {
        let alert = NSAlert()
        alert.messageText = "Android Monitor Host v\(latest.description) 可用"
        var info = "当前版本 v\(current.description)。"
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            // Show first ~600 chars so the dialog doesn't blow up on long notes.
            let trimmed = notes.count > 600 ? String(notes.prefix(600)) + "…" : notes
            info += "\n\n更新说明：\n\(trimmed)"
        }
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "查看 Release 页")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            performInstall(release: release)
        case .alertThirdButtonReturn:
            if let url = URL(string: release.html_url) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Install pipeline

    private func performInstall(release: ReleaseInfo) {
        guard let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") && !$0.name.hasSuffix(".sha256") }),
              let zipURL = URL(string: zipAsset.browser_download_url) else {
            presentInfo(title: "更新文件缺失", message: "Release 中没有找到 .app 的 zip 资源。")
            return
        }
        let sha256Asset = release.assets.first(where: { $0.name.hasSuffix(".zip.sha256") })
        let sha256URL = sha256Asset.flatMap { URL(string: $0.browser_download_url) }

        isBusy = true
        emitStatus("正在下载更新…")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let workDir = try self.makeWorkDir()
                let zipPath = workDir.appendingPathComponent(zipAsset.name)
                try self.download(from: zipURL, to: zipPath)

                if let sha256URL {
                    let shaPath = workDir.appendingPathComponent("\(zipAsset.name).sha256")
                    try self.download(from: sha256URL, to: shaPath)
                    DispatchQueue.main.async { self.emitStatus("正在校验下载…") }
                    try self.verifyChecksum(zip: zipPath, sha256File: shaPath)
                }

                DispatchQueue.main.async { self.emitStatus("正在解压更新…") }
                let extractedDir = workDir.appendingPathComponent("extracted")
                try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
                try self.unzip(zipPath: zipPath, to: extractedDir)

                guard let newApp = try self.findApp(in: extractedDir) else {
                    throw UpdaterError.message("解压后没有找到 .app。")
                }

                DispatchQueue.main.async {
                    self.emitStatus("准备安装…")
                    self.swapAndRelaunch(newApp: newApp)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.emitStatus(nil)
                    self.presentInfo(title: "更新失败", message: error.localizedDescription)
                }
            }
        }
    }

    private func download(from url: URL, to destination: URL) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        var resultURL: URL?
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error { resultError = error; return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                resultError = UpdaterError.message("下载失败：HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            guard let tempURL else {
                resultError = UpdaterError.message("下载完成但没有临时文件。")
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)
                resultURL = destination
            } catch {
                resultError = error
            }
        }
        task.resume()
        semaphore.wait()
        if let resultError { throw resultError }
        guard resultURL != nil else { throw UpdaterError.message("下载失败。") }
    }

    private func verifyChecksum(zip: URL, sha256File: URL) throws {
        let expectedRaw = try String(contentsOf: sha256File, encoding: .utf8)
        // shasum output looks like: "<hex>  <filename>"
        let expectedHex = expectedRaw
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)?
            .lowercased() ?? ""
        guard expectedHex.count == 64 else {
            throw UpdaterError.message("校验文件格式异常，无法验证下载完整性。")
        }
        let actualHex = try sha256(of: zip).lowercased()
        guard actualHex == expectedHex else {
            throw UpdaterError.message("下载文件校验失败：sha256 不匹配。\n期望 \(expectedHex)\n实际 \(actualHex)")
        }
    }

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func unzip(zipPath: URL, to destination: URL) throws {
        // ditto preserves the ad-hoc signature and resource forks that the
        // zip step in CI created with `ditto -c -k --keepParent`.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipPath.path, destination.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdaterError.message("解压失败 (ditto exit \(process.terminationStatus)): \(stderr)")
        }
    }

    private func findApp(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        if let direct = contents.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        // The CI zip uses --keepParent, so the .app should be the only child
        // dir. Recurse one level just in case.
        for sub in contents where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let nested = try findApp(in: sub) {
                return nested
            }
        }
        return nil
    }

    // MARK: - Swap + relaunch

    private func swapAndRelaunch(newApp: URL) {
        let destination = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL: URL
        do {
            scriptURL = try writeRelaunchScript(parentPID: pid, newApp: newApp, destination: destination)
        } catch {
            isBusy = false
            emitStatus(nil)
            presentInfo(title: "更新失败", message: "无法准备替换脚本：\(error.localizedDescription)")
            return
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [scriptURL.path]

        // Detach stdio so the helper survives our termination cleanly.
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice

        do {
            try helper.run()
        } catch {
            isBusy = false
            emitStatus(nil)
            presentInfo(title: "更新失败", message: "无法启动替换脚本：\(error.localizedDescription)")
            return
        }

        // Hand off — the helper will wait for our PID to exit, then mv +
        // open the new bundle. From here we just quit cleanly.
        emitStatus("正在替换并重新启动…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    private func writeRelaunchScript(parentPID: Int32, newApp: URL, destination: URL) throws -> URL {
        let logURL = URL(fileURLWithPath: "/tmp/android-monitor-updater.log")
        let script = #"""
        #!/bin/bash
        set -u
        PARENT_PID=__PARENT_PID__
        NEW_APP=__NEW_APP__
        DEST_APP=__DEST_APP__
        LOG=__LOG__

        log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >>"$LOG"; }
        log "updater starting (parent pid $PARENT_PID)"

        # Wait up to 10s for parent to exit.
        for _ in $(seq 1 50); do
            if ! kill -0 "$PARENT_PID" 2>/dev/null; then break; fi
            sleep 0.2
        done

        # Backup the old bundle so we can roll back if mv of the new one fails.
        BACKUP_APP="${DEST_APP}.bak.$$"
        if [ -d "$DEST_APP" ]; then
            if ! mv "$DEST_APP" "$BACKUP_APP"; then
                log "ERROR: failed to move existing bundle aside"
                /usr/bin/open "$DEST_APP" 2>/dev/null || true
                exit 1
            fi
        fi

        if mv "$NEW_APP" "$DEST_APP"; then
            log "moved new bundle into place"
            /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
            rm -rf "$BACKUP_APP" 2>/dev/null || true
            log "launching $DEST_APP"
            /usr/bin/open "$DEST_APP"
            log "done"
            exit 0
        else
            log "ERROR: failed to install new bundle, rolling back"
            mv "$BACKUP_APP" "$DEST_APP" 2>/dev/null || true
            /usr/bin/open "$DEST_APP" 2>/dev/null || true
            exit 1
        fi
        """#

        // Substitute placeholders with quoted shell strings to handle paths
        // containing spaces (which "Android Monitor Host.app" obviously has).
        let body = script
            .replacingOccurrences(of: "__PARENT_PID__", with: String(parentPID))
            .replacingOccurrences(of: "__NEW_APP__", with: shellQuote(newApp.path))
            .replacingOccurrences(of: "__DEST_APP__", with: shellQuote(destination.path))
            .replacingOccurrences(of: "__LOG__", with: shellQuote(logURL.path))

        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("android-monitor-updater-\(UUID().uuidString).sh")
        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func shellQuote(_ s: String) -> String {
        // Wrap in single quotes; embed any literal single quotes safely.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Helpers

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var currentVersion: SemVer? {
        guard let str = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return SemVer(parsing: str)
    }

    private func makeWorkDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-monitor-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func emitStatus(_ message: String?) {
        let cb = onStatusMessage
        DispatchQueue.main.async { cb?(message) }
    }
}

enum UpdaterError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

/// Minimal semver-ish comparator. Accepts an optional leading `v`/`V`, then
/// up to three dot-separated integer components, plus an optional
/// `-prerelease` tail (compared lexically; releases beat prereleases).
struct SemVer: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init?(parsing raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".")
        guard let majStr = core.first, let maj = Int(majStr) else { return nil }
        self.major = maj
        self.minor = core.count > 1 ? (Int(core[1]) ?? 0) : 0
        self.patch = core.count > 2 ? (Int(core[2]) ?? 0) : 0
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    static func < (l: SemVer, r: SemVer) -> Bool {
        if l.major != r.major { return l.major < r.major }
        if l.minor != r.minor { return l.minor < r.minor }
        if l.patch != r.patch { return l.patch < r.patch }
        switch (l.prerelease, r.prerelease) {
        case (nil, nil): return false
        case (nil, _?):  return false  // release > prerelease
        case (_?, nil):  return true
        case (let a?, let b?): return a < b
        }
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }
}
