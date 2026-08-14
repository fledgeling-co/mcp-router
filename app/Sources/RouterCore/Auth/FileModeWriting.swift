import Foundation

/// Creating a directory or a file at an exact POSIX mode.
///
/// R1's `FileSystem` has no mode parameter, and B60 requires `0700` on the auth directory and
/// `0600` on each record — this file holds bearer tokens for the user's accounts, and the default
/// umask would leave them group- and world-readable.
///
/// This is a **separate, narrow protocol** rather than three new methods on `FileSystem`, for one
/// reason: `FileSystem` is R1's and is byte-identical on `main` and on the in-flight `ai/r3`, so
/// editing it would manufacture a merge conflict for a capability only this module needs. Adding a
/// protocol here and conforming `RealFileSystem` to it in an extension touches no shared file.
public protocol FileModeWriting: Sendable {
    func createDirectory(atPath path: String, mode: UInt16) throws
    func writeFile(_ data: Data, atPath path: String, mode: UInt16) throws
    /// The mode actually on disk, so a test can assert the bits rather than trust the call.
    func fileMode(atPath path: String) throws -> UInt16
}

extension RealFileSystem: FileModeWriting {
    public func createDirectory(atPath path: String, mode: UInt16) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: mode)]
        )
        // `createDirectory` applies the attribute only when it creates the directory. An existing
        // directory with looser bits would otherwise keep them, which is precisely the case that
        // matters — a 0755 auth directory left over from an earlier run.
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path
        )
    }

    public func writeFile(_ data: Data, atPath path: String, mode: UInt16) throws {
        // Create-then-chmod leaves a window in which the file exists at the umask's mode with the
        // token already in it. Writing through a file descriptor opened with the mode closes that
        // window: the bits are set by `open`, before any byte is written.
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(mode))
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(errno))
            ])
        }
        defer { close(fd) }
        // O_CREAT honours the mode only when the file is new; an existing record keeps its old
        // bits, so set them explicitly too.
        _ = fchmod(fd, mode_t(mode))
        try data.withUnsafeBytes { raw in
            // An empty record has no base address, and writing nothing is a success rather than a
            // failure — guarding here is what keeps that from being a force-unwrap crash.
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                guard written > 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                        NSLocalizedDescriptionKey: String(cString: strerror(errno))
                    ])
                }
                offset += written
            }
        }
    }

    public func fileMode(atPath path: String) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let number = attributes[.posixPermissions] as? NSNumber else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT), userInfo: [
                NSLocalizedDescriptionKey: "no posix permissions on \(path)"
            ])
        }
        return number.uint16Value
    }
}
