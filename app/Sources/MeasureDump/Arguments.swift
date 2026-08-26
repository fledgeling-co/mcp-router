//
//  The command line this harness takes, and what it refuses.
//
//  Split out of `main.swift` when that file passed 400 lines. The parse is the half of the tool
//  that has nothing to do with rendering: it decides *what* to measure and says what it could not
//  honour, and `main.swift` decides how.
//
#if MEASURE && os(macOS)

    import Foundation
    import MCPRouterUI
    import SwiftUI

    struct Arguments {
        var surface: Surface = .servers
        var state: State = .ideal
        var appearance: ColorScheme = .dark
        var appearanceName = "dark"
        var width = 1280.0
        var height = 820.0
        var output = "planning/fidelity/servers.dump.json"
        /// How long the run loop is spun for the layout to settle, in seconds.
        var settle = 1.5
        /// The base URL of a **running** router to fetch `.readme`'s content from, instead of
        /// M19's fixture.
        ///
        /// M30 added a second implementation of `CapabilityDocumentSource` that reads a real
        /// package through the control API, and nothing rendered it: the `.readme` arm below builds
        /// `FixtureCapabilityDocumentSource`, so every dump and every capture of that panel — M23's
        /// included — is a picture of a JSON file in this repository. That is a measurement of the
        /// *layout* and it was never anything else, but it means no one had seen the panel draw a
        /// document a router actually served.
        ///
        /// Naming a URL here swaps the fixture for `ControlAPICapabilityDocumentSource` against
        /// that router. It is opt-in and it is never a default, because a harness that silently
        /// reached for the network would make M23's fidelity dumps depend on whether a daemon
        /// happened to be up.
        var documentFrom: URL?
        /// Which server on that router to ask for. Only read when `documentFrom` is set.
        var documentServer = "m30-look"
        /// Where to write a PNG of the hosted view, if anywhere.
        ///
        /// Rendered off the hosting view with `cacheDisplay(in:to:)` rather than photographed off
        /// the screen. `UI_VERIFICATION.md` rule 1 forbids taking the user's display, and a
        /// `screencapture` of a region photographs whatever is on top of it rather than the window
        /// meant — this path needs no visible window at all, so there is nothing to steal and
        /// nothing to occlude the subject.
        var png: String?
        /// Every argument this could not honour, in the words it would report them in.
        ///
        /// Collected rather than defaulted away. An unreadable `--surface` used to fall back to the
        /// only surface there is and an unreadable `--state` to `ideal`, so `--state loadng` wrote a
        /// dump of the ideal frame into `servers.loadng.json` and the tool exited 0 — a measurement
        /// of a surface nobody asked for, reported as a success. That is the same shape as a layer
        /// that could not run reading as agreement, one level below the gate, and the fix is the
        /// same: say what could not be honoured and exit 3.
        var rejected: [String] = []

        /// A number a frame can actually be laid out at.
        private static func positive(_ text: String) -> Double? {
            guard let value = Double(text), value > 0 else { return nil }
            return value
        }

        /// A duration. Zero is allowed: it means "read whatever one layout pass produced".
        private static func nonNegative(_ text: String) -> Double? {
            guard let value = Double(text), value >= 0 else { return nil }
            return value
        }

        static func parse(_ argv: [String]) -> Arguments {
            var out = Arguments()
            var i = 0
            while i < argv.count {
                let key = argv[i]
                let value = i + 1 < argv.count ? argv[i + 1] : nil
                i += out.apply(key, value) ? 2 : 1
            }
            return out
        }

        /// Applies one argument, or records why it could not be.
        ///
        /// The groups below are the tool's four kinds of argument — what to draw, how big, where it
        /// goes, and M30's live-document pair. One switch over all eleven read as a single decision
        /// and was one over the complexity limit; each group is small enough to see whole, and a key
        /// belonging to none of them is the only case that does not consume a value.
        ///
        /// - Returns: whether `value` was consumed, so the caller knows how far to step.
        private mutating func apply(_ key: String, _ value: String?) -> Bool {
            if applySubject(key, value) { return true }
            if applyFrame(key, value) { return true }
            if applyOutput(key, value) { return true }
            if applyDocument(key, value) { return true }
            rejected.append("'\(key)' is not an argument this tool takes")
            return false
        }

        /// What to draw: the surface, its drawn state, and the appearance to resolve colours in.
        private mutating func applySubject(_ key: String, _ value: String?) -> Bool {
            switch key {
            case "--surface":
                surface = take(key, value, Self.oneOf(Surface.allCases), Surface.init(rawValue:))
                    ?? surface
            case "--state":
                state = take(key, value, Self.oneOf(State.allCases), State.init(rawValue:)) ?? state
            case "--appearance":
                let parsed = take(
                    key, value, Self.oneOf(Appearance.allCases), Appearance.init(rawValue:)
                )
                appearance = parsed.map { $0 == .light ? .light : .dark } ?? appearance
                appearanceName = parsed?.rawValue ?? appearanceName
            default:
                return false
            }
            return true
        }

        /// How big to draw it, and how long to let it settle.
        private mutating func applyFrame(_ key: String, _ value: String?) -> Bool {
            switch key {
            case "--width":
                width = take(key, value, "a positive number", Self.positive) ?? width
            case "--height":
                height = take(key, value, "a positive number", Self.positive) ?? height
            case "--settle":
                settle = take(key, value, "a non-negative number", Self.nonNegative) ?? settle
            default:
                return false
            }
            return true
        }

        /// Where what it drew is written.
        private mutating func applyOutput(_ key: String, _ value: String?) -> Bool {
            switch key {
            case "--out":
                output = take(key, value, "a path", Self.nonEmpty) ?? output
            case "--png":
                png = take(key, value, "a path", Self.nonEmpty) ?? png
            default:
                return false
            }
            return true
        }

        /// M30's pair: the router to read `.readme`'s document from, and which server to ask for.
        private mutating func applyDocument(_ key: String, _ value: String?) -> Bool {
            switch key {
            case "--document-from":
                documentFrom = take(key, value, "a URL") { URL(string: $0) } ?? documentFrom
            case "--document-server":
                documentServer = take(key, value, "a name", Self.nonEmpty) ?? documentServer
            default:
                return false
            }
            return true
        }

        /// Reads `value` through `convert`, or records why it could not be and returns nil.
        private mutating func take<T>(
            _ key: String, _ value: String?, _ expected: String, _ convert: (String) -> T?
        ) -> T? {
            guard let value else {
                rejected.append("\(key) was given no value")
                return nil
            }
            guard let converted = convert(value) else {
                rejected.append("\(key) '\(value)' is not \(expected)")
                return nil
            }
            return converted
        }

        /// A path. The empty string is refused rather than treated as "wherever the default was".
        private static func nonEmpty(_ text: String) -> String? {
            text.isEmpty ? nil : text
        }

        /// The values an enum-backed argument accepts, in the words the refusal prints them in.
        private static func oneOf(_ cases: some Collection<some RawRepresentable<String>>) -> String {
            "one of " + cases.map(\.rawValue).joined(separator: ", ")
        }
    }

#endif
