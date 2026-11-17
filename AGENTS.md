# Instructions for coding agents

This file contains development and release procedures. Keep the root README focused on information for people evaluating, installing, and using OptTab.

## Project basics

- OptTab is a native Swift and AppKit menu bar app for macOS 13 and later.
- `Package.swift` defines a single executable target at `Sources/OptTab`.
- The app’s bundle identifier is `dev.opttab`.
- Keep the app bundle named `OptTab.app`. Version numbers belong in `App/Info.plist`, release tags, release notes, and archive filenames; do not append them to the app bundle name.
- The GitHub repository slug and URLs are `opttab`.
- The README is public-facing and should not contain a current version number or internal build/release commands.
- `releases/v1.0.x.md` are historical CmdTab release notes. Keep their original product name; new OptTab releases use the same `releases/` directory.

## Build

Build a local app bundle with:

```bash
./build-app.sh
```

This creates or replaces `dist/OptTab.app`. The script accepts an optional output bundle path. `OPTTAB_BINARY` can point it at an already-built executable; the release script uses that to package a universal binary.

The app icon is stored in `App/AppIcon.icns` and copied into `Contents/Resources/AppIcon.icns`. `App/AppIcon.png` is the editable source artwork. Keep the ICNS asset in sync if the artwork changes. `App/menu-bar-icon.png` is a separate menu bar template image.

The build is ad-hoc signed because the project does not have an Apple Developer ID certificate. Ad-hoc signing is not notarization and may cause Gatekeeper warnings for downloaded builds.

## Moving from CmdTab

- Keep the one-time migration in `LegacyMigration.swift`: it copies the old app’s preferences, migrates `dev.cmdtab.login` to `dev.opttab.login`, asks any running `dev.cmdtab` app to quit, and removes the old lock file.
- Keep old CmdTab identifiers and preference keys in the migration code. The new app identity is `dev.opttab`; macOS permissions must be granted again for OptTab.
- Do not remove the migration marker or old identity support without an explicit migration plan for users who skip releases.

## Release procedure

Use an annotated version tag such as `v2.0.2`. Keep the app name `OptTab.app` unchanged.

1. Start from a clean, up-to-date `master` branch and confirm that the release tag and GitHub release do not already exist.
2. Set `CFBundleShortVersionString` and increment `CFBundleVersion` in `App/Info.plist`.
3. Add `releases/v<version>.md` with the user-visible changes, update the minimum-macOS or support information only if it changed, and review the README for factual changes. Do not put the current version in the README.
4. Build the universal app and archive on macOS:

   ```bash
   ./build-release.sh
   ```

   This creates `dist/OptTab.app` and `dist/OptTab-<version>-macos-universal.zip`. The archive contains the app bundle; `dist/` is ignored by Git.
5. Verify the app version, both architectures, icon, signature, and archive:

   ```bash
   VERSION=2.0.2
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/OptTab.app/Contents/Info.plist
   /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' dist/OptTab.app/Contents/Info.plist
   lipo -info dist/OptTab.app/Contents/MacOS/OptTab
   test -s dist/OptTab.app/Contents/Resources/AppIcon.icns
   codesign --verify --deep --strict dist/OptTab.app
   unzip -t "dist/OptTab-${VERSION}-macos-universal.zip"
   shasum -a 256 "dist/OptTab-${VERSION}-macos-universal.zip"
   ```

   Confirm the app bundle inside the ZIP is named `OptTab.app`, with no version suffix. Record and compare the archive SHA-256 after uploading it.
6. Review and stage the release changes, commit, and tag:

   ```bash
   VERSION=2.0.2
   git add -A
   git diff --cached
   git commit -m "Prepare OptTab ${VERSION} release"
   git tag -a "v${VERSION}" -m "OptTab ${VERSION}"
   git push origin master "v${VERSION}"
   ```
7. Confirm `gh auth status`, then publish the archive and notes:

   ```bash
   VERSION=2.0.2
   gh release create "v${VERSION}" \
     --title "OptTab ${VERSION}" \
     --notes-file "releases/v${VERSION}.md" \
     "dist/OptTab-${VERSION}-macos-universal.zip"
   ```

8. Verify the published release with `gh release view v2.0.2 --json tagName,isDraft,publishedAt,url,assets` and confirm the uploaded asset’s name, size, and digest match the local archive.

## Permissions and troubleshooting

- Accessibility and Input Monitoring are required for window switching. Screen Recording is optional and only enables thumbnails.
- Grant permissions after installing OptTab at its final location. Ad-hoc rebuilds can change the app signature, which may cause macOS to ask for permissions again.
- With `swift run`, permissions may need to be granted to the development executable or the launching terminal instead of the packaged app.
- `Run at startup` creates a per-user LaunchAgent at `~/Library/LaunchAgents/dev.opttab.login.plist`.
- Window discovery on other macOS Spaces uses a private Accessibility interface. Keep the public fallback working if that interface becomes unavailable.
