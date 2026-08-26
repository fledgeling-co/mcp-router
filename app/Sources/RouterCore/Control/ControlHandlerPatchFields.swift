import Foundation

/// `PATCH /servers/:name`'s writable fields.
///
/// Split out of `ControlHandler.swift` because that file outgrew the 400-line limit, which is the
/// same reason `PoolReapingTests` was split from `PoolTests`. The cut is at a seam rather than at a
/// line count: everything here answers "what may a PATCH write, and in what order", and nothing
/// here decides whether the request is allowed to run at all.
extension ControlHandler {
    /// The five fields `PATCH /servers/:name` may write, applied in the order the reference
    /// writes them.
    ///
    /// Lifted out of `patch` rather than left inline: five gated arms plus the body around them
    /// put that function over both the complexity and the body-length limits, and the arms are a
    /// list rather than a flow, which is the shape that reads better with a name on it.
    ///
    /// **The order is the contract, not a style choice.** It is the order members are appended
    /// to the user's `servers.json`, which R4's parity gate diffs against the reference byte for
    /// byte.
    /// Internal rather than private: `patch` lives in `ControlHandler.swift` and Swift's
    /// `private` does not reach across files, even within one type.
    static func applyPatchFields(
        to entry: inout [JSONMember],
        supplied: (String) -> JSONValue??
    ) {
        func set(_ key: String, _ value: JSONValue?) {
            let target = JSString(key)
            guard let value else {
                // `undefined` removes the member — it does **not** write null (B42).
                entry.removeAll { $0.key == target }
                return
            }
            if let at = entry.firstIndex(where: { $0.key == target }) {
                entry[at] = JSONMember(key: target, value: value)
            } else {
                entry.append(JSONMember(key: target, value: value))
            }
        }

        // The fixed order `projects, warm, idleMs, placard, disabled`, each gated on key
        // presence. `disabled` is LAST and the position is load-bearing twice: this order
        // is the order members are appended to the user's `servers.json`, which is diffed
        // byte for byte against the reference; and the 400 body for a non-object PATCH
        // names whichever key is tested first, so moving `disabled` above `projects` would
        // change a message that has nothing to do with it.
        if let projects = supplied("projects") {
            // `b.projects?.length ? b.projects : undefined` — the raw value is stored when
            // its `length` reads truthy, so a string survives (B42). An `asArray` test here
            // would drop `projects: "x"`, which the reference keeps.
            set("projects", (projects?.jsLengthIsTruthy ?? false) ? projects : nil)
        }
        if let warm = supplied("warm") {
            set("warm", (warm?.isTruthy ?? false) ? warm : nil)
        }
        if let idleMs = supplied("idleMs") {
            // Assigned as given, including 0 and null — the reference's one inconsistency
            // among these four, ported rather than tidied (P2).
            set("idleMs", idleMs)
        }
        if let placard = supplied("placard") {
            set("placard", placard)
        }
        if let disabled = supplied("disabled") {
            // Shaped like `warm` rather than like `idleMs`: a falsy value removes the
            // member instead of writing `false`, so turning a server back on leaves the
            // config as it found it.
            set("disabled", (disabled?.isTruthy ?? false) ? disabled : nil)
        }
    }
}
