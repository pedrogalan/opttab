# CmdTab

CmdTab is a macOS window switcher for the app you’re using. Hold **Option** and press **Tab** to cycle through that app’s windows without switching to a different app.

[Download CmdTab](https://github.com/pedrogalan/cmdtab/releases/latest)

## Requirements

- macOS 13 or later
- Apple silicon or Intel Mac
- Accessibility and Input Monitoring permissions for window switching
- Screen Recording permission for window thumbnails (optional)

## Install

1. Download the universal ZIP from the [GitHub Releases page](https://github.com/pedrogalan/cmdtab/releases).
2. Open the ZIP and move `CmdTab.app` to your Applications folder.
3. Open CmdTab. If macOS warns that it can’t verify the app, Control-click `CmdTab.app`, choose **Open**, then confirm.
4. In the Settings window, open **Permissions** and grant Accessibility and Input Monitoring. Grant Screen Recording if you want window thumbnails.

CmdTab is distributed without an Apple Developer ID signature or notarization, so macOS displays a security warning on first launch. The app is universal and runs natively on both Apple silicon and Intel Macs.

## Use CmdTab

- Hold **Option** and press **Tab** to move forward through the frontmost app’s windows.
- Hold **Option+Shift** and press **Tab** to move backward.
- Release **Option** to focus the selected window.
- Press **Escape** to cancel.

CmdTab runs in the menu bar, not the Dock, and opens Settings when it launches. Close Settings to keep CmdTab running. When the menu bar icon is visible, use it to reopen Settings or quit; if you hide the icon, launch CmdTab again to reopen Settings.

## Settings

- **Run at startup** launches CmdTab when you sign in.
- **Show menu bar icon** controls whether CmdTab appears in the menu bar.
- **Include windows from other spaces** adds windows on other macOS Desktops. This option uses a private macOS Accessibility interface, so it may stop working after a macOS update; switching windows on the current Desktop is unaffected.
- **Thumbnail size** changes the size of the switcher cards.

Accessibility and Input Monitoring are required for switching windows. Screen Recording is only needed to show thumbnails; without it, cards use the app icon instead. The Permissions tab shows each permission’s status and links to the relevant System Settings pane.

Window availability and ordering can vary by app. Some apps expose their windows differently, and windows on other Desktops may not always be available.

## Uninstall

Turn off **Run at startup** in Settings, quit CmdTab from the menu bar, then remove `CmdTab.app` from Applications.
