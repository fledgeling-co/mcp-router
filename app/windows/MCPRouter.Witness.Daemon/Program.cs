using System.Globalization;

// A process that starts, says so once, and then waits to be killed.
//
// THE LOG IS NOT THE EVIDENCE. Each start appends a line here, and the witness lane carries those
// lines as corroboration only: a process reporting its own start is the writer reporting on
// itself, which is the shape this campaign exists to refuse. The evidence for "the scheduler
// started it again" is Get-ScheduledTaskInfo's LastRunTime and the CIM process table, neither of
// which this program can reach or influence. The log is here because a run count that disagrees
// with the scheduler's account is worth seeing.
//
// Written beside the executable rather than under a path from the environment, because a task the
// scheduler starts gets the user's stored environment block and not the environment of whatever
// registered it, so an env-var path would resolve to nothing and the file would silently never
// appear.

var port = 0;
for (var i = 0; i < args.Length - 1; i++)
{
    if (string.Equals(args[i], "--port", StringComparison.Ordinal))
    {
        int.TryParse(args[i + 1], NumberStyles.Integer, CultureInfo.InvariantCulture, out port);
    }
}

var exeDir = AppContext.BaseDirectory;
var logPath = Path.Combine(exeDir, "witness-daemon-runs.log");
var line = string.Format(
    CultureInfo.InvariantCulture,
    "{0}\tpid={1}\tport={2}{3}",
    DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
    Environment.ProcessId,
    port,
    Environment.NewLine);

try
{
    File.AppendAllText(logPath, line);
}
catch (IOException)
{
    // Two starts racing on the same file must not take the process down: a daemon that exits 0
    // because it could not write its own log would look to the scheduler like a task that
    // succeeded and finished, and the restart arm would then be measuring the wrong thing.
}

Console.Out.Write(line);
Console.Out.Flush();

// Forever. The exit code only ever comes from whoever terminates this, which is what makes
// LastTaskResult a reading about the kill rather than about the payload.
await Task.Delay(Timeout.Infinite).ConfigureAwait(false);
