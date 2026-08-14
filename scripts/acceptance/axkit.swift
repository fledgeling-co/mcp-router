import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// The M1 acceptance harness's hands and eyes, in one binary.
//
// **Everything here works on a background window on purpose.** `planning/practices/UI_VERIFICATION.md`
// forbids the developer loop from taking the user's screen, and the previous version of this gate
// took it repeatedly: it launched with `open` (which activates), and re-issued
// `tell application … to activate` before every keystroke, because synthetic events delivered
// through System Events only reach a frontmost app.
//
// The routes below were each measured on 2026-08-14 against this build with Ghostty frontmost
// throughout, and the frontmost application is asserted unchanged by the script that drives them:
//
// - reading the whole accessibility tree, including the **complete menu bar with help tags**, needs
//   no activation and no menu to be opened — SwiftUI's `CommandGroup` items were all present;
// - `CGEvent.postToPid` delivers a bare key to a background app's focused responder;
// - setting `AXSelectedRows` on the sidebar outline moves the selection;
// - setting the content scroll area's vertical scroll bar `AXValue` scrolls it;
// - `AXPosition` / `AXSize` on the window are settable, so a move and resize needs no mouse.
//
// One route does **not** work in the background, and it is recorded rather than worked around:
// `AXPress` on a menu item returns `.success` and does nothing, because the item's action reaches
// the window through `@FocusedValue` and an inactive app has no focused scene. That is why A23's
// command→operation link moved into `ShellCommandRouter`, where a unit test can reach it.

let args = CommandLine.arguments

func die(_ message: String, _ code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("axkit: \(message)\n".utf8))
    exit(code)
}

func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func string(_ element: AXUIElement, _ name: String) -> String {
    guard let value = attr(element, name) else { return "" }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}

func boolField(_ element: AXUIElement, _ name: String) -> String {
    guard let value = attr(element, name), let n = value as? NSNumber else { return "" }
    return n.boolValue ? "1" : "0"
}

func pair(_ element: AXUIElement, _ name: String) -> (Double, Double)? {
    guard let value = attr(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    // swiftlint:disable:next force_cast
    let axValue = value as! AXValue
    if AXValueGetType(axValue) == .cgPoint {
        var p = CGPoint.zero
        if AXValueGetValue(axValue, .cgPoint, &p) { return (Double(p.x), Double(p.y)) }
    }
    if AXValueGetType(axValue) == .cgSize {
        var s = CGSize.zero
        if AXValueGetValue(axValue, .cgSize, &s) { return (Double(s.width), Double(s.height)) }
    }
    return nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attr(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

/// Every string an element and its descendants announce, joined — what a screen reader would say
/// for a row. Used to name a sidebar row, whose title lives on a child rather than on the row.
func spokenText(_ element: AXUIElement, depth: Int = 0) -> String {
    var parts: [String] = []
    func collect(_ e: AXUIElement, _ d: Int) {
        guard d < 5 else { return }
        for name in [
            kAXTitleAttribute as String,
            kAXValueAttribute as String,
            kAXDescriptionAttribute as String
        ] {
            let text = string(e, name)
            if !text.isEmpty, !parts.contains(text) { parts.append(text) }
        }
        for child in children(e) {
            collect(child, d + 1)
        }
    }
    collect(element, depth)
    return parts.joined(separator: "|")
}

func application(_ pidArgument: String) -> (pid_t, AXUIElement) {
    guard let pid = pid_t(pidArgument) else { die("bad pid '\(pidArgument)'") }
    return (pid, AXUIElementCreateApplication(pid))
}

/// The app's ordinary window — not the Debug design gallery.
func standardWindow(_ app: AXUIElement) -> AXUIElement? {
    let windows = (attr(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    return windows.first { string($0, kAXSubroleAttribute as String) == "AXStandardWindow" } ?? windows.first
}

func firstElement(in root: AXUIElement, role: String, last: Bool = false) -> AXUIElement? {
    var found: AXUIElement?
    func walk(_ e: AXUIElement, _ d: Int) {
        guard d < 24 else { return }
        if string(e, kAXRoleAttribute as String) == role {
            if last { found = e } else if found == nil { found = e; return }
        }
        for c in children(e) {
            walk(c, d + 1)
        }
    }
    walk(root, 0)
    return found
}

func bitmap(_ path: String) -> NSBitmapImageRep? {
    guard let image = NSImage(contentsOfFile: path), let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

guard args.count >= 2 else { die("usage: axkit <command> …") }

switch args[1] {
// ------------------------------------------------------------------ observation

case "trusted":
    print(AXIsProcessTrusted() ? "yes" : "no")

case "session":
    let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    let locked = (d["CGSSessionScreenIsLocked"] as? Int) ?? 0
    let onConsole = (d["kCGSSessionOnConsoleKey"] as? Int) ?? 0
    if d.isEmpty { print("nosession") } else if locked == 1 { print("locked") }
    else if onConsole != 1 { print("notconsole") } else { print("ok") }

case "front":
    // The guard the whole gate rests on: if this ever answers "MCP Router", the run took the screen.
    print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")

case "dump":
    guard args.count >= 4 else { die("usage: axkit dump <pid> window|menu") }
    guard AXIsProcessTrusted() else { die("not trusted for accessibility") }
    let (_, app) = application(args[2])
    var rows = 0
    func emit(_ element: AXUIElement, depth: Int) {
        let pos = pair(element, kAXPositionAttribute as String) ?? (-1, -1)
        let size = pair(element, kAXSizeAttribute as String) ?? (-1, -1)
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        let fields = [
            "\(depth)",
            string(element, kAXRoleAttribute as String),
            string(element, kAXSubroleAttribute as String),
            clean(string(element, kAXTitleAttribute as String)),
            clean(string(element, kAXValueAttribute as String)),
            clean(string(element, kAXDescriptionAttribute as String)),
            clean(string(element, kAXHelpAttribute as String)),
            boolField(element, kAXEnabledAttribute as String),
            boolField(element, kAXSelectedAttribute as String),
            clean(string(element, "AXMenuItemCmdChar")),
            clean(string(element, "AXMenuItemCmdModifiers")),
            clean(string(element, kAXIdentifierAttribute as String)),
            String(format: "%.1f", pos.0), String(format: "%.1f", pos.1),
            String(format: "%.1f", size.0), String(format: "%.1f", size.1),
            boolField(element, kAXFocusedAttribute as String)
        ]
        print(fields.joined(separator: "\t"))
        rows += 1
        guard depth < 24 else { return }
        for child in children(element) {
            emit(child, depth: depth + 1)
        }
    }
    switch args[3] {
    case "window":
        guard let window = standardWindow(app) else { die("no windows") }
        emit(window, depth: 0)
    case "menu":
        guard let bar = attr(app, "AXMenuBar") else { die("no menu bar") }
        // swiftlint:disable:next force_cast
        emit(bar as! AXUIElement, depth: 0)
    default: die("unknown dump mode")
    }
    if rows == 0 { die("walked zero elements") }

case "selected":
    // Which sidebar rows report themselves selected, by what they announce.
    let (_, app) = application(args[2])
    guard let window = standardWindow(app), let outline = firstElement(in: window, role: "AXOutline") else {
        die("no sidebar outline")
    }
    let selected = (attr(outline, "AXSelectedRows") as? [AXUIElement]) ?? []
    for row in selected {
        print(spokenText(row))
    }

case "title":
    let (_, app) = application(args[2])
    guard let window = standardWindow(app) else { die("no window") }
    print(string(window, kAXTitleAttribute as String))

case "frame":
    let (_, app) = application(args[2])
    guard let window = standardWindow(app) else { die("no window") }
    let p = pair(window, kAXPositionAttribute as String) ?? (-1, -1)
    let s = pair(window, kAXSizeAttribute as String) ?? (-1, -1)
    print(String(format: "%.0f,%.0f,%.0f,%.0f", p.0, p.1, s.0, s.1))

case "winid":
    // The CGWindowID, for `screencapture -l` — the only capture that photographs *this* window
    // rather than whatever is on top of its screen region.
    guard let pid = pid_t(args[2]) else { die("bad pid") }
    let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
    for window in (info as? [[String: Any]]) ?? [] {
        guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
              (window[kCGWindowLayer as String] as? Int) == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let height = bounds["Height"] as? Double, height > 100,
              let id = window[kCGWindowNumber as String] as? Int else { continue }
        print(id)
        exit(0)
    }
    die("no on-screen window for pid \(args[2])")

// ------------------------------------------------------------------ background-safe actuation

case "select":
    // Moves the sidebar selection by setting the row's own `AXSelected`. Background-safe, and it
    // is the same attribute a screen-reader user's selection sets.
    guard args.count >= 4 else { die("usage: axkit select <pid> <row prefix>") }
    let (_, app) = application(args[2])
    guard let window = standardWindow(app), let outline = firstElement(in: window, role: "AXOutline") else {
        die("no sidebar outline")
    }
    let rows = children(outline).filter { string($0, kAXRoleAttribute as String) == "AXRow" }
    guard let row = rows.first(where: { spokenText($0).hasPrefix(args[3]) }) else {
        die("no sidebar row starting '\(args[3])'", 1)
    }
    let result = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
    print(result == .success ? "OK" : "ERR \(result.rawValue)")
    if result != .success { exit(1) }

case "press":
    // `AXPress` on the first button whose accessibility **description** contains a substring.
    //
    // Background-safe, and measured to be so: a SwiftUI `Button`'s AXPress runs its action directly
    // on the element and needs no focused scene. That is the difference from a **menu item**, whose
    // action reaches the window through `@FocusedValue` — an inactive app has no focused scene, so
    // AXPress there returns `.success` and does nothing. This verb is deliberately restricted to
    // buttons for that reason, and a caller wanting a menu item should not reach for it.
    //
    // The description rather than the title, because SwiftUI puts a `Button`'s `accessibilityLabel`
    // there — measured against this app on 2026-08-14, where every list row reported an empty title
    // and a full description.
    guard args.count >= 4 else { die("usage: axkit press <pid> <description substring>") }
    let (_, pressApp) = application(args[2])
    guard let pressWindow = standardWindow(pressApp) else { die("no window") }
    var pressed = false
    func pressMatching(_ element: AXUIElement) {
        if pressed { return }
        if string(element, kAXRoleAttribute as String) == "AXButton",
           string(element, kAXDescriptionAttribute as String).contains(args[3])
        {
            pressed = AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
            if pressed { return }
        }
        for child in children(element) {
            pressMatching(child)
        }
    }
    pressMatching(pressWindow)
    print(pressed ? "OK" : "ERR")
    if !pressed { exit(1) }

case "key":
    // A key event delivered to one process. Unlike a System Events keystroke this does not require
    // the app to be frontmost, and it cannot land in whatever app the user is actually using.
    guard args.count >= 4, let pid = pid_t(args[2]), let code = UInt16(args[3]) else {
        die("usage: axkit key <pid> <keycode> [cmd]")
    }
    var flags: CGEventFlags = []
    if args.count > 4, args[4] == "cmd" { flags.insert(.maskCommand) }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else {
        die("could not build a key event")
    }
    down.flags = flags
    up.flags = flags
    down.postToPid(pid)
    usleep(60000)
    up.postToPid(pid)
    print("sent")

case "scroll":
    // Scrolls the content zone by setting its scroll bar's value. A scroll-wheel event posted to
    // the pid was measured to be dropped, and warping the cursor to scroll would move the user's
    // pointer — this moves neither.
    guard args.count >= 4, let fraction = Double(args[3]) else { die("usage: axkit scroll <pid> <0…1>") }
    let (_, app) = application(args[2])
    guard let window = standardWindow(app),
          let area = firstElement(in: window, role: "AXScrollArea", last: true),
          let barRef = attr(area, "AXVerticalScrollBar") else { die("no content scroll area") }
    // swiftlint:disable:next force_cast
    let bar = barRef as! AXUIElement
    let result = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: fraction))
    print(result == .success ? "OK" : "ERR \(result.rawValue)")
    if result != .success { exit(1) }

case "rowrect":
    // The screen rectangle of one sidebar row, so a pixel measurement has somewhere to look.
    guard args.count >= 4 else { die("usage: axkit rowrect <pid> <row prefix>") }
    let (_, app) = application(args[2])
    guard let window = standardWindow(app), let outline = firstElement(in: window, role: "AXOutline") else {
        die("no sidebar outline")
    }
    let rows = children(outline).filter { string($0, kAXRoleAttribute as String) == "AXRow" }
    guard let row = rows.first(where: { spokenText($0).hasPrefix(args[3]) }) else {
        die("no sidebar row starting '\(args[3])'", 1)
    }
    let p = pair(row, kAXPositionAttribute as String) ?? (-1, -1)
    let s = pair(row, kAXSizeAttribute as String) ?? (-1, -1)
    print(String(format: "%.0f,%.0f,%.0f,%.0f", p.0, p.1, s.0, s.1))

case "focus":
    // Moves keyboard focus to the sidebar, so A24 can compare a focused row with an unfocused one.
    // `AXFocused` is settable on the outline, which is how a screen-reader user's focus moves there,
    // and it needs no activation.
    let (_, app) = application(args[2])
    guard let window = standardWindow(app), let outline = firstElement(in: window, role: "AXOutline") else {
        die("no sidebar outline")
    }
    let result = AXUIElementSetAttributeValue(outline, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    print(result == .success ? "OK" : "ERR \(result.rawValue)")
    if result != .success { exit(1) }

case "accent":
    // Counts accent-coloured pixels in a rectangle, and reports the longest unbroken horizontal run
    // of them and where it starts.
    //
    // A24 asks for a *rendered* measurement of keyboard focus — visible, accent-bound, 2pt. Colour
    // is matched by dominance rather than by an exact hex, deliberately: `ColorToken.accent` is
    // composited over a translucent sidebar material, so its rendered value is not its authored one
    // and pinning the blend would pin the appearance instead of the meaning. Blue clearly ahead of
    // both other channels is what "accent" means here and what no other shell colour satisfies —
    // `live` is green, `attention` orange, `fail` red, and every tier is neutral.
    guard args.count >= 8, let rep = bitmap(args[2]),
          let x0 = Int(args[3]), let x1 = Int(args[4]), let y0 = Int(args[5]), let y1 = Int(args[6]),
          let margin = Double(args[7])
    else {
        die("usage: axkit accent <png> <x0> <x1> <y0> <y1> <margin>")
    }
    var total = 0
    var bestRun = 0
    var bestRunX = -1
    var bestRunY = -1
    for y in y0 ... min(y1, rep.pixelsHigh - 1) {
        var run = 0
        for x in x0 ... min(x1, rep.pixelsWide - 1) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let isAccent = c.blueComponent - c.redComponent > margin
                && c.blueComponent - c.greenComponent > margin
            if isAccent {
                total += 1
                run += 1
                if run > bestRun { bestRun = run; bestRunX = x - run + 1; bestRunY = y }
            } else {
                run = 0
            }
        }
    }
    print("\(total) \(bestRun) \(bestRunX) \(bestRunY)")

case "setframe":
    guard args.count >= 7 else { die("usage: axkit setframe <pid> <x> <y> <w> <h>") }
    let (_, app) = application(args[2])
    guard let window = standardWindow(app) else { die("no window") }
    var origin = CGPoint(x: Double(args[3]) ?? 0, y: Double(args[4]) ?? 0)
    var size = CGSize(width: Double(args[5]) ?? 0, height: Double(args[6]) ?? 0)
    guard let originValue = AXValueCreate(.cgPoint, &origin),
          let sizeValue = AXValueCreate(.cgSize, &size) else { die("could not build the frame values") }
    let a = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
    let b = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    print(a == .success && b == .success ? "OK" : "ERR \(a.rawValue)/\(b.rawValue)")
    if a != .success || b != .success { exit(1) }

case "hidden":
    // Used once, as the proof that macOS dispatches a ⌘-chord to this app while it is inactive.
    guard let pid = pid_t(args[2]), let running = NSRunningApplication(processIdentifier: pid) else {
        print("gone")
        exit(0)
    }
    if args.count > 3 {
        switch args[3] {
        case "unhide": running.unhide()
        // Hiding is how this gate pushes the app **out** of the front without activating anything
        // else. macOS promotes a background app to frontmost on its own when whatever was in front
        // goes away, and observed on 2026-08-14 that is exactly what happened mid-run: another app
        // took focus, dropped it, and this one inherited it. `hide()` removes it from the front and
        // `unhide()` brings its windows back **without** activating — the pair is the only way to
        // correct that without taking the screen for something else.
        case "hide": running.hide()
        default: break
        }
    }
    print(running.isHidden ? "hidden" : "visible")

case "terminate":
    // A graceful quit that does not activate the app, unlike `tell application … to quit`.
    guard let pid = pid_t(args[2]), let running = NSRunningApplication(processIdentifier: pid) else {
        print("gone")
        exit(0)
    }
    print(running.terminate() ? "OK" : "REFUSED")

// ------------------------------------------------------------------ pixels

case "sample":
    guard args.count >= 5, let rep = bitmap(args[2]), let x = Int(args[3]),
          let y = Int(args[4]) else { die("bad sample") }
    guard x < rep.pixelsWide, y < rep.pixelsHigh,
          let c = rep.colorAt(x: x, y: y) else { die("sample out of range") }
    print(String(
        format: "#%02X%02X%02X",
        Int((c.redComponent * 255).rounded()),
        Int((c.greenComponent * 255).rounded()),
        Int((c.blueComponent * 255).rounded())
    ))

case "uniform":
    // The dominant colour of one row of pixels, and what share of the row it covers.
    //
    // This is what identifies a hairline. A separator is a **uniform** line across the whole content
    // width; content scrolling under the top edge is not. An earlier version of the A34 assertion
    // compared before/after pixel counts, which a completeness critic correctly showed could not
    // tell the two apart — and the negative control that was added to check it promptly failed,
    // confirming the band was tracking content.
    guard args.count >= 6, let rep = bitmap(args[2]),
          let x0 = Int(args[3]), let x1 = Int(args[4]), let y = Int(args[5])
    else {
        die("usage: axkit uniform <png> <x0> <x1> <y>")
    }
    guard y >= 0, y < rep.pixelsHigh else { die("row \(y) is outside the image") }
    var counts: [String: Int] = [:]
    var total = 0
    for x in x0 ... min(x1, rep.pixelsWide - 1) {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        let key = String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
        counts[key, default: 0] += 1
        total += 1
    }
    guard total > 0, let best = counts.max(by: { $0.value < $1.value }) else { die("no pixels sampled") }
    print(String(format: "%@ %.3f", best.key, Double(best.value) / Double(total)))

case "banddiff":
    // How much of one row of pixels changed between two captures, across a horizontal span.
    //
    // A hairline that appears under the toolbar changes a whole row at once; content moving behind
    // it changes a scattered few. Reporting the *best row* and its fraction is what lets the script
    // assert the separator's signature rather than "some pixels differ", which a scroll produces
    // anywhere.
    guard args.count >= 8, let a = bitmap(args[2]), let b = bitmap(args[3]),
          let x0 = Int(args[4]), let x1 = Int(args[5]), let y0 = Int(args[6]), let y1 = Int(args[7])
    else {
        die("usage: axkit banddiff <a.png> <b.png> <x0> <x1> <y0> <y1>")
    }
    var bestRow = -1
    var bestFraction = 0.0
    for y in y0 ... y1 where y < min(a.pixelsHigh, b.pixelsHigh) {
        var changed = 0
        var counted = 0
        for x in stride(from: x0, through: min(x1, min(a.pixelsWide, b.pixelsWide) - 1), by: 1) {
            guard let ca = a.colorAt(x: x, y: y), let cb = b.colorAt(x: x, y: y) else { continue }
            counted += 1
            if abs(ca.redComponent - cb.redComponent) > 0.002
                || abs(ca.greenComponent - cb.greenComponent) > 0.002
                || abs(ca.blueComponent - cb.blueComponent) > 0.002 { changed += 1 }
        }
        guard counted > 0 else { continue }
        let fraction = Double(changed) / Double(counted)
        if fraction > bestFraction { bestFraction = fraction; bestRow = y }
    }
    print(String(format: "%d %.3f", bestRow, bestFraction))

default:
    die("unknown command '\(args[1])'")
}
