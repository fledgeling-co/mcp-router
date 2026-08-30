namespace MCPRouter.Shell.Model;

/// <summary>
/// One command on the app's command surface.
///
/// DESIGN.md §11 rule 9 restates §3 rule 9's guarantee against a platform with no global menu
/// bar: every command the app can perform is reachable from one enumerable in-window surface,
/// and every command on it carries an access key so <c>Alt</c> enumerates the whole set without a
/// pointer. This type is that set; <see cref="CommandCatalog"/> is that one surface.
/// </summary>
/// <param name="Id">Stable id, used by the view to wire the handler.</param>
/// <param name="Menu">Which top-level menu it sits under.</param>
/// <param name="Label">Sentence case, §11 rule 2. Windows states no menu-title exception.</param>
/// <param name="AccessKey">Unique within its menu.</param>
/// <param name="Accelerator">Only where DESIGN.md §13's table grants one.</param>
/// <param name="Availability">Live, needs a selection, or not built - with the reason.</param>
/// <param name="Order">Position within its menu, separators included as gaps.</param>
public sealed record AppCommand(
    string Id,
    string Menu,
    string Label,
    string AccessKey,
    Accelerator? Accelerator,
    Availability Availability,
    int Order,
    bool SeparatorBefore = false);

/// <summary>
/// A key DESIGN.md §13 names that is a behaviour rather than a command accelerator.
///
/// These are declared rather than left to each surface to rediscover, and the parity gate
/// matches them against §13's own non-chord rows - so a row cannot be quietly dropped on the
/// grounds that it was not a chord.
/// </summary>
public sealed record KeyboardBehaviour(string Key, string Behaviour);
