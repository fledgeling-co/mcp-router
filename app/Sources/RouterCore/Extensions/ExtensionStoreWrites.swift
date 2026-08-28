import Foundation

/// Adding and removing, split from the reading half so neither file carries both.
///
/// The split is the same one `ControlHarnesses.swift` makes and for a related reason: a file that
/// reads a store and a file that writes one fail differently and are reviewed differently. Here it
/// also keeps each file inside the repository's length cap without raising it.
public extension DiskExtensionStore {
    /// Validate everything, stage the whole entry, then move it into place.
    ///
    /// **Order is the guarantee.** Every refusal below happens before a single byte is written, and
    /// the write itself lands in `<root>/.staging/…` and is renamed into the kind directory in one
    /// operation. So a malformed request leaves nothing behind, and a write that dies halfway
    /// leaves its wreckage in `.staging` where no listing reads — there is no state in which the
    /// store holds half an entry under a name a caller asked for.
    func add(
        _ kind: ExtensionKind, name: String, files: [ExtensionFile]
    ) -> ExtensionWriteOutcome {
        if let refusal = Self.refusal(kind, name: name, files: files) {
            return .refused(refusal)
        }
        let destination = entryPath(kind, name)
        guard !FileManager.default.fileExists(atPath: destination) else {
            return .refused(ExtensionRefusal(
                status: 409, reason: "nameTaken",
                message: "a \(kind.singular) named \"\(name)\" already exists"
            ))
        }
        let staging = stagingPath(kind, name)
        do {
            try write(files, into: staging)
            try FileManager.default.createDirectory(
                atPath: directory(for: kind), withIntermediateDirectories: true
            )
            // `moveItem` refuses an occupied destination rather than replacing it, which is the
            // behaviour this call wants: two adds racing on one name must not have the loser
            // silently overwrite the winner.
            try FileManager.default.moveItem(atPath: staging, toPath: destination)
        } catch {
            try? FileManager.default.removeItem(atPath: staging)
            return .refused(ExtensionRefusal(
                status: 500, reason: "writeFailed",
                message: "\(name) could not be written: \(error.localizedDescription)"
            ))
        }
        // Read back from disk rather than reported from the request. The response then says what
        // the store holds, which is the same claim `GET` makes and is checkable against it.
        guard let record = read(kind, name: name) else {
            return .refused(ExtensionRefusal(
                status: 500, reason: "writeFailed",
                message: "\(name) was written and could not be read back"
            ))
        }
        return .added(record)
    }

    /// Moved, never deleted — the bytes end up at `<root>/.removed/<kind>/<name>/<millis>` and the
    /// outcome carries that path.
    ///
    /// That is what "reversible" means here, and it is deliberately weaker than an undo route: the
    /// router does not put the entry back for you, it declines to destroy it. The millisecond
    /// component means removing, re-adding and removing again keeps both copies instead of the
    /// second removal overwriting the first.
    func remove(_ kind: ExtensionKind, name: String) -> ExtensionRemoveOutcome {
        guard ExtensionNaming.isWellFormedName(name) else {
            return .refused(Self.invalidName(name))
        }
        let entry = entryPath(kind, name)
        guard FileManager.default.fileExists(atPath: entry) else {
            return .refused(ExtensionRefusal(
                status: 404, reason: "unknown",
                message: "no \(kind.singular) named \"\(name)\""
            ))
        }
        let destination = removedPath(kind, name)
        do {
            try FileManager.default.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(atPath: entry, toPath: destination)
        } catch {
            return .refused(ExtensionRefusal(
                status: 500, reason: "removeFailed",
                message: "\(name) could not be moved aside: \(error.localizedDescription)"
            ))
        }
        return .removed(destination)
    }
}

private extension DiskExtensionStore {
    func stagingPath(_ kind: ExtensionKind, _ name: String) -> String {
        let staging = (root as NSString).appendingPathComponent(".staging")
        return (staging as NSString)
            .appendingPathComponent("\(kind.rawValue)-\(name)-\(Int(clockMilliseconds))")
    }

    func removedPath(_ kind: ExtensionKind, _ name: String) -> String {
        let removed = (root as NSString).appendingPathComponent(".removed")
        let kindDirectory = (removed as NSString).appendingPathComponent(kind.rawValue)
        let entry = (kindDirectory as NSString).appendingPathComponent(name)
        return (entry as NSString).appendingPathComponent(String(Int(clockMilliseconds)))
    }

    func write(_ files: [ExtensionFile], into staging: String) throws {
        try FileManager.default.createDirectory(
            atPath: staging, withIntermediateDirectories: true
        )
        for file in files {
            let path = (staging as NSString).appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try Data(file.text.utf8).write(to: URL(fileURLWithPath: path))
        }
    }

    static func invalidName(_ name: String) -> ExtensionRefusal {
        ExtensionRefusal(
            status: 400, reason: "invalidName",
            message: "\"\(name)\" is not a usable name: letters, digits, dot, underscore and "
                + "hyphen only, no leading dot, at most \(ExtensionNaming.maximumNameLength) "
                + "characters"
        )
    }

    /// Every refusal that can be decided from the request alone, in the order they are checked.
    static func refusal(
        _ kind: ExtensionKind, name: String, files: [ExtensionFile]
    ) -> ExtensionRefusal? {
        guard ExtensionNaming.isWellFormedName(name) else { return invalidName(name) }
        guard !files.isEmpty else {
            return ExtensionRefusal(
                status: 400, reason: "noFiles",
                message: "a \(kind.singular) needs at least \(kind.descriptorPath)"
            )
        }
        if let refusal = pathRefusal(files) { return refusal }
        guard let descriptor = files.first(where: { $0.path == kind.descriptorPath }) else {
            return ExtensionRefusal(
                status: 400, reason: "missingDescriptor",
                message: "a \(kind.singular) must carry \(kind.descriptorPath)"
            )
        }
        return descriptorRefusal(kind, name: name, text: descriptor.text)
    }

    static func pathRefusal(_ files: [ExtensionFile]) -> ExtensionRefusal? {
        var seen: [String] = []
        for file in files {
            guard ExtensionNaming.isWellFormedRelativePath(file.path) else {
                return ExtensionRefusal(
                    status: 400, reason: "invalidFilePath",
                    message: "\"\(file.path)\" is not a relative path inside the entry"
                )
            }
            guard !seen.contains(file.path) else {
                return ExtensionRefusal(
                    status: 400, reason: "duplicateFilePath",
                    message: "\"\(file.path)\" is given twice, so one copy would be lost"
                )
            }
            seen.append(file.path)
        }
        return nil
    }

    /// The descriptor has to parse **and** name the entry it is being registered as.
    ///
    /// The listing reports `title` separately from `name` because on disk the two can drift — a
    /// person can edit a descriptor after it was stored, and a reading that hid that would be
    /// reporting the request rather than the file. At the door they must agree, because an entry
    /// whose directory and descriptor disagree is exactly what makes ingestion (R30) unable to
    /// tell one entry from two.
    static func descriptorRefusal(
        _ kind: ExtensionKind, name: String, text: String
    ) -> ExtensionRefusal? {
        switch ExtensionDescriptor.read(kind, text: text) {
        case let .unreadable(problem):
            return ExtensionRefusal(
                status: 400, reason: "malformedDescriptor", message: problem
            )
        case let .read(reading):
            guard reading.title != name else { return nil }
            return ExtensionRefusal(
                status: 400, reason: "nameMismatch",
                message: "\(kind.descriptorPath) names \"\(reading.title)\", "
                    + "which is not the \"\(name)\" it is being added as"
            )
        }
    }
}
