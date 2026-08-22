// A keyboard-shortcut probe for a two-button sheet action row, and its presence control.
//
// M18's verifier found `.keyboardShortcut(.cancelAction)` on Cleanup's destructive **Remove**
// button, so Escape performed the removal. This file is the instrument that established it, and
// the instrument that decides the shape of the fix: which of `Return` and `Escape` reaches which
// control, per candidate shape, read from the action that actually ran rather than from the API's
// documentation.
//
// **It is committed rather than left in `/tmp`.** `planning/features-to-triage/G6-…` records four
// cited sweeps that no longer exist, and the rule it lands on: an artifact a record cites as
// evidence is committed, or the record does not cite it. The verifier's own version of this probe
// lived in `/tmp/escprobe` and happened to survive the same day; this one is reconstructed from
// that shape rather than recovered, and adds the `Return` column and the three candidate shapes.
//
// Usage: `swiftc -O escape-shortcut-probe.swift -o /tmp/<dir>/probe && probe <shape> <key> <outdir>`
// See `run-escape-probe.sh`, which runs the whole matrix and prints it as a table.

import AppKit
import os
import SwiftUI

// MARK: - The matrix

/// Which shortcuts each candidate action row hangs on which button.
///
/// Named for the tree they describe rather than for a verdict, so a row cannot silently become the
/// name of something else: `preM18` is `87e16dc`, `m18Shipped` is `6721e5c`'s
/// `CleanupSheets.swift:99-107`, and the three `candidate…` rows are shapes under consideration.
///
/// **One row now describes two trees, and the name only says one of them.** `preM18` is also the
/// shape gap-fix 2 shipped, so the row that certifies the current tree is named for the old one.
/// Kept rather than renamed, because the matrix is quoted by line in two records and a rename would
/// strand both; read `pre-m18` as *the shape before M18 and after gap-fix 2* wherever it appears.
enum Shape: String, CaseIterable {
    /// `87e16dc` — Cancel took Escape, the destructive button carried nothing.
    case preM18 = "pre-m18"
    /// `6721e5c` — Cancel took Return, and Escape was moved onto Remove. The defect.
    case m18Shipped = "m18"
    /// Cancel carries Escape *and* Return; the destructive button carries nothing.
    case candidateStacked = "stacked"
    /// The same two, applied in the other order — SwiftUI may keep only one.
    case candidateStackedReversed = "stacked-rev"
    /// `ServerSheets.swift:265` and both sheets M18 drew: Return only, and no Escape path at all.
    case defaultOnly = "default-only"
    /// Return only on the button, with `.onExitCommand` on the sheet's own body.
    case exitCommand = "exit-command"
    /// Return on the visible button, and Escape on a zero-size zero-opacity twin beside it — the
    /// usual workaround for a one-action sheet, measured rather than assumed to work.
    case hiddenCancel = "hidden-cancel"

    var cancelHoldsCancelAction: Bool {
        switch self {
        case .preM18, .candidateStacked, .candidateStackedReversed: true
        case .m18Shipped, .defaultOnly, .exitCommand, .hiddenCancel: false
        }
    }

    var cancelHoldsDefaultAction: Bool {
        switch self {
        case .m18Shipped, .candidateStacked, .candidateStackedReversed, .defaultOnly, .exitCommand,
             .hiddenCancel: true
        case .preM18: false
        }
    }

    var removeHoldsCancelAction: Bool { self == .m18Shipped }
    var sheetHandlesExitCommand: Bool { self == .exitCommand }
    var hasHiddenCancelTwin: Bool { self == .hiddenCancel }
    var reversedStacking: Bool { self == .candidateStackedReversed }
}

enum Key: String, CaseIterable {
    case escape
    case `return`

    var code: UInt16 { self == .escape ? 53 : 36 }
    var characters: String { self == .escape ? "\u{1b}" : "\r" }
}

// MARK: - Arguments

let arguments = Array(CommandLine.arguments.dropFirst())
guard let shape = Shape(rawValue: arguments.first ?? ""),
      let key = Key(rawValue: arguments.dropFirst().first ?? ""),
      let outputDirectory = arguments.dropFirst(2).first
else {
    FileHandle.standardError.write(Data("usage: probe <shape> <key> <outdir>\n".utf8))
    exit(2)
}

let resultURL = URL(fileURLWithPath: outputDirectory)
    .appendingPathComponent("result-\(shape.rawValue)-\(key.rawValue).txt")
let stateURL = URL(fileURLWithPath: outputDirectory)
    .appendingPathComponent("state-\(shape.rawValue)-\(key.rawValue).txt")

/// First write wins. A shape where both a button *and* `.onExitCommand` fire would otherwise report
/// only the last one, and which arrived first is the thing being measured.
let recorded = OSAllocatedUnfairLock(initialState: false)
func record(_ outcome: String) {
    let alreadyWritten = recorded.withLock { written -> Bool in
        defer { written = true }
        return written
    }
    guard !alreadyWritten else { return }
    try? outcome.write(to: resultURL, atomically: true, encoding: .utf8)
}

// MARK: - The sheet under test

struct ProbeSheet: View {
    /// Threaded rather than read from the top-level `let`: a type declaration in a script's main
    /// file cannot close over one, and threading it is what the product code does anyway.
    let shape: Shape
    let key: Key
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("probe sheet — \(shape.rawValue) / \(key.rawValue)")
            HStack(spacing: 12) {
                cancelButton
                removeButton
                if shape.hasHiddenCancelTwin { hiddenCancelTwin }
            }
        }
        .padding(24)
        .frame(width: 380, height: 160)
        // Attached only for the `exit-command` shape, so the other five measure the buttons alone.
        .modifier(ExitCommandIfNeeded(enabled: shape.sheetHandlesExitCommand))
    }

    @ViewBuilder private var cancelButton: some View {
        let button = Button("Cancel") {
            record("CANCEL")
            dismiss()
        }
        if shape.reversedStacking {
            button.keyboardShortcut(.defaultAction).keyboardShortcut(.cancelAction)
        } else if shape.cancelHoldsCancelAction, shape.cancelHoldsDefaultAction {
            button.keyboardShortcut(.cancelAction).keyboardShortcut(.defaultAction)
        } else if shape.cancelHoldsCancelAction {
            button.keyboardShortcut(.cancelAction)
        } else if shape.cancelHoldsDefaultAction {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    @ViewBuilder private var removeButton: some View {
        let button = Button("Remove", role: .destructive) {
            record("REMOVE")
            dismiss()
        }
        if shape.removeHoldsCancelAction {
            button.keyboardShortcut(.cancelAction)
        } else {
            button
        }
    }

    /// The workaround under test: a control nobody can see, carrying the shortcut the visible one
    /// cannot also hold. Hidden from assistive technology as well as from the eye, because a
    /// zero-size button VoiceOver still announces is a worse defect than the missing key.
    private var hiddenCancelTwin: some View {
        Button("") {
            record("HIDDEN_CANCEL")
            dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private struct ExitCommandIfNeeded: ViewModifier {
        let enabled: Bool

        func body(content: Content) -> some View {
            if enabled {
                content.onExitCommand { record("EXIT_COMMAND") }
            } else {
                content
            }
        }
    }
}

struct ProbeRoot: View {
    let shape: Shape
    let key: Key
    @State private var showingSheet = false

    var body: some View {
        Text("host window")
            .frame(width: 440, height: 240)
            .sheet(isPresented: $showingSheet) {
                ProbeSheet(shape: shape, key: key, dismiss: { showingSheet = false })
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showingSheet = true }
            }
    }
}

// MARK: - The key press

/// Posted to the process rather than synthesised at the HID layer, which is the technique
/// `Settings/SettingsWindow.swift:81-84` records using to establish that the Settings scene does
/// not close on Escape by itself. It needs no accessibility permission and it reaches the
/// responder chain of whichever window is key — recorded in `state-…` so a run where the sheet
/// never became key is visible rather than silently answering about the wrong window.
func post(_ key: Key) {
    let window = NSApp.keyWindow ?? NSApp.windows.last
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        guard let event = NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: key.characters,
            charactersIgnoringModifiers: key.characters,
            isARepeat: false,
            keyCode: key.code
        ) else { continue }
        NSApp.postEvent(event, atStart: false)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let window = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 440, height: 240),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
window.title = "escape-shortcut-probe"
window.contentView = NSHostingView(rootView: ProbeRoot(shape: shape, key: key))
window.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)

DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
    let sheets = NSApp.windows.filter(\.isSheet)
    let state = "windows:\(NSApp.windows.count) sheets:\(sheets.count) "
        + "keyIsSheet:\(NSApp.keyWindow?.isSheet.description ?? "nil")"
    try? state.write(to: stateURL, atomically: true, encoding: .utf8)
    post(key)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
    // `NEITHER` is written as a value rather than left as a missing file, so "the key did nothing"
    // and "the run never started" are distinguishable in the results directory.
    record("NEITHER")
    // **`exit` rather than `NSApp.terminate`, and the reason is a measurement.** The first version
    // of this probe called `terminate(nil)` and hung indefinitely on exactly the cells where
    // nothing fired: AppKit will not close a window that still has a sheet attached, so a shape
    // where the key reached no control never exits. That hang is a second, accidental witness that
    // the sheet really is still up in a `NEITHER` cell — and it is also why this line cannot be
    // the polite one.
    exit(0)
}

application.run()
