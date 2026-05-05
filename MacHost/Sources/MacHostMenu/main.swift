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
    private var setupWindowController: SetupWindowController?
    private let deviceMonitor = ADBDeviceMonitor()
    private var deviceState = ADBDeviceState(status: .unknown)
    private var selectedDeviceSerial: String?
    private var operationMessage: String?
    private var screenCapturePermissionGranted: Bool?
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
    private var bundledReceiverAPKURL: URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("android-receiver-debug.apk")
            if FileManager.default.isReadableFile(atPath: candidate.path) {
                return candidate
            }
        }

        let candidate = packageRoot
            .appendingPathComponent("AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk")
        return FileManager.default.isReadableFile(atPath: candidate.path) ? candidate : nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        deviceMonitor.onUpdate = { [weak self] state in
            guard let self else {
                return
            }
            self.deviceState = state
            self.ensureSelectedDevice()
            if self.restartStreamAfterWake == true,
               state.canStartStream,
               self.streamProcess?.isRunning != true {
                self.restartStreamAfterWake = false
                if let device = self.selectedAuthorizedDevice() {
                    self.startStream(settings: self.settings, device: device)
                }
            } else {
                self.updateStatusTitle()
                self.rebuildMenu()
                self.updateSetupWindow()
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
        openSetup()
        refreshScreenCapturePermissionStatus()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let deviceItem = NSMenuItem(title: deviceState.menuTitle, action: nil, keyEquivalent: "")
        deviceItem.isEnabled = false
        menu.addItem(deviceItem)
        if !deviceState.authorizedDevices.isEmpty {
            let deviceMenu = NSMenu()
            for device in deviceState.authorizedDevices {
                let item = NSMenuItem(title: device.summary, action: #selector(selectDeviceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.serial
                item.state = device.serial == selectedDeviceSerial ? .on : .off
                deviceMenu.addItem(item)
            }
            let chooseDeviceItem = NSMenuItem(title: "Choose Device", action: nil, keyEquivalent: "")
            chooseDeviceItem.submenu = deviceMenu
            menu.addItem(chooseDeviceItem)
        }
        menu.addItem(menuItem("Refresh Device", #selector(refreshDevice)))
        menu.addItem(menuItem("Open Setup Window", #selector(openSetup)))
        menu.addItem(NSMenuItem.separator())

        let startItem = menuItem("Start Stream (\(settings.summary))", #selector(startCurrentSettings))
        startItem.isEnabled = streamProcess?.isRunning != true && deviceState.canStartStream
        menu.addItem(startItem)

        let installItem = menuItem("Install/Update Android Client", #selector(installOrUpdateSelectedDevice))
        installItem.isEnabled = deviceState.canStartStream
        menu.addItem(installItem)

        let statusPanelItem = menuItem("Start Status Panel", #selector(startStatusPanel))
        statusPanelItem.isEnabled = statusProcess?.isRunning != true && deviceState.canStartStream
        menu.addItem(statusPanelItem)

        let settingsItem = menuItem("Settings...", #selector(openSettings))
        settingsItem.isEnabled = streamProcess?.isRunning != true
        menu.addItem(settingsItem)

        let screenCaptureItem = menuItem("Request Screen Recording Permission", #selector(requestScreenCapturePermissionFromMenu))
        screenCaptureItem.state = screenCapturePermissionGranted == true ? .on : .off
        menu.addItem(screenCaptureItem)

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
        guard let device = selectedAuthorizedDevice() else {
            operationMessage = "请先连接并授权 Android 设备。"
            openSetup()
            return
        }
        startStream(settings: settings, device: device)
    }

    @objc private func refreshDevice() {
        deviceState = ADBDeviceState(status: .unknown)
        operationMessage = "正在刷新设备..."
        updateStatusTitle()
        rebuildMenu()
        updateSetupWindow()
        deviceMonitor.refresh()
    }

    @objc private func openSetup() {
        let controller: SetupWindowController
        if let setupWindowController {
            controller = setupWindowController
        } else {
            controller = SetupWindowController()
            controller.onRefresh = { [weak self] in
                self?.refreshDevice()
            }
            controller.onInstall = { [weak self] device in
                self?.installOrUpdate(device: device)
            }
            controller.onStartDisplay = { [weak self] device in
                guard let self else {
                    return
                }
                self.selectedDeviceSerial = device.serial
                self.startStream(settings: self.settings, device: device)
            }
            controller.onStartStatus = { [weak self] device in
                self?.selectedDeviceSerial = device.serial
                self?.startStatusPanelForDevice(device)
            }
            controller.onOpenSettings = { [weak self] in
                self?.openSettings()
            }
            controller.onRequestScreenCapture = { [weak self] in
                self?.requestScreenCapturePermissionFromMenu()
            }
            controller.onRestartApp = { [weak self] in
                self?.restartApp()
            }
            controller.onQuitApp = { [weak self] in
                self?.quit()
            }
            setupWindowController = controller
        }

        updateSetupWindow()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectDeviceFromMenu(_ sender: NSMenuItem) {
        selectedDeviceSerial = sender.representedObject as? String
        operationMessage = nil
        rebuildMenu()
        updateSetupWindow()
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
                if let device = self.selectedAuthorizedDevice() {
                    self.startStream(settings: self.settings, device: device)
                }
            } else {
                self.updateStatusTitle()
                self.rebuildMenu()
                self.updateSetupWindow()
            }
        }
    }

    @objc private func openSettings() {
        let controller = SettingsWindowController(settings: settings) { [weak self] newSettings in
            self?.settings = newSettings
            self?.rebuildMenu()
            self?.updateSetupWindow()
        }
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func requestScreenCapturePermissionFromMenu() {
        let result = runBackendScreenCapturePermissionCheck(requestIfMissing: true)
        screenCapturePermissionGranted = result.succeeded
        if result.succeeded {
            operationMessage = "屏幕录制权限已授权。请点击“重启应用”后继续。"
        } else {
            operationMessage = "请在系统设置中允许 Android Monitor Host/phase0-spike 进行屏幕录制。授权后点击“重启应用”。"
        }
        updateStatusTitle()
        rebuildMenu()
        updateSetupWindow()
    }

    @objc private func requestAccessibilityPermissionFromMenu() {
        if !AXIsProcessTrusted() {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        rebuildMenu()
        updateSetupWindow()
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
        updateSetupWindow()
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
        updateSetupWindow()
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
        updateSetupWindow()
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
        updateSetupWindow()
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
        updateSetupWindow()
    }

    @objc private func installOrUpdateSelectedDevice() {
        guard let device = selectedAuthorizedDevice() else {
            operationMessage = "请先选择一个已授权的 Android 设备。"
            openSetup()
            return
        }
        installOrUpdate(device: device)
    }

    private func installOrUpdate(device: ADBDevice) {
        guard let apkURL = bundledReceiverAPKURL else {
            showError("找不到 Android 客户端 APK。请先运行 scripts/package-mac-host-app.sh 重新打包应用。")
            return
        }

        selectedDeviceSerial = device.serial
        operationMessage = "正在安装 Android 客户端到 \(device.summary)..."
        updateStatusTitle()
        rebuildMenu()
        updateSetupWindow()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ADBClient.installReceiver(apkURL: apkURL, on: device)
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                if result.succeeded {
                    self.operationMessage = "Android 客户端已安装到 \(device.summary)。"
                    self.deviceMonitor.refresh()
                } else {
                    self.operationMessage = "安装失败。"
                    self.showError("安装 Android 客户端失败：\n\(result.output)")
                }
                self.updateStatusTitle()
                self.rebuildMenu()
                self.updateSetupWindow()
            }
        }
    }

    private func startStream(settings: HostSettings, device: ADBDevice) {
        if streamProcess?.isRunning == true {
            stopStream()
        }

        let permission = runBackendScreenCapturePermissionCheck(requestIfMissing: false)
        screenCapturePermissionGranted = permission.succeeded
        guard permission.succeeded else {
            operationMessage = "扩展屏需要屏幕录制权限。授权后点击“重启应用”。"
            updateStatusTitle()
            rebuildMenu()
            updateSetupWindow()
            let requested = runBackendScreenCapturePermissionCheck(requestIfMissing: true)
            screenCapturePermissionGranted = requested.succeeded
            if requested.succeeded {
                operationMessage = "屏幕录制权限已授权，正在继续启动扩展屏..."
                updateSetupWindow()
                startStream(settings: settings, device: device)
                return
            }
            rebuildMenu()
            updateSetupWindow()
            return
        }

        selectedDeviceSerial = device.serial
        operationMessage = "正在准备 \(device.summary)：检查客户端、配置 USB 通道..."
        updateStatusTitle()
        rebuildMenu()
        updateSetupWindow()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            let installed = ADBClient.packageInstalled(on: device)
            guard installed || self.bundledReceiverAPKURL != nil else {
                DispatchQueue.main.async {
                    self.operationMessage = "缺少 Android 客户端 APK。"
                    self.showError("没有检测到手机客户端，且 Mac app 内没有可安装的 APK。请重新运行 scripts/package-mac-host-app.sh。")
                }
                return
            }

            if let apkURL = self.bundledReceiverAPKURL, !installed {
                let install = ADBClient.installReceiver(apkURL: apkURL, on: device)
                if !install.succeeded {
                    DispatchQueue.main.async {
                        self.operationMessage = "自动安装失败。"
                        self.showError("没有检测到手机客户端，自动安装失败：\n\(install.output)")
                    }
                    return
                }
            }

            let reverse = ADBClient.configureReverse(port: settings.port, on: device)
            if !reverse.succeeded {
                DispatchQueue.main.async {
                    self.operationMessage = "USB 通道配置失败。"
                    self.showError("ADB reverse 配置失败：\n\(reverse.output)")
                }
                return
            }

            ADBClient.forceStopReceiver(on: device)
            let launch = ADBClient.launchReceiver(on: device)
            if !launch.succeeded {
                DispatchQueue.main.async {
                    self.operationMessage = "手机客户端启动失败。"
                    self.showError("启动 Android Monitor 失败：\n\(launch.output)")
                }
                return
            }

            DispatchQueue.main.async {
                self.operationMessage = "手机客户端已就绪，正在启动扩展屏..."
                self.launchStreamBackend(settings: settings)
            }
        }
    }

    private func launchStreamBackend(settings: HostSettings) {
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
            "--port", "\(settings.port)",
            "--no-adb-reverse"
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
                self?.updateSetupWindow()
            }
        }

        do {
            try process.run()
            streamProcess = process
            operationMessage = "扩展屏已启动。手机会自动连接到 Mac。"
            updateStatusTitle()
            rebuildMenu()
            updateSetupWindow()
        } catch {
            try? logFile.close()
            self.logFile = nil
            operationMessage = "扩展屏启动失败。"
            statusItem.button?.title = "AM: Start Failed"
            rebuildMenu()
            updateSetupWindow()
        }
    }

    @objc private func startStatusPanel() {
        guard let device = selectedAuthorizedDevice() else {
            operationMessage = "请先连接并授权 Android 设备。"
            openSetup()
            return
        }
        startStatusPanelForDevice(device)
    }

    private func startStatusPanelForDevice(_ device: ADBDevice) {
        if statusProcess?.isRunning == true {
            stopStatusPanel()
        }

        selectedDeviceSerial = device.serial
        let reverse = ADBClient.configureReverse(port: 38889, on: device)
        if !reverse.succeeded {
            showError("Status Panel USB 通道配置失败：\n\(reverse.output)")
            return
        }
        ADBClient.forceStopReceiver(on: device)
        _ = ADBClient.launchReceiver(on: device, statusMode: true)

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
                self?.updateSetupWindow()
            }
        }

        do {
            try process.run()
            statusProcess = process
            operationMessage = "状态面板已启动。"
            updateStatusTitle()
            rebuildMenu()
            updateSetupWindow()
        } catch {
            try? logFile.close()
            statusLogFile = nil
            operationMessage = "状态面板启动失败。"
            statusItem.button?.title = "AM: Status Failed"
            rebuildMenu()
            updateSetupWindow()
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
        updateSetupWindow()
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
        updateSetupWindow()
    }

    private func ensureSelectedDevice() {
        let authorized = deviceState.authorizedDevices
        if let selectedDeviceSerial,
           authorized.contains(where: { $0.serial == selectedDeviceSerial }) {
            return
        }
        selectedDeviceSerial = authorized.first?.serial
    }

    private func selectedAuthorizedDevice() -> ADBDevice? {
        ensureSelectedDevice()
        guard let selectedDeviceSerial else {
            return deviceState.authorizedDevices.first
        }
        return deviceState.authorizedDevices.first(where: { $0.serial == selectedDeviceSerial })
            ?? deviceState.authorizedDevices.first
    }

    private func updateSetupWindow() {
        let setupMessage = operationMessage
            ?? (screenCapturePermissionGranted == false ? "需要先授权屏幕录制。授权后点击“重启应用”。" : nil)
        setupWindowController?.update(
            deviceState: deviceState,
            selectedSerial: selectedDeviceSerial,
            streamRunning: streamProcess?.isRunning == true,
            statusRunning: statusProcess?.isRunning == true,
            message: setupMessage
        )
    }

    private func showError(_ message: String) {
        updateStatusTitle()
        rebuildMenu()
        updateSetupWindow()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Android Monitor"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func refreshScreenCapturePermissionStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = self?.runBackendScreenCapturePermissionCheck(requestIfMissing: false)
            DispatchQueue.main.async { [weak self] in
                guard let self, let result else {
                    return
                }
                self.screenCapturePermissionGranted = result.succeeded
                self.rebuildMenu()
                self.updateSetupWindow()
            }
        }
    }

    private func runBackendScreenCapturePermissionCheck(requestIfMissing: Bool) -> CommandResult {
        let arguments = requestIfMissing
            ? ["--check-screen-capture-permission", "--request-screen-capture-permission"]
            : ["--check-screen-capture-permission"]

        let process = Process()
        if let bundledBackendURL {
            process.executableURL = bundledBackendURL
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = packageRoot
            process.arguments = ["swift", "run", "phase0-spike"] + arguments
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, output: error.localizedDescription)
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: stdout + stderr)
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    @objc private func revealStatusLog() {
        NSWorkspace.shared.activateFileViewerSelecting([statusLogURL])
    }

    @objc private func restartApp() {
        let bundleURL = Bundle.main.bundleURL

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.5; /usr/bin/open \"$1\"",
            "android-monitor-relaunch",
            bundleURL.path
        ]
        try? process.run()
        quit()
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
