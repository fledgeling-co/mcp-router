using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace MCPRouter.Shell.Live.Lifecycle;

/// <summary>The result of one <c>schtasks.exe</c> invocation, exit code included.</summary>
/// <remarks>
/// The exit code is carried rather than folded into a boolean because schtasks distinguishes
/// "no such task" (1) from "access denied" (5) from "the XML is invalid" (1 with a different
/// message), and a supervisor that reduced all three to <c>false</c> would report a permissions
/// problem as an absent registration. That is the shape where an operator is told the daemon is
/// not registered and re-registers it forever.
/// </remarks>
public sealed record TaskCliResult(int ExitCode, string StandardOutput, string StandardError)
{
    public bool Succeeded => ExitCode == 0;
}

/// <summary>Running <c>schtasks.exe</c>, behind an interface so the argv can be read in a test.</summary>
/// <remarks>
/// The seam exists for one reason, and it is not tidiness. Every claim WIN23 makes about the
/// registration - that the trigger is logon, that the principal is un-elevated, that a crash is
/// restarted - is a claim about the ARGUMENTS and the XML this supervisor produces. Behind a real
/// process those claims can only be checked by mutating the machine, which a unit suite must not
/// do; in front of a fake they are checkable by reading exactly what would have been sent.
///
/// This does NOT make the unit tests evidence that the task scheduler accepted it. Nothing here
/// can establish that, and the effect-witness lane exists because nothing here can:
/// <c>scripts/windows/win23-logon-task-witness.ps1</c> registers for real and reads the result
/// back through a different API than the one that wrote it.
/// </remarks>
public interface ITaskSchedulerCli
{
    TaskCliResult Run(IReadOnlyList<string> arguments);
}

/// <summary>The real one: <c>schtasks.exe</c> out of System32, decoded by its own byte-order mark.</summary>
public sealed class SchtasksCli : ITaskSchedulerCli
{
    private readonly string _exePath;

    public SchtasksCli(string? exePath = null)
    {
        // Resolved absolutely rather than left to PATH. A supervisor that registers the machine's
        // startup behaviour is exactly the thing that must not be steered by a `schtasks.exe`
        // dropped earlier on the caller's PATH.
        //
        // IsNullOrWhiteSpace and not `??`, because the empty string is the shape this argument
        // arrives in from a caller that meant "use the default". PowerShell casts $null to the
        // empty string when binding a string parameter, so the witness lane's
        // `SchtasksCli::new([string] $null)` reached a `??` unchanged and produced a ProcessStartInfo
        // with no FileName - which fails at Start with "a file name has not been provided", a
        // message about the process rather than about the argument that caused it.
        _exePath = string.IsNullOrWhiteSpace(exePath)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe")
            : exePath!;
    }

    public TaskCliResult Run(IReadOnlyList<string> arguments)
    {
        var info = new ProcessStartInfo
        {
            FileName = _exePath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var argument in arguments)
        {
            info.ArgumentList.Add(argument);
        }

        using var process = Process.Start(info)
            ?? throw new InvalidOperationException($"could not start {_exePath}");

        // Read stdout as BYTES and decode by sniffing the mark. `schtasks /Query /XML` emits
        // UTF-16LE with a BOM while every other subcommand emits the console code page, so a
        // StreamReader fixed to one encoding returns either mojibake or a string with a NUL
        // between every character - and the XML parse then fails in a way that reads like the
        // scheduler refused the query rather than like this reader chose the wrong decoder.
        byte[] rawOut;
        using (var buffer = new MemoryStream())
        {
            process.StandardOutput.BaseStream.CopyTo(buffer);
            rawOut = buffer.ToArray();
        }
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        return new TaskCliResult(process.ExitCode, DecodeByMark(rawOut), stderr);
    }

    internal static string DecodeByMark(byte[] raw)
    {
        if (raw.Length >= 2 && raw[0] == 0xFF && raw[1] == 0xFE)
        {
            return new UnicodeEncoding(false, true).GetString(raw, 2, raw.Length - 2);
        }
        if (raw.Length >= 2 && raw[0] == 0xFE && raw[1] == 0xFF)
        {
            return new UnicodeEncoding(true, true).GetString(raw, 2, raw.Length - 2);
        }
        if (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF)
        {
            return Encoding.UTF8.GetString(raw, 3, raw.Length - 3);
        }
        return Encoding.UTF8.GetString(raw);
    }
}
