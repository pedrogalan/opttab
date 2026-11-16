import AppKit

final class SettingsWindowController: NSObject {
    private let window: NSWindow
    private let runAtStartupCheckbox = NSButton(
        checkboxWithTitle: "Run at startup",
        target: nil,
        action: nil
    )

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "CmdTab Settings"
        window.isReleasedWhenClosed = false
        window.center()

        setupContent()
    }

    func show() {
        runAtStartupCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setupContent() {
        guard let content = window.contentView else { return }

        runAtStartupCheckbox.target = self
        runAtStartupCheckbox.action = #selector(toggleRunAtStartup(_:))

        let hint = NSTextField(
            wrappingLabelWithString: "CmdTab stays in the menu bar. Press Alt+Tab to switch between windows of the current app."
        )
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 320

        let stack = NSStackView(views: [runAtStartupCheckbox, hint])
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
}
