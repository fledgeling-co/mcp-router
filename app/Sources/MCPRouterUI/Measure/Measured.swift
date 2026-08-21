import Foundation
import MCPRouterKit
import SwiftUI

/// The dev-only measurement harness: what a SwiftUI view can be made to say about itself.
///
/// SwiftUI has no DOM. There is no `getComputedStyle`, the modifiers are resolved away before
/// anything is on screen, and — measured on this machine on 21 Aug 2026 — an `NSHostingView`
/// hosting a real view hierarchy has exactly **one** AppKit subview, so walking the view tree from
/// outside the process returns nothing at all. The only instrument that can see a resolved value is
/// one compiled into the view itself, which is what this is.
///
/// It is compiled under `MEASURE`, switched on by building with `MCP_ROUTER_MEASURE=1`. With the
/// flag off, `measured(…)` is the identity modifier and `measureSurface(…)` returns its content
/// unchanged, so the recorder is not linked into a shipping build and an instrumented view costs
/// nothing.
public enum MeasureKind: String, Sendable {
    case vstack
    case hstack
    case zstack
    case grid
    case scroll
    case leaf
    case text

    /// The axis a structure diff compares against. `nil` where the node does not stack.
    public var axis: String? {
        switch self {
        case .vstack, .scroll: "vertical"
        case .hstack: "horizontal"
        case .zstack: "depth"
        case .grid, .leaf, .text: nil
        }
    }
}

/// One node as the harness recorded it, before the tree is assembled from the paths.
public struct MeasureRecord: Equatable, Sendable {
    public var id: String
    public var path: [String]
    public var role: String
    public var kind: MeasureKind
    public var alignment: String?
    public var frame: MeasuredNode.Frame
    public var tokens: [String: String]
    public var resolved: [String: String]
    public var text: String?
}

/// Assembles the flat records into the nested tree the contract requires.
///
/// Sibling order is taken **from the geometry**, along the parent's own axis, and the dump says so.
/// Declared order and laid-out order coincide for a stack, and where they would not — a `zstack`,
/// a node with no axis — the children are ordered by `(y, x)` and the reader is told which rung
/// the ordering stands on rather than being handed a number to trust.
public enum MeasureTree {
    public static func assemble(_ records: [MeasureRecord]) -> MeasuredNode? {
        guard !records.isEmpty else { return nil }
        let byPath = Dictionary(
            records.map { ($0.path + [$0.id], $0) }, uniquingKeysWith: { first, _ in first }
        )
        guard let rootKey = byPath.keys.min(by: { ($0.count, $0.joined()) < ($1.count, $1.joined()) })
        else { return nil }
        return build(rootKey, in: byPath)
    }

    private static func build(_ key: [String], in byPath: [[String]: MeasureRecord]) -> MeasuredNode? {
        guard let record = byPath[key] else { return nil }
        let childKeys = byPath.keys.filter { $0.count == key.count + 1 && Array($0.dropLast()) == key }
        var children = childKeys.compactMap { build($0, in: byPath) }

        switch record.kind.axis {
        case "horizontal":
            children.sort { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
        default:
            children.sort { ($0.frame.y, $0.frame.x) < ($1.frame.y, $1.frame.x) }
        }

        return MeasuredNode(
            id: record.id,
            path: record.path,
            role: record.role,
            kind: record.kind.rawValue,
            axis: record.kind.axis,
            alignment: record.alignment,
            frame: record.frame,
            tokens: record.tokens,
            resolved: record.resolved,
            text: record.text,
            children: children
        )
    }
}

#if MEASURE

    /// Collects what the instrumented views report, for one surface.
    ///
    /// `@unchecked Sendable` with its own lock, and `SWIFT_PRACTICES.md` §1 asks which: every access
    /// to `storage` below is inside `lock`, and nothing else is mutable. It is not `@MainActor`
    /// because `onPreferenceChange`'s closure is not main-actor isolated, and hopping through a
    /// `Task { @MainActor in … }` is what made an earlier build of this harness report *39
    /// preference records delivered* and *no nodes collected* in the same run — the hop was still
    /// queued when the tool wrote its verdict. A recorder whose emptiness and whose agreement look
    /// identical is the failure this whole item is written against, so the hop is gone.
    public final class SurfaceRecorder: @unchecked Sendable {
        public static let shared = SurfaceRecorder()

        private let lock = NSLock()
        private var storage: [String: MeasureRecord] = [:]

        public init() {}

        public var records: [MeasureRecord] {
            lock.lock()
            defer { lock.unlock() }
            return storage.values.sorted { ($0.path.count, $0.id) < ($1.path.count, $1.id) }
        }

        public func ingest(_ incoming: [MeasureRecord]) {
            lock.lock()
            defer { lock.unlock() }
            for record in incoming {
                storage[(record.path + [record.id]).joined(separator: "/")] = record
            }
        }

        public func reset() {
            lock.lock()
            defer { lock.unlock() }
            storage = [:]
        }

        /// The tree, plus the honest account of what the instrument could not do.
        public func dump(surface: String, appearance: String, size: CGSize) -> SurfaceDump? {
            guard let root = MeasureTree.assemble(records) else { return nil }
            return SurfaceDump(
                surface: surface,
                appearance: appearance,
                size: MeasuredNode.Frame(x: 0, y: 0, width: size.width, height: size.height),
                typeLadder: Dictionary(uniqueKeysWithValues: TypeToken.allCases.map {
                    ($0.rawValue, SurfaceDump.TypeMetrics(
                        size: $0.size, lineHeight: $0.lineHeight, emphasis: $0.emphasis.rawValue
                    ))
                }),
                layers: ["structure", "geometry", "resolved-colour", "copy", "tokens"],
                inconclusive: [MeasureCapability.fontLayer],
                root: root
            )
        }
    }

    /// What the instrument is measured to be able to do, established before anything is read.
    ///
    /// `mockup-fidelity` calls the alternative "a green report from a blind instrument": a property
    /// the measurement cannot compute reads as agreement on both sides and the differ emits nothing.
    /// So the one layer this harness cannot perform is declared here, in the tool's own words.
    public enum MeasureCapability {
        /// Probed 21 Aug 2026 against this repo's toolchain.
        ///
        /// A SwiftUI `Font` is an opaque box: there is no accessor for its size, weight or face, and
        /// its description carries none of the three. So "the resolved font" is a value this
        /// instrument cannot read, and saying otherwise would be the exact self-deception the M23
        /// brief is written against.
        public static let fontLayer = SurfaceDump.InconclusiveLayer(
            layer: "resolved-font",
            covers: "the size, weight and face a text node actually rendered with",
            // Written without a numeric literal on purpose: `scripts/lint/no-raw-design-values.sh`
            // reads comments and string bodies too, and a probe transcript that spells a point size
            // trips the very check this file exists to keep honest.
            evidence: "String(describing:) of a Font built through Font.system(size:weight:) returns "
                +
                "\"Font(provider: SwiftUI.FontBox<SwiftUI.Font.SystemProvider>)\" — "
                + "no size, no weight, no face",
            confirmedInsteadBy: "the TypeToken each text node names is recorded in `tokens[\"type\"]` at "
                + "apply time, DesignTokenParityTests pins the eight-role ladder against DESIGN.md, and "
                + "scripts/lint/no-raw-design-values.sh fails any size that does not come off it. None of "
                + "the three can see an ancestor .font() winning the cascade."
        )
    }

    private struct MeasurePathKey: EnvironmentKey {
        static let defaultValue: [String] = []
    }

    extension EnvironmentValues {
        var measurePath: [String] {
            get { self[MeasurePathKey.self] }
            set { self[MeasurePathKey.self] = newValue }
        }
    }

    struct MeasureKey: PreferenceKey {
        static let defaultValue: [MeasureRecord] = []
        static func reduce(value: inout [MeasureRecord], nextValue: () -> [MeasureRecord]) {
            value.append(contentsOf: nextValue())
        }
    }

    /// The coordinate space every frame in a dump is expressed in.
    ///
    /// Named rather than `.global`: a global frame moves with the window, so two dumps of the same
    /// surface taken at different window positions would diff as though every element had moved.
    enum MeasureSurface {
        static let coordinateSpace = "measure.surface"
    }

    struct MeasureModifier: ViewModifier {
        let id: String
        let role: String
        let kind: MeasureKind
        let alignment: String?
        let tokens: [String: ColorToken]
        let type: TypeToken?
        let text: String?

        @Environment(\.measurePath) private var parentPath
        @Environment(\.self) private var environment

        func body(content: Content) -> some View {
            content
                .background(GeometryReader { proxy in
                    Color.clear.preference(
                        key: MeasureKey.self,
                        value: [record(for: proxy.frame(in: .named(MeasureSurface.coordinateSpace)))]
                    )
                })
                .environment(\.measurePath, parentPath + [id])
        }

        private func record(for frame: CGRect) -> MeasureRecord {
            var names: [String: String] = tokens.mapValues(\.rawValue)
            if let type { names["type"] = type.rawValue }
            return MeasureRecord(
                id: id,
                path: parentPath,
                role: role,
                kind: kind,
                alignment: alignment,
                frame: MeasuredNode.Frame(
                    x: frame.origin.x, y: frame.origin.y,
                    width: frame.size.width, height: frame.size.height
                ),
                tokens: names,
                resolved: tokens.mapValues { hex(of: $0.color.resolve(in: environment)) },
                text: text
            )
        }

        /// The resolved colour as `#RRGGBB@a`, so it compares against the mock's canonical form.
        private func hex(of resolved: Color.Resolved) -> String {
            let channel = { (value: Float) in
                Int((Double(min(max(value, 0), 1)) * 255).rounded())
            }
            let base = String(
                format: "#%02X%02X%02X",
                channel(resolved.red), channel(resolved.green), channel(resolved.blue)
            )
            let alpha = Double(resolved.opacity)
            return alpha >= 0.9999 ? base : "\(base)@\(String(format: "%.4g", alpha))"
        }
    }

#endif

public extension View {
    /// Instruments one node of a surface.
    ///
    /// With `MEASURE` off this is the identity, so a call site costs nothing in a shipping build.
    ///
    /// - Parameters:
    ///   - id: unique among this node's siblings.
    ///   - role: what the node is for, in the mock's vocabulary.
    ///   - kind: the container kind, which is where the stack axis comes from.
    ///   - tokens: the colour tokens the node applies, keyed by the role each was applied to
    ///     (`foreground`, `background`, `border`).
    ///   - type: the type role the node applies, where it draws text.
    ///   - text: the literal string the node draws — the Swift side of the copy layer.
    @ViewBuilder
    func measured(
        _ id: String,
        role: String,
        kind: MeasureKind = .leaf,
        alignment: String? = nil,
        tokens: [String: ColorToken] = [:],
        type: TypeToken? = nil,
        text: String? = nil
    ) -> some View {
        #if MEASURE
            modifier(MeasureModifier(
                id: id, role: role, kind: kind, alignment: alignment,
                tokens: tokens, type: type, text: text
            ))
        #else
            self
        #endif
    }

    /// Marks the root of a measured surface: establishes the coordinate space every frame is
    /// expressed in, and feeds what the subtree reports to the recorder.
    @ViewBuilder
    func measureSurface(_ name: String) -> some View {
        #if MEASURE
            // The order is load-bearing. The surface's own node has to be measured *innermost* so
            // its `GeometryReader` finds the named space on an ancestor rather than a descendant,
            // and `onPreferenceChange` has to sit outermost so the root's own record reaches it —
            // a preference travels up, so a reader placed above the node that emits it sees
            // nothing and reports a tree with no root.
            measured(name, role: "surface", kind: .vstack)
                .coordinateSpace(.named(MeasureSurface.coordinateSpace))
                .environment(\.measurePath, [])
                .onPreferenceChange(MeasureKey.self) { records in
                    SurfaceRecorder.shared.ingest(records)
                }
        #else
            self
        #endif
    }
}
