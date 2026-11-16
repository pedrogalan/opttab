# CmdTab (prototype)

Minimal macOS menu bar app that captures `Alt+Tab` and shows an overlay to switch between windows of the **current/frontmost app** (Cmd+Tab-style, but per-app).

## Stack
- Swift + AppKit (native)
- Global key capture via `CGEvent.tapCreate` (key down + flags changed)
- Window enumeration/focus via Accessibility API (`AXUIElement`)

## Build CmdTab.app (double-clickable)
```bash
./build-app.sh
open dist/CmdTab.app
```

This builds a release binary, wraps it in `dist/CmdTab.app`, and ad-hoc signs it. You can also double-click `dist/CmdTab.app` in Finder.

## Run (development)
```bash
swift build
./.build/debug/CmdTab
# or: swift run
```

A menu bar item (`⌘⇥`) should appear. **A settings window opens on every launch**; you can reopen it from the menu bar item → **Settings…**. Use the menu to quit.

## Settings
- **Run at startup**: writes/removes a per-user LaunchAgent at `~/Library/LaunchAgents/dev.cmdtab.login.plist` and bootstraps it into the current session.
- **Show menu bar icon**: shows/hides the `⌘⇥` menu bar item (persisted in `UserDefaults`). If hidden, launch CmdTab again to reopen Settings — the second launch asks the running instance to show Settings, then exits.
- The LaunchAgent points at whichever executable is currently running (inside `dist/CmdTab.app` or the `.build/...` binary). Running from a different location updates the plist on next launch.

## Release build
```bash
swift build -c release
./.build/release/CmdTab
```

## How it works
- `Alt+Tab`: open overlay (windows of the frontmost app) and move selection forward
- `Alt+Shift+Tab`: move selection backward
- Keep holding `Alt` and press `Tab` repeatedly to choose
- Release `Alt`: focus the selected window
- `Esc` while overlay is visible: cancel
- Many windows are shown in up to two rows of thumbnails (horizontal scrolling only if they still don't fit)

## Permissions required
macOS will block global key capture and window control until you grant permissions:
1. **Accessibility**: needed to enumerate and focus other apps' windows.
2. **Input Monitoring**: needed for the global `Alt+Tab` event tap.
3. **Screen Recording**: needed for window thumbnails. Without it the switcher falls back to showing the app icon on each card.

The Settings window shows each permission as **Granted** or **Missing**, with an **Open…** button that jumps to the right System Settings pane. CmdTab reconnects its event tap automatically when Accessibility/Input Monitoring are granted.

Because the app is ad-hoc signed, rebuilding can change its signature and macOS may stop honoring previously granted permissions. If Alt+Tab stops working after a rebuild, reset and re-grant:

```bash
tccutil reset Accessibility dev.cmdtab
tccutil reset ListenEvent dev.cmdtab
tccutil reset ScreenCapture dev.cmdtab
```

When running via `swift build`/`swift run`, the executable is inside `.build/debug/CmdTab`; you may need to grant permission to that binary or to the launching terminal/IDE, then relaunch.

## Notes / MVP limitations
- Uses windows from the app's Accessibility `AXWindows` list (minimized windows filtered best-effort).
- Overlay shows a horizontal row of window thumbnails (screenshots) with titles; falls back to the app icon if thumbnails are unavailable.
- Thumbnails are captured asynchronously and cached per window (cache is used to show cards instantly).
  - Windows with no cache entry are captured immediately when the switcher opens.
  - If `Alt` is held with no `Tab` presses for 3 seconds, visible thumbnails refresh; this repeats every 3 seconds while idle.
  - Pressing `Tab`/`Alt+Shift+Tab` resets that 3-second idle timer.
- Window order/behavior can vary by app (e.g. browsers, document-based apps).
- The `.app` is ad-hoc signed for local use; for distribution, use Developer ID signing and notarization.

## Next iterations
- MRU ordering per app and better window filtering (off-screen/sheets/tabs where possible).
- Richer overlay (animations, smooth scrolling, live previews).
- Configurable hotkeys and app-specific behavior.
