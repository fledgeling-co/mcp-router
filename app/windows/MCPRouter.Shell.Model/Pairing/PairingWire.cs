using System;
using System.Linq;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Pairing;

/// <summary>
/// The body <c>POST /pairing/codes</c> answers, and the <c>code</c> member of <c>GET /pairing/state</c>.
/// Exact keys, decoded with <see cref="ServersWire.Options"/> like every other reader of the router.
/// </summary>
public sealed record PairingCodeBody
{
    public required string Code { get; init; }
    public required DateTimeOffset IssuedAt { get; init; }
    public required DateTimeOffset ExpiresAt { get; init; }

    /// <summary>
    /// The code the router wrote, checked against the Crockford alphabet the phone types from. A value
    /// outside it is refused rather than shown: a code the phone cannot enter is a number nobody can use.
    /// The refusal does not echo the code, because it is a credential a phone is about to be given.
    /// </summary>
    public IssuedPairingCode ToIssued()
    {
        if (Code is not { Length: CodeLength } || Code.Any(c => !Alphabet.Contains(c)))
        {
            throw new ControlApiException(
                ControlApiFailure.MalformedResponse,
                "the router sent a pairing code outside the Crockford alphabet");
        }
        return new IssuedPairingCode(Code, IssuedAt, ExpiresAt);
    }

    /// <summary>The alphabet of <c>PairingCode.swift</c>: digits and letters, without I, L, O or U.</summary>
    private const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    private const int CodeLength = 8;
}

/// <summary>The body <c>GET /pairing/state</c> answers. The live code, or null once there is none to pair with.</summary>
public sealed record PairingStateBody
{
    public PairingCodeBody? Code { get; init; }
}

/// <summary>The body <c>DELETE /pairing/codes</c> answers: whether a live code was there to revoke.</summary>
public sealed record PairingRevokeBody
{
    public required bool Revoked { get; init; }
}
