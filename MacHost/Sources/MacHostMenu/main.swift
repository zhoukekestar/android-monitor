import AppKit
import ApplicationServices
import Foundation
import ServiceManagement

final class MenuHostApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var streamProcess: Process?
    private var statusProcess: Process?
    private var logFile: FileHandle?
    private var statusLogFile: FileHandle?
    private var settings = HostSettings.load()
    private var settingsWindowController: SettingsWindowController?
    private let deviceMonitor = ADBDeviceMonitor()
    private var deviceState = ADBDeviceState(status: .unknown)
    private var restartStreamAfterWake = false

    private let logURL = URL(fileURLWithPath: "/tmp/android-monitor-menubar.log")
    private let statusLogURL = URL(fileURLWithPath: "/tmp/android-monitor-status-panel.log")
    private let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private var bundledBackendURL: URL? {
        guard let executableURL = Bundle.main.executableURL else {
            return nil
        }
        let candidate = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("phase0-spike")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }
    private var bundledStatusPanelURL: URL? {
        guard let executableURL = Bundle.main.executableURL else {
            return nil
        }
        let candidate = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("status-panel-server")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        deviceMonitor.onUpdate = { [weak self] state in
            self?.deviceState = state
            if self?.restartStreamAfterWake == true,
               state.canStartStream,
               self?.streamProcess?.isRunning != true {
                self?.restartStreamAfterWake = false
                if let settings = self?.settings {
                    self?.startStream(settings: settings)
                }
            } else {
                self?.updateStatusTitle()
                self?.rebuildMenu()
            }
        }
        deviceMonitor.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        updateStatusTitle()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let deviceItem = NSMenuItem(title: deviceState.menuTitle, action: nil, keyEquivalent: "")
        deviceItem.isEnabled = false
        menu.addItem(deviceItem)
        menu.addItem(menuItem("Refresh Device", #selector(refreshDevice)))
        menu.addItem(NSMenuItem.separator())

        let startItem = menuItem("Start Stream (\(settings.summary))", #selector(startCurrentSettings))
        startItem.isEnabled = streamProcess?.isRunning != true && deviceState.canStartStream
        menu.addItem(startItem)

        let statusPanelItem = menuItem("Start Status Panel", #selector(startStatusPanel))
        statusPanelItem.isEnabled = statusProcess?.isRunning != true
        menu.addItem(statusPanelItem)

        let settingsItem = menuItem("Settings...", #selector(openSettings))
        settingsItem.isEnabled = streamProcess?.isRunning != true
        menu.addItem(settingsItem)

        let accessibilityItem = menuItem("Request Accessibility Permission", #selector(requestAccessibilityPermissionFromMenu))
        accessibilityItem.state = AXIsProcessTrusted() ? .on : .off
        menu.addItem(accessibilityItem)

        let loginItem = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Use 800x480 @ 15 FPS", #selector(use800x480)))
        menu.addItem(menuItem("Use 1024x600 @ 15 FPS", #selector(use1024x600)))
        menu.addItem(menuItem("Use 1024x600 @ 30 FPS Low Latency", #selector(use1024x600LowLatency)))
        menu.addItem(menuItem("Use 1280x720 @ 15 FPS", #selector(use1280x720)))
        menu.addItem(menuItem("Use 1280x720 @ 30 FPS", #selector(use1280x720Fast)))
        menu.addItem(NSMenuItem.separator())

        let stopItem = menuItem("Stop Stream", #selector(stopStream))
        stopItem.isEnabled = streamProcess?.isRunning == true
        menu.addItem(stopItem)

        let stopStatusItem = menuItem("Stop Status Panel", #selector(stopStatusPanel))
        stopStatusItem.isEnabled = statusProcess?.isRunning == true
        menu.addItem(stopStatusItem)

        let logItem = menuItem("Reveal Stream Log", #selector(revealLog))
        logItem.isEnabled = FileManager.default.fileExists(atPath: logURL.path)
        menu.addItem(logItem)

        let statusLogItem = menuItem("Reveal Status Log", #selector(revealStatusLog))
        statusLogItem.isEnabled = FileManager.default.fileExists(atPath: statusLogURL.path)
        menu.addItem(statusLogItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("Quit", #selector(quit)))
        statusItem.menu = menu
    }

    private func updateStatusTitle() {
        let streamRunning = streamProcess?.isRunning == true
        let statusRunning = statusProcess?.isRunning == true
        if streamRunning && statusRunning {
            statusItem.button?.title = "AM: Stream+Status"
        } else if streamRunning {
            statusItem.button?.title = "AM: Stream"
        } else if statusRunning {
            statusItem.button?.title = "AM: Status"
        } else {
            statusItem.button?.title = "AM: \(deviceState.shortStatus)"
        }
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func startCurrentSettings() {
        startStream(settings: settings)
    }

    @objc private func refreshDevice() {
        deviceState = ADBDeviceState(status: .unknown)
        updateStatusTitle()
        rebuildMenu()
        deviceMonitor.refresh()
    }

    @objc private func handleWillSleep() {
        restartStreamAfterWake = streamProcess?.isRunning == true
        if restartStreamAfterWake {
            stopStream()
        }
        statusItem.button?.title = "AM: Sleep"
    }

    @objc private func handleDidWake() {
        deviceState = ADBDeviceState(status: .unknown)
        updateStatusTitle()
        rebuildMenu()
        deviceMonitor.refresh()

        guard restartStreamAfterWake else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.restartStreamAfterWake else {
                return
            }
            self.deviceMonitor.refresh()
            if self.deviceState.canStartStream {
                self.restartStreamAfterWake = false
                self.startStream(settings: self.settings)
            } else {
                self.updateStatusTitle()
                self.rebuildMenu()
            }
        }
    }

    @objc private func openSettings() {
        let controller = SettingsWindowController(settings: settings) { [weak self] newSettings in
            self?.settings = newSettings
            self?.rebuildMenu()
        }
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func requestAccessibilityPermissionFromMenu() {
        if !AXIsProcessTrusted() {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            rebuildMenu()
        } catch {
            statusItem.button?.title = "AM: Login Failed"
            rebuildMenu()
        }
    }

    @objc private func use800x480() {
        settings = HostSettings(
            width: 800,
            height: 480,
            fps: 15,
            bitrateMbps: 1,
            port: settings.port,
            outputPath: settings.outputPath
        )
        settings.save()
        rebuildMenu()
    }

    @objc private func use1024x600() {
        settings = HostSettings(
            width: 1024,
            height: 600,
            fps: 15,
            bitrateMbps: 2,
            port: settings.port,
            outputPath: settings.outputPath
        )
        settings.save()
        rebuildMenu()
    }

    @objc private func use1024x600LowLatency() {
        settings = HostSettings(
            width: 1024,
            height: 600,
            fps: 30,
            bitrateMbps: 3,
            port: settings.port,
            outputPath: settings.outputPath
        )
        settings.save()
        rebuildMenu()
    }

    @objc private func use1280x720() {
        settings = HostSettings(
            width: 1280,
            height: 720,
            fps: 15,
            bitrateMbps: 3,
            port: settings.port,
            outputPath: settings.outputPath
        )
        settings.save()
        rebuildMenu()
    }

    @objc private func use1280x720Fast() {
        settings = HostSettings(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateMbps: 4,
            port: settings.port,
            outputPath: settings.outputPath
        )
        settings.save()
        rebuildMenu()
    }

    private func startStream(settings: HostSettings) {
        if streamProcess?.isRunning == true {
            stopStream()
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logFile = try? FileHandle(forWritingTo: logURL) else {
            statusItem.button?.title = "AM: Log Error"
            return
        }
        self.logFile = logFile

        let process = Process()
        let backendArguments = [
            "--width", "\(settings.width)",
            "--height", "\(settings.height)",
            "--fps", "\(settings.fps)",
            "--bitrate-mbps", "\(settings.bitrateMbps)",
            "--duration", "3600",
            "--output", settings.outputPath,
            "--port", "\(settings.port)"
        ]
        if let bundledBackendURL {
            process.executableURL = bundledBackendURL
            process.arguments = backendArguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = packageRoot
            process.arguments = ["swift", "run", "phase0-spike"] + backendArguments
        }
        process.standardOutput = logFile
        process.standardError = logFile
        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                self?.streamProcess = nil
                try? self?.logFile?.close()
                self?.logFile = nil
                self?.updateStatusTitle()
                self?.rebuildMenu()
            }
        }

        do {
            try process.run()
            streamProcess = process
            updateStatusTitle()
            rebuildMenu()
        } catch {
            try? logFile.close()
            self.logFile = nil
            statusItem.button?.title = "AM: Start Failed"
            rebuildMenu()
        }
    }

    @objc private func startStatusPanel() {
        if statusProcess?.isRunning == true {
            stopStatusPanel()
        }

        FileManager.default.createFile(atPath: statusLogURL.path, contents: nil)
        guard let logFile = try? FileHandle(forWritingTo: statusLogURL) else {
            statusItem.button?.title = "AM: Status Log Error"
            return
        }
        statusLogFile = logFile

        let process = Process()
        let arguments = ["38889"]
        if let bundledStatusPanelURL {
            process.executableURL = bundledStatusPanelURL
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = packageRoot
            process.arguments = ["swift", "run", "status-panel-server"] + arguments
        }
        process.standardOutput = logFile
        process.standardError = logFile
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.statusProcess = nil
                try? self?.statusLogFile?.close()
                self?.statusLogFile = nil
                self?.updateStatusTitle()
                self?.rebuildMenu()
            }
        }

        do {
            try process.run()
            statusProcess = process
            updateStatusTitle()
            rebuildMenu()
        } catch {
            try? logFile.close()
            statusLogFile = nil
            statusItem.button?.title = "AM: Status Failed"
            rebuildMenu()
        }
    }

    @objc private func stopStream() {
        guard let process = streamProcess else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        streamProcess = nil
        try? logFile?.close()
        logFile = nil
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func stopStatusPanel() {
        guard let process = statusProcess else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        statusProcess = nil
        try? statusLogFile?.close()
        statusLogFile = nil
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    @objc private func revealStatusLog() {
        NSWorkspace.shared.activateFileViewerSelecting([statusLogURL])
    }

    @objc private func quit() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        deviceMonitor.stop()
        stopStream()
        stopStatusPanel()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = MenuHostApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
