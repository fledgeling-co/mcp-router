#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Which destinations have a board, and which are still the shell's honest placeholder.
    ///
    /// The orchestrator's condition on the scaffold copy was that it must not be able to survive
    /// into a Release build of a shipped surface, preferably as something enforced rather than
    /// promised. This is the enforcement, in three parts:
    ///
    /// 1. **Structural.** `ScaffoldedDestination` is failable and refuses to exist for a destination
    ///    in `installed`, so the placeholder cannot be constructed for a surface that has shipped —
    ///    not "should not", cannot.
    /// 2. **Tested.** `ShellIntegrationTests` asserts the two sets are exact complements in both
    ///    directions, so shipping a board without retiring its scaffold fails, and so does the
    ///    reverse.
    /// 3. **In the binary.** `scripts/acceptance/mac-shell.sh` reads this list out of the source and
    ///    requires the Release bundle to carry the scaffold copy **iff** the list is non-empty. When
    ///    the last board lands, a Release build still containing the sentence fails the gate.
    ///
    /// M1 installs no boards, which is the whole point of it: the shell is the deliverable and the
    /// seven boards are seven other items.
    public enum BoardRegistry {
        /// Destinations whose real surface is compiled into this build.
        ///
        /// M2–M8 each add exactly one entry here alongside the view that justifies it. M3 added
        /// `.servers`, and this line is the whole difference between a board that exists and a board
        /// the user can reach: without it `ContentZone` still renders the placeholder, however
        /// complete the view is.
        public static let installed: Set<Destination> = [.servers, .skills]

        public static func hasBoard(_ destination: Destination) -> Bool {
            installed.contains(destination)
        }

        /// The destinations still showing the placeholder, in sidebar order.
        public static var scaffolded: [Destination] {
            Destination.ordered.filter { !hasBoard($0) }
        }
    }

    /// Permission to render the placeholder, which only a destination without a board can obtain.
    ///
    /// A plain `Destination` parameter would let a future edit hand the scaffold a shipped surface
    /// and nothing would object until someone noticed the sentence on screen. This makes that a
    /// `nil` at the call site instead.
    public struct ScaffoldedDestination: Equatable, Sendable {
        public let destination: Destination

        public init?(_ destination: Destination) {
            guard !BoardRegistry.hasBoard(destination) else { return nil }
            self.destination = destination
        }
    }

    /// The copy the scaffold renders, held as data so the gate can read it out of source.
    public enum ScaffoldCopy {
        /// The sentence the Release gate greps for. Deliberately one literal, in one place.
        public static let sentinel = "isn't built yet"

        public static func title(for destination: Destination) -> String {
            "\(destination.title) \(sentinel)"
        }

        /// Names what *is* here and what the missing part is waiting on, rather than apologising.
        /// No action control: the thing that would fix this is another item shipping, which is not
        /// something a button can do.
        public static func detail(for destination: Destination) -> String {
            """
            This build ships the window, its menus and its keyboard. \
            The \(destination.title.lowercased()) surface arrives with the item that owns it.
            """
        }
    }

    /// The honest per-destination placeholder.
    struct ScaffoldPane: View {
        let scaffolded: ScaffoldedDestination

        private var destination: Destination { scaffolded.destination }

        var body: some View {
            VStack(spacing: MetricToken.selectionRadius.leadingScalar) {
                IconView(Icon(rawValue: destination.iconName) ?? .conduit, size: TypeToken.title1.size)
                    .foregroundStyle(ColorToken.t3.color)
                Text(ScaffoldCopy.title(for: destination))
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                Text(ScaffoldCopy.detail(for: destination))
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: MetricToken.sidebar.leadingScalar * 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
#endif
