import Foundation

/// How an upstream's implementation was located, when it could be located at all.
public enum ContentClass: String, Sendable, Hashable {
    /// The command is an `npx` invocation, and the package it names is in npm's cache.
    case npxPackage = "npx-package"
    /// The command, or the first argument that is one, is an absolute path to a file on this disk.
    case localFile = "local-file"
    /// The router cannot say what code this upstream runs. **Never treated as movement.**
    case unresolved
}

/// What an upstream's implementation is *right now*, as opposed to what its config says.
///
/// This is the content component the manifest key has never had. `UpstreamHash` is an identity
/// hash over command, args, cwd and env — deliberately, because identity is what makes a cached
/// manifest safe to share between sessions — and it is unchanged by this item. What it cannot see
/// is a change *behind* an identity that stayed put, and on this machine that is the ordinary case
/// rather than the exotic one. Measured 2026-08-28 over the 21 configured upstreams: 15 are stdio,
/// and **every one of the 15** can change its code with command, args and env byte-identical —
/// three `npx` invocations carrying a floating spec (`media-gen-pro-mcp@latest`, `mcp-remote`,
/// `@modelcontextprotocol/server-github`), four pointing at a `dist/` build output in a local
/// checkout, and the rest at a binary that an upgrade replaces in place.
///
/// So the key gains a component rather than being replaced, exactly as the brief assumed.
public struct ContentIdentity: Sendable, Hashable {
    public let contentClass: ContentClass
    /// A short digest over whatever was resolved. `nil` when nothing was.
    public let digest: String?
    /// The thing the digest was taken over — a package directory, or a file path — so a reader can
    /// check the answer rather than trust it.
    public let source: String?
    /// Why it could not be resolved. Present exactly when ``contentClass`` is `.unresolved`.
    public let reason: String?

    public init(contentClass: ContentClass, digest: String?, source: String?, reason: String?) {
        self.contentClass = contentClass
        self.digest = digest
        self.source = source
        self.reason = reason
    }

    public static func unresolved(_ reason: String) -> ContentIdentity {
        ContentIdentity(contentClass: .unresolved, digest: nil, source: nil, reason: reason)
    }

    /// True when this reading can be compared against another at all.
    public var isResolved: Bool { digest != nil }
}

/// Resolving an upstream to the code it currently runs.
public enum ContentResolution {
    /// Flags `npx` takes before the package spec. Anything else is the spec.
    ///
    /// `-p`/`--package` take a value, and that value **is** the package — `npx -p pkg cmd` runs
    /// `cmd` out of `pkg`. Treating it as a flag to skip would resolve the wrong argument.
    private static let valuelessFlags: Set<String> = [
        "-y", "--yes", "--no", "--no-install", "-q", "--quiet"
    ]

    public static func resolve(_ upstream: UpstreamConfig, probe: any CacheProbing) -> ContentIdentity {
        guard upstream.isStdio, let command = upstream.command, !command.isEmpty else {
            return .unresolved(
                "an http upstream's implementation is not on this machine, so there is nothing here to digest"
            )
        }
        if isNpx(command) {
            return resolveNpx(args: upstream.args, probe: probe)
        }
        return resolveLocalFile(command: command, args: upstream.args, probe: probe)
    }

    /// The npx half: find the package spec, then the cache entry that was fetched for it.
    ///
    /// Several entries for one package is a resolvable state rather than an ambiguous one. Two of
    /// the 48 entries measured here were both fetched for `ref-tools-mcp` — 154 MB each — and npm
    /// keys an entry on a hash of the spec string it was given, which this router cannot compute.
    /// So the digest covers **all** of them, sorted: a change to any one moves it, which is the
    /// property staleness needs, and naming the live one is a guess it does not have to make.
    private static func resolveNpx(args: [String], probe: any CacheProbing) -> ContentIdentity {
        guard let spec = packageSpec(args) else {
            return .unresolved("this npx invocation names no package, so there is nothing to look up")
        }
        let name = packageName(spec)
        let matches = probe.npxEntries().filter { entry in
            entry.requested.contains { $0.name == name }
        }
        guard !matches.isEmpty else {
            return .unresolved(
                "no npx cache entry was fetched for \"\(name)\"; it has not been run on this machine yet"
            )
        }
        var material: [String] = []
        for entry in matches.sorted(by: { $0.directory < $1.directory }) {
            for request in entry.requested.sorted(by: { $0.name < $1.name }) where request.name == name {
                let version = request.installedVersion ?? "?"
                material.append("\(entry.directory)|\(request.name)@\(version)")
            }
        }
        return ContentIdentity(
            contentClass: .npxPackage,
            digest: UpstreamHash.digest(of: material.joined(separator: "\n")),
            source: matches.map(\.directory).sorted().joined(separator: ", "),
            reason: nil
        )
    }

    /// The local-file half: the first of the command and its arguments that is an absolute path to
    /// a readable file is the entry point.
    ///
    /// Written this way rather than as a special case for `node`, because the four shapes it has to
    /// cover on this machine are `node <abs>/dist/index.js`, `<abs>/warden-mcp`,
    /// `<abs>/obscura mcp` and `<abs>/docker-mcp-guard` — a rule about absolute paths covers all
    /// four, and a rule about interpreters covers one.
    private static func resolveLocalFile(
        command: String, args: [String], probe: any CacheProbing
    ) -> ContentIdentity {
        for candidate in [command] + args where candidate.hasPrefix("/") {
            guard let stamp = probe.fileStamp(candidate) else { continue }
            return ContentIdentity(
                contentClass: .localFile,
                digest: UpstreamHash.digest(of: "\(candidate)|\(stamp)"),
                source: candidate,
                reason: nil
            )
        }
        return .unresolved(
            "\"\(command)\" is not npx, and neither it nor its arguments name a file on this disk"
        )
    }

    // MARK: - Parsing

    static func isNpx(_ command: String) -> Bool {
        let base = (command as NSString).lastPathComponent
        return base == "npx" || base == "npx.cmd"
    }

    /// The package spec inside an `npx` argument list, or `nil` when there is not one.
    static func packageSpec(_ args: [String]) -> String? {
        var index = args.startIndex
        while index < args.endIndex {
            let argument = args[index]
            if argument == "--" {
                index += 1
                continue
            }
            if argument == "-p" || argument == "--package" {
                let next = index + 1
                return next < args.endIndex ? args[next] : nil
            }
            if valuelessFlags.contains(argument) || argument.hasPrefix("-") {
                index += 1
                continue
            }
            return argument
        }
        return nil
    }

    /// `ref-tools-mcp@3.0.3` → `ref-tools-mcp`; `@scope/name@1.0.0` → `@scope/name`.
    ///
    /// The scoped case is why this is not `split(separator: "@").first`: a leading `@` is part of
    /// the name, so the separator is the **last** `@` that is not at index 0.
    static func packageName(_ spec: String) -> String {
        let searchFrom = spec.hasPrefix("@") ? spec.index(after: spec.startIndex) : spec.startIndex
        guard let at = spec[searchFrom...].lastIndex(of: "@") else { return spec }
        return String(spec[spec.startIndex ..< at])
    }
}
