import AppKit
import Foundation

/// Migrates the user's existing CmdTab installation on OptTab's first launch.
enum LegacyCmdTabMigration {
    private static let completionKey = "didMigrateFromCmdTab"
    private static let legacyBundleIdentifier = "dev.cmdtab"

    /// Returns a message if OptTab should stop launching until CmdTab is closed.
    static func runIfNeeded() -> String? {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: completionKey) else { return nil }

        do {
            try LaunchAtLogin.migrateLegacyAgentIfNeeded()
        } catch {
            return "OptTab couldn’t migrate CmdTab’s Run at startup setting. \(error.localizedDescription)"
        }

        let legacyApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: legacyBundleIdentifier
        )
        legacyApps.forEach { _ = $0.terminate() }

        let deadline = Date().addingTimeInterval(5)
        while legacyApps.contains(where: { !$0.isTerminated }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        guard legacyApps.allSatisfy(\.isTerminated) else {
            return "Quit CmdTab from the menu bar, then open OptTab again to finish the rename."
        }

        Preferences.migrateLegacyCmdTabSettings()
        removeLegacyLockFile()
        defaults.set(true, forKey: completionKey)
        return nil
    }

    private static func removeLegacyLockFile() {
        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CmdTab", isDirectory: true)
        let lockFile = supportDirectory.appendingPathComponent("instance.lock")
        try? FileManager.default.removeItem(at: lockFile)
        try? FileManager.default.removeItem(at: supportDirectory)
    }
}
