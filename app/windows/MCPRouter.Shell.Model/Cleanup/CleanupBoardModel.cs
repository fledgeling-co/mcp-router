using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;

namespace MCPRouter.Shell.Model.Cleanup;

public sealed class CleanupBoardModel
{
    private readonly List<CleanupRow> _neverCalledRows = new();
    private readonly List<CleanupRow> _quietRows = new();

    public int SelectedDaysWindow { get; set; } = 30;
    public bool IsLoading { get; private set; }
    public string? ErrorMessage { get; private set; }

    public IReadOnlyList<CleanupRow> NeverCalledRows => _neverCalledRows;
    public IReadOnlyList<CleanupRow> QuietRows => _quietRows;

    public int TotalCandidates => _neverCalledRows.Count + _quietRows.Count;
    public int SelectedCount => _neverCalledRows.Count(r => r.IsSelected) + _quietRows.Count(r => r.IsSelected);

    public void PopulateSampleData()
    {
        _neverCalledRows.Clear();
        _quietRows.Clear();

        _neverCalledRows.Add(new CleanupRow(
            Id: "pocketsmith",
            Name: "pocketsmith",
            Kind: CleanupKind.Server,
            ToolCount: 2,
            InstalledDate: "14 Jul 2026",
            WhyItMightStillMatter: "Never signed in, so it has never had the chance",
            SecondaryActionLabel: "Sign in instead"
        ));

        _neverCalledRows.Add(new CleanupRow(
            Id: "ai-elements",
            Name: "ai-elements",
            Kind: CleanupKind.Server,
            ToolCount: 2,
            InstalledDate: "2 Jun 2026",
            WhyItMightStillMatter: "Superseded by a skill you use weekly",
            SecondaryActionLabel: "Remove…",
            IsSelected: true
        ));

        _neverCalledRows.Add(new CleanupRow(
            Id: "graphify",
            Name: "graphify",
            Kind: CleanupKind.Skill,
            ToolCount: null,
            InstalledDate: "9 Aug 2026",
            WhyItMightStillMatter: "Installed 10 days ago — probably just early",
            SecondaryActionLabel: "Keep"
        ));

        _quietRows.Add(new CleanupRow(
            Id: "media-gen-pro",
            Name: "media-gen-pro",
            Kind: CleanupKind.Server,
            ToolCount: 31,
            InstalledDate: "42 d ago",
            WhyItMightStillMatter: "Used in bursts — three runs in one week, then nothing",
            SecondaryActionLabel: "Keep"
        ));

        _quietRows.Add(new CleanupRow(
            Id: "acceptance-e2e",
            Name: "acceptance-e2e",
            Kind: CleanupKind.Skill,
            ToolCount: 12,
            InstalledDate: "36 d ago",
            WhyItMightStillMatter: "Tied to a project that shipped",
            SecondaryActionLabel: "Remove…"
        ));
    }

    public void SetSelection(string id, bool isSelected)
    {
        for (int i = 0; i < _neverCalledRows.Count; i++)
        {
            if (_neverCalledRows[i].Id == id)
            {
                _neverCalledRows[i] = _neverCalledRows[i] with { IsSelected = isSelected };
                return;
            }
        }
        for (int i = 0; i < _quietRows.Count; i++)
        {
            if (_quietRows[i].Id == id)
            {
                _quietRows[i] = _quietRows[i] with { IsSelected = isSelected };
                return;
            }
        }
    }

    public void MarkAllAsKeep()
    {
        for (int i = 0; i < _neverCalledRows.Count; i++)
        {
            _neverCalledRows[i] = _neverCalledRows[i] with { IsSelected = false };
        }
        for (int i = 0; i < _quietRows.Count; i++)
        {
            _quietRows[i] = _quietRows[i] with { IsSelected = false };
        }
    }

    public List<CleanupRow> GetSelectedRows()
    {
        var list = _neverCalledRows.Where(r => r.IsSelected).ToList();
        list.AddRange(_quietRows.Where(r => r.IsSelected));
        return list;
    }
}
