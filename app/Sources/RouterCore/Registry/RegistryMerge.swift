import Foundation

/// The two indexes, merged. A port of `src/registry.ts`.
///
/// Every row is a `JSObjectDraft` rather than a struct, because the merge is a JavaScript spread
/// and the resulting **key order is on the wire**: a merged row keeps the official row's order and
/// appends Smithery's numbers, so `useCount` lands after `install`, not where a Swift type would
/// declare it (N2, S3).
public enum Registry {
    /// `/github\.com[/:]([^/]+)\/([^/.?#]+)/i` → `"<owner>/<repo>"`, lowercased.
    ///
    /// Case-insensitive, matches anywhere in the string, and stops the repo segment at the first
    /// `.`, `?`, `#` or `/` — so `https://github.com/Owner/Repo.git#readme` keys `owner/repo`.
    static func repoKey(_ url: JSONValue?) -> JSString? {
        // `if (!url) return undefined` — ToBoolean, so an empty string yields no key.
        guard let url, url.isTruthy, case let .string(text) = url else { return nil }
        let haystack = text.string
        guard let anchor = haystack.range(of: "github.com", options: .caseInsensitive) else { return nil }

        var rest = haystack[anchor.upperBound...]
        guard let separator = rest.first, separator == "/" || separator == ":" else { return nil }
        rest = rest.dropFirst()

        let owner = rest.prefix { $0 != "/" }
        guard !owner.isEmpty else { return nil }
        rest = rest.dropFirst(owner.count)
        guard rest.first == "/" else { return nil }
        rest = rest.dropFirst()

        let repo = rest.prefix { $0 != "/" && $0 != "." && $0 != "?" && $0 != "#" }
        guard !repo.isEmpty else { return nil }
        return JSString("\(owner.lowercased())/\(repo.lowercased())")
    }

    /// `e.displayName.toLowerCase().replace(/[^a-z0-9]/g, '')` — lowercase **first**, so `"A-B"`
    /// keys `"ab"`. Applied only when `repoKey` yields nothing.
    static func dedupeKey(_ row: JSObjectDraft) -> JSString {
        if let key = repoKey(row.get("repository")) { return key }
        let display = row.get("displayName")?.asString?.string ?? ""
        return JSString(display.lowercased().filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
    }

    // MARK: - Decoding the two indexes

    /// `officialInstall(s)` — remotes win over packages, and only npm and pypi yield a command.
    static func officialInstall(_ server: JSObjectDraft) -> JSONValue? {
        let remote = server.get("remotes")?.asArray?.first
        let remoteObject = remote?.asObjectMembers
        let remoteURL = remoteObject?.first { $0.key == JSString("url") }?.value
        if let remoteURL, remoteURL.isTruthy {
            let type = remoteObject?.first { $0.key == JSString("type") }?.value
            let headers = remoteObject?.first { $0.key == JSString("headers") }?.value.asArray ?? []
            var install = JSObjectDraft()
            // `remote.type === 'sse' ? 'sse' : 'http'` — strict equality, so anything else is http.
            install.set("type", .string(JSString(type?.asString == JSString("sse") ? "sse" : "http")))
            install.set("url", remoteURL)
            install.set("requires", .array(headers.compactMap { header in
                let members = header.asObjectMembers
                let name = members?.first { $0.key == JSString("name") }?.value
                // `.filter((h) => h.name)` — ToBoolean, so an empty name drops the row.
                guard let name, name.isTruthy else { return nil }
                var requirement = JSObjectDraft()
                requirement.set("name", name)
                requirement.set("description", members?.first { $0.key == JSString("description") }?.value)
                requirement.set("isSecret", members?.first { $0.key == JSString("isSecret") }?.value)
                return requirement.jsonValue
            }))
            return install.jsonValue
        }

        let package = server.get("packages")?.asArray?.first?.asObjectMembers
        let identifier = package?.first { $0.key == JSString("identifier") }?.value
        // `if (!pkg?.identifier) return undefined` — ToBoolean.
        guard let identifier, identifier.isTruthy, let id = identifier.asString else { return nil }
        let registryType = package?.first { $0.key == JSString("registryType") }?.value.asString

        var install = JSObjectDraft()
        if registryType == JSString("npm") {
            let version = package?.first { $0.key == JSString("version") }?.value
            // `pkg.version ? `${id}@${ver}` : id` — ToBoolean on the version.
            var argument = id
            if let version, version.isTruthy {
                argument = JSString("\(id.string)@\(version.jsDisplayString)")
            }
            install.set("type", .string(JSString("stdio")))
            install.set("command", .string(JSString("npx")))
            install.set("args", .array([.string(JSString("-y")), .string(argument)]))
            return install.jsonValue
        }
        if registryType == JSString("pypi") {
            install.set("type", .string(JSString("stdio")))
            install.set("command", .string(JSString("uvx")))
            install.set("args", .array([.string(id)]))
            return install.jsonValue
        }
        // Anything else would be a guess at a command line, and a wrong command is worse than none.
        return nil
    }

    /// One official row, in the reference's member order.
    static func officialRow(_ entry: JSONValue) -> JSObjectDraft? {
        let row = entry.asObjectMembers
        let server = row?.first { $0.key == JSString("server") }?.value
        guard let serverMembers = server?.asObjectMembers else { return nil }
        var draft = JSObjectDraft()
        for member in serverMembers {
            draft.set(member.key.string, member.value)
        }

        let name = draft.get("name")
        // `if (!s?.name) return []` — an empty name is skipped, not carried.
        guard let name, name.isTruthy, let nameText = name.asString else { return nil }

        // `Object.values(row._meta ?? {})[0]` — the first value in ECMAScript key order (S4).
        let meta = row?.first { $0.key == JSString("_meta") }?.value
        let firstMeta = JSONMember.ecmaOrdered(meta?.asObjectMembers ?? []).first?.value
        let updatedAt = firstMeta?.asObjectMembers?.first { $0.key == JSString("updatedAt") }?.value

        var out = JSObjectDraft()
        out.set("id", .string(nameText))
        out.set("name", .string(nameText))
        // `s.name.split('/').pop() ?? s.name` — a trailing slash yields "", which is nullish-safe
        // and therefore survives as an empty display name.
        out.set(
            "displayName",
            .string(JSString(nameText.string.split(separator: "/", omittingEmptySubsequences: false).last
                    .map(String.init) ?? nameText.string))
        )
        out.set("description", draft.nullish("description") ?? .string(JSString("")))
        out.set("source", .string(JSString("official")))
        out.set(
            "repository",
            draft.get("repository")?.asObjectMembers?.first { $0.key == JSString("url") }?.value
        )
        out.set("version", draft.get("version"))
        out.set("updatedAt", updatedAt)
        out.set("install", officialInstall(draft))
        return out
    }

    /// One Smithery row. Note there is no `version` member, and `displayName` falls back on
    /// **truthiness** (`||`), not nullishness — an empty display name becomes the qualified name.
    static func smitheryRow(_ entry: JSONValue) -> JSObjectDraft? {
        guard let members = entry.asObjectMembers else { return nil }
        var draft = JSObjectDraft()
        for member in members {
            draft.set(member.key.string, member.value)
        }

        let qualified = draft.get("qualifiedName")
        guard let qualified, qualified.isTruthy, let qualifiedText = qualified.asString else { return nil }

        let display = draft.get("displayName")
        var out = JSObjectDraft()
        out.set("id", .string(JSString("smithery:\(qualifiedText.string)")))
        out.set("name", .string(qualifiedText))
        out.set(
            "displayName",
            .string((display?.isTruthy ?? false) ? (display?.asString ?? qualifiedText) : qualifiedText)
        )
        out.set("description", draft.nullish("description") ?? .string(JSString("")))
        out.set("source", .string(JSString("smithery")))
        out.set("repository", draft.get("homepage"))
        out.set("updatedAt", draft.get("createdAt"))
        out.set("useCount", draft.get("useCount"))
        out.set("verified", draft.get("verified"))
        out.set("iconUrl", draft.get("iconUrl"))

        // `s.remote && s.isDeployed` — both ToBoolean.
        if draft.get("remote")?.isTruthy ?? false, draft.get("isDeployed")?.isTruthy ?? false {
            var install = JSObjectDraft()
            var requirement = JSObjectDraft()
            requirement.set("name", .string(JSString("Authorization")))
            requirement.set("description", .string(JSString("Bearer <your Smithery API key>")))
            requirement.set("isSecret", .bool(true))
            install.set("type", .string(JSString("http")))
            install.set("url", .string(JSString("https://server.smithery.ai/\(qualifiedText.string)/mcp")))
            install.set("requires", .array([requirement.jsonValue]))
            out.set("install", install.jsonValue)
        } else {
            // Assigned `undefined`, so the key exists and a merge overwrites it **in this slot**.
            out.set("install", nil)
        }
        return out
    }

    // MARK: - Merge and rank

    /// The dedupe map: official rows first, then Smithery merged onto matching keys.
    ///
    /// Within one index a repeated key **overwrites** — `byKey.set` is last-wins — which is why the
    /// map is built by assignment rather than by skipping duplicates.
    static func merge(official: [JSObjectDraft], smithery: [JSObjectDraft]) -> [JSObjectDraft] {
        var order: [JSString] = []
        var byKey: [JSString: JSObjectDraft] = [:]

        func put(_ key: JSString, _ row: JSObjectDraft) {
            if byKey[key] == nil { order.append(key) }
            byKey[key] = row
        }

        for row in official {
            put(dedupeKey(row), row)
        }
        for row in smithery {
            let key = dedupeKey(row)
            guard let existing = byKey[key] else { put(key, row); continue }

            // `{...existing, source, useCount, verified, iconUrl, install}` — every override lands
            // in the slot the official row already gave the key, and only genuinely new keys append.
            var merged = existing.spread()
            merged.set("source", .string(JSString("both")))
            merged.set("useCount", row.nullish("useCount") ?? existing.get("useCount"))
            merged.set("verified", row.nullish("verified") ?? existing.get("verified"))
            merged.set("iconUrl", row.nullish("iconUrl") ?? existing.get("iconUrl"))
            // Official install wins: it is the authoritative statement of how to run it.
            merged.set("install", existing.get("install") ?? row.get("install"))
            byKey[key] = merged
        }
        return order.compactMap { byKey[$0] }
    }

    /// `useCount` desc, then `stars` desc, then `updatedAt` descending by `localeCompare`.
    ///
    /// Implemented as an explicit **stable** merge sort: `Array.prototype.sort` is stable by
    /// specification and B56 turns on a three-way tie keeping arrival order, while Swift's `sort`
    /// carries no such guarantee.
    static func rank(_ rows: [JSObjectDraft]) -> [JSObjectDraft] {
        func numeric(_ row: JSObjectDraft, _ key: String) -> Double {
            // `(x ?? 0)` — nullish only, then arithmetic coercion.
            guard let value = row.get(key) else { return 0 }
            switch value {
            case .null: return 0
            case let .number(number): return number
            case let .string(text): return JSToNumber.number(text.string)
            case let .bool(flag): return flag ? 1 : 0
            case .array, .object: return .nan
            }
        }
        func before(_ lhs: JSObjectDraft, _ rhs: JSObjectDraft) -> Bool {
            let use = numeric(rhs, "useCount") - numeric(lhs, "useCount")
            // `if (use) return use` — ToBoolean, so a NaN difference falls through to the next key.
            if use != 0, !use.isNaN { return use < 0 }
            let stars = numeric(rhs, "stars") - numeric(lhs, "stars")
            if stars != 0, !stars.isNaN { return stars < 0 }
            let left = lhs.get("updatedAt")?.asString?.string ?? ""
            let right = rhs.get("updatedAt")?.asString?.string ?? ""
            return JSLocaleCompare.compare(right, left) < 0
        }

        // Bottom-up merge sort; equal elements keep their left-hand (arrival) order.
        var source = rows
        var width = 1
        while width < source.count {
            var merged: [JSObjectDraft] = []
            merged.reserveCapacity(source.count)
            var start = 0
            while start < source.count {
                let middle = min(start + width, source.count)
                let end = min(start + 2 * width, source.count)
                var left = start
                var right = middle
                while left < middle, right < end {
                    if before(source[right], source[left]) {
                        merged.append(source[right]); right += 1
                    } else {
                        merged.append(source[left]); left += 1
                    }
                }
                merged.append(contentsOf: source[left ..< middle])
                merged.append(contentsOf: source[right ..< end])
                start = end
            }
            source = merged
            width *= 2
        }
        return source
    }
}
