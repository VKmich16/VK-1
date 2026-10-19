import Foundation
import Darwin

/// Prevent two instances using the same profile from racing on state/status files.
/// flock is released by the OS even after a crash; the empty file may remain.
final class InstanceLock {
    private let descriptor: Int32

    init(directory: URL) throws {
        let path = directory.appendingPathComponent("pet.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
    }

    deinit { close(descriptor) }
}
