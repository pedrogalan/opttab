import AppKit

extension Notification.Name {
    static let cmdTabShowSettings = Notification.Name("dev.cmdtab.showSettings")
}

final class SettingsWindowController: NSObject {
    var onShowMenuBarIconChanged: ((Bool) -> Void)?

    private static let githubURL = URL(string: "https://github.com/pedrogalan/cmdtab")!

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
    private let includeOtherSpacesCheckbox = NSButton(
        checkboxWithTitle: "Include windows from other spaces",
        target: nil,
        action: nil
    )
    private let thumbnailSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private var statusLabels: [Permission: NSTextField] = [:]

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
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
        showMenuBarIconCheckbox.state = Preferences.shared.showMenuBarIcon ? .on : .off
        includeOtherSpacesCheckbox.state = Preferences.shared.includeWindowsFromOtherSpaces ? .on : .off
        if let index = ThumbnailSize.allCases.firstIndex(of: Preferences.shared.thumbnailSize) {
            thumbnailSizePopup.selectItem(at: index)
        }
        refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setupContent() {
        guard let content = window.contentView else { return }

        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabView)

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = makeGeneralView()
        tabView.addTabViewItem(generalItem)

        let aboutItem = NSTabViewItem(identifier: "about")
        aboutItem.label = "About"
        aboutItem.view = makeAboutView()
        tabView.addTabViewItem(aboutItem)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func makeGeneralView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 400))

        runAtStartupCheckbox.target = self
        runAtStartupCheckbox.action = #selector(toggleRunAtStartup(_:))

        showMenuBarIconCheckbox.target = self
        showMenuBarIconCheckbox.action = #selector(toggleShowMenuBarIcon(_:))

        includeOtherSpacesCheckbox.target = self
        includeOtherSpacesCheckbox.action = #selector(toggleIncludeOtherSpaces(_:))

        thumbnailSizePopup.removeAllItems()
        thumbnailSizePopup.addItems(withTitles: ThumbnailSize.allCases.map(\.title))
        thumbnailSizePopup.target = self
        thumbnailSizePopup.action = #selector(changeThumbnailSize(_:))

        let thumbnailLabel = NSTextField(labelWithString: "Thumbnail size:")
        thumbnailLabel.font = NSFont.systemFont(ofSize: 12)

        let thumbnailRow = NSStackView(views: [thumbnailLabel, thumbnailSizePopup])
        thumbnailRow.orientation = .horizontal
        thumbnailRow.alignment = .centerY
        thumbnailRow.spacing = 8

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let permissionsHeader = NSTextField(labelWithString: "Permissions")
        permissionsHeader.font = NSFont.boldSystemFont(ofSize: 12)

        warningLabel.font = NSFont.systemFont(ofSize: 11)
        warningLabel.textColor = .systemOrange
        warningLabel.preferredMaxLayoutWidth = 430

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
        hint.preferredMaxLayoutWidth = 430

        let stack = NSStackView(views: [
            runAtStartupCheckbox,
            showMenuBarIconCheckbox,
            includeOtherSpacesCheckbox,
            thumbnailRow,
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
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
            separator.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -32),
        ])

        return view
    }

    private func makeAboutView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 400))

        let iconView = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let nameLabel = NSTextField(labelWithString: "CmdTab")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 20)
        nameLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: "Version \(appVersion)")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let description = NSTextField(
            wrappingLabelWithString: "A per-app Alt+Tab window switcher for macOS. Hold Alt and press Tab to cycle through the windows of the frontmost app."
        )
        description.font = NSFont.systemFont(ofSize: 12)
        description.alignment = .center
        description.preferredMaxLayoutWidth = 360

        let githubButton = NSButton(
            title: "github.com/pedrogalan/cmdtab",
            target: self,
            action: #selector(openGitHub)
        )
        githubButton.bezelStyle = .rounded

        let year = Calendar.current.component(.year, from: Date())
        let copyright = NSTextField(labelWithString: "© \(year) Pedro Galán")
        copyright.font = NSFont.systemFont(ofSize: 10)
        copyright.textColor = .tertiaryLabelColor
        copyright.alignment = .center

        let stack = NSStackView(views: [
            iconView,
            nameLabel,
            versionLabel,
            description,
            githubButton,
            copyright,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])

        return view
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
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

    @objc private func toggleIncludeOtherSpaces(_ sender: NSButton) {
        Preferences.shared.includeWindowsFromOtherSpaces = sender.state == .on
    }

    @objc private func changeThumbnailSize(_ sender: NSPopUpButton) {
        guard ThumbnailSize.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        Preferences.shared.thumbnailSize = ThumbnailSize.allCases[sender.indexOfSelectedItem]
    }

    @objc private func openPermissionSettings(_ sender: NSButton) {
        guard let permission = Permission(rawValue: sender.tag) else { return }
        NSWorkspace.shared.open(permission.settingsURL)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(Self.githubURL)
    }
}
