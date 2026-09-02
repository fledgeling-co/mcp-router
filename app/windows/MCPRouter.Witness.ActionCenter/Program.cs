using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

// Reads what is actually in this user's Action Center, and can take back out of it anything a
// witness put there.
//
// WHY IT EXISTS. DEF-082 recorded that no instrument on this host could see a toast in the Action
// Center, and gave a reason: enumerating one needs UserNotificationListener, whose
// userNotificationListener capability is only grantable to a packaged application, and
// MCPRouter.Shell is WindowsPackageType=None. MEASURED 2026-09-03 on this machine, that reason is
// wrong. From an ordinary unpackaged Win32 process with no package identity at all - Package.Current
// throws InvalidOperationException - UserNotificationListener.Current resolves, RequestAccessAsync
// returns Allowed, and GetNotificationsAsync returns the toasts that are really there, including
// ones raised by MCPRouter.Shell's own witness runs the day before. No MSIX, no capability, no
// consent prompt.
//
// WHAT DOES NOT WORK UNPACKAGED, and it is the reason this tool matches on TEXT rather than on
// publisher: every member of UserNotification.AppInfo - AppUserModelId, PackageFamilyName,
// DisplayInfo - throws NotImplementedException (0x80004001) for a caller with no package identity.
// So this tool can say what a notification SAYS and when it arrived, and cannot say who raised it.
// A lane built on it has to make the text carry the attribution, and has to say that it does.
//
// This is a harness binary. It is referenced by no product project and ships in nothing.

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        string outPath = null;
        var removeIds = new List<uint>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--out" && i + 1 < args.Length) { outPath = args[++i]; }
            else if (args[i] == "--remove" && i + 1 < args.Length
                     && uint.TryParse(args[++i], NumberStyles.Integer, CultureInfo.InvariantCulture, out var id))
            {
                removeIds.Add(id);
            }
        }

        UserNotificationListener listener;
        UserNotificationListenerAccessStatus access;
        try
        {
            listener = UserNotificationListener.Current;
            access = await listener.RequestAccessAsync();
        }
        catch (Exception e)
        {
            // Written as a document rather than thrown, because a lane that gets no file cannot
            // tell "the listener refused" from "the tool never ran", and those want different
            // remedies.
            Write(outPath, new
            {
                schema = "mcprouter.action-center-witness/1",
                ok = false,
                failure = e.GetType().Name,
                hresult = "0x" + e.HResult.ToString("X8", CultureInfo.InvariantCulture),
                message = e.Message.Trim(),
            });
            return 3;
        }

        foreach (var id in removeIds)
        {
            try { listener.RemoveNotification(id); }
            catch (Exception e)
            {
                Console.Error.WriteLine($"remove {id} failed: {e.GetType().Name} 0x{e.HResult:X8}");
            }
        }

        var records = new List<object>();
        var failure = (string)null;
        try
        {
            foreach (var notification in await listener.GetNotificationsAsync(NotificationKinds.Toast))
            {
                records.Add(new
                {
                    id = notification.Id,
                    createdUtc = SafeCreated(notification),
                    text = SafeText(notification),
                    // Collected so the lane can SAY it is empty rather than the reader having to
                    // discover it. An unpackaged caller gets NotImplementedException here, every
                    // time, for every notification.
                    appUserModelId = SafeAumid(notification),
                });
            }
        }
        catch (Exception e)
        {
            failure = e.GetType().Name + " 0x" + e.HResult.ToString("X8", CultureInfo.InvariantCulture);
        }

        Write(outPath, new
        {
            schema = "mcprouter.action-center-witness/1",
            ok = failure is null,
            failure,
            access = access.ToString(),
            packaged = IsPackaged(),
            readAtUtc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
            count = records.Count,
            notifications = records,
        });
        return failure is null ? 0 : 1;
    }

    private static string SafeCreated(UserNotification n)
    {
        try { return n.CreationTime.UtcDateTime.ToString("o", CultureInfo.InvariantCulture); }
        catch (Exception e) { return "UNREADABLE: " + e.GetType().Name; }
    }

    private static string SafeAumid(UserNotification n)
    {
        try { return n.AppInfo.AppUserModelId; }
        catch (Exception e) { return "UNREADABLE: " + e.GetType().Name + " 0x" + e.HResult.ToString("X8", CultureInfo.InvariantCulture); }
    }

    private static string[] SafeText(UserNotification n)
    {
        try
        {
            var binding = n.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric);
            if (binding is null) { return Array.Empty<string>(); }
            var parts = new List<string>();
            foreach (var element in binding.GetTextElements()) { parts.Add(element.Text); }
            return parts.ToArray();
        }
        catch (Exception e)
        {
            return new[] { "UNREADABLE: " + e.GetType().Name };
        }
    }

    private static bool IsPackaged()
    {
        try { _ = Windows.ApplicationModel.Package.Current.Id.FullName; return true; }
        catch (Exception) { return false; }
    }

    private static void Write(string path, object document)
    {
        var json = JsonSerializer.Serialize(document, new JsonSerializerOptions { WriteIndented = true });
        if (string.IsNullOrEmpty(path)) { Console.Out.Write(json); return; }
        File.WriteAllText(path, json, new UTF8Encoding(false));
        Console.Out.Write(json);
    }
}
