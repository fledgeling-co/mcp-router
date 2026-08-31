using System;
using System.Collections.Generic;

namespace MCPRouter.Shell.Model.CapabilityDocument;

public sealed class CapabilityDocumentViewModel
{
    public CapabilityDocumentTab ActiveTab { get; set; } = CapabilityDocumentTab.Capabilities;
    public CapabilityDocument? Document { get; private set; }

    public void LoadDocument(string id)
    {
        Document = new CapabilityDocument(
            CapabilityId: id,
            DisplayName: id,
            InstalledVersion: "v1.2.0",
            CandidateVersion: "v1.3.0",
            IsUpdateHeld: true,
            CapabilityDeltas: new List<CapabilityDiffItem>
            {
                new("execute_raw_query", "Execute arbitrary read queries against specified databases", true, true),
                new("export_schema", "Generate schema DDL representation", true, false)
            },
            ChangelogText: "### v1.3.0 (2026-08-25)\n- Added execute_raw_query tool\n- Improved connection pooling\n- Added schema export capability",
            FlagsWorthKnowing: new List<string>
            {
                "Requires network access to target database port",
                "Holds credentials in memory during active session"
            }
        );
    }
}
