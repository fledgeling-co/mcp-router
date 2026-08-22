import Foundation

/// A manifest path whose DIRECTORY really exists, for a suite whose manifest does not.
///
/// The three manifest writers take ``ConfigMutationLock`` on `<manifestPath>.lock` (R19), and that
/// sidecar is a real file even when the manifest itself lives in a `MemoryFileSystem`. It has to
/// be: `flock` is an OS behaviour that a memory double would simulate rather than exhibit, which is
/// the seam `ImportConfigWriterLockTests` already draws for `servers.json`, and a lock the Swift
/// router took only against its own in-process bookkeeping would exclude the reference from nothing.
///
/// `/router/manifest.json` — the path these suites used — has no directory to put a sidecar in, so
/// every write through them reported `could not open the lock file` instead of the behaviour under
/// test. The manifest bytes still go to the memory filesystem; only the lock is real.
///
/// Unique per call, because Swift Testing runs suites in parallel and two tests sharing one path
/// would contend for one real lock rather than running independently.
enum ManifestLockScratch {
    static func path(_ label: String = "manifest") -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-\(label)-\(UUID().uuidString)")
        // A failure here surfaces as the lock refusal this exists to avoid, named in the message,
        // so it reports itself rather than hiding as an unexplained expectation failure.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("manifest.json").path
    }
}
