import ApplicationServices
import Foundation

// Every attribute name a process's menu bar exposes, with its value, for every element in it.
//
// `axkit dump` emits a **fixed seventeen columns**, which is the right shape for asserting on
// things we know are there and the wrong shape for asking whether something is there at all: an
// attribute it does not name is invisible to it, and its absence from the output says nothing.
// This asks the tree what it has, rather than asking it for a list of names decided in advance —
// so a badge exposed under any name at all, on the item or on a child of it, appears here.
//
// usage: axattrs <pid>
// output: TSV — depth, role, title, attribute, value

let args = CommandLine.arguments
guard args.count >= 2, let pid = Int32(args[1]) else {
    FileHandle.standardError.write(Data("usage: axattrs <pid>\n".utf8))
    exit(2)
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("axattrs: not trusted for accessibility\n".utf8))
    exit(2)
}

let app = AXUIElementCreateApplication(pid)

func copy(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func describe(_ value: CFTypeRef?) -> String {
    guard let value else { return "<nil>" }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    if let a = value as? [Any] { return "<array \(a.count)>" }
    if CFGetTypeID(value) == AXUIElementGetTypeID() { return "<element>" }
    if CFGetTypeID(value) == AXValueGetTypeID() {
        // Decoded rather than stamped `<axvalue>`, because the width of a menu item is the one
        // number on this plane that is about **layout** rather than about annotation — whether
        // AppKit reserved room for a badge, a chord, or both.
        // swiftlint:disable:next force_cast
        let axValue = value as! AXValue
        switch AXValueGetType(axValue) {
        case .cgSize:
            var size = CGSize.zero
            AXValueGetValue(axValue, .cgSize, &size)
            return String(format: "%.1fx%.1f", size.width, size.height)
        case .cgPoint:
            var point = CGPoint.zero
            AXValueGetValue(axValue, .cgPoint, &point)
            return String(format: "%.1f,%.1f", point.x, point.y)
        case .cgRect:
            var rect = CGRect.zero
            AXValueGetValue(axValue, .cgRect, &rect)
            return String(
                format: "%.1f,%.1f %.1fx%.1f",
                rect.origin.x,
                rect.origin.y,
                rect.width,
                rect.height
            )
        default: return "<axvalue>"
        }
    }
    return "\(value)"
}

func names(_ element: AXUIElement) -> [String] {
    var raw: CFArray?
    guard AXUIElementCopyAttributeNames(element, &raw) == .success else { return [] }
    return (raw as? [String]) ?? []
}

func clean(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
}

func walk(_ element: AXUIElement, depth: Int) {
    let role = describe(copy(element, kAXRoleAttribute as String))
    let title = describe(copy(element, kAXTitleAttribute as String))
    for name in names(element) {
        // Children are walked rather than printed as `<array N>`, and skipping the name here keeps
        // the row count honest about how many *annotations* an item carries.
        if name == kAXChildrenAttribute as String { continue }
        print(
            "\(depth)\t\(clean(role))\t\(clean(title))\t\(name)\t\(clean(describe(copy(element, name as String))))"
        )
    }
    guard depth < 12 else { return }
    let children = (copy(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    for child in children {
        walk(child, depth: depth + 1)
    }
}

guard let bar = copy(app, "AXMenuBar") else {
    FileHandle.standardError.write(Data("axattrs: no menu bar for pid \(pid)\n".utf8))
    exit(1)
}

// swiftlint:disable:next force_cast
walk(bar as! AXUIElement, depth: 0)
