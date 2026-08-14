import Foundation
import MCPRouterKit
import Testing
@testable import MCPRouterUI

/// Structural guards over this feature's own source.
///
/// Each of these guards a rule that no runtime assertion can reach, and each states the failure it
/// catches. The scanning is deliberately done on source with **comments and string literals
/// stripped first** — the naive version matches its own documentation and then gets deleted for
/// being noisy, which is how a gate dies.
@Suite("Phone source guards")
struct PhoneSourceGuardTests {
    /// The repository root, found by walking up until `DESIGN.md` is beside us.
    static func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw GuardError.rootNotFound
    }

    enum GuardError: Error { case rootNotFound, nothingScanned }

    static func swiftFiles(under relativePath: String) throws -> [(name: String, source: String)] {
        let root = try repoRoot().appendingPathComponent(relativePath)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw GuardError.nothingScanned
        }
        var files: [(String, String)] = []
        for case let path as String in walker where path.hasSuffix(".swift") {
            let url = root.appendingPathComponent(path)
            files.append((path, try String(contentsOf: url, encoding: .utf8)))
        }
        // A scan that scanned nothing must not read as a pass — the same failure mode the lint
        // script and `make test` both guard against.
        guard !files.isEmpty else { throw GuardError.nothingScanned }
        return files
    }

    /// Remove `//` comments, `///` doc comments and string literals, so a rule cannot be tripped by
    /// prose that merely mentions the thing it forbids — and, more importantly, cannot be *evaded*
    /// by a value hidden in an interpolation.
    static func stripped(_ source: String) -> String {
        var out = ""
        for line in source.components(separatedBy: .newlines) {
            let withoutComment = line.components(separatedBy: "//").first ?? ""
            var inString = false
            var kept = ""
            for character in withoutComment {
                if character == "\"" { inString.toggle(); continue }
                if !inString { kept.append(character) }
            }
            out += kept + "\n"
        }
        return out
    }

    // MARK: A3 — no raw design value outside the one file allowed to write one

    /// `no-raw-design-values.sh` already forbids a colour literal and a numeric font size across
    /// both modules. It does not cover **spacing, radii and line heights**, which is where a phone
    /// layout's numbers actually live. `PhoneMetric` is the one file permitted to hold them, on the
    /// same argument the design system makes for its two binding files: a value has to be written
    /// somewhere, so it is written somewhere readable and forbidden everywhere else.
    @Test("no Phone view writes a spacing, radius or size number of its own")
    func noRawGeometryInViews() throws {
        let files = try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")
        #expect(files.count >= 6, "only \(files.count) phone files were scanned")

        // A numeric literal as the argument to any of the geometry modifiers.
        let pattern = try NSRegularExpression(
            pattern: #"\.(padding|spacing|cornerRadius|lineSpacing|frame|offset|inset|lineWidth|opacity)\s*\(\s*[^)]*?(?<![A-Za-z0-9_.])\d"#,
            options: [.dotMatchesLineSeparators]
        )

        for (name, source) in files where name != "PhoneMetric.swift" {
            let body = Self.stripped(source)
            let matches = pattern.matches(
                in: body,
                range: NSRange(body.startIndex..., in: body)
            )
            for match in matches {
                guard let range = Range(match.range, in: body) else { continue }
                let snippet = body[range].trimmingCharacters(in: .whitespacesAndNewlines)
                // `frame(maxWidth: .infinity)` and friends carry no number and never match; a
                // genuine literal does.
                Issue.record("\(name) writes a raw geometry value: \(snippet) — name a PhoneMetric")
            }
        }
    }

    /// The one place the numbers may live still has to *be* that place.
    @Test("PhoneMetric derives from the shared tokens where a token exists")
    func metricUsesTokensWhereTheyExist() {
        // The row and the tile are what the skeleton and the populated row share; if these two ever
        // stop agreeing, the board jumps when data lands.
        #expect(PhoneMetric.row == PhoneMetric.minimumTarget)
        #expect(PhoneMetric.tile == 30, "DESIGN.md §4: row tiles are 30pt")
        #expect(PhoneMetric.tileRadius == 7, "DESIGN.md §4: row tiles are radius 7")
        #expect(PhoneMetric.minimumTarget == 44)
    }

    // MARK: A2 — no badges

    /// A badge is a count, a count is observed data, and this feature observes none of it.
    @Test("nothing in the phone shell attaches a badge")
    func noBadges() throws {
        let files = try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone")
            + (try Self.swiftFiles(under: "app/MCPRouterIOS"))
        for (name, source) in files {
            let body = Self.stripped(source)
            #expect(!body.contains(".badge("), "\(name) attaches a badge")
            #expect(!body.contains("badgeValue"), "\(name) sets a badge value")
            #expect(!body.contains("applicationIconBadgeNumber"), "\(name) sets an app badge")
        }
    }

    // MARK: A19 — the scanner reads codes, never images

    /// The scanner's promise to the user is "no image is stored or sent anywhere". This is the half
    /// of that promise a static check can hold: no capture output that produces frames, and no API
    /// that would write or upload one. The other half — that the configured session really has one
    /// metadata output and nothing else — is asserted at runtime in the iOS suite, because a symbol
    /// list can always be evaded by a wrapper and a configured session cannot.
    @Test("the iOS target has no frame capture, no file write and no upload")
    func scannerCannotPersistOrUpload() throws {
        let forbidden = [
            "AVCaptureVideoDataOutput",
            "AVCapturePhotoOutput",
            "AVCaptureMovieFileOutput",
            "AVCaptureStillImageOutput",
            "PHPhotoLibrary",
            "UIImageWriteToSavedPhotosAlbum",
            "URLSession",
            "FileHandle",
            ".write(to:",
            "writeToFile"
        ]
        for (name, source) in try Self.swiftFiles(under: "app/MCPRouterIOS") {
            let body = Self.stripped(source)
            for symbol in forbidden {
                #expect(!body.contains(symbol), "\(name) references \(symbol)")
            }
        }
    }

    // MARK: A18 — the camera purpose string

    /// Declared in the source of truth. The *generated* plist is asserted in the iOS suite, which is
    /// the only place that proves what actually shipped — this one proves the input is right and is
    /// available even when nothing has been generated.
    @Test("project.yml declares a non-empty camera purpose string for the iOS target only")
    func cameraPurposeStringDeclared() throws {
        let yaml = try String(
            contentsOf: try Self.repoRoot().appendingPathComponent("app/project.yml"),
            encoding: .utf8
        )
        guard let range = yaml.range(of: "NSCameraUsageDescription:") else {
            Issue.record("project.yml does not declare NSCameraUsageDescription")
            return
        }
        let after = yaml[range.upperBound...].prefix(220)
        #expect(after.contains("camera"), "the purpose string does not describe the use")
        #expect(after.contains("pairing code"), "the purpose string does not say what is read")

        // The macOS app never opens a camera, and an unused purpose string is exactly the
        // over-declaration `SWIFT_PRACTICES.md` §6 rules out.
        let macSection = yaml.range(of: "MCPRouter:").map { yaml[$0.lowerBound...] }
        let iosStart = macSection?.range(of: "MCPRouterIOS:")
        if let macSection, let iosStart {
            let macOnly = macSection[..<iosStart.lowerBound]
            #expect(!macOnly.contains("NSCameraUsageDescription"), "the Mac target declares a camera string it never uses")
        }
    }

    // MARK: A22 — the Keychain accessibility class

    /// `ThisDeviceOnly` is load-bearing rather than incidental: the plain class travels in an
    /// encrypted backup, which would restore a pairing credential onto a device its owner never
    /// paired. A source check because the attribute is set once, at write time, and a round-trip
    /// test on the same device cannot tell the two classes apart.
    @Test("the pairing store binds the record to this device and to no other accessibility class")
    func keychainAccessibilityIsDeviceOnly() throws {
        let source = try String(
            contentsOf: try Self.repoRoot()
                .appendingPathComponent("app/Sources/MCPRouterKit/Pairing/PairingRecordStore.swift"),
            encoding: .utf8
        )
        let body = Self.stripped(source)
        #expect(body.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))

        for weaker in [
            "kSecAttrAccessibleAlways",
            "kSecAttrAccessibleWhenUnlocked\n",
            "kSecAttrAccessibleAfterFirstUnlock\n",
            "kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly"
        ] {
            #expect(!body.contains(weaker), "the store also uses \(weaker.trimmingCharacters(in: .newlines))")
        }
    }

    /// Nothing secret may reach a store that is not the Keychain.
    @Test("no pairing state is written to UserDefaults or a plist")
    func noPairingStateOutsideTheKeychain() throws {
        let files = try Self.swiftFiles(under: "app/Sources/MCPRouterKit/Pairing")
            + (try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone"))
            + (try Self.swiftFiles(under: "app/MCPRouterIOS"))
        for (name, source) in files {
            let body = Self.stripped(source)
            #expect(!body.contains("UserDefaults"), "\(name) touches UserDefaults")
            #expect(!body.contains("NSKeyedArchiver"), "\(name) archives to a file")
        }
    }

    // MARK: A9 — the Mac issues, the phone consumes

    /// There is no code generator on this side, and its absence is the guarantee. A phone that can
    /// mint a code is a phone that can pair itself.
    @Test("nothing on the phone generates a pairing code")
    func phoneNeverMintsACode() throws {
        let files = try Self.swiftFiles(under: "app/Sources/MCPRouterKit/Pairing")
            + (try Self.swiftFiles(under: "app/Sources/MCPRouterUI/Phone"))
        for (name, source) in files {
            let body = Self.stripped(source)
            for generator in ["randomElement", "SecRandomCopyBytes", "UUID(", "arc4random", ".shuffled("] {
                #expect(!body.contains(generator), "\(name) can generate a code with \(generator)")
            }
        }
    }
}
