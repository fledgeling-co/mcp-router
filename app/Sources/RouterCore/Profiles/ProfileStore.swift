import Foundation

/// Named profiles, on the router's own disk, at `<router home>/profiles`.
///
/// **Nothing outside `root` is read or written**, and the containment argument is
/// ``ExtensionNaming``'s rather than a second one: a profile name is one well-formed segment that
/// does not begin with a dot, so `.staging` and `.removed` cannot be addressed by a request.
///
/// One file per profile rather than one index holding all of them, and that is the same choice
/// ``DiskExtensionStore`` made for the same reason: an index is a second thing that can disagree
/// with the bytes, and a profile written or deleted behind the router's back must show up on the
/// next read rather than on the next restart.
///
/// `FileManager` directly rather than the ``FileSystem`` seam. The seam expresses single files and
/// has no way to enumerate a directory or to ask whether a path is one, and a store proven against
/// its in-memory double would be proven against something that is not a directory.
public struct DiskProfileStore: ProfileStoring {
    /// `<router home>/profiles`.
    public let root: String
    let clock: any RouterClock

    public init(root: String, clock: any RouterClock = SystemClock()) {
        self.root = root
        self.clock = clock
    }

    private var manager: FileManager { FileManager.default }

    private var stagingRoot: String { (root as NSString).appendingPathComponent(".staging") }
    private var removedRoot: String { (root as NSString).appendingPathComponent(".removed") }

    func filePath(_ name: String) -> String {
        (root as NSString).appendingPathComponent("\(name).json")
    }

    private func isDirectory(_ path: String) -> Bool {
        var flag: ObjCBool = false
        return manager.fileExists(atPath: path, isDirectory: &flag) && flag.boolValue
    }

    // MARK: - Reading

    public func list() -> ProfileListing {
        // A router nobody has written a profile to is empty, not unreadable. The directory is
        // created on the first write rather than at start-up, so its absence is the ordinary state
        // of a fresh home and reporting it as a failure would be a fabricated problem.
        guard isDirectory(root) else { return ProfileListing(root: root, rows: []) }
        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: root)
        } catch {
            return ProfileListing(
                root: root, rows: [],
                unreadable: "\(root) could not be read: \(error.localizedDescription)"
            )
        }
        // Sorted so two reads of an unchanged store agree; `contentsOfDirectory` promises no order.
        // Dotted entries are skipped — `.staging` and `.removed` are this store's own bookkeeping
        // and are not profiles.
        let files = names
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }
            .sorted()
        return ProfileListing(root: root, rows: files.map { file in
            row(String(file.dropLast(".json".count)))
        })
    }

    public func read(name: String) -> ProfileListingRow? {
        guard ExtensionNaming.isWellFormedName(name),
              manager.fileExists(atPath: filePath(name))
        else { return nil }
        return row(name)
    }

    private func row(_ name: String) -> ProfileListingRow {
        let path = filePath(name)
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(bytes: bytes, encoding: .utf8)
        else {
            return ProfileListingRow(
                name: name, record: nil, problem: "\(name).json is missing or is not UTF-8"
            )
        }
        switch ProfileDocument.read(name: name, text: text) {
        case let .read(record): return ProfileListingRow(name: name, record: record)
        case let .unreadable(problem):
            return ProfileListingRow(name: name, record: nil, problem: problem)
        }
    }

    // MARK: - Writing

    /// Every refusal is decided before a byte is written, and the write itself lands in `.staging`
    /// and is renamed into place in one operation.
    ///
    /// A profile is **replaced** rather than refused when it already exists, which is where this
    /// differs from `POST /extensions/:kind` and is why the route is a `PUT`. An extension entry is
    /// a directory of bytes somebody supplied; a profile is a selection somebody is editing, and a
    /// store that refused the second edit would make the route unusable for the thing it is for.
    public func write(_ record: ProfileRecord) -> ProfileWriteOutcome {
        guard ExtensionNaming.isWellFormedName(record.name) else {
            return .refused(ExtensionRefusal(
                status: 400, reason: "bad-name",
                message: "\"\(record.name)\" is not a usable profile name: one segment of ASCII "
                    + "letters, digits, dot, underscore, hyphen or at-sign, not starting with a dot"
            ))
        }
        if let refusal = Self.refuseSelection(record) { return .refused(refusal) }
        do {
            try manager.createDirectory(atPath: stagingRoot, withIntermediateDirectories: true)
            try manager.createDirectory(atPath: root, withIntermediateDirectories: true)
        } catch {
            return .refused(ExtensionRefusal(
                status: 500, reason: "store-unwritable",
                message: "\(root) could not be prepared: \(error.localizedDescription)"
            ))
        }
        let staged = (stagingRoot as NSString)
            .appendingPathComponent("\(record.name).\(Int(clock.nowMilliseconds)).json")
        let text = JSStringify.prettyTwoSpace(ProfileDocument.value(record))
        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: staged), options: .atomic)
            // `replaceItemAt` rather than `moveItem`, because a profile being edited already has a
            // file at the destination and `moveItem` refuses one.
            _ = try manager.replaceItemAt(
                URL(fileURLWithPath: filePath(record.name)), withItemAt: URL(fileURLWithPath: staged)
            )
        } catch {
            try? manager.removeItem(atPath: staged)
            return .refused(ExtensionRefusal(
                status: 500, reason: "write-failed",
                message: "\(record.name) could not be written: \(error.localizedDescription)"
            ))
        }
        return .written(record)
    }

    /// The names inside the selection, checked before anything is created.
    ///
    /// A selected name has to be addressable in the store it selects over, so it is held to the
    /// same rule an entry's own name is. A profile carrying `../../etc` would otherwise be written
    /// happily and only refused later, by the projection, one surface away from the person who
    /// typed it.
    static func refuseSelection(_ record: ProfileRecord) -> ExtensionRefusal? {
        let groups: [(String, [String])] = [
            ("servers", record.servers), ("skills", record.skills),
            ("plugins", record.plugins), ("marketplaces", record.marketplaces)
        ]
        for (label, names) in groups {
            for (position, name) in names.enumerated() where !ExtensionNaming.isWellFormedName(name) {
                return ExtensionRefusal(
                    status: 400, reason: "bad-selection",
                    message: "\(label)[\(position)] is not a usable name: \"\(name)\""
                )
            }
        }
        return nil
    }

    /// Moves the profile to `<root>/.removed/<name>/<millis>.json` and returns that path.
    ///
    /// **Nothing is deleted.** The millisecond stamp is why removing, re-writing and removing again
    /// keeps both copies rather than the second overwriting the first.
    public func remove(name: String) -> ProfileRemoveOutcome {
        guard ExtensionNaming.isWellFormedName(name) else {
            return .refused(ExtensionRefusal(
                status: 400, reason: "bad-name",
                message: "\"\(name)\" is not a usable profile name"
            ))
        }
        guard manager.fileExists(atPath: filePath(name)) else {
            return .refused(ExtensionRefusal(
                status: 404, reason: "no-such-profile",
                message: "no profile named \"\(name)\""
            ))
        }
        let destinationDirectory = (removedRoot as NSString).appendingPathComponent(name)
        let destination = (destinationDirectory as NSString)
            .appendingPathComponent("\(Int(clock.nowMilliseconds)).json")
        do {
            try manager.createDirectory(
                atPath: destinationDirectory, withIntermediateDirectories: true
            )
            try manager.moveItem(atPath: filePath(name), toPath: destination)
        } catch {
            return .refused(ExtensionRefusal(
                status: 500, reason: "remove-failed",
                message: "\(name) could not be moved aside: \(error.localizedDescription)"
            ))
        }
        return .removed(destination)
    }
}
