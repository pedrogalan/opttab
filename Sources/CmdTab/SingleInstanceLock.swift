import Darwin
import Foundation

/// Ensures only one CmdTab process runs at a time.
///
/// This matters for the "Run at startup" toggle: `launchctl bootstrap` with
/// `RunAtLoad` starts the job immediately, and we don't want a second instance
/// to appear when the user enables it while the app is already running.
final class SingleInstanceLock {
    private var fileDescriptor: Int32 = -1

    func acquire() -> Bool {
        let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CmdTab", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        let lockPath = supportDirectory.appendingPathComponent("instance.lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            // If we can't create the lock file, fail open rather than blocking the app.
            return true
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }

        fileDescriptor = descriptor
        return true
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
