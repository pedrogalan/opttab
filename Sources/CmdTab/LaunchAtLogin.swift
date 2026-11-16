import Darwin
import Foundation

/// Manages "run at startup" for the current executable.
///
/// While CmdTab is an unbundled SwiftPM executable, `SMAppService` isn't
/// available in a useful way, so this writes a per-user LaunchAgent plist and
/// bootstraps it into the current GUI session.
enum LaunchAtLogin {
    private static let label = "dev.cmdtab.login"

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writePlist()
            refreshJob()
        } else {
            bootoutJob()
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        }
    }

    /// Keeps the LaunchAgent pointing at the current executable path (the build
    /// location can change between runs during development).
    static func syncIfEnabled() {
        guard isEnabled else { return }
        try? writePlist()
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static var executablePath: String {
        URL(
            fileURLWithPath: CommandLine.arguments[0],
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
    }

    private static func writePlist() throws {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let properties: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: properties,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    private static func refreshJob() {
        bootoutJob()
        _ = launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func bootoutJob() {
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
