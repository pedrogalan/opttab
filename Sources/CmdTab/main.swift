import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Darwin

private struct WindowEntry {
    let element: AXUIElement
    let title: String
    let windowID: CGWindowID?
}

private final class ThumbnailCache {
    private struct Entry {
        let image: NSImage
        let capturedAt: Date
    }

    private var entries: [CGWindowID: Entry] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "cmdtab.thumbnail-capture",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func cachedImage(for windowID: CGWindowID) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return entries[windowID]?.image
    }

    func capture(windowID: CGWindowID, size: NSSize, completion: @escaping (NSImage?) -> Void) {
        queue.async { [weak self] in
            let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
            guard let cgImage else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                let image = NSImage(cgImage: cgImage, size: size)
                self?.store(image, for: windowID)
                completion(image)
            }
        }
    }

    private func store(_ image: NSImage, for windowID: CGWindowID) {
        lock.lock()
        entries[windowID] = Entry(image: image, capturedAt: Date())
        if entries.count > 200 {
            let oldest = entries.sorted { $0.value.capturedAt < $1.value.capturedAt }
            for (id, _) in oldest.prefix(entries.count - 150) {
                entries.removeValue(forKey: id)
            }
        }
        lock.unlock()
    }
}

private final class SwitcherOverlayController {
    private static let idleRefreshInterval: TimeInterval = 3

    private var cardSize = ThumbnailSize.medium.cardSize
    private var thumbSize = ThumbnailSize.medium.thumbSize
    private var panel: NSPanel?
    private var cardViews: [NSView] = []
    private var imageViews: [NSImageView] = []
    private var entries: [WindowEntry] = []
    private var currentAppIcon: NSImage?
    private var documentView: NSView?
    private var generation = 0
    private var idleWorkItem: DispatchWorkItem?
    private let thumbnailCache = ThumbnailCache()

    func show(
        appName: String,
        appIcon: NSImage?,
        entries: [WindowEntry],
        selectedIndex: Int,
        thumbnailSize: ThumbnailSize
    ) {
        if panel == nil {
            createPanel()
        }
        guard let panel, let content = panel.contentView else { return }

        cardSize = thumbnailSize.cardSize
        thumbSize = thumbnailSize.thumbSize

        generation += 1
        let gen = generation
        self.entries = entries
        currentAppIcon = appIcon

        content.subviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        imageViews.removeAll()

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        if let appIcon {
            let iconView = NSImageView(image: appIcon)
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true
            header.addArrangedSubview(iconView)
        }
        let headerLabel = NSTextField(labelWithString: appName)
        headerLabel.font = NSFont.boldSystemFont(ofSize: 13)
        headerLabel.textColor = .labelColor
        header.addArrangedSubview(headerLabel)
        root.addArrangedSubview(header)

        let screenWidth = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.width ?? 1440
        let maxPanelWidth = screenWidth - 80
        let cardSpacing: CGFloat = 12
        let rowSpacing: CGFloat = 12
        let horizontalPadding: CGFloat = 30

        let maxCardsPerRow = max(
            1,
            Int((maxPanelWidth - horizontalPadding + cardSpacing) / (cardSize.width + cardSpacing))
        )
        let rowCount = entries.count <= maxCardsPerRow ? 1 : 2
        let cardsInFirstRow = rowCount == 1 ? entries.count : Int(ceil(Double(entries.count) / 2.0))

        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .centerX
        grid.spacing = rowSpacing
        grid.translatesAutoresizingMaskIntoConstraints = false

        for (index, entry) in entries.enumerated() {
            if index == 0 || index == cardsInFirstRow {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .top
                row.spacing = cardSpacing
                row.translatesAutoresizingMaskIntoConstraints = false
                grid.addArrangedSubview(row)
            }
            guard let row = grid.arrangedSubviews.last as? NSStackView else { continue }
            let (card, imageView) = makeCard(appIcon: appIcon, entry: entry)
            row.addArrangedSubview(card)
            cardViews.append(card)
            imageViews.append(imageView)
        }

        grid.layoutSubtreeIfNeeded()
        let gridSize = grid.fittingSize

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false

        grid.frame = NSRect(origin: .zero, size: gridSize)
        grid.translatesAutoresizingMaskIntoConstraints = true
        scroll.documentView = grid
        documentView = grid
        scroll.heightAnchor.constraint(equalToConstant: gridSize.height + 6).isActive = true

        root.addArrangedSubview(scroll)

        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let desiredWidth = gridSize.width + horizontalPadding
        let panelWidth = max(360, min(maxPanelWidth, desiredWidth))
        let panelHeight = gridSize.height + 58

        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        center(panel: panel)
        scroll.hasHorizontalScroller = gridSize.width > panelWidth - horizontalPadding

        updateSelection(selectedIndex)
        panel.orderFrontRegardless()

        // Cached thumbnails render immediately; windows without a cached image are
        // captured right away so new windows show their screenshot ASAP.
        for (index, entry) in entries.enumerated() {
            loadThumbnail(for: entry, at: index, generation: gen)
        }
    }

    private func makeCard(appIcon: NSImage?, entry: WindowEntry) -> (NSView, NSImageView) {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 2
        card.layer?.borderColor = NSColor.clear.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: cardSize.width).isActive = true
        card.heightAnchor.constraint(equalToConstant: cardSize.height).isActive = true

        let imageView = NSImageView(image: Self.placeholderThumbnail(appIcon: appIcon, size: thumbSize))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: entry.title.isEmpty ? "Untitled Window" : entry.title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(imageView)
        card.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: thumbSize.width),
            imageView.heightAnchor.constraint(equalToConstant: thumbSize.height),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
        ])

        return (card, imageView)
    }

    private func loadThumbnail(for entry: WindowEntry, at index: Int, generation gen: Int) {
        guard imageViews.indices.contains(index) else { return }

        guard let windowID = entry.windowID else {
            imageViews[index].image = Self.placeholderThumbnail(appIcon: currentAppIcon, size: thumbSize)
            return
        }

        if let cached = thumbnailCache.cachedImage(for: windowID) {
            imageViews[index].image = cached
        } else {
            imageViews[index].image = Self.placeholderThumbnail(appIcon: currentAppIcon, size: thumbSize)
            captureThumbnail(windowID: windowID, generation: gen)
        }
    }

    private func captureThumbnail(windowID: CGWindowID, generation gen: Int) {
        thumbnailCache.capture(windowID: windowID, size: thumbSize) { [weak self] image in
            guard let self, let image, self.generation == gen else { return }
            guard let index = self.entries.firstIndex(where: { $0.windowID == windowID }),
                  self.imageViews.indices.contains(index) else { return }
            self.imageViews[index].image = image
        }
    }

    /// Re-captures every visible card. Called after Alt has been held idle for a while.
    func refreshThumbnails() {
        guard isVisible, CGPreflightScreenCaptureAccess() else { return }
        let gen = generation
        for entry in entries {
            guard let windowID = entry.windowID else { continue }
            captureThumbnail(windowID: windowID, generation: gen)
        }
    }

    func updateSelection(_ index: Int) {
        for (i, card) in cardViews.enumerated() {
            if i == index {
                card.layer?.borderColor = NSColor.controlAccentColor.cgColor
                card.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            } else {
                card.layer?.borderColor = NSColor.clear.cgColor
                card.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        scrollSelectedCardIntoView(index)
        resetIdleRefresh()
    }

    /// Restarts the 3-second idle timer used to refresh stale screenshots.
    func resetIdleRefresh() {
        idleWorkItem?.cancel()
        scheduleIdleRefresh()
    }

    private func scheduleIdleRefresh() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            self.refreshThumbnails()
            self.scheduleIdleRefresh()
        }
        idleWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.idleRefreshInterval,
            execute: work
        )
    }

    private func scrollSelectedCardIntoView(_ index: Int) {
        guard let panel, let content = panel.contentView,
              let scroll = findScrollView(in: content),
              let card = cardViews[safe: index],
              let documentView else { return }
        let rect = card.convert(card.bounds, to: documentView)
        scroll.contentView.scrollToVisible(rect)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    func hide() {
        generation += 1
        idleWorkItem?.cancel()
        idleWorkItem = nil
        panel?.orderOut(nil)
        entries = []
        currentAppIcon = nil
        documentView = nil
        cardViews.removeAll()
        imageViews.removeAll()
    }

    var isVisible: Bool { panel?.isVisible == true }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14
        visual.layer?.masksToBounds = true
        panel.contentView = visual
        self.panel = panel
    }

    private func center(panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private static func placeholderThumbnail(appIcon: NSImage?, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        if let icon = appIcon {
            let side = min(size.width, size.height) * 0.45
            let rect = NSRect(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2,
                width: side,
                height: side
            )
            icon.draw(in: rect)
        }
        image.unlockFocus()
        return image
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let overlay = SwitcherOverlayController()
    private let settingsController = SettingsWindowController()
    private let preferences = Preferences.shared

    private var switching = false
    private var switchApp: NSRunningApplication?
    private var switchEntries: [WindowEntry] = []
    private var selectedIndex: Int = 0

    private let otherSpaceCacheLifetime: TimeInterval = 10
    private let otherSpaceScanBudget: TimeInterval = 0.25
    private var otherSpaceElementsCache: [pid_t: (date: Date, elements: [CGWindowID: AXUIElement])] = [:]
    private let otherSpaceScanQueue = DispatchQueue(
        label: "cmdtab.other-space-scan",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var switchGeneration = 0

    private var showMenuBarIcon: Bool {
        get {
            preferences.showMenuBarIcon
        }
        set {
            preferences.showMenuBarIcon = newValue
            updateStatusItemVisibility()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateStatusItemVisibility()
        requestPermissionsIfNeeded()
        setupEventTap()
        LaunchAtLogin.syncIfEnabled()

        settingsController.onShowMenuBarIconChanged = { [weak self] visible in
            self?.showMenuBarIcon = visible
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowSettingsNotification(_:)),
            name: .cmdTabShowSettings,
            object: nil
        )

        settingsController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController.show()
        return true
    }

    private func updateStatusItemVisibility() {
        if showMenuBarIcon {
            setupStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "⌘⇥"
            button.toolTip = "CmdTab (Alt+Tab window switcher)"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Switcher", action: #selector(showSwitcherNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        retryEventTapIfNeeded()
    }

    private func retryEventTapIfNeeded() {
        guard eventTap == nil,
              Permission.accessibility.isGranted,
              Permission.inputMonitoring.isGranted else { return }
        setupEventTap()
    }

    private func requestPermissionsIfNeeded() {
        for permission in Permission.allCases where !permission.isGranted {
            permission.request()
        }
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            return delegate.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("Failed to create event tap. Check Accessibility/Input Monitoring permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let altDown = event.flags.contains(.maskAlternate)
            if switching && !altDown {
                commitSwitch()
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskShift, .maskAlternate])

        if keyCode == Int64(kVK_Escape) && switching {
            cancelSwitch()
            return nil
        }

        if keyCode == Int64(kVK_Tab) && modifiers == .maskAlternate {
            if switching {
                advanceSelection(reverse: false)
            } else {
                beginSwitch(reverse: false)
            }
            return nil
        }

        if keyCode == Int64(kVK_Tab) && modifiers == [.maskAlternate, .maskShift] {
            if switching {
                advanceSelection(reverse: true)
            } else {
                beginSwitch(reverse: true)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    @objc private func showSwitcherNow() {
        if switching {
            advanceSelection(reverse: false)
        } else {
            beginSwitch(reverse: false)
        }
    }

    private func beginSwitch(reverse: Bool) {
        guard Permission.accessibility.isGranted, Permission.inputMonitoring.isGranted else {
            for permission in [Permission.accessibility, .inputMonitoring] where !permission.isGranted {
                permission.request()
            }
            return
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        let includeOthers = preferences.includeWindowsFromOtherSpaces
        let result = windowEntries(for: frontApp, includeOtherSpaces: includeOthers)
        var entries = result.entries
        var needsScan = false

        if includeOthers, PrivateAX.shared.isAvailable {
            if let extras = cachedOtherSpaceEntries(
                for: frontApp.processIdentifier,
                excluding: result.knownIDs
            ) {
                entries.append(contentsOf: extras)
            } else {
                needsScan = true
            }
        }

        switchGeneration += 1
        let generation = switchGeneration

        if entries.count > 1 {
            showSwitcher(app: frontApp, entries: entries, reverse: reverse)
            if needsScan {
                startOtherSpaceScan(
                    app: frontApp,
                    baseEntries: entries,
                    knownIDs: result.knownIDs,
                    generation: generation,
                    reverse: reverse,
                    deferred: false
                )
            }
        } else if needsScan {
            // A single window on this Desktop doesn't mean the app has only one
            // window. Wait for the scan instead of flashing a one-card overlay,
            // and only show it if windows on another Desktop show up.
            startOtherSpaceScan(
                app: frontApp,
                baseEntries: entries,
                knownIDs: result.knownIDs,
                generation: generation,
                reverse: reverse,
                deferred: true
            )
        }
    }

    private func showSwitcher(app: NSRunningApplication, entries: [WindowEntry], reverse: Bool) {
        switchApp = app
        switchEntries = entries
        switching = true

        // Start from focused window, then move once in requested direction (like Cmd+Tab behavior)
        let focusedIdx = focusedWindowIndex(for: app, entries: entries) ?? 0
        selectedIndex = reverse
            ? (focusedIdx - 1 + entries.count) % entries.count
            : (focusedIdx + 1) % entries.count

        overlay.show(
            appName: app.localizedName ?? "App",
            appIcon: app.icon,
            entries: entries,
            selectedIndex: selectedIndex,
            thumbnailSize: preferences.thumbnailSize
        )
    }

    private func advanceSelection(reverse: Bool) {
        guard switching, !switchEntries.isEmpty else { return }
        selectedIndex = reverse
            ? (selectedIndex - 1 + switchEntries.count) % switchEntries.count
            : (selectedIndex + 1) % switchEntries.count
        overlay.updateSelection(selectedIndex)
    }

    private func commitSwitch() {
        guard switching else { return }
        let app = switchApp
        let entries = switchEntries
        let index = selectedIndex
        endSession()
        guard let app, entries.indices.contains(index) else { return }
        focus(window: entries[index].element, in: app)
    }

    private func cancelSwitch() {
        guard switching else { return }
        endSession()
    }

    private func endSession() {
        switchGeneration += 1
        switching = false
        switchApp = nil
        switchEntries = []
        selectedIndex = 0
        overlay.hide()
    }

    private func windowEntries(
        for app: NSRunningApplication,
        includeOtherSpaces: Bool
    ) -> (entries: [WindowEntry], knownIDs: Set<CGWindowID>) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        let windows = result == .success ? (windowsRef as? [AXUIElement] ?? []) : []

        let cgWindows = onScreenWindowInfo(for: app.processIdentifier)
        let onScreenIDs = Set(cgWindows.map(\.id))
        var usedIDs: Set<CGWindowID> = []
        var knownIDs: Set<CGWindowID> = []
        var entries: [WindowEntry] = []

        for win in windows {
            var titleRef: CFTypeRef?
            let title: String
            if AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef) == .success,
               let t = titleRef as? String {
                title = t
            } else {
                title = ""
            }

            let windowID = resolveWindowID(for: win, title: title, candidates: cgWindows, used: &usedIDs)
            if let windowID {
                knownIDs.insert(windowID)
            }

            // Best-effort filter: skip minimized windows
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool, minimized {
                continue
            }

            // Windows on other spaces are not in the on-screen window list. Keep
            // windows whose ID we could not resolve (conservative fallback).
            if !includeOtherSpaces, let windowID, !onScreenIDs.contains(windowID) {
                continue
            }

            entries.append(WindowEntry(element: win, title: title, windowID: windowID))
        }

        return (entries, knownIDs)
    }

    /// Extras from a fresh cache, or `nil` when the cache has expired and a
    /// background scan is needed.
    ///
    /// The cache holds *every* window element found for the process, not just the
    /// ones that were off-Space at scan time. Which windows are "extra" depends on
    /// the active Desktop, so it must be recomputed per call; otherwise switching
    /// to the other Desktop finds only a stale, now-empty extra set.
    private func cachedOtherSpaceEntries(
        for pid: pid_t,
        excluding knownIDs: Set<CGWindowID>
    ) -> [WindowEntry]? {
        guard let cached = otherSpaceElementsCache[pid],
              Date().timeIntervalSince(cached.date) < otherSpaceCacheLifetime else { return nil }
        return makeOtherSpaceEntries(from: cached.elements, excluding: knownIDs)
    }

    private func makeOtherSpaceEntries(
        from elements: [CGWindowID: AXUIElement],
        excluding knownIDs: Set<CGWindowID>
    ) -> [WindowEntry] {
        elements.compactMap { windowID, element in
            guard !knownIDs.contains(windowID) else { return nil }
            // Cached elements go stale when a window closes.
            guard PrivateAX.shared.isAlive(element) else { return nil }
            return makeWindowEntry(element: element, windowID: windowID)
        }
    }

    /// Scans for off-Desktop windows off the event-tap thread. Results are applied
    /// on the main thread, either by appending cards to a visible switcher or by
    /// showing it for the first time (when only one on-Desktop window was known).
    private func startOtherSpaceScan(
        app: NSRunningApplication,
        baseEntries: [WindowEntry],
        knownIDs: Set<CGWindowID>,
        generation: Int,
        reverse: Bool,
        deferred: Bool
    ) {
        let pid = app.processIdentifier
        otherSpaceScanQueue.async { [weak self] in
            guard let self else { return }
            let elements = PrivateAX.shared.allWindowElements(pid: pid, budget: self.otherSpaceScanBudget)

            DispatchQueue.main.async {
                guard generation == self.switchGeneration else { return }
                self.storeOtherSpaceCache(pid: pid, elements: elements)

                let extras = self.makeOtherSpaceEntries(from: elements, excluding: knownIDs)
                guard !extras.isEmpty else { return }

                if deferred {
                    guard !self.switching,
                          baseEntries.count + extras.count > 1,
                          CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate),
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                        return
                    }
                    self.showSwitcher(app: app, entries: baseEntries + extras, reverse: reverse)
                } else {
                    guard self.switching,
                          self.switchApp?.processIdentifier == pid else { return }

                    let existingIDs = Set(self.switchEntries.compactMap(\.windowID))
                    let newEntries = extras.filter { entry in
                        guard let id = entry.windowID else { return true }
                        return !existingIDs.contains(id)
                    }
                    guard !newEntries.isEmpty else { return }

                    self.switchEntries.append(contentsOf: newEntries)
                    self.overlay.show(
                        appName: app.localizedName ?? "App",
                        appIcon: app.icon,
                        entries: self.switchEntries,
                        selectedIndex: self.selectedIndex,
                        thumbnailSize: self.preferences.thumbnailSize
                    )
                }
            }
        }
    }

    private func storeOtherSpaceCache(pid: pid_t, elements: [CGWindowID: AXUIElement]) {
        otherSpaceElementsCache[pid] = (Date(), elements)
        if otherSpaceElementsCache.count > 20,
           let oldest = otherSpaceElementsCache.min(by: { $0.value.date < $1.value.date }) {
            otherSpaceElementsCache.removeValue(forKey: oldest.key)
        }
    }

    private func makeWindowEntry(element: AXUIElement, windowID: CGWindowID) -> WindowEntry? {
        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let minimized = minimizedRef as? Bool, minimized {
            return nil
        }

        var titleRef: CFTypeRef?
        let title = (AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success
            ? titleRef as? String
            : nil) ?? ""

        return WindowEntry(element: element, title: title, windowID: windowID)
    }

    private struct CGWindowInfoLite {
        let id: CGWindowID
        let name: String
    }

    private func onScreenWindowInfo(for pid: pid_t) -> [CGWindowInfoLite] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = info[kCGWindowNumber as String] as? Int else { return nil }
            let name = info[kCGWindowName as String] as? String ?? ""
            return CGWindowInfoLite(id: CGWindowID(number), name: name)
        }
    }

    private func resolveWindowID(
        for element: AXUIElement,
        title: String,
        candidates: [CGWindowInfoLite],
        used: inout Set<CGWindowID>
    ) -> CGWindowID? {
        // Private SPI gives the real CGWindowID; AXWindowNumber is unavailable on
        // recent macOS versions.
        if let id = PrivateAX.shared.windowID(of: element) {
            used.insert(id)
            return id
        }

        var numberRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &numberRef) == .success,
           let number = numberRef as? Int, number > 0 {
            let id = CGWindowID(number)
            used.insert(id)
            return id
        }

        // Fallback: match by window title, then by remaining on-screen windows.
        if !title.isEmpty,
           let match = candidates.first(where: { !used.contains($0.id) && $0.name == title }) {
            used.insert(match.id)
            return match.id
        }
        if let match = candidates.first(where: { !used.contains($0.id) }) {
            used.insert(match.id)
            return match.id
        }
        return nil
    }

    private func focusedWindowIndex(for app: NSRunningApplication, entries: [WindowEntry]) -> Int? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let focused = (focusedRef as! AXUIElement)
        return entries.firstIndex(where: { CFEqual($0.element, focused) })
    }

    private func focus(window: AXUIElement, in app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        app.activate(options: [.activateIgnoringOtherApps])
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func handleShowSettingsNotification(_ notification: Notification) {
        settingsController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let instanceLock = SingleInstanceLock()
guard instanceLock.acquire() else {
    // Another CmdTab is already running: ask it to show Settings, then exit.
    DistributedNotificationCenter.default().post(name: .cmdTabShowSettings, object: nil)
    Thread.sleep(forTimeInterval: 0.2)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
