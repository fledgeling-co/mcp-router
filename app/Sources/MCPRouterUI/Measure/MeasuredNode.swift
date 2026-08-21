import Foundation

/// One node of a measured surface: what it is, what contains it, how it lays out, where it landed,
/// and which tokens it named.
///
/// The shape is the whole point of the M23 contract. `mockup-fidelity`'s React Native reference
/// records what a flat `{type, text, style}` list costs: such a dump cannot tell an `HStack` card
/// from a `VStack` card, a present divider from an absent one, or a two-column grid from a stack,
/// so every colour can match while the entire layout is wrong and the differ emits nothing. A node
/// here therefore carries **containment** (`path`), **layout** (`axis`, `alignment`) and
/// **geometry** (`frame`) as required fields rather than as optional extras.
public struct MeasuredNode: Codable, Equatable, Sendable {
    /// The node's own identifier, unique among its siblings.
    public var id: String
    /// The ancestors' identifiers, outermost first. `[]` is the surface root.
    public var path: [String]
    /// What this node is for, in the mock's vocabulary — `board-header`, `primary-action`, `row`.
    public var role: String
    /// The container kind: `vstack`, `hstack`, `zstack`, `grid`, `scroll`, `leaf`.
    public var kind: String
    /// The stack axis, where the node is a stack.
    public var axis: String?
    /// The stack alignment, where the node is a stack.
    public var alignment: String?
    /// The node's frame in the surface's own coordinate space.
    public var frame: Frame
    /// The design tokens the node named, by the role each was applied to.
    public var tokens: [String: String]
    /// What those tokens actually resolved to in the appearance being measured.
    ///
    /// This is the resolved half of the style layer, and it is a real measurement:
    /// `Color.resolve(in:)` runs the dynamic provider against the environment the view is being
    /// rendered in, so a token that lost the appearance cascade shows up here as the wrong value
    /// rather than as the name it declared.
    public var resolved: [String: String]
    /// The literal text the node draws, where it draws any. This is the copy layer's Swift side.
    public var text: String?
    /// Children, in the order they were laid out along the parent's axis.
    public var children: [MeasuredNode]

    public struct Frame: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            // Rounded to a tenth of a point on the way in. SwiftUI resolves text frames to
            // fractions that differ in the last binary digit between runs, and a diff that reports
            // `7.499999` against `7.5` as a finding trains its reader to ignore it.
            self.x = (x * 10).rounded() / 10
            self.y = (y * 10).rounded() / 10
            self.width = (width * 10).rounded() / 10
            self.height = (height * 10).rounded() / 10
        }
    }

    public init(
        id: String,
        path: [String],
        role: String,
        kind: String,
        axis: String? = nil,
        alignment: String? = nil,
        frame: Frame,
        tokens: [String: String] = [:],
        resolved: [String: String] = [:],
        text: String? = nil,
        children: [MeasuredNode] = []
    ) {
        self.id = id
        self.path = path
        self.role = role
        self.kind = kind
        self.axis = axis
        self.alignment = alignment
        self.frame = frame
        self.tokens = tokens
        self.resolved = resolved
        self.text = text
        self.children = children
    }
}

/// A whole surface's dump: the appearance it was measured in, what the instrument could and could
/// not do, and the node tree.
///
/// `inconclusive` is a first-class field rather than a footnote. The brief's third exit state turns
/// on it: a layer the verdict depended on that could not run has to be reported, and the tool's own
/// failure string is carried verbatim so "this layer cannot run here" cannot decay into "the
/// shadows match".
public struct SurfaceDump: Codable, Equatable, Sendable {
    public var surface: String
    public var appearance: String
    public var size: MeasuredNode.Frame
    /// Layers that ran, by name.
    /// The type ladder as the build carries it, so the gate can check a text node's measured height
    /// against the line height its token declares without re-deriving the ladder from `DESIGN.md`
    /// and drifting from it.
    public var typeLadder: [String: TypeMetrics]
    public var layers: [String]
    /// Layers that could not run, each with the instrument's own words.
    public var inconclusive: [InconclusiveLayer]
    public var root: MeasuredNode

    public struct TypeMetrics: Codable, Equatable, Sendable {
        public var size: Double
        public var lineHeight: Double
        public var emphasis: String

        public init(size: Double, lineHeight: Double, emphasis: String) {
            self.size = size
            self.lineHeight = lineHeight
            self.emphasis = emphasis
        }
    }

    public struct InconclusiveLayer: Codable, Equatable, Sendable {
        public var layer: String
        /// What the layer would have covered.
        public var covers: String
        /// Quoted verbatim from the tool. A paraphrase here is how a blind instrument reports
        /// agreement.
        public var evidence: String
        /// Where the claim is confirmed instead, or `nil` when nothing confirms it.
        public var confirmedInsteadBy: String?

        public init(layer: String, covers: String, evidence: String, confirmedInsteadBy: String?) {
            self.layer = layer
            self.covers = covers
            self.evidence = evidence
            self.confirmedInsteadBy = confirmedInsteadBy
        }
    }

    public init(
        surface: String,
        appearance: String,
        size: MeasuredNode.Frame,
        typeLadder: [String: TypeMetrics],
        layers: [String],
        inconclusive: [InconclusiveLayer],
        root: MeasuredNode
    ) {
        self.surface = surface
        self.appearance = appearance
        self.size = size
        self.typeLadder = typeLadder
        self.layers = layers
        self.inconclusive = inconclusive
        self.root = root
    }

    /// Every node in the tree, flattened. For counting, not for diffing — a diff reads the tree.
    public var allNodes: [MeasuredNode] {
        func walk(_ node: MeasuredNode) -> [MeasuredNode] {
            [node] + node.children.flatMap(walk)
        }
        return walk(root)
    }
}
