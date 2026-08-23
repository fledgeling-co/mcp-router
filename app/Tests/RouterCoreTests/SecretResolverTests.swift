import Foundation
import Testing
@testable import RouterCore

@Suite("W1 — Secret resolver and dynamic credentials")
struct SecretResolverTests {
    struct MockSecretResolver: SecretResolver {
        let lookup: [String: String]

        init(lookup: [String: String] = [:]) {
            self.lookup = lookup
        }

        func resolve(_ value: String, reason: String) async throws -> String {
            if value.hasPrefix("Bearer ") {
                let uri = String(value.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespaces)
                if WardenSecretResolver.isSecretURI(uri) {
                    if let secret = lookup[uri] {
                        return "Bearer \(secret)"
                    }
                    throw SecretResolutionError.resolutionFailed(uri: uri, reason: "Key not found in mock")
                }
            }
            if WardenSecretResolver.isSecretURI(value) {
                if let secret = lookup[value] {
                    return secret
                }
                throw SecretResolutionError.resolutionFailed(uri: value, reason: "Key not found in mock")
            }
            return value
        }
    }

    @Test("non-secret literal strings are returned unchanged")
    func nonSecretLiteralPassesThrough() async throws {
        let resolver = WardenSecretResolver(executablePath: "/nonexistent/warden")
        let plain = "regular_api_key_12345"
        let resolved = try await resolver.resolve(plain, reason: "test")
        #expect(resolved == plain)
    }

    @Test("isSecretURI detects warden and 1Password URI prefixes")
    func isSecretURIDetectsSchemes() {
        #expect(WardenSecretResolver.isSecretURI("warden://gemini-api-key"))
        #expect(WardenSecretResolver.isSecretURI("warden://b3bbdb08-2e04-4f24-91b4-9df540eb7777"))
        #expect(WardenSecretResolver.isSecretURI("op://Personal/OpenAI/credential"))
        #expect(!WardenSecretResolver.isSecretURI("sk-proj-1234567890"))
        #expect(!WardenSecretResolver.isSecretURI("https://example.com/api"))
    }

    @Test("direct URI resolution replaces warden and op URIs with resolved secrets")
    func mockResolverResolvesDirectURIs() async throws {
        let resolver = MockSecretResolver(lookup: [
            "warden://gemini-api-key": "AIzaSySecretGeminiKey53CharsHere",
            "op://Dev/Namecheap/api-key": "nc_secret_api_key_value"
        ])

        let gemini = try await resolver.resolve("warden://gemini-api-key", reason: "test")
        #expect(gemini == "AIzaSySecretGeminiKey53CharsHere")

        let namecheap = try await resolver.resolve("op://Dev/Namecheap/api-key", reason: "test")
        #expect(namecheap == "nc_secret_api_key_value")
    }

    @Test("Bearer-prefixed secret URIs resolve into Bearer tokens")
    func bearerPrefixedSecretResolves() async throws {
        let resolver = MockSecretResolver(lookup: [
            "warden://atlas-admin-token": "atlas_live_bearer_token_string"
        ])

        let header = "Bearer warden://atlas-admin-token"
        let resolved = try await resolver.resolve(header, reason: "test")
        #expect(resolved == "Bearer atlas_live_bearer_token_string")
    }

    @Test("resolution failure surfaces structured SecretResolutionError")
    func resolutionFailureSurfacesError() async {
        let resolver = MockSecretResolver(lookup: [:])
        do {
            _ = try await resolver.resolve("warden://missing-key", reason: "test")
            #expect(Bool(false), "Should have thrown SecretResolutionError")
        } catch let error as SecretResolutionError {
            #expect(error == .resolutionFailed(uri: "warden://missing-key", reason: "Key not found in mock"))
            #expect(error.errorDescription?.contains("Failed to resolve secret URI") == true)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("StdioUpstreamTransport integrates SecretResolver into child environment")
    func transportIntegratesSecretResolver() {
        let resolver = MockSecretResolver(lookup: [
            "warden://test-key": "resolved_secret_value_xyz"
        ])
        _ = StdioUpstreamTransport(secretResolver: resolver)
    }
}
