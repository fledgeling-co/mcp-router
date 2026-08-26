// Can this session composite a window at all?
//
// Three of the eight acceptance lanes drive a real macOS window and read it back through
// CGWindowList. In a session that cannot composite — no logged-in GUI seat, a locked screen, a
// runner attached over ssh — those lanes do not fail an assertion about the product: they never
// see a window, time out, and report a harness state as if it were a verdict. That is `G4`'s
// class, and the whole of this item.
//
// So the aggregator prints this count beside its table. It is a condition of the measurement,
// not a measurement: two runs of the same eight lanes on the same commit legitimately disagree
// when this number is 0 on one of them, and a table that does not carry it cannot be compared
// with another table at all.
//
// It counts every on-screen window in the session, not this app's — the question is whether the
// window server is reachable and returning, which is answered before MCP Router launches.
import CoreGraphics
import Foundation

let info = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []
let named = info.filter { ($0[kCGWindowName as String] as? String)?.isEmpty == false }
print("\(info.count) \(named.count)")
