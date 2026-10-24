import Darwin
import Foundation

/// A process-lifetime lease on a state directory. Keep the file in place after
/// closing it: unlinking a locked file would let a new process lock another inode.
final class StateDirectoryLock {
    enum Failure: Error {
        case alreadyRunning
    }

    private let descriptor: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(".instance.lock")
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Self.systemError() }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw Failure.alreadyRunning }
            throw Self.systemError(code)
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    private static func systemError(_ code: Int32 = errno) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
