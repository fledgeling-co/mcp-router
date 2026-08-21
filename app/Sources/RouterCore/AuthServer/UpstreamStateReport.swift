import Foundation

/// What is actually wrong with each upstream, in the four states that are not one state.
///
/// THE MEASUREMENT THIS IS WRITTEN AGAINST, taken from the live router on 2026-08-21: 13
/// upstreams, 8 serving tools, 5 silent — and only two of the five are authorisation problems.
/// `auth.authorized` reads true for **four** of the five, so it is not a health signal; the tool
/// count is the observable that discriminates.
///
/// `mobbin` is the case this type exists to get right. It holds a valid access token, a refresh
/// token and an `authorizedAt` stamp, and it serves nothing. A report that said "these need
/// authorising" would be wrong about it, and would send its owner to a command that cannot help.
/// Its row says so and carries no command.
///
/// Read from `config.upstreams`, never from the credential directory. `pocketsmith.json` is on
/// disk with a half-finished registration for a server that is not an upstream at all; a report
/// built from the directory listing would name it and be wrong.
public enum UpstreamStateKind: String, Sendable {
    case serving
    case neverAuthorised = "never-authorised"
    case halfAuthorised = "half-authorised"
    case authorisedNotServing = "authorised-not-serving"
    case notAnAuthProblem = "not-an-auth-problem"
}

public struct UpstreamReport: Sendable, Equatable {
    public var name: String
    public var tools: Int
    public var kind: UpstreamStateKind
    /// What the state is, in one clause.
    public var headline: String
    /// What to do about it. Empty when there is nothing useful to do.
    public var remedy: String
    /// The command to type, present only when running it can actually help.
    public var command: String?
    /// The error the router recorded, verbatim.
    public var detail: String?
}

public enum UpstreamStateReport {
    /// The verb the installed entry point actually exposes.
    ///
    /// `mcpr` is a shell function on the author's machine wrapping `node …/dist/index.js`, and an
    /// install under `~/.local/share` has no alias at all. Printing a command that works only if
    /// the reader shares one shell profile is worse than printing none, so this is composed from
    /// the executable this process was actually started from.
    public static func entryPoint(
        arguments: [String] = CommandLine.arguments
    ) -> String {
        guard let script = arguments.first, !script.isEmpty else { return "mcp-router" }
        return script.hasSuffix(".js") ? "node \(script)" : script
    }

    /// Every upstream, classified.
    public static func rows(
        config: RouterConfig,
        manifest: Manifest,
        auth: FileAuthStore,
        nowMilliseconds: Double,
        entry: String
    ) async -> [UpstreamReport] {
        var out: [UpstreamReport] = []
        for upstream in config.upstreams {
            out.append(
                await row(
                    upstream: upstream, manifest: manifest, auth: auth,
                    nowMilliseconds: nowMilliseconds, entry: entry
                )
            )
        }
        return out
    }

    private static func row(
        upstream: UpstreamConfig,
        manifest: Manifest,
        auth: FileAuthStore,
        nowMilliseconds: Double,
        entry verb: String
    ) async -> UpstreamReport {
        let cached = manifest.entry(named: upstream.name)
        let indexError = cached?.error?.string
        let tools = indexError != nil ? 0 : (cached?.tools.count ?? 0)
        if tools > 0 {
            return UpstreamReport(
                name: upstream.name, tools: tools, kind: .serving,
                headline: "serving \(tools) tool\(tools == 1 ? "" : "s")", remedy: ""
            )
        }

        // `!isStdio(u) && u.oauth !== false` is `describe`'s own test for "this upstream can be
        // authorised at all". A stdio child and an HTTP upstream with `oauth: false` cannot, so
        // their silence is never an authorisation story however encouraging `auth.authorized` is.
        let authCapable = !upstream.isStdio && upstream.oauth != false
        guard authCapable else {
            return UpstreamReport(
                name: upstream.name, tools: 0, kind: .notAnAuthProblem,
                headline: "serving no tools, and it does not use authorisation",
                remedy: indexError != nil
                    ? "Authorising will not help. Fix the error below, then re-index it."
                    : "Authorising will not help. Re-index it and see what it reports.",
                command: "\(verb) index --force",
                detail: indexError
            )
        }

        let name = JSString(upstream.name)
        let record = await auth.read(name)
        let exists = await auth.recordExists(name)
        if !exists {
            return UpstreamReport(
                name: upstream.name, tools: 0, kind: .neverAuthorised,
                headline: "never authorised",
                remedy: "Authorise it, and its tools appear at the next index.",
                command: "\(verb) auth \(upstream.name)",
                detail: indexError
            )
        }
        if !record.hasAccessToken {
            return UpstreamReport(
                name: upstream.name, tools: 0, kind: .halfAuthorised,
                headline: "authorisation was started and never finished",
                remedy: "The browser leg never came back. Run it again.",
                command: "\(verb) auth \(upstream.name)",
                detail: indexError
            )
        }

        let refused = indexError.map(AuthRefusal.isRefusal) ?? false
        let refreshHeld = record.hasRefreshToken
        let at = record.authorizedAt?.string
        let expiry = record.accessTokenExpiry
        let expired = expiry.map { $0 < nowMilliseconds } ?? false
        var held: [String] = [at.map { "authorised on \($0)" } ?? "authorised"]
        if expired, let expiry {
            held.append("its access token expired on \(JSDate.iso8601(milliseconds: expiry))")
        }
        held.append(refreshHeld ? "a refresh token is held" : "no refresh token is held")
        let heldText = held.joined(separator: ", ")

        // A refused credential with nothing to refresh from is the one sub-case where
        // re-authorising is the remedy. With a refresh token behind it, it is not — which is
        // `mobbin`, and is why this branch is not simply "has tokens, therefore fine".
        if refused, !refreshHeld {
            return UpstreamReport(
                name: upstream.name, tools: 0, kind: .authorisedNotServing,
                headline: "\(heldText), and the credential it holds was refused",
                remedy: "There is nothing to refresh from, so authorise it again.",
                command: "\(verb) auth \(upstream.name)",
                detail: indexError
            )
        }
        return UpstreamReport(
            name: upstream.name, tools: 0, kind: .authorisedNotServing,
            headline: "\(heldText), and serving no tools anyway",
            remedy: "This is not an authorisation problem and re-authorising will not fix it. "
                + "The upstream is reachable and authorised and is returning no tools.",
            detail: indexError
        )
    }

    /// The same set, as one paragraph for `initialize`'s `instructions`.
    ///
    /// This reaches the **model** rather than the human — hosts inject it into the system prompt —
    /// so it is written to answer "why can't you use X" correctly instead of leaving the assistant
    /// to guess that the capability does not exist. Kept short: it is paid for on every
    /// `initialize`.
    public static func instructions(from rows: [UpstreamReport]) -> String {
        let silent = rows.filter { $0.kind != .serving }
        let serving = rows.count - silent.count
        let head = "This router relays \(rows.count) MCP servers; \(serving) are serving tools right now."
        guard !silent.isEmpty else { return head }
        let lines = silent.map { row -> String in
            let command = row.command.map { " To fix: `\($0)`." } ?? ""
            return "- \(row.name): \(row.headline). \(row.remedy)\(command)"
        }
        return head
            + " \(silent.count) are not, and their tools are therefore absent from tools/list."
            + " Do not tell the user a capability does not exist when it is one of these:\n"
            + lines.joined(separator: "\n")
    }
}
