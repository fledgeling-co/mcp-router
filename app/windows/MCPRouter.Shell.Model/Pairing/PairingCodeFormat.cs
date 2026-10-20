namespace MCPRouter.Shell.Model.Pairing;

/// <summary>
/// The wire form of a pairing code (plan §2.4): eight Crockford characters, uppercase, no separator. The alphabet
/// leaves out I, L, O and U, the characters a reader confuses with a digit or with each other, so a code read off
/// one screen can be typed into another.
/// </summary>
public static class PairingCodeFormat
{
    /// <summary>The alphabet of <c>PairingCode.swift</c>: digits and letters, without I, L, O or U.</summary>
    public const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    public const int CodeLength = 8;

    public static bool IsWellFormed(string? code) =>
        code is { Length: CodeLength } && code.All(character => Alphabet.Contains(character));
}
