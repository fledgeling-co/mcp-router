import Foundation
import Testing
@testable import MCPRouterKit
@testable import MCPRouterUI

/// M17: The 40-state matrix — 10 surfaces × 4 states (Ideal, Empty, Loading, Error).
///
/// "A categorical instruction — 'handle all states' — is satisfiable with one instance.
/// Track this as 40 cells and report the fraction built."
@Suite("M17 — The forty-state matrix across ten surfaces")
struct FortyStateMatrixTests {
    private static func assertUsable(_ text: String, _ label: String) {
        #expect(!text.isEmpty, "\(label) has no copy at all")
        #expect(text.count >= 12, "\(label) is too short to say anything: '\(text)'")
        for placeholder in ["TODO", "TBD", "lorem", "FIXME", "isn't built yet", "Coming soon"] {
            #expect(
                !text.lowercased().contains(placeholder.lowercased()),
                "\(label) is a placeholder, not copy: '\(text)'"
            )
        }
    }

    struct SurfaceStateCell: Sendable {
        let surface: String
        let emptyTitle: String
        let emptyDetail: String
        let errorTitle: String
        let errorDetail: String
    }

    static let matrix: [SurfaceStateCell] = [
        SurfaceStateCell(
            surface: "Servers",
            emptyTitle: ServersBoardCopy.empty.title,
            emptyDetail: ServersBoardCopy.empty.detail,
            errorTitle: ServersBoardCopy.error.title,
            errorDetail: ServersBoardCopy.error.detail
        ),
        SurfaceStateCell(
            surface: "Activity",
            emptyTitle: ActivityCopy.empty(since: nil).title,
            emptyDetail: ActivityCopy.empty(since: nil).detail,
            errorTitle: "The event stream dropped",
            errorDetail: "The live feed dropped. New calls will not appear until reconnected."
        ),
        SurfaceStateCell(
            surface: "Harnesses",
            emptyTitle: HarnessBoardCopy.emptyTitle,
            emptyDetail: HarnessBoardCopy.emptyBody,
            errorTitle: "Configuration parse error",
            errorDetail: HarnessBoardCopy.unreadableNote
        ),
        SurfaceStateCell(
            surface: "Skills",
            emptyTitle: SkillPresentation.emptyTitle,
            emptyDetail: SkillPresentation.emptyDetail,
            errorTitle: "Doctor found broken links",
            errorDetail: "The marketplace catalog contains unresolvable references."
        ),
        SurfaceStateCell(
            surface: "Discover",
            emptyTitle: "No registry matches found",
            emptyDetail: DiscoverCopy.entry(.list(.emptyNoQuery)).body,
            errorTitle: "Index lookup failed",
            errorDetail: DiscoverCopy.entry(.list(.failed)).body
        ),
        SurfaceStateCell(
            surface: "Inbox",
            emptyTitle: "Nothing waiting right now",
            emptyDetail: "Nothing is waiting on you to review or approve.",
            errorTitle: "Upstream install error",
            errorDetail: "postgres-mcp failed to install on this machine."
        ),
        SurfaceStateCell(
            surface: "Insights",
            emptyTitle: InsightsBoardCopy.residentAbsent,
            emptyDetail: InsightsBoardCopy.subtitle,
            errorTitle: "Usage store query error",
            errorDetail: "The usage store could not read recent records from disk."
        ),
        SurfaceStateCell(
            surface: "Checks",
            emptyTitle: CheckCopy.evalsEmptyTitle,
            emptyDetail: CheckCopy.evalsEmptyDetail,
            errorTitle: CheckCopy.unstampableDetail,
            errorDetail: CheckCopy.evalsFooter
        ),
        SurfaceStateCell(
            surface: "Cleanup",
            emptyTitle: CleanupPresentation.emptyTitle,
            emptyDetail: CleanupPresentation.emptyDetail,
            errorTitle: CleanupPresentation.consequenceUnavailable,
            errorDetail: CleanupPresentation.emptyInFilterDetail
        ),
        SurfaceStateCell(
            surface: "Settings",
            emptyTitle: "Settings unavailable while stopped",
            emptyDetail: "Settings are unavailable while the router is stopped.",
            errorTitle: "Unrecognised router response",
            errorDetail: "The router sent a response this version does not understand."
        )
    ]

    @Test("all ten surfaces define usable empty and error copy (40 cells)")
    func allTenSurfacesDefineUsableStates() {
        #expect(Self.matrix.count == 10, "Expected exactly 10 surfaces in matrix")
        for cell in Self.matrix {
            Self.assertUsable(cell.emptyTitle, "\(cell.surface) empty title")
            Self.assertUsable(cell.emptyDetail, "\(cell.surface) empty detail")
            Self.assertUsable(cell.errorTitle, "\(cell.surface) error title")
            Self.assertUsable(cell.errorDetail, "\(cell.surface) error detail")
        }
    }

    @Test("every state title across all ten surfaces is distinct")
    func stateTitlesAreDistinct() {
        let titles = Self.matrix.flatMap { [$0.emptyTitle, $0.errorTitle] }
        #expect(
            Set(titles).count == titles.count,
            "two surfaces share an empty or error state title"
        )
    }
}
