import Foundation

/// Decides whether an image a document names may be shown, and where it is.
///
/// **An image reference is a request to fetch something, and the document making it is untrusted.**
/// The brief's rule is that images resolve from inside the downloaded package and from nowhere
/// else: a remote reference would tell a third party which capability is being read — the same
/// exposure a shield opens — and a `file:` or absolute reference would put an arbitrary path on the
/// disk in front of a reader who is looking at a marketplace document.
///
/// So one function, three refusals, and every one of them named. A refusal is drawn as a
/// placeholder carrying its reason rather than being dropped: the reader learns the document
/// pointed somewhere the app would not go, which is a thing worth knowing about a package you are
/// deciding whether to install.
///
/// This is the only file in the item that computes a filesystem path, and it lives in the kit for
/// the reason `SWIFT_PRACTICES.md` §8 gives — the view layer must not reach past the control API,
/// so a resolved image arrives at the view as bytes rather than as a path it could open.
public enum PackageImageResolver {
    /// Why a reference was not resolved. Each case is user-facing copy's input, so each one is a
    /// distinct thing that happened rather than a shared "invalid".
    public enum Refusal: Error, Equatable, Sendable {
        /// The reference carries a scheme — `https:`, `data:`, `file:` — so it points outside the
        /// package by construction.
        case remote(scheme: String)
        /// An absolute filesystem path. Inside the package or not, the document does not get to
        /// name one.
        case absolutePath
        /// A relative path that climbs out of the package root.
        case escapesPackage
        /// Resolved inside the package, and nothing is there.
        case notInPackage
        /// Inside the package and not a kind this app renders as an image. A boundary rather than a
        /// convenience: an image reference is a request to read a file, and `svg` is a document
        /// format that can carry script.
        case unsupportedType(extension: String)
        /// Read, and larger than the transport will send. `limitBytes` is the cap it hit, which is
        /// what makes the sentence say **which** rule refused it rather than only that one did.
        case tooLarge(limitBytes: Int)
        /// The response's shared image budget was spent before this reference was reached.
        case budgetExhausted
        /// A refusal this version of the app does not recognise, kept rather than dropped.
        ///
        /// A router newer than this app can name a reason that did not exist when this was built.
        /// Dropping it would draw the figure as though nothing had happened; keeping it says the
        /// document pointed somewhere the router would not go, which is the part worth knowing.
        case unrecognised(reason: String)

        /// What the placeholder says. Present tense, states what happened, no blame, and it says
        /// what the app did rather than what the document did wrong (`DESIGN.md` §6).
        public var sentence: String {
            switch self {
            case let .remote(scheme):
                "Not shown — this image is loaded from \(scheme), and nothing here reaches the network."
            case .absolutePath:
                "Not shown — this image names a path on your Mac rather than a file in the package."
            case .escapesPackage:
                "Not shown — this image points outside the package it came with."
            case .notInPackage:
                "Not shown — the package does not contain this image."
            case let .unsupportedType(ext):
                ext.isEmpty
                    ? "Not shown — this file has no extension, so it is not a kind this app draws."
                    : "Not shown — this app doesn't draw \(ext) files."
            case let .tooLarge(limitBytes):
                "Not shown — this image is larger than the \(limitBytes / 1024) KB the router will send."
            case .budgetExhausted:
                "Not shown — this document's images together exceed what the router will send."
            case let .unrecognised(reason):
                "Not shown — the router refused this image, and this version doesn't know \(reason)."
            }
        }
    }

    /// Resolves one reference against one package root.
    ///
    /// - Parameters:
    ///   - reference: the reference exactly as the document wrote it.
    ///   - root: the directory the package was unpacked into.
    public static func resolve(
        _ reference: String,
        inPackageAt root: URL
    ) -> Result<URL, Refusal> {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)

        // A scheme is decided before anything else, because `URL(fileURLWithPath:)` will happily
        // treat `https://example.com/a.png` as a relative path called `https:` and then resolve it
        // inside the package — a remote reference laundered into a local one.
        if let scheme = URL(string: trimmed)?.scheme, !scheme.isEmpty {
            return .failure(.remote(scheme: scheme.lowercased()))
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return .failure(.absolutePath)
        }

        // Both sides standardised **and symlink-resolved**, then compared on **path components**
        // rather than on a string prefix. Three separate ways this check is written wrong, and all
        // three are closed here:
        //
        //   * `/pkg-evil/x.png` has `/pkg` as a string prefix and is not inside `/pkg`.
        //   * `URL(fileURLWithPath:relativeTo:)` resolves against the base's **parent** unless the
        //     base was built with `isDirectory: true`, so `docs/a.png` under `/pkg` landed at
        //     `/tmp/docs/a.png` — outside the package, and every legitimate reference was refused.
        //     Measured, not reasoned about: it is why this appends a component instead.
        //   * a package can ship a **symlink** pointing out of itself, which standardising alone
        //     does not see. A downloaded archive is exactly where one comes from.
        let base = URL(fileURLWithPath: root.path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let candidate = base.appendingPathComponent(trimmed)
            .standardizedFileURL.resolvingSymlinksInPath()
        let baseParts = base.pathComponents
        let candidateParts = candidate.pathComponents
        guard candidateParts.count > baseParts.count,
              Array(candidateParts.prefix(baseParts.count)) == baseParts
        else {
            return .failure(.escapesPackage)
        }

        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return .failure(.notInPackage)
        }
        return .success(candidate)
    }
}
