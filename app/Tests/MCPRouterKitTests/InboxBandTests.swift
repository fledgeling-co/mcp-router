import Foundation
import Testing
@testable import MCPRouterKit

/// The menu-bar inbox band, as a value — which is what makes its states assertable at all.
///
/// Every clause here is a call to `InboxBand.make` or `InboxAnnouncement.make` with constructed
/// inputs. Nothing renders, nothing polls, and no notification centre is involved, which is the
/// point: `spec-I6.md`'s state matrix is a matrix over values.
@Suite("I6 · the menu-bar inbox band")
struct InboxBandTests {
    static let now = Date(timeIntervalSince1970: 1_770_000_000)
    static let device = "Luke's iPhone"

    /// A resolved entry, decoded rather than built, because `RegistryEntry` has no public
    /// initialiser and inventing one for a test would widen the shipping surface.
    static func entry(id: String, stdio: Bool = true) throws -> RegistryEntry {
        let install = stdio
            ? #"{"type":"stdio","command":"node","args":["server.js"]}"#
            : #"{"type":"http","url":"https://example.com/mcp"}"#
        let json = """
        {"id":"\(id)","name":"\(id)","displayName":"Local notes","description":"d",
         "source":"official","install":\(install)}
        """
        return try JSONDecoder().decode(RegistryEntry.self, from: Data(json.utf8))
    }

    static func item(
        id: String,
        queuedSecondsAgo: TimeInterval,
        resolved: RegistryEntry? = nil,
        name: String = "From the phone"
    ) -> InboxItem {
        InboxItem(
            envelope: InboxEnvelope(
                version: 1,
                id: id,
                entryID: "entry-\(id)",
                displayName: name,
                queuedAt: now.addingTimeInterval(-queuedSecondsAgo),
                deviceName: device
            ),
            resolved: resolved
        )
    }

    // MARK: - A1 · absent, not empty

    /// The clause the type's optionality exists for, and the same device `PopoverContent.band`
    /// uses: a view test cannot tell a hidden band from a band rendering zero rows, because both
    /// draw nothing. A nil-versus-empty assertion can.
    @Test("nothing waiting produces no band at all, never a band of zero rows")
    func emptyIsAbsent() {
        #expect(InboxBand.make(waiting: [], device: Self.device, now: Self.now) == nil)
        #expect(InboxBand.make(waiting: [], device: nil, now: Self.now) == nil)
    }

    @Test("one waiting item produces one row and no overflow")
    func oneItem() throws {
        let band = try #require(
            InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 120, resolved: Self.entry(id: "e"))],
                device: Self.device,
                now: Self.now
            )
        )
        #expect(band.rows.count == 1)
        #expect(band.overflow == 0)
        #expect(band.rows[0].id == "q-1")
    }

    // MARK: - A2 · the cap never hides a count

    @Test("more than the cap draws the cap and states the remainder")
    func manyItems() throws {
        let items = (1 ... 7).map { Self.item(id: "q-\($0)", queuedSecondsAgo: Double(1000 - $0)) }
        let band = try #require(InboxBand.make(waiting: items, device: Self.device, now: Self.now))

        #expect(band.rows.count == MenuBarPresentation.inboxBandLimit)
        #expect(band.overflow == 7 - MenuBarPresentation.inboxBandLimit)
        // The true total is in the header line, so capping the rows never hides how many there are.
        #expect(band.headline.contains("7"))
        #expect(InboxCopy.Band.overflow(band.overflow).contains("\(7 - MenuBarPresentation.inboxBandLimit)"))
    }

    // MARK: - A3 · oldest first

    /// The ordering is the opposite of the pane's, and deliberately: a band is a queue you drain
    /// from the front, and — the load-bearing half — newest-first inserts an arrival at index 0 and
    /// pushes every row down one while the popover is open.
    ///
    /// Asserted on a list whose **array order and time order differ**, so a build that forwarded
    /// the caller's ordering, or the pane's newest-first, fails rather than passing by coincidence.
    @Test("rows are oldest first, whatever order the caller held them in")
    func oldestFirst() throws {
        let items = [
            Self.item(id: "newest", queuedSecondsAgo: 10),
            Self.item(id: "oldest", queuedSecondsAgo: 900),
            Self.item(id: "middle", queuedSecondsAgo: 400)
        ]
        let band = try #require(InboxBand.make(waiting: items, device: Self.device, now: Self.now))
        #expect(band.rows.map(\.id) == ["oldest", "middle", "newest"])
    }

    // MARK: - A4 · an arrival moves nothing

    /// The state the brief names by hand: an item arrives while the popover is already open.
    ///
    /// The assertion is not that the new row appears — it is that **every row that was already on
    /// screen keeps its index**. That is what stops a press landing on the wrong item, and it is
    /// the entire reason the ordering above is what it is.
    @Test("an item arriving while the popover is open displaces no row already on screen")
    func arrivalAppends() throws {
        let before = [
            Self.item(id: "a", queuedSecondsAgo: 600),
            Self.item(id: "b", queuedSecondsAgo: 300)
        ]
        let after = before + [Self.item(id: "c", queuedSecondsAgo: 1)]

        let first = try #require(InboxBand.make(waiting: before, device: Self.device, now: Self.now))
        let second = try #require(InboxBand.make(waiting: after, device: Self.device, now: Self.now))

        #expect(second.rows.count == first.rows.count + 1)
        for (index, row) in first.rows.enumerated() {
            #expect(second.rows[index].id == row.id, "row \(index) moved when something arrived")
        }
        #expect(second.rows.last?.id == "c")
    }

    /// And at or above the cap it does not render at all — only the counts change, so the rows on
    /// screen are byte-identical.
    @Test("an arrival past the cap changes the counts and none of the rows")
    func arrivalPastTheCap() throws {
        let full = (1 ... 3).map { Self.item(id: "q-\($0)", queuedSecondsAgo: Double(900 - $0 * 10)) }
        let first = try #require(InboxBand.make(waiting: full, device: Self.device, now: Self.now))
        let second = try #require(
            InboxBand.make(
                waiting: full + [Self.item(id: "late", queuedSecondsAgo: 1)],
                device: Self.device,
                now: Self.now
            )
        )
        #expect(second.rows == first.rows)
        #expect(second.overflow == 1)
        #expect(first.overflow == 0)
    }

    // MARK: - A5 · one wording, one source

    /// `DESIGN.md` §6 asks for one name per state taken from one source rather than spelled twice.
    /// The popover and the pane are two surfaces describing one queue.
    @Test("the header line is the pane's own subtitle, byte for byte")
    func headlineIsThePanesSubtitle() throws {
        for (count, device) in [(1, Self.device), (4, Self.device), (2, nil)] as [(Int, String?)] {
            let items = (0 ..< count).map { Self.item(id: "q-\($0)", queuedSecondsAgo: Double($0 + 1)) }
            let band = try #require(InboxBand.make(waiting: items, device: device, now: Self.now))
            #expect(band.headline == InboxCopy.subtitle(waiting: count, device: device))
        }
    }

    // MARK: - A6 · above the attention band

    /// Stated as a value rather than measured on a screenshot. The reason it is above is structural:
    /// the attention band's length is unbounded, so an inbox band after it can be pushed below the
    /// fold on a Mac with several held changes.
    @Test("the inbox zone renders above the attention band")
    func inboxOutranksAttention() throws {
        let band = try #require(
            InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 5)],
                device: Self.device,
                now: Self.now
            )
        )
        let content = PopoverContent(
            counts: MenuBarPresentation.Counts(running: 1, idle: 0, tools: 2),
            band: [MenuBarPresentation.AttentionRow(server: "s", cause: .heldChange)],
            inbox: .band(band)
        )
        let zones = content.zones
        let inbox = try #require(zones.firstIndex(of: .inbox))
        let attention = try #require(zones.firstIndex(of: .attention))
        #expect(inbox < attention)
        #expect(zones.first == .header)
        #expect(zones.last == .footer)
    }

    // MARK: - A9 · the phone describes nothing

    /// The security property the whole envelope design turns on, carried onto the popover and the
    /// notification: the phone names *which* entry it means, and the Mac reads what that entry does.
    @Test("a resolved row's capability line is the Mac's own reading of the entry")
    func capabilityComesFromTheRegistry() throws {
        let entry = try Self.entry(id: "e-1")
        let band = try #require(
            InboxBand.make(
                waiting: [Self.item(
                    id: "q-1",
                    queuedSecondsAgo: 60,
                    resolved: entry,
                    name: "PHONE SAID THIS"
                )],
                device: Self.device,
                now: Self.now
            )
        )
        #expect(band.rows[0].capability == RegistryCapability.statement(for: entry).headline)
        #expect(band.rows[0].capability == "Runs a program on this Mac")
        // The phone's name is not rendered for a resolved item: the Mac shows what it read, because
        // that is the name attached to the thing that would actually run.
        #expect(band.rows[0].title == entry.displayName)
        #expect(band.rows[0].title != "PHONE SAID THIS")
    }

    @Test("an unresolved row has no capability line and keeps the name the phone displayed")
    func partialRow() throws {
        let band = try #require(
            InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 60, resolved: nil, name: "Withdrawn entry")],
                device: Self.device,
                now: Self.now
            )
        )
        #expect(band.rows[0].capability == nil)
        #expect(band.rows[0].isPartial)
        #expect(band.rows[0].title == "Withdrawn entry")
    }

    // MARK: - The status item

    /// A second reason for the same dot rather than a second dot. Both conditions end in a human
    /// deciding something, so the bar still carries no count and still one colour.
    @Test("a queued item takes the menu-bar dot, in the same colour and with no count")
    func queuedItemTakesTheDot() {
        #expect(!MenuBarPresentation.statusItemNeedsAttention([], waiting: 0))
        #expect(MenuBarPresentation.statusItemNeedsAttention([], waiting: 1))
        #expect(MenuBarPresentation.statusItemDotToken == .attention)
        #expect(MenuBarPresentation.statusItemLabel([], waiting: 0) == "MCP Router")
        #expect(MenuBarPresentation.statusItemLabel([], waiting: 1) == "MCP Router, 1 item needs a decision")
        #expect(MenuBarPresentation.statusItemLabel([], waiting: 4) == "MCP Router, 4 items need a decision")
        for waiting in [0, 1, 12] {
            let label = MenuBarPresentation.statusItemLabel([], waiting: waiting)
            #expect(!label.hasPrefix("\(waiting)"), "the bar's own glyph must carry no count")
        }
    }
}
