#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// One block's inline runs, drawn.
    ///
    /// The runs arrived sanitised — `MarkdownInline` keeps presentation intent and an `https` link
    /// and nothing else — so this only decides how the two survivors look. A code span takes the
    /// instrument voice and the `--f1` fill the mock gives it; a link takes `--accent-text`, which
    /// is the accent solved *as text* and the reason `DESIGN.md` §2 splits it from `--accent`: the
    /// published blue measures 3.52:1 on the light ground and a 13pt label wants 4.5:1.
    ///
    /// **A code span's fill has no corner here, and the mock draws one.** SwiftUI's attributed
    /// `backgroundColor` paints a rectangle behind the glyphs and takes no radius, and the
    /// alternative — splitting every paragraph into a flow of separate views — would put the inline
    /// layout back in this file and lose the system parser's line breaking. Declared in
    /// `planning/fidelity/readme.layers.json` rather than approximated.
    struct MarkdownInlineText: View {
        let inline: MarkdownInline
        var role: TypeToken = .body
        var tint: ColorToken = .t1

        var body: some View {
            Text(styled)
                .typeRole(role)
                .foregroundStyle(tint.color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }

        /// Rebuilds the run stream with this layer's own attributes.
        ///
        /// Rebuilt rather than mutated in place for the same reason the sanitiser rebuilds: what
        /// comes out carries exactly what was put on it, and a run that acquires an attribute
        /// somewhere else cannot survive the copy.
        private var styled: AttributedString {
            var out = AttributedString()
            for run in inline.attributed.runs {
                var piece = AttributedString(String(inline.attributed[run.range].characters))
                if let intent = run.inlinePresentationIntent {
                    piece.inlinePresentationIntent = intent
                    if intent.contains(.code) {
                        piece.font = TypeToken.callout.monospacedFont
                        piece.backgroundColor = ColorToken.f1.color
                    }
                }
                if let link = run.link {
                    piece.link = link
                    piece.foregroundColor = ColorToken.accentText.color
                    piece.underlineStyle = .single
                }
                out.append(piece)
            }
            return out
        }
    }
#endif
