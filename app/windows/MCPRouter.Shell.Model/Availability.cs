namespace MCPRouter.Shell.Model;

/// <summary>
/// Why a command is or is not live right now.
///
/// DESIGN.md §5 requires a disabled state that "dims in place with a discoverable reason", and
/// §11 rule 4 requires that it never disappears. A command whose feature has not been built is
/// therefore on the command surface, disabled, carrying the sentence that says so - not absent.
/// Dropping it would make §11 rule 9's completeness guarantee true only of a command set that
/// shrinks to fit.
/// </summary>
public enum AvailabilityKind
{
    /// <summary>The shell can perform this now.</summary>
    Available,

    /// <summary>Live once something is selected; the reason says what.</summary>
    NeedsSelection,

    /// <summary>Nothing behind it yet. The reason names the item that will build it.</summary>
    Unbuilt,
}

/// <param name="Kind">Which of the three states this is.</param>
/// <param name="Reason">
/// The sentence a user can discover. Empty only for <see cref="AvailabilityKind.Available"/>.
/// </param>
/// <param name="OwningItem">
/// For <see cref="AvailabilityKind.Unbuilt"/>, the pipeline id that will build it - so a reader
/// of the menu can find the work rather than guess whether it was forgotten.
/// </param>
public readonly record struct Availability(AvailabilityKind Kind, string Reason, string? OwningItem)
{
    public static Availability Available { get; } =
        new(AvailabilityKind.Available, string.Empty, null);

    public static Availability NeedsSelection(string reason) =>
        new(AvailabilityKind.NeedsSelection, reason, null);

    public static Availability Unbuilt(string owningItem, string reason) =>
        new(AvailabilityKind.Unbuilt, reason, owningItem);

    public bool IsEnabled => Kind == AvailabilityKind.Available;
}
