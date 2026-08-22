#if os(macOS)
    import Foundation
    import Testing

    /// Which control holds which keyboard shortcut, on every sheet in the app.
    ///
    /// **The regression these exist for.** M18 moved `.keyboardShortcut(.cancelAction)` off Cancel
    /// and onto the destructive **Remove** button on Cleanup's remove sheet, so Escape performed an
    /// irreversible removal and Return dismissed — the two keys the spec assigns, swapped. It was
    /// measured on a reproduction rather than read:
    /// `planning/evidence/M18-gapfix-2/escape-shortcut-probe.swift` posts a keycode 53 at both
    /// shapes and reports `REMOVE` for the shipped one against `CANCEL` for the one before it.
    ///
    /// **Nothing caught it, and that is the part these tests answer.** Before this file, no test in
    /// `app/Tests` named either shortcut — 1757 green tests and a zero that the verdict established
    /// with a planted probe rather than inferred from a quiet grep.
    @Suite("Sheet keyboard shortcut bindings")
    struct SheetShortcutGuardTests {
        /// The fifteen sheet views, named so that a sixteenth is a deliberate classification rather
        /// than something that quietly joins the population.
        ///
        /// M18's verdict enumerated **fourteen** and this is fifteen: `MissingSubjectSheet`
        /// (`Boards/SkillSheets.swift`) is a real sheet, presented at `SkillSheets.swift:18`, and it
        /// was outside that table. So the figure that verdict reports as *8 of 14 sheets have no
        /// Escape path* was 9 of 15 — the conclusion it drew is unchanged and its population was one
        /// short, which is why this list is asserted rather than described.
        static let sheetViews: Set<String> = [
            "ActivityResetHistorySheet", "AddServerSheet", "ChildPathSheet", "DiscoverDetailSheet",
            "HeldChangeSheet", "HeldVersionSheet", "InboxReviewSheet", "MarketplacesSheet",
            "MissingSubjectSheet", "OfficialMarkSheet", "PairingSheet", "RemoveServerDialog",
            "RemoveServerSheet", "ResetHistorySheet", "SkillProvenanceSheet"
        ]

        /// The sheets with no Escape path, each with why it was left rather than fixed.
        ///
        /// **An allowlist, and an honest one: these are open defects, not exemptions.** All six
        /// predate M18 and none was drawn by it, which is where the gap-fix drew its line — the
        /// clause binds on this item at the sheets M18 itself drew. Every one of the six carries
        /// `.defaultAction` on an affirmative control (`Add`, `Accept the new text`, `Done`) or no
        /// shortcut at all, so closing them is a decision about what Escape *means* on each surface
        /// rather than the one-line move the remove sheets took, and the measurement below shows
        /// there is no way to add Escape without taking Return off the control that has it.
        static let noEscapePath: [String: String] = [
            "AddServerSheet": "Cancel carries nothing; the form's affirmative is Index and add",
            "HeldChangeSheet": "three-way decision — Escape has no obvious meaning among them",
            "HeldVersionSheet": "one Done control, holding Return",
            "MarketplacesSheet": "one Done control, holding Return",
            "MissingSubjectSheet": "one Done control, holding Return",
            "PairingSheet": "Done closes the session and stops the ticker; it holds Return"
        ]

        // MARK: - The scanner, armed before anything is read through it

        /// The fixture is the shipped M18 row, near enough to trip a parser that has gone blind.
        @Test("the scanner sees the defect it was built for, and passes the shape that replaced it")
        func theScannerSeesTheDefectItWasBuiltFor() {
            let defective = """
            struct ProbeSheet: View {
                var body: some View {
                    HStack {
                        Button("Cancel") { board.sheet = nil }
                            .buttonStyle(ProminentButtonStyle())
                            .keyboardShortcut(.defaultAction)
                        Button("Remove", role: .destructive) {
                            Task { await board.remove(name, keepHistory: keepHistory) }
                        }
                        .buttonStyle(StandardButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .disabled(candidate == nil)
                    }
                }
            }
            """
            let views = SheetShortcutScan.views(in: defective, file: "fixture.swift")
            #expect(views.count == 1, "the scanner stopped recognising a sheet view")
            #expect(views.first?.controls.count == 2, "the scanner stopped pairing modifiers to buttons")
            let destructive = views.first?.controls.filter(\.isDestructive) ?? []
            #expect(destructive.count == 1, "the scanner stopped reading `role: .destructive`")
            let blind = "the scanner missed the shortcut on the destructive button, so every guard "
                + "below would now pass by reading nothing"
            #expect(destructive.first?.shortcuts == ["cancelAction"], "\(blind)")

            let fixed = defective
                .replacingOccurrences(
                    of: ".keyboardShortcut(.defaultAction)",
                    with: ".keyboardShortcut(.cancelAction)"
                )
                .replacingOccurrences(of: """
                    .buttonStyle(StandardButtonStyle())
                            .keyboardShortcut(.cancelAction)
                """, with: "        .buttonStyle(StandardButtonStyle())")
            let repaired = SheetShortcutScan.views(in: fixed, file: "fixture.swift")
            #expect(
                repaired.first?.controls.first(where: \.isDestructive)?.shortcuts.isEmpty == true,
                "the scanner reports a shortcut on a destructive button that carries none"
            )
        }

        // MARK: - The binding, over the shipped tree

        @Test("no destructive control anywhere carries a keyboard shortcut")
        func noDestructiveControlCarriesAShortcut() throws {
            var offenders: [String] = []
            // Every view, not only the sheets: three destructive buttons in this tree are elsewhere.
            for view in try SheetShortcutScan.allViews() {
                for control in view.controls where control.isDestructive && !control.shortcuts.isEmpty {
                    offenders.append("\(view.file):\(control.line) \(view.name) → \(control.shortcuts)")
                }
            }
            #expect(
                offenders.isEmpty,
                "a key activates a destructive action — DESIGN.md §9, never the default button: \(offenders)"
            )
        }

        /// The blocker's own row, named rather than left to the sweep above.
        @Test("both remove surfaces bind Escape to Cancel and no key to Remove")
        func theRemoveSurfacesBindEscapeToCancel() throws {
            let views = try SheetShortcutScan.allSheetViews()
            for name in ["RemoveServerSheet", "RemoveServerDialog"] {
                let view = try #require(views.first { $0.name == name }, "\(name) was not scanned")
                let destructive = view.controls.filter(\.isDestructive)
                #expect(destructive.count == 1, "\(name) no longer has exactly one destructive control")
                #expect(destructive.first?.shortcuts.isEmpty == true, "\(name)'s Remove carries a key")
                #expect(
                    view.shortcuts == ["cancelAction"],
                    "\(name) should bind Escape and nothing else, and binds \(view.shortcuts)"
                )
            }
        }

        /// **Measured, not assumed:** one control cannot hold two shortcuts. The probe applies
        /// `.cancelAction` and `.defaultAction` to one button in both orders, and SwiftUI keeps the
        /// innermost and silently drops the other — Escape fires and Return does nothing, or the
        /// reverse. So a pair written together is a bug that compiles, and one of the two keys a
        /// reader believes is bound is not.
        @Test("no control carries two keyboard shortcuts, because SwiftUI would drop one")
        func noControlCarriesTwoShortcuts() throws {
            var offenders: [String] = []
            for view in try SheetShortcutScan.allViews() {
                for control in view.controls where control.shortcuts.count > 1 {
                    offenders.append("\(view.file):\(control.line) \(view.name) → \(control.shortcuts)")
                }
            }
            #expect(offenders.isEmpty, "only the innermost of these is live: \(offenders)")
        }

        // MARK: - Which control takes the accent fill

        /// The seven sheet views carrying a control written `Button("Cancel")`.
        ///
        /// Named rather than counted, because the guard below reads the **literal-label**
        /// population and a control whose label is an expression is invisible to it —
        /// `PairingFlowView`'s `Button(…secondaryActionLabel ?? "Cancel", role: .cancel)` is the one
        /// such control in the tree, and it is covered by the `role: .cancel` half of the sweep
        /// instead. Asserting the set makes an eighth Cancel a classification someone made rather
        /// than a control that quietly joined a population and was excused by it.
        static let cancelControlViews: Set<String> = [
            "ActivityResetHistorySheet", "AddServerSheet", "DiscoverDetailSheet", "InboxReviewSheet",
            "RemoveServerDialog", "RemoveServerSheet", "ResetHistorySheet"
        ]

        /// The style reader and the label reader, each shown reading and shown failing.
        ///
        /// Two fixtures rather than one: an offender that must be found, and the same row repaired,
        /// which must not be. An absence check whose reader has gone blind reports the same clean
        /// answer as a conforming tree, and the blind version is the one that arrives silently.
        @Test("the scanner reads a button's label and its style, in both directions")
        func theScannerReadsLabelsAndStyles() {
            let filled = """
            struct ProbeSheet: View {
                var body: some View {
                    HStack {
                        Button("Cancel") { board.sheet = nil }
                            .buttonStyle(ProminentButtonStyle())
                            .keyboardShortcut(.cancelAction)
                        Button(ProbeCopy.dismiss) { board.sheet = nil }
                            .buttonStyle(.plain)
                        Button("Remove", role: .destructive) {
                            Task { await board.remove(name) }
                        }
                        .buttonStyle(StandardButtonStyle())
                    }
                }
            }
            """
            let controls = SheetShortcutScan.views(in: filled, file: "fixture.swift")
                .first?.controls ?? []
            #expect(controls.count == 3, "the scanner stopped pairing modifiers to buttons")
            #expect(
                controls.map(\.label) == ["Cancel", "", "Remove"],
                "the label reader is wrong: \(controls.map(\.label))"
            )
            #expect(
                controls.map(\.buttonStyles) == [
                    ["ProminentButtonStyle"],
                    ["plain"],
                    ["StandardButtonStyle"]
                ],
                "the style reader is wrong: \(controls.map(\.buttonStyles))"
            )
            #expect(
                Self.accentFilledCancels(in: SheetShortcutScan.views(in: filled, file: "fixture.swift"))
                    .count == 1,
                "the sweep did not find a planted accent-filled Cancel, so a clean tree proves nothing"
            )

            // The fixture's only prominent style is Cancel's, so this repairs that row and nothing
            // else; `#expect` above has already established there are exactly three controls.
            let repaired = filled.replacingOccurrences(
                of: ".buttonStyle(ProminentButtonStyle())",
                with: ".buttonStyle(StandardButtonStyle())"
            )
            #expect(repaired != filled, "the repair matched nothing, so the check below proves nothing")
            #expect(
                Self.accentFilledCancels(in: SheetShortcutScan.views(in: repaired, file: "fixture.swift"))
                    .isEmpty,
                "the sweep reports an offender on a row that draws Cancel plain"
            )
        }

        /// Every control that dismisses and takes the accent fill, as `file:line view → styles`.
        static func accentFilledCancels(in views: [SheetShortcutScan.SheetView]) -> [String] {
            var offenders: [String] = []
            for view in views {
                for control in view.controls
                    where (control.label == "Cancel" || control.isCancelRole)
                    && control.buttonStyles.contains("ProminentButtonStyle")
                {
                    offenders.append("\(view.file):\(control.line) \(view.name) → \(control.buttonStyles)")
                }
            }
            return offenders
        }

        /// **The blocker gap-fix 3 exists for.** `DESIGN.md`:441 — *"One prominent accent-filled
        /// action per view, trailing. Cancel leads. Destructive is never the default."* — puts the
        /// fill on a trailing affirmative and Cancel in the leading position, so Cancel is never the
        /// control that takes it; `DESIGN.md`:433 makes a violation of that section *"a defect rather
        /// than a variation"*.
        ///
        /// M18 filled `RemoveServerSheet`'s Cancel at `4c320a8` and `RemoveServerDialog`'s came from
        /// `589ab2e`. Both drifted in with the whole suite green, which is the same way the shortcut
        /// defect arrived, and is why this is a guard rather than a fixed comment.
        @Test("no control labelled Cancel is the accent-filled action")
        func noCancelControlIsAccentFilled() throws {
            let offenders = try Self.accentFilledCancels(in: SheetShortcutScan.allViews())
            #expect(
                offenders.isEmpty,
                "Cancel leads and the accent fill is trailing — DESIGN.md §3.4 rule 4: \(offenders)"
            )
        }

        @Test("the literal-Cancel population is the seven views named here")
        func theCancelPopulationIsTheSevenNamed() throws {
            let found = try Set(
                SheetShortcutScan.allViews()
                    .filter { view in view.controls.contains { $0.label == "Cancel" } }
                    .map(\.name)
            )
            let added = found.subtracting(Self.cancelControlViews).sorted()
            let gone = Self.cancelControlViews.subtracting(found).sorted()
            #expect(
                found == Self.cancelControlViews,
                "the Cancel population moved. Added: \(added). Gone: \(gone)"
            )
        }

        // MARK: - The population, and the gap that is left in it

        @Test("the sheet population is the fifteen named here")
        func thePopulationIsTheFifteenNamed() throws {
            let found = try Set(SheetShortcutScan.allSheetViews().map(\.name))
            let added = found.subtracting(Self.sheetViews).sorted()
            let gone = Self.sheetViews.subtracting(found).sorted()
            #expect(found == Self.sheetViews, "the sheet population moved. Added: \(added). Gone: \(gone)")
        }

        @Test("every sheet outside the recorded gap can be dismissed with Escape")
        func everySheetOutsideTheGapCarriesAnEscapePath() throws {
            let views = try SheetShortcutScan.allSheetViews()
            var offenders: [String] = []
            for view in views where Self.noEscapePath[view.name] == nil {
                if !view.shortcuts.contains("cancelAction") {
                    offenders.append("\(view.file):\(view.line) \(view.name) → \(view.shortcuts)")
                }
            }
            #expect(offenders.isEmpty, "no control on these takes Escape: \(offenders)")

            // The allowlist's own presence control: a name that has stopped matching a sheet is an
            // exemption granted to nothing, and it would hide the next real gap behind it.
            let names = Set(views.map(\.name))
            let stale = Self.noEscapePath.keys.filter { !names.contains($0) }
            #expect(stale.isEmpty, "these are excused and no longer exist: \(stale.sorted())")
        }
    }
#endif
