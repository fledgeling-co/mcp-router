import Foundation

// Prints the addresses the Mac app itself says it ships, one row per address:
//
//     <axis>\t<address>\t<label>\t<state>\t<detail>
//
// where `axis` is `destination` or `sheet`, `address` is the stable key the campaign binds a
// surface to, and `state` is `shipped` for something the build can actually present or
// `declared:<owner>` for a sheet kind the type names and no board hosts yet.
//
// **Compiled against the shipped `Destination.swift` and `RouterSheet.swift` rather than parsing
// them**, so what this prints is the answer the app gives rather than a reading of its text. Two
// facts here are unreachable by a parser and both of them decide a row:
//
//   · `Destination.title` is a `switch` that does not follow the case names — `.evals` reads
//     `Checks`. A `case`-line scraper prints `Evals`, and the campaign's own surface is called
//     `Mac Checks board`. M35 measured exactly this one file over and had the same reason.
//   · `RouterSheet.Kind.isHosted` is computed from `owner`, another `switch`. Whether a sheet kind
//     is something the build presents or something M22 still owes is not visible in the
//     declaration at all — every one of the sixteen looks identical as a `case` line. A gate that
//     could not tell them apart would demand campaign coverage of three sheets that do not exist.
//
// The two lists grow when the enums grow, with nothing to edit: `Destination.ordered` is
// `allCases` and `Kind.allCases` is `CaseIterable`, both compiler-generated from the declarations.
// That is the whole point — a destination cannot be added to this app without appearing here, and
// therefore without the reconciler noticing that no campaign surface claims it.
//
// `@main` rather than top-level code because top-level statements are only legal in `main.swift`,
// and this file is named for what it reads.
@main
enum SurfaceOracle {
    static func main() {
        let destinations = Destination.ordered
        let sheetKinds = RouterSheet.Kind.allCases

        // Guarded SEPARATELY, not as one combined emptiness check. An oracle that printed sheets
        // and no destinations would let the reconciler pass with an empty destination axis — zero
        // shipped destinations, therefore zero unenumerated ones, therefore green. That is the
        // stale answer wearing the derivation's clothes, which is the failure this whole file is
        // about. Both axes have had cases since M1, so either being empty is a broken oracle
        // rather than a small app.
        guard !destinations.isEmpty else {
            FileHandle.standardError.write(Data("Destination.ordered is empty\n".utf8))
            exit(2)
        }
        guard !sheetKinds.isEmpty else {
            FileHandle.standardError.write(Data("RouterSheet.Kind.allCases is empty\n".utf8))
            exit(2)
        }

        for destination in destinations {
            print([
                "destination",
                "destination:\(destination.rawValue)",
                destination.title,
                "shipped",
                destination.group.rawValue,
            ].joined(separator: "\t"))
        }

        for kind in sheetKinds {
            // `owner` is non-nil exactly when the kind is drawn in the mock and no board can
            // present it. Reported rather than filtered out, so a kind that acquires a host shows
            // up as newly shipped instead of appearing from nowhere.
            let state = kind.isHosted ? "shipped" : "declared:\(kind.owner ?? "unknown")"
            print([
                "sheet",
                "sheet:\(kind.rawValue)",
                kind.rawValue,
                state,
                kind.rawValue.hasPrefix("-") ? "build-only" : "in-mock",
            ].joined(separator: "\t"))
        }
    }
}
