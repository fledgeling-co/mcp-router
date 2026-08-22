import Foundation

/// Every string the Settings window's seven panes draw, and the reason each pane draws what it does.
///
/// Held apart from `SettingsPresentation` because the two have different subjects:
/// `SettingsPresentation` computes *values* from what the router serves, and this is the pane
/// copy — labels, card headers, helper sentences and, for the three panes the product has nothing
/// to put in, the one sentence saying what governs the thing and where it is set today. Both stay
/// in `MCPRouterKit` so `SettingsPaneCopyTests` and `SettingsHonestyTests` can reach them without a
/// UI stack.
///
/// **What a pane with nothing left to build draws.** Not an empty pane, and not the mock's controls
/// rendered inert. It draws its name, its one line, and one sentence naming where the thing is
/// decided today — the shape `SettingsPresentation.routerHelp` already ships and M8 approved. That
/// satisfies `DESIGN.md` §6 (nothing invented) and §5 (say what happened and what to do), keeps the
/// seven-pane count real rather than decorative, and is copy, which is the cheapest thing in this
/// window to reverse when the capability lands.
public enum SettingsPaneCopy {
    // MARK: - Router

    /// The card headers this window carries forward from the shipped Settings board, unchanged.
    /// `scripts/acceptance/m8-settings-menubar.sh` reads all four back off the rendered window.
    public static let routerGroup = "Router"
    public static let warmSetGroup = "Warm set"
    public static let menuBarGroup = "Menu bar"
    public static let controlTokenGroup = "Control token"

    public static let endpointLabel = "Endpoint"
    public static let homeLabel = "Home"
    public static let idleLabel = "Idle reaper"
    public static let sinceLabel = "Counting since"

    /// Copying the endpoint is an app affordance rather than a router setting: the string is already
    /// on screen and the pasteboard is the app's own.
    public static let copyEndpointAction = "Copy"
    public static let copyEndpointDone = "Copied"

    // MARK: - Harnesses

    /// Nothing on this pane is settable from this app, and the sentence says where it is settable.
    ///
    /// Measured against the wire on 2026-08-22: `ControlPaths.isControlPath` admits `/servers`,
    /// `/usage` and `/registry` and nothing else, so there is no harnesses endpoint to read a
    /// preference from or write one to. Adoption and reconciliation live in `RouterCore` and are
    /// driven by the command line.
    public static let harnessesGovernance = """
    Set from the command line, not here. Which harnesses this router fronts, whether a new stdio \
    server is adopted, and whether a drifted configuration is reconciled are decided by \
    `mcp-router harnesses` and `mcp-router watch`. The app reaches the router over one loopback \
    channel and that channel serves no harness settings at all, so there is nothing here it could \
    read or write.
    """

    // MARK: - Session analyst

    /// The pane exists because the window has seven, and it says plainly that the thing it is named
    /// for is not in this build. Stating the absence is `DESIGN.md` §6 applied to a whole pane:
    /// drawing the mock's six controls would promise a model, a schedule and a notification that
    /// nothing in either target can produce.
    public static let analystGovernance = """
    This build has no session analyst. Nothing reads your agent logs, no model is called on your \
    behalf, and no finding is ever generated — so there is no model to pick, no schedule to set \
    and nothing to be notified about yet. The pane is here because the window's areas are fixed; \
    what would go in it is not built.
    """

    // MARK: - Updates

    public static let updatesGovernance = """
    This build checks for nothing. It does not look for new versions of itself, and a capability \
    you have installed stays the version you installed until you install another. There is no \
    interval, no channel and no unattended-install rule, because there is no check to configure.
    """

    // MARK: - Security

    public static let pairedDevicesGroup = "Paired devices"
    public static let pairedDevicesLabel = "Paired"
    /// Observed from the inbox snapshot the shell already polls — the one place this Mac learns a
    /// phone's name — rather than from a devices endpoint, which the control API does not serve.
    public static let pairedDevicesNone = "No device paired"
    public static let pairedDevicesAction = "Manage…"

    public static let pairedDevicesHelp = """
    A paired phone can queue a capability for you to review here; it can do nothing else. Pairing \
    and unpairing are Inbox's, which is where the queue and the device both live.
    """

    // MARK: - Menu bar

    public static let statusItemLabel = "Status item"

    // MARK: - Advanced

    public static let filesGroup = "Files"
    public static let logLabel = "Router log"
    public static let configurationLabel = "Configuration"

    /// The router's log file, named by path and **not** by size.
    ///
    /// The mock draws `~/.claude/mcp-router/router.log · 4.2 MB`. The path is derived from the same
    /// directory the client resolves to find the token, so it is observed; the megabyte figure would
    /// need a `stat` of a file in a directory A36's one-channel rule keeps this layer out of, and
    /// `DESIGN.md` §6 forbids a number nobody observed either way.
    public static let filesHelp = """
    Both files are the router's own. The app reads neither: it reaches the router over the loopback \
    control API and nothing else, which is what lets the router be replaced underneath it.
    """

    /// What the build identity line says when the process carries no bundle to read one from.
    public static let buildIdentityUnknown = "This build reports no version."

    // MARK: - Shared

    /// Shown on a pane whose values all come from a router that has never answered.
    ///
    /// The headline and advice themselves are `ControlAPIError`'s, asserted verbatim by
    /// `ControlCopyTests`; this is the sentence that follows them, naming what is missing rather
    /// than repeating that something failed.
    public static let routerFactsUnavailable = """
    Its endpoint, reaper and counting window are the router's own and are only knowable while it \
    is up.
    """

    /// The one sentence each pane the product has nothing to put in draws, or `nil` where the pane
    /// draws real controls.
    ///
    /// Exhaustive over `SettingsPane`, so a pane added later cannot skip the decision.
    public static func governance(for pane: SettingsPane) -> String? {
        switch pane {
        case .harnesses: harnessesGovernance
        case .analyst: analystGovernance
        case .updates: updatesGovernance
        case .router, .security, .menuBar, .advanced: nil
        }
    }
}
