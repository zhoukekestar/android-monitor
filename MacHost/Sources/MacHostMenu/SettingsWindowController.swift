import AppKit

final class SettingsWindowController: NSWindowController {
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let fpsPopup = NSPopUpButton()
    private let bitrateField = NSTextField()
    private let portField = NSTextField()
    private let outputPathField = NSTextField()
    private let onSave: (HostSettings) -> Void

    init(settings: HostSettings, onSave: @escaping (HostSettings) -> Void) {
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Monitor Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        configureControls(settings: settings)
        window.contentView = makeContentView()
        window.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func configureControls(settings: HostSettings) {
        widthField.integerValue = settings.width
        heightField.integerValue = settings.height
        bitrateField.integerValue = settings.bitrateMbps
        portField.integerValue = settings.port
        outputPathField.stringValue = settings.outputPath

        fpsPopup.addItems(withTitles: ["15", "30", "60"])
        fpsPopup.selectItem(withTitle: "\(settings.fps)")
        if fpsPopup.selectedItem == nil {
            fpsPopup.addItem(withTitle: "\(settings.fps)")
            fpsPopup.selectItem(withTitle: "\(settings.fps)")
        }
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let form = NSGridView(views: [
            [label("Width"), widthField],
            [label("Height"), heightField],
            [label("FPS"), fpsPopup],
            [label("Bitrate Mbps"), bitrateField],
            [label("TCP Port"), portField],
            [label("Output Path"), outputPathField]
        ])
        form.translatesAutoresizingMaskIntoConstraints = false
        form.rowSpacing = 10
        form.columnSpacing = 12
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.distribution = .gravityAreas

        root.addSubview(form)
        root.addSubview(buttons)

        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            form.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            form.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),

            widthField.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            outputPathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),

            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: form.bottomAnchor, constant: 22)
        ])

        return root
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    @objc private func save() {
        do {
            let fpsValue = Int(fpsPopup.titleOfSelectedItem ?? "") ?? 15
            let settings = try HostSettings(
                width: widthField.integerValue,
                height: heightField.integerValue,
                fps: fpsValue,
                bitrateMbps: bitrateField.integerValue,
                port: portField.integerValue,
                outputPath: outputPathField.stringValue
            ).validated()
            settings.save()
            onSave(settings)
            close()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func cancel() {
        close()
    }
}
