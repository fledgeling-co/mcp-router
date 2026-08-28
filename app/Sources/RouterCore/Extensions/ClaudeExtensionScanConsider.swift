import Foundation

/// The per-entry half of ``ClaudeExtensionScan``, split from the enumeration so neither file
/// carries both — the same split ``DiskExtensionStore`` makes between reading and writing, and for
/// the same reason: the enumeration fails by not finding things, and this fails by refusing them.
extension ClaudeExtensionScan {
    /// One entry the scan is deciding about, as it was found. A value rather than five parameters
    /// because a caller holding four of the five is describing half an entry — the same seam
    /// ``ClaudeSettingsEdit/Destination`` is drawn on.
    struct Subject: Sendable, Hashable {
        let kind: ExtensionKind
        let name: String
        let sourcePath: String
        let version: String?
        let settingsKey: String?
    }

    /// One entry's decision, taken in a fixed order so a candidate refused for two reasons is
    /// always reported under the same one.
    ///
    /// It carries `now` rather than reading a clock, and that is the point of it being a value the
    /// scan constructs once: a long scan that re-read the clock per entry would judge its first and
    /// its last candidate against different nows, which is the drift the settle window exists to
    /// remove.
    struct Context: Sendable {
        let tree: ClaudeTree
        let store: any ExtensionStoring
        let settle: Double
        let now: Double

        func consider(
            _ subject: Subject,
            into candidates: inout [IngestCandidate],
            or blocked: inout [IngestBlocked]
        ) {
            let (kind, name, source) = (subject.kind, subject.name, subject.sourcePath)
            func refuse(_ reason: String, _ detail: String) {
                blocked.append(IngestBlocked(
                    kind: kind, name: name, sourcePath: source, reason: reason, detail: detail
                ))
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source, isDirectory: &isDirectory) else {
                // Measured: one of the 127 install records on this machine
                // (`studio-proxy@diolog-plugins`) names an `installPath` that is not there. The
                // register is not the disk, and a row that says otherwise is reported rather than
                // acted on.
                return refuse("sourceMissing", "\(source) does not exist")
            }
            guard isDirectory.boolValue else {
                return refuse("notADirectory", "\(source) is not a directory")
            }
            guard ExtensionNaming.isWellFormedName(name) else {
                return refuse(
                    "unusableName",
                    "\"\(name)\" cannot be a directory name inside the router's store"
                )
            }
            switch descriptor(kind, at: source) {
            case let .failure(message):
                // The acceptance clause, at its one decision point. Measured on this machine:
                // 2 of 24 skill directories carry no `SKILL.md`, and 2 of the 127 install records
                // resolve to a directory with no `.claude-plugin/plugin.json`. All four are
                // reported here and none of them is moved.
                return refuse("unreadableDescriptor", message)
            case let .success(reading):
                guard store.read(kind, name: name) == nil else {
                    return refuse(
                        "alreadyInRouter",
                        "the router already holds a \(kind.singular) named \"\(name)\", "
                            + "so ingesting would have to choose between two copies"
                    )
                }
                guard let stamp = ExtensionStamp.measure(source) else {
                    return refuse("unmeasurable", "\(source) could not be walked")
                }
                guard ExtensionStamp.isSettled(
                    stamp, now: now, settleMilliseconds: settle
                ) else {
                    let age = Int((now - stamp.newestModifiedMilliseconds) / 1000)
                    return refuse(
                        "notSettled",
                        "something under \(source) changed \(age)s ago, inside the "
                            + "\(Int(settle / 1000))s settle window"
                    )
                }
                candidates.append(IngestCandidate(
                    kind: kind, name: name, sourcePath: source, title: reading.title,
                    version: subject.version, settingsKey: subject.settingsKey,
                    stamp: stamp,
                    note: reading.title == name ? nil
                        : "\(kind.descriptorPath) calls this \"\(reading.title)\"; it is stored "
                        + "under \"\(name)\", which is the name Claude resolves it by"
                ))
            }
        }

        /// The entry's own descriptor, read through the same rule ``DiskExtensionStore`` reads it
        /// with. A second, laxer rule here is how the store starts holding entries it would refuse
        /// to list cleanly.
        private func descriptor(
            _ kind: ExtensionKind, at source: String
        ) -> Reading<ExtensionDescriptor.Reading> {
            let path = (source as NSString).appendingPathComponent(kind.descriptorPath)
            guard let data = FileManager.default.contents(atPath: path) else {
                return .failure("\(source) carries no \(kind.descriptorPath)")
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure("\(path) is not UTF-8")
            }
            switch ExtensionDescriptor.read(kind, text: text) {
            case let .read(reading): return .success(reading)
            case let .unreadable(problem): return .failure("\(source): \(problem)")
            }
        }
    }
}
