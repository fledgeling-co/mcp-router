using System.Text;

namespace MCPRouter.Shell.Model;

/// <summary>
/// One keyboard chord, in DESIGN.md §13's own spelling.
///
/// The spelling matters because the parity gate reads §13's table and compares it to what the app
/// binds. Two spellings of one chord is the drift the gate exists to catch, so the document's
/// text and the app's value are parsed into this one type rather than compared as strings.
/// </summary>
public readonly record struct Accelerator(bool Ctrl, bool Shift, bool Alt, string Key)
{
    // Both factories normalise through the same function TryParse uses. They did not, once, and
    // the parity gate went red in both directions at the same time: the app held Key "Del" and
    // the document parsed to "DEL", so one chord looked like two missing ones. A value type whose
    // two construction paths disagree is the drift the gate exists to catch, arriving inside the
    // gate's own arithmetic.
    public static Accelerator Control(string key) => new(true, false, false, Normalise(key));

    public static Accelerator Bare(string key) => new(false, false, false, Normalise(key));

    /// <summary>
    /// Parses "Ctrl+N", "Shift+F6", "Del", "Ctrl+1". Returns false for anything else, including
    /// the non-chord rows §13 also carries (<c>Alt</c>, <c>Return</c>, <c>Esc</c>, <c>Space</c>),
    /// which are behaviours rather than command accelerators and are held elsewhere.
    /// </summary>
    public static bool TryParse(string text, out Accelerator accelerator)
    {
        accelerator = default;
        if (string.IsNullOrWhiteSpace(text)) return false;

        var parts = text.Trim().Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        bool ctrl = false, shift = false, alt = false;
        string? key = null;

        foreach (var part in parts)
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl": ctrl = true; break;
                case "shift": shift = true; break;
                case "alt": alt = true; break;
                default:
                    if (key is not null) return false;   // two non-modifier tokens is not a chord
                    key = part;
                    break;
            }
        }

        if (key is null) return false;

        // A bare key is a chord only when it is one of the named editing keys. A bare letter or
        // a bare "Return" is a behaviour, not an accelerator, and must not be swallowed here.
        if (!ctrl && !shift && !alt && !IsBareChordKey(key)) return false;

        accelerator = new Accelerator(ctrl, shift, alt, Normalise(key));
        return true;
    }

    private static bool IsBareChordKey(string key) =>
        key.Equals("Del", StringComparison.OrdinalIgnoreCase) ||
        key.Equals("Delete", StringComparison.OrdinalIgnoreCase);

    private static string Normalise(string key) =>
        key.Equals("Delete", StringComparison.OrdinalIgnoreCase) ? "Del" : key.ToUpperInvariant();

    public override string ToString()
    {
        var sb = new StringBuilder();
        if (Ctrl) sb.Append("Ctrl+");
        if (Shift) sb.Append("Shift+");
        if (Alt) sb.Append("Alt+");
        sb.Append(Key.Equals("DEL", StringComparison.OrdinalIgnoreCase) ? "Del" : Key);
        return sb.ToString();
    }
}
