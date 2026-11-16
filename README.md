# CmdTab (prototype)

Minimal macOS menu bar app that captures `Alt+Tab` and shows an overlay to switch between windows of the **current/frontmost app** (Cmd+Tab-style, but per-app).

## Stack
- Swift + AppKit (native)
- Global key capture via `CGEvent.tapCreate` (key down + flags changed)
- Window enumeration/focus via Accessibility API (`AXUIElement`)

## Run (development)
```bash
swift build
./.build/debug/CmdTab
# or: swift run
```

A menu bar item (`⌘⇥`) should appear. Use the menu to quit.

## How it works
- `Alt+Tab`: open overlay (windows of the frontmost app) and move selection forward
- `Alt+Shift+Tab`: move selection backward
- Keep holding `Alt` and press `Tab` repeatedly to choose
- Release `Alt`: focus the selected window
- `Esc` while overlay is visible: cancel

## Permissions required
macOS will block global key capture and window control until you grant permissions:
1. **Accessibility**: System Settings → Privacy & Security → Accessibility → allow the app/binary running `CmdTab`.
2. **Input Monitoring** (may be required on newer macOS for event taps): System Settings → Privacy & Security → Input Monitoring → allow it.
3. **Screen Recording**: needed for window thumbnails. Without it the switcher falls back to showing the app icon on each card.

When running via `swift build`/`swift run`, the executable is inside `.build/debug/CmdTab`; you may need to grant permission to that binary or to the launching terminal/IDE, then relaunch.

## Notes / MVP limitations
- Uses windows from the app's Accessibility `AXWindows` list (minimized windows filtered best-effort).
- Overlay shows a horizontal row of window thumbnails (screenshots) with titles; falls back to the app icon if thumbnails are unavailable.
- Thumbnails are captured asynchronously and cached per window (cache is used to show cards instantly).
  - Windows with no cache entry are captured immediately when the switcher opens.
  - If `Alt` is held with no `Tab` presses for 3 seconds, visible thumbnails refresh; this repeats every 3 seconds while idle.
  - Pressing `Tab`/`Alt+Shift+Tab` resets that 3-second idle timer.
- Window order/behavior can vary by app (e.g. browsers, document-based apps).
- Prototype executable; a polished app should be a bundled `.app` (`LSUIElement=true`) with signing/notarization.

## Next iterations
- MRU ordering per app and better window filtering (off-screen/sheets/tabs where possible).
- Richer overlay (animations, smooth scrolling, live previews).
- Configurable hotkeys and app-specific behavior.
