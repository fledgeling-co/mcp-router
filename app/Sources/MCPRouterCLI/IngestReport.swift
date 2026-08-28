import Foundation
import RouterCore

/// What `mcp-router ingest` prints, in both of its shapes.
///
/// Split from the verb so the dispatch reads as the decisions it makes. The JSON is built out of
/// ``JSONValue`` members rather than through an encoder, for the same reason the control routes are:
/// a caller comparing bytes needs an order that does not depend on a hash seed.
enum IngestReport {
    static func plan(_ scan: ClaudeScan, json: Bool, settleMilliseconds: Double) -> String {
        guard !json else { return JSStringify.compact(planValue(scan)) + "\n" }
        var out = "ingest plan — reading \(scan.tree.root)\n"
        out += "NOTHING BELOW HAS HAPPENED. Re-run with --apply to carry it out.\n\n"
        for register in scan.unreadableRegisters {
            out += "  ! a register could not be read, so its kind was not scanned: \(register)\n"
        }
        if !scan.unreadableRegisters.isEmpty { out += "\n" }
        out += "would ingest (\(scan.candidates.count))\n"
        for candidate in scan.candidates {
            out += "  \(Copy.pad(candidate.kind.singular, 12)) \(Copy.pad(candidate.name, 42)) "
            out += "\(candidate.stamp.files) files, \(candidate.stamp.bytes) bytes"
            out += candidate.version.map { " · \($0)" } ?? ""
            out += "\n      from \(candidate.sourcePath)\n"
            if let note = candidate.note { out += "      note: \(note)\n" }
        }
        out += "\nleft alone (\(scan.blocked.count))\n"
        for blocked in scan.blocked {
            out += "  \(Copy.pad(blocked.kind.singular, 12)) \(Copy.pad(blocked.name, 42)) "
            out += "\(blocked.reason)\n      \(blocked.detail)\n"
        }
        out += "\nSettle window \(Int(settleMilliseconds / 1000))s. A tree that changes while it is "
        out += "being copied is\nrefused at the verify step as well, so this window is a filter "
        out += "rather than the guarantee.\n"
        return out
    }

    static func applied(_ run: ExtensionIngest.Run, scan: ClaudeScan, json: Bool) -> String {
        guard !json else { return JSStringify.compact(appliedValue(run, scan: scan)) + "\n" }
        var out = "ingest \(run.runId) — \(scan.tree.root)\n\n"
        for outcome in run.outcomes {
            out += "  \(Copy.pad(outcome.state.rawValue, 9)) "
            out += "\(Copy.pad(outcome.candidate.kind.singular, 12)) "
            out += "\(Copy.pad(outcome.candidate.name, 42)) \(outcome.detail)\n"
            if let quarantine = outcome.quarantinePath {
                out += "            Claude's copy is at \(quarantine)\n"
            }
        }
        if let settings = run.settings {
            out += "\nsettings.json: \(settings.removed.count) key(s) withdrawn, "
            out += "\(settings.absent.count) already absent, "
            out += "\(settings.topLevelBefore) top-level keys before and "
            out += "\(settings.topLevelAfter) after\n"
            if let backup = settings.backupPath { out += "  backed up to \(backup)\n" }
        }
        if let failure = run.settingsFailure {
            out += "\n  ! settings.json was NOT edited: \(failure)\n"
        }
        out += run.manifestPath.map {
            "\nundo this run with:\n  mcp-router ingest --undo \($0)\n"
        } ?? "\n  ! no run manifest was written, so this run is not undoable from the router\n"
        return out
    }

    static func undone(_ report: ExtensionIngestUndo.Report, json: Bool) -> String {
        guard !json else { return JSStringify.compact(undoneValue(report)) + "\n" }
        var out = "undo \(report.runId)\n\n"
        for outcome in report.outcomes {
            out += "  \(Copy.pad(outcome.state.rawValue, 9)) "
            out += "\(Copy.pad(outcome.kind.singular, 12)) "
            out += "\(Copy.pad(outcome.name, 42)) \(outcome.detail)\n"
        }
        out += "\nsettings.json: \(report.settingsRestored) key(s) put back\n"
        if let failure = report.settingsFailure {
            out += "  ! settings.json was NOT edited: \(failure)\n"
        }
        return out
    }

    // MARK: - JSON

    static func planValue(_ scan: ClaudeScan) -> JSONValue {
        .object([
            member("claudeRoot", .string(JSString(scan.tree.root))),
            member("applied", .bool(false)),
            member("candidateCount", .number(Double(scan.candidates.count))),
            member("blockedCount", .number(Double(scan.blocked.count))),
            member("candidates", .array(scan.candidates.map(candidateValue))),
            member("blocked", .array(scan.blocked.map(blockedValue))),
            member(
                "unreadableRegisters",
                .array(scan.unreadableRegisters.map { .string(JSString($0)) })
            )
        ])
    }

    static func appliedValue(_ run: ExtensionIngest.Run, scan: ClaudeScan) -> JSONValue {
        .object([
            member("runId", .string(JSString(run.runId))),
            member("claudeRoot", .string(JSString(scan.tree.root))),
            member("applied", .bool(true)),
            member(
                "manifestPath",
                run.manifestPath.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            member("outcomes", .array(run.outcomes.map(outcomeValue))),
            member("blocked", .array(scan.blocked.map(blockedValue))),
            member(
                "settingsRemoved",
                run.settings.map { JSONValue.number(Double($0.removed.count)) } ?? .null
            ),
            member(
                "settingsTopLevelBefore",
                run.settings.map { JSONValue.number(Double($0.topLevelBefore)) } ?? .null
            ),
            member(
                "settingsTopLevelAfter",
                run.settings.map { JSONValue.number(Double($0.topLevelAfter)) } ?? .null
            ),
            member(
                "settingsFailure",
                run.settingsFailure.map { JSONValue.string(JSString($0)) } ?? .null
            )
        ])
    }

    static func undoneValue(_ report: ExtensionIngestUndo.Report) -> JSONValue {
        .object([
            member("runId", .string(JSString(report.runId))),
            member("settingsRestored", .number(Double(report.settingsRestored))),
            member(
                "settingsFailure",
                report.settingsFailure.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            member("outcomes", .array(report.outcomes.map { outcome in
                .object([
                    member("kind", .string(JSString(outcome.kind.rawValue))),
                    member("name", .string(JSString(outcome.name))),
                    member("state", .string(JSString(outcome.state.rawValue))),
                    member("detail", .string(JSString(outcome.detail)))
                ])
            }))
        ])
    }

    static func candidateValue(_ candidate: IngestCandidate) -> JSONValue {
        .object([
            member("kind", .string(JSString(candidate.kind.rawValue))),
            member("name", .string(JSString(candidate.name))),
            member("title", .string(JSString(candidate.title))),
            member("sourcePath", .string(JSString(candidate.sourcePath))),
            member("version", candidate.version.map { JSONValue.string(JSString($0)) } ?? .null),
            member(
                "settingsKey",
                candidate.settingsKey.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            member("files", .number(Double(candidate.stamp.files))),
            member("bytes", .number(Double(candidate.stamp.bytes))),
            member("digest", .string(JSString(candidate.stamp.digest))),
            member("note", candidate.note.map { JSONValue.string(JSString($0)) } ?? .null)
        ])
    }

    static func blockedValue(_ blocked: IngestBlocked) -> JSONValue {
        .object([
            member("kind", .string(JSString(blocked.kind.rawValue))),
            member("name", .string(JSString(blocked.name))),
            member("sourcePath", .string(JSString(blocked.sourcePath))),
            member("reason", .string(JSString(blocked.reason))),
            member("detail", .string(JSString(blocked.detail)))
        ])
    }

    static func outcomeValue(_ outcome: IngestOutcome) -> JSONValue {
        .object([
            member("kind", .string(JSString(outcome.candidate.kind.rawValue))),
            member("name", .string(JSString(outcome.candidate.name))),
            member("state", .string(JSString(outcome.state.rawValue))),
            member("storedPath", outcome.storedPath.map { JSONValue.string(JSString($0)) } ?? .null),
            member(
                "quarantinePath",
                outcome.quarantinePath.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            member("detail", .string(JSString(outcome.detail)))
        ])
    }

    private static func member(_ key: String, _ value: JSONValue) -> JSONMember {
        JSONMember(key: JSString(key), value: value)
    }
}
