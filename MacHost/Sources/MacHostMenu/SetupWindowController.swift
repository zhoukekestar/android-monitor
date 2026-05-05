import AppKit

final class SetupWindowController: NSWindowController {
    var onRefresh: (() -> Void)?
    var onInstall: ((ADBDevice) -> Void)?
    var onStartDisplay: ((ADBDevice) -> Void)?
    var onStartStatus: ((ADBDevice) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestScreenCapture: (() -> Void)?
    var onRestartApp: (() -> Void)?
    var onQuitApp: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "正在检测设备...")
    private let devicePopup = NSPopUpButton()
    private let installButton = NSButton(title: "安装/更新手机客户端", target: nil, action: nil)
    private let startDisplayButton = NSButton(title: "开始扩展屏", target: nil, action: nil)
    private let startStatusButton = NSButton(title: "打开状态面板", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新设备", target: nil, action: nil)
    private let settingsButton = NSButton(title: "画质/延迟设置", target: nil, action: nil)
    private let screenPermissionButton = NSButton(title: "授权屏幕录制", target: nil, action: nil)
    private let restartButton = NSButton(title: "重启应用", target: nil, action: nil)
    private let quitButton = NSButton(title: "退出应用", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "")

    private var devices: [ADBDevice] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Monitor"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        configureControls()
        window.contentView = makeContentView()
        window.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        deviceState: ADBDeviceState,
        selectedSerial: String?,
        streamRunning: Bool,
        statusRunning: Bool,
        message: String?
    ) {
        devices = deviceState.authorizedDevices
        devicePopup.removeAllItems()

        if devices.isEmpty {
            devicePopup.addItem(withTitle: "未检测到已授权设备")
        } else {
            for device in devices {
                devicePopup.addItem(withTitle: device.summary)
                devicePopup.lastItem?.representedObject = device.serial
            }

            if let selectedSerial,
               let index = devices.firstIndex(where: { $0.serial == selectedSerial }) {
                devicePopup.selectItem(at: index)
            } else {
                devicePopup.selectItem(at: 0)
            }
        }

        statusLabel.stringValue = message ?? statusText(for: deviceState)
        hintLabel.stringValue = hintText(for: deviceState)

        let hasDevice = !devices.isEmpty
        installButton.isEnabled = hasDevice
        startDisplayButton.isEnabled = hasDevice && !streamRunning
        startStatusButton.isEnabled = hasDevice && !statusRunning
        startDisplayButton.title = streamRunning ? "扩展屏运行中" : "开始扩展屏"
        startStatusButton.title = statusRunning ? "状态面板运行中" : "打开状态面板"
    }

    private func configureControls() {
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3

        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 4

        installButton.target = self
        installButton.action = #selector(install)
        startDisplayButton.target = self
        startDisplayButton.action = #selector(startDisplay)
        startDisplayButton.bezelStyle = .rounded
        startDisplayButton.keyEquivalent = "\r"
        startStatusButton.target = self
        startStatusButton.action = #selector(startStatus)
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        screenPermissionButton.target = self
        screenPermissionButton.action = #selector(requestScreenCapture)
        restartButton.target = self
        restartButton.action = #selector(restartApp)
        quitButton.target = self
        quitButton.action = #selector(quitApp)
    }

    private func makeContentView() -> NSView {
        let root = NSView()

        let title = NSTextField(labelWithString: "双击即用：连接手机，选择设备，然后开始扩展屏")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 2

        let deviceLabel = NSTextField(labelWithString: "投屏设备")
        deviceLabel.alignment = .right

        let form = NSGridView(views: [
            [deviceLabel, devicePopup]
        ])
        form.translatesAutoresizingMaskIntoConstraints = false
        form.rowSpacing = 10
        form.columnSpacing = 12
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill

        let primaryButtons = NSStackView(views: [installButton, startDisplayButton, startStatusButton])
        primaryButtons.orientation = .horizontal
        primaryButtons.spacing = 10
        primaryButtons.distribution = .fillEqually
        primaryButtons.translatesAutoresizingMaskIntoConstraints = false

        let secondaryButtons = NSStackView(views: [refreshButton, settingsButton, screenPermissionButton])
        secondaryButtons.orientation = .horizontal
        secondaryButtons.spacing = 10
        secondaryButtons.translatesAutoresizingMaskIntoConstraints = false

        let appControlButtons = NSStackView(views: [restartButton, quitButton])
        appControlButtons.orientation = .horizontal
        appControlButtons.spacing = 10
        appControlButtons.translatesAutoresizingMaskIntoConstraints = false

        for view in [title, statusLabel, form, primaryButtons, secondaryButtons, appControlButtons, hintLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),

            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),

            form.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            form.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 18),
            devicePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 330),

            primaryButtons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            primaryButtons.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            primaryButtons.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 22),

            secondaryButtons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            secondaryButtons.topAnchor.constraint(equalTo: primaryButtons.bottomAnchor, constant: 12),

            appControlButtons.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            appControlButtons.topAnchor.constraint(equalTo: secondaryButtons.bottomAnchor, constant: 12),

            hintLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: appControlButtons.bottomAnchor, constant: 18),
            hintLabel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        ])

        return root
    }

    private func selectedDevice() -> ADBDevice? {
        let index = devicePopup.indexOfSelectedItem
        guard devices.indices.contains(index) else {
            return nil
        }
        return devices[index]
    }

    private func statusText(for deviceState: ADBDeviceState) -> String {
        switch deviceState.status {
        case .unknown:
            return "正在检测 Android 设备..."
        case .adbMissing:
            return "没有找到 adb。请安装 Android Studio，或把 Android SDK platform-tools 加到 PATH。"
        case .noDevice:
            return "没有检测到手机。请用 USB 连接手机，并打开 USB 调试。"
        case .unauthorized:
            return "手机还没有授权 USB 调试。请解锁手机，并点允许调试。"
        case .authorized:
            return "已检测到设备。点击“开始扩展屏”会自动检查并安装手机客户端。"
        }
    }

    private func hintText(for deviceState: ADBDeviceState) -> String {
        switch deviceState.status {
        case .authorized:
            return "建议先使用 1024x600 @ 30 FPS Low Latency。触摸输入默认关闭，手机画面上长按可切换。"
        default:
            return "普通使用流程：双击 Mac app -> 连接并授权手机 -> 选择设备 -> 开始扩展屏。"
        }
    }

    @objc private func refresh() {
        onRefresh?()
    }

    @objc private func install() {
        guard let device = selectedDevice() else {
            NSSound.beep()
            return
        }
        onInstall?(device)
    }

    @objc private func startDisplay() {
        guard let device = selectedDevice() else {
            NSSound.beep()
            return
        }
        onStartDisplay?(device)
    }

    @objc private func startStatus() {
        guard let device = selectedDevice() else {
            NSSound.beep()
            return
        }
        onStartStatus?(device)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func requestScreenCapture() {
        onRequestScreenCapture?()
    }

    @objc private func restartApp() {
        onRestartApp?()
    }

    @objc private func quitApp() {
        onQuitApp?()
    }
}
