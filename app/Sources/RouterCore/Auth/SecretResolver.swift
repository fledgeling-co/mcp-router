import Foundation

/// Resolves dynamic secret URIs (`warden://` and `op://`) on demand at upstream connection time.
///
/// Implements the router half of WAR-0057 / W1, replacing static credentials stored at rest
/// in `servers.json` with dynamic broker resolution.
public protocol SecretResolver: Sendable {
    /// Resolves a single secret URI or returns literal text unchanged.
    func resolve(_ value: String, reason: String) async throws -> String
}

/// A secret resolver that talks to the Warden CLI or socket IPC.
public struct WardenSecretResolver: SecretResolver {
    public let executablePath: String?
    public let socketPath: String?

    public init(executablePath: String? = nil, socketPath: String? = nil) {
        self.executablePath = executablePath
        self.socketPath = socketPath
    }

    /// Whether a value is a secret URI that requires dynamic resolution.
    public static func isSecretURI(_ value: String) -> Bool {
        value.hasPrefix("warden://") || value.hasPrefix("op://")
    }

    /// Resolves dynamic secret references within a string or header value.
    /// Handles both direct `warden://...` and Bearer-prefixed `Bearer warden://...`.
    public func resolve(_ value: String, reason: String) async throws -> String {
        if value.hasPrefix("Bearer ") {
            let uri = String(value.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespaces)
            if Self.isSecretURI(uri) {
                let resolved = try await resolveDirectURI(uri, reason: reason)
                return "Bearer \(resolved)"
            }
        }

        if Self.isSecretURI(value) {
            return try await resolveDirectURI(value, reason: reason)
        }

        return value
    }

    private func resolveDirectURI(_ uri: String, reason: String) async throws -> String {
        let binary = executablePath ?? Self.findWardenBinary()
        guard let binaryPath = binary, FileManager.default.isExecutableFile(atPath: binaryPath) else {
            let pathDesc = binary ?? "default paths"
            throw SecretResolutionError.brokerUnavailable("Warden executable not found at \(pathDesc)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        var args = ["resolve", uri, "--reason", reason, "--json"]
        if let sock = socketPath ?? ProcessInfo.processInfo.environment["WARDEN_SOCKET_PATH"] {
            args.append(contentsOf: ["--socket", sock])
        }
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw SecretResolutionError.brokerUnavailable(
                "Failed to spawn warden CLI: \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errText = (String(bytes: stderrData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = errText.isEmpty ? "warden resolve exited with \(process.terminationStatus)" : errText
            throw SecretResolutionError.resolutionFailed(uri: uri, reason: desc)
        }

        if let json = try? JSONParser.parse(stdoutData),
           case let .object(members) = json,
           let secretVal = members.first(where: { $0.key.string == "secret_value" })?.value,
           case let .string(secretStr) = secretVal
        {
            return secretStr.string
        }

        let raw = (String(bytes: stdoutData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw SecretResolutionError.resolutionFailed(uri: uri, reason: "Warden returned empty secret")
        }
        return raw
    }

    private static func findWardenBinary() -> String? {
        let candidates = [
            "/Applications/Warden.app/Contents/MacOS/warden",
            "/usr/local/bin/warden",
            "/opt/homebrew/bin/warden"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}

public enum SecretResolutionError: Error, LocalizedError, Equatable {
    case brokerUnavailable(String)
    case resolutionFailed(uri: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .brokerUnavailable(msg):
            "Secret broker unavailable: \(msg)"
        case let .resolutionFailed(uri, reason):
            "Failed to resolve secret URI '\(uri)': \(reason)"
        }
    }
}
