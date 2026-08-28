import Foundation
import Testing
@testable import MCPRouterKit

/// The second link of M34's chain: what an observed reason tells you about the badge beside it.
///
/// **This exists because the badge is not readable on the app's own menu and the reason is.**
/// `menu-badge-lane.sh` measures why — SwiftUI does not publish an `NSMenuItem`'s badge to the
/// accessibility plane, and this app's menu bar is SwiftUI's. `menu-reason-plane.sh` re-measures
/// that on the product rather than on a fixture, and reads back what *is* published: the long
/// reason, in `AXHelp`, written by `ShellMenuReasons` in the same pass and out of the same
/// `availability(in:)` value as the badge.
///
/// So a claim about the badge on the running app is a claim about the reason plus this file. That
/// makes the honest form of the claim a two-link chain, and it is only worth as much as its weaker
/// link — which is why the property below is the strong one rather than the convenient one.
///
/// **What is asserted is that the map is a FUNCTION**, not that the two are merely both present. If
/// one sentence could appear beside two different badges, reading the sentence off the plane would
/// leave the badge undetermined and the chain would carry nothing. That is the property, and it is
/// asserted over every command in every context the type can be in rather than over the default
/// one — the running app is never in the default context, and `MenuCommandRuleTests`'
/// `badgeIsPresentExactlyWhereUnavailable` reads `.none` only.
@Suite("Menu bar — a reason determines the badge beside it")
struct MenuReasonBadgePairingTests {
    /// Every context the type distinguishes, rather than a sample of them.
    ///
    /// `CommandContext` branches on two things only — whether a required board is installed, and
    /// whether a server is selected and tripped — so the product of the board subsets that matter
    /// and the three selection states is the whole space these answers can vary over. The board
    /// subsets are the empty set, each single destination, and the full set: a command gates on one
    /// named destination, so any subset containing it answers the same as the singleton.
    static var everyContext: [MenuCommand.CommandContext] {
        var installedSets: [Set<Destination>] = [[], Set(Destination.allCases)]
        installedSets += Destination.allCases.map { Set([$0]) }
        return installedSets.flatMap { installed in
            [nil, true, false].map { tripped in
                MenuCommand.CommandContext(installedDestinations: installed, selectedServerIsTripped: tripped)
            }
        }
    }

    /// The claim `menu-reason-plane.sh` leans on, stated as the relation it needs.
    @Test("one reason never appears beside two different badges")
    func aReasonDeterminesItsBadge() {
        var badgeForReason: [String: String] = [:]
        var pairs = 0
        for command in MenuCommand.allCases {
            for context in Self.everyContext {
                guard let reason = command.reason(in: context) else { continue }
                guard let observed = command.availability(in: context).badge else {
                    // Reported here rather than skipped: a command carrying a reason and no badge
                    // is the case that would break the chain silently, so it fails rather than
                    // dropping out of the loop's denominator.
                    #expect(Bool(false), "\(command.title) carries a reason and no badge")
                    continue
                }
                pairs += 1
                if let seen = badgeForReason[reason] {
                    #expect(
                        seen == observed,
                        "'\(reason)' appears beside both '\(seen)' and '\(observed)', so reading the reason off the accessibility plane would not determine the badge"
                    )
                } else {
                    badgeForReason[reason] = observed
                }
            }
        }
        // Without this the loop above passes over an empty set: a build in which no command was
        // ever unavailable would satisfy every assertion inside it and prove nothing.
        #expect(pairs > 0, "no command was unavailable in any context, so the relation was never exercised")
        #expect(
            badgeForReason.count >= 3,
            "only \(badgeForReason.count) distinct reason(s) were reached; the three availability classes should each contribute at least one"
        )
    }

    /// The converse, which is what makes the reason a usable proxy at all.
    ///
    /// A command that carried a badge and no reason would be one the plane cannot see is
    /// unavailable: `AXHelp` would be empty and the shortcut column would still be occupied. The
    /// lane would read that item as available and be wrong about it, silently.
    @Test("a badge and a reason are present together or not at all, in every context")
    func neitherAppearsWithoutTheOther() {
        var checked = 0
        for command in MenuCommand.allCases {
            for context in Self.everyContext {
                let reason = command.reason(in: context)
                let badge = command.availability(in: context).badge
                #expect(
                    (reason == nil) == (badge == nil),
                    "\(command.title) in \(context.installedDestinations.count) installed / tripped=\(String(describing: context.selectedServerIsTripped)): reason=\(String(describing: reason)) badge=\(String(describing: badge))"
                )
                checked += 1
            }
        }
        #expect(checked == MenuCommand.allCases.count * Self.everyContext.count)
        #expect(checked > 0)
    }

    /// The vocabulary `menu-reason-plane.sh` derives from the source, held to what the model emits.
    ///
    /// The lane reads its accepted sentences out of `MenuCommandAvailability.swift` with `sed`
    /// rather than carrying a copy, so the two cannot drift — but a `sed` that stopped matching
    /// would yield an EMPTY vocabulary and the lane would then refuse every real reason. This is
    /// the count that says the model still has three shapes of answer for it to find.
    @Test("the reasons the model emits are the three shapes the lane knows how to read")
    func theVocabularyHasThreeShapes() {
        var generic = Set<String>()
        var specialised = Set<String>()
        for command in MenuCommand.allCases {
            for context in Self.everyContext {
                guard let reason = command.reason(in: context) else { continue }
                if reason.hasSuffix(" hasn't been built yet.") && reason != CommandAvailability.featureUnbuilt.reason {
                    specialised.insert(reason)
                } else {
                    generic.insert(reason)
                }
            }
        }
        // The COUNT first, and it is the half that can fail. Comparing the observed set against
        // `[surfaceAbsent.reason, needsServerSelection.reason]` derives the expectation from the
        // same source as the measurement, so collapsing those two onto one sentence shrinks both
        // sides together and the comparison stays true — measured, under exactly that mutation.
        // Two classes that share a sentence are the drift this whole file exists to refuse, so the
        // assertion that catches it is the arithmetic one.
        #expect(generic.count == 2, "the two generic sentences collapsed onto \(generic.sorted())")
        #expect(generic.contains(CommandAvailability.surfaceAbsent.reason ?? ""))
        #expect(generic.contains(CommandAvailability.needsServerSelection.reason ?? ""))
        #expect(specialised.count == 9, "the specialised sentences are \(specialised.sorted())")
        // The generic `.featureUnbuilt` sentence is a string the app can never utter, because
        // `reason(in:)` specialises that answer for every command. The lane's vocabulary therefore
        // omits it deliberately, and this is what keeps that omission correct.
        #expect(!specialised.contains(CommandAvailability.featureUnbuilt.reason ?? ""))
        #expect(!generic.contains(CommandAvailability.featureUnbuilt.reason ?? ""))
    }
}
