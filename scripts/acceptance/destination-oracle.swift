import Foundation

// Prints the app's own destination list, one row per destination, in sidebar order:
//
//     <rawValue>\t<title>\t<group>
//
// **Compiled against the shipped `Destination.swift` rather than parsing it**, so what this prints
// is the answer the app itself gives. `title` in particular is a `switch` the sidebar, the window
// title and the View menu all read, and it does not follow the case names — `.evals` reads
// `Checks`. A reader that scraped `case` lines would have printed `Evals` and been wrong about the
// one destination whose label was deliberately renamed away from its identifier.
//
// This exists because `mac-shell.sh` hand-named the destination set in three places and a fourth
// counted it by parsing. M22 shipped `harnesses` and `insights`; none of the four followed, and the
// lane contradicted itself inside one run — passing *9 destination rows share one height* from the
// parsed count and *all seven destinations are in the accessibility tree* from a hand-written list,
// two lines of the same output disagreeing about how many destinations the app has. The list here
// grows when `Destination` grows, with nothing to edit.
//
// `Destination.ordered` is `allCases`, which the compiler generates from the declaration, so a
// destination cannot be added without appearing here.
// `@main` rather than top-level code because top-level statements are only legal in a file called
// `main.swift`, and this file is named for what it reads.
@main
enum DestinationOracle {
    static func main() {
        let destinations = Destination.ordered

        // An empty list is a broken oracle, never an empty app: `Destination` has had cases since M1, and
        // every caller below turns this into a `for` loop. An empty one would run zero assertions and
        // report a pass — the stale answer wearing the derivation's clothes, which is the failure this
        // whole change is about.
        guard !destinations.isEmpty else {
            FileHandle.standardError.write(Data("Destination.ordered is empty\n".utf8))
            exit(2)
        }

        for destination in destinations {
            print([destination.rawValue, destination.title, destination.group.rawValue].joined(separator: "\t"))
        }
    }
}
