using System;
using System.Collections.Generic;
using System.Linq;
using MCPRouter.Shell.Model.Servers;

namespace MCPRouter.Shell.Model.Inbox;

public sealed class InboxBoardModel
{
    private readonly List<InboxItem> _items = new();

    public DecisionState SelectedFilter { get; set; } = DecisionState.Undecided;
    public string? PairedDeviceName { get; set; }
    public string? Error { get; private set; }
    public bool Loading { get; private set; }
    public bool Writing { get; private set; }
    public bool HasLoaded { get; private set; }
    private readonly IRouterInboxService? _service;

    public InboxBoardModel(IRouterInboxService? service = null) { _service = service; }

    public async Task LoadAsync(CancellationToken cancellation = default)
    {
        if (_service is null || Loading) return;
        Loading = true;
        try
        {
            var snapshot = await _service.ReadAsync(cancellation);
            var rows = snapshot.Items.Select(RouterInboxService.Present).ToList();
            _items.Clear();
            _items.AddRange(rows);
            PairedDeviceName = snapshot.PairedDeviceNames?.FirstOrDefault();
            HasLoaded = true;
            Error = null;
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (ControlApiException ex) { Error = ex.UserFacingDescription; }
        catch (Exception) { Error = "The inbox could not be read. Your last reading is kept; try again."; }
        finally { Loading = false; }
    }

    public async Task DecideAsync(string id, string action, CancellationToken cancellation = default)
    {
        if (_service is null || Writing) return;
        var item = _items.FirstOrDefault(i => i.Id == id);
        if (item is null || action == "accept" && (!item.CanApprove || item.ReviewDigest is null)) return;
        Writing = true;
        try
        {
            await _service.DecideAsync(id, action, action == "accept" ? item.ReviewDigest : null, cancellation);
            Error = null;
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (ControlApiException ex) { Error = ex.UserFacingDescription; return; }
        catch (Exception) { Error = "The decision could not be saved. This item has not been marked as handled."; return; }
        finally { Writing = false; }
        await LoadAsync(cancellation);
    }


    public IReadOnlyList<InboxItem> AllItems => _items;

    public int UndecidedCount => _items.Count(i => i.State == DecisionState.Undecided);
    public int ApprovedCount => _items.Count(i => i.State == DecisionState.Approved);
    public int NotForMeCount => _items.Count(i => i.State == DecisionState.NotForMe);

    public IReadOnlyList<InboxItem> FilteredItems => _items.Where(i => i.State == SelectedFilter).ToList();

    public void PopulateSampleData()
    {
        _items.Clear();

        _items.Add(new InboxItem(
            Id: "postgres-mcp",
            Name: "postgres-mcp",
            OriginKind: InboxOriginKind.Phone,
            OriginLabel: "from Luke's iPhone",
            ArrivedAgo: "2 min ago",
            Lede: "Queued from Discover on the phone. It has not been downloaded and nothing has been written to any harness.",
            CapabilityLines: new List<InboxCapabilityLine>
            {
                new("Read any table in the database you point it at", true),
                new("Run arbitrary SQL, including writes, unless you set it read-only", true),
                new("No network access beyond that database", false),
                new("No filesystem access", false)
            },
            State: DecisionState.Undecided,
            ToolCount: 6
        ));

        _items.Add(new InboxItem(
            Id: "docker-mcp",
            Name: "docker-mcp",
            OriginKind: InboxOriginKind.SessionAnalyst,
            OriginLabel: "Session analyst",
            ArrivedAgo: "41 min ago",
            Lede: "You ran docker logs and docker ps by hand 14 times across 6 sessions this week, twice after an agent said it could not see container output.",
            CapabilityLines: new List<InboxCapabilityLine>
            {
                new("Inspect running containers and service logs", true),
                new("Start and stop containers on demand", true)
            },
            State: DecisionState.Undecided,
            HistoryContext: "~/.claude/history.jsonl   9 matches\n~/.grok/sessions/         3 matches\n~/.codex/history.jsonl    2 matches"
        ));

        _items.Add(new InboxItem(
            Id: "fetch",
            Name: "fetch",
            OriginKind: InboxOriginKind.Phone,
            OriginLabel: "from Luke's iPhone",
            ArrivedAgo: "3 hours ago",
            Lede: "Queued from Discover on the phone. It has not been downloaded and nothing has been written to any harness.",
            CapabilityLines: new List<InboxCapabilityLine>
            {
                new("Fetch URLs and convert HTML to markdown", false)
            },
            State: DecisionState.Undecided,
            ToolCount: 1
        ));
    }

    public void Approve(string id)
    {
        for (int i = 0; i < _items.Count; i++)
        {
            if (_items[i].Id == id)
            {
                _items[i] = _items[i] with { State = DecisionState.Approved };
                return;
            }
        }
    }

    public void Decline(string id)
    {
        for (int i = 0; i < _items.Count; i++)
        {
            if (_items[i].Id == id)
            {
                _items[i] = _items[i] with { State = DecisionState.NotForMe };
                return;
            }
        }
    }
}
