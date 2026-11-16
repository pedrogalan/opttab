import AppKit

extension Notification.Name {
    static let cmdTabShowSettings = Notification.Name("dev.cmdtab.showSettings")
}

final class SettingsWindowController: NSObject {
    var isMenuBarIconVisible: (() -> Bool)?
    var onShowMenuBarIconChanged: ((Bool) -> Void)?

    private let window: NSWindow
    private let runAtStartupCheckbox = NSButton(
        checkboxWithTitle: "Run at startup",
        target: nil,
        action: nil
    )
    private let showMenuBarIconCheckbox = NSButton(
        checkboxWithTitle: "Show menu bar icon",
        target: nil,
        action: nil
    )
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private var statusLabels: [Permission: NSTextField] = [:]

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "CmdTab Settings"
        window.isReleasedWhenClosed = false
        window.center()

        setupContent()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPermissions),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func show() {
        runAtStartupCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        showMenuBarIconCheckbox.state = (isMenuBarIconVisible?() ?? true) ? .on : .off
        refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setupContent() {
        guard let content = window.contentView else { return }

        runAtStartupCheckbox.target = self
        runAtStartupCheckbox.action = #selector(toggleRunAtStartup(_:))

        showMenuBarIconCheckbox.target = self
        showMenuBarIconCheckbox.action = #selector(toggleShowMenuBarIcon(_:))

        let separator = NSBox()
        separator.boxType = .separator

        let permissionsHeader = NSTextField(labelWithString: "Permissions")
        permissionsHeader.font = NSFont.boldSystemFont(ofSize: 12)

        warningLabel.font = NSFont.systemFont(ofSize: 11)
        warningLabel.textColor = .systemOrange
        warningLabel.preferredMaxLayoutWidth = 400

        var permissionRows: [NSView] = []
        for permission in Permission.allCases {
            let title = NSTextField(labelWithString: permission.title)
            title.font = NSFont.systemFont(ofSize: 12)

            let status = NSTextField(labelWithString: "")
            status.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            status.alignment = .right
            status.translatesAutoresizingMaskIntoConstraints = false
            status.widthAnchor.constraint(equalToConstant: 60).isActive = true
            statusLabels[permission] = status

            let openButton = NSButton(
                title: "Open…",
                target: self,
                action: #selector(openPermissionSettings(_:))
            )
            openButton.bezelStyle = .inline
            openButton.controlSize = .small
            openButton.tag = permission.rawValue

            let row = NSStackView(views: [title, status, openButton])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            permissionRows.append(row)
        }

        let hint = NSTextField(
            wrappingLabelWithString: "Press Alt+Tab to switch between windows of the current app. Reopen this window by launching CmdTab again."
        )
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 400

        let stack = NSStackView(views: [
            runAtStartupCheckbox,
            showMenuBarIconCheckbox,
            separator,
            permissionsHeader,
            warningLabel,
        ] + permissionRows + [
            hint,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
    }

    @objc private func refreshPermissions() {
        for permission in Permission.allCases {
            let granted = permission.isGranted
            guard let status = statusLabels[permission] else { continue }
            status.stringValue = granted ? "Granted" : "Missing"
            status.textColor = granted ? .systemGreen : .systemRed
        }

        let missingCore = !Permission.accessibility.isGranted || !Permission.inputMonitoring.isGranted
        let missingScreenRecording = !Permission.screenRecording.isGranted

        if missingCore {
            warningLabel.stringValue = "Alt+Tab needs Accessibility and Input Monitoring. Grant them, then return here; CmdTab reconnects automatically."
            warningLabel.isHidden = false
        } else if missingScreenRecording {
            warningLabel.stringValue = "Screen Recording is needed for window thumbnails. Without it, cards show the app icon."
            warningLabel.isHidden = false
        } else {
            warningLabel.stringValue = ""
            warningLabel.isHidden = true
        }
    }

    @objc private func toggleRunAtStartup(_ sender: NSButton) {
        let enabled = sender.state == .on
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            sender.state = enabled ? .off : .on

            let alert = NSAlert()
            alert.messageText = "Could not update the startup setting"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
        }
    }

    @objc private func toggleShowMenuBarIcon(_ sender: NSButton) {
        onShowMenuBarIconChanged?(sender.state == .on)
    }

    @objc private func openPermissionSettings(_ sender: NSButton) {
        guard let permission = Permission(rawValue: sender.tag) else { return }
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
