#!/usr/bin/env python3
"""F6 — what an update check can actually read on this machine.

Read-only. Walks a Claude tree and reports SHAPE AND COUNTS only: no value from any file
under it is printed, so the output is safe to commit.

    python3 planning/evidence/F6/measure-update-surface.py [--claude-home ~/.claude]

The one question it answers: for each installed extension, can the router say whether a
newer one exists, and by reading what? The design of `ExtensionFreshness` rests on the
answer being *no* for most of them, in four distinguishable ways.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SEMVER = re.compile(r"^\d+\.\d+\.\d+")
HEXSHA = re.compile(r"^[0-9a-f]{7,40}$")
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---", re.S)


def version_shape(value):
    if not value:
        return "absent"
    if SEMVER.match(value):
        return "semver"
    if HEXSHA.match(value):
        return "hexsha"
    return "other"


def measure_skills(root):
    directory = os.path.join(root, "skills")
    if not os.path.isdir(directory):
        return {"directories": 0, "with_descriptor": 0, "shapes": {}}
    names = sorted(n for n in os.listdir(directory) if not n.startswith("."))
    shapes = {}
    described = 0
    for name in names:
        path = os.path.join(directory, name, "SKILL.md")
        if not os.path.exists(path):
            continue
        described += 1
        with open(path, encoding="utf-8", errors="replace") as handle:
            block = FRONTMATTER.match(handle.read())
        version = None
        if block:
            for line in block.group(1).split("\n"):
                if line.startswith("version:"):
                    version = line.split(":", 1)[1].strip()
        shape = version_shape(version)
        shapes[shape] = shapes.get(shape, 0) + 1
    return {"directories": len(names), "with_descriptor": described, "shapes": shapes}


def read_installed(root):
    path = os.path.join(root, "plugins", "installed_plugins.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle).get("plugins", {})


def read_marketplaces(root):
    directory = os.path.join(root, "plugins", "marketplaces")
    if not os.path.isdir(directory):
        return {}, {}
    catalogue, provenance = {}, {}
    for name in sorted(os.listdir(directory)):
        home = os.path.join(directory, name)
        if not os.path.isdir(home):
            continue
        provenance[name] = "git" if os.path.isdir(os.path.join(home, ".git")) else "not-a-git-checkout"
        manifest = os.path.join(home, ".claude-plugin", "marketplace.json")
        if not os.path.exists(manifest):
            catalogue[name] = None
            continue
        try:
            with open(manifest, encoding="utf-8") as handle:
                offered = json.load(handle).get("plugins", [])
        except (ValueError, OSError):
            catalogue[name] = None
            continue
        catalogue[name] = {
            entry.get("name"): entry for entry in offered if isinstance(entry, dict)
        }
    return catalogue, provenance


def compare(installed, catalogue):
    verdicts = {}
    backwards = 0
    for identity, records in installed.items():
        name, _, market = identity.rpartition("@")
        held = (records or [{}])[0].get("version")
        if market not in catalogue or catalogue[market] is None:
            verdicts["no-catalogue"] = verdicts.get("no-catalogue", 0) + 1
            continue
        offer = catalogue[market].get(name)
        if offer is None:
            verdicts["not-offered"] = verdicts.get("not-offered", 0) + 1
            continue
        available = offer.get("version")
        if not available:
            verdicts["catalogue-declares-no-version"] = verdicts.get("catalogue-declares-no-version", 0) + 1
            continue
        if available == held:
            verdicts["same"] = verdicts.get("same", 0) + 1
            continue
        if version_shape(held) == "semver" and version_shape(available) == "semver":
            held_parts = [int(p) for p in held.split(".")[:3]]
            available_parts = [int(p) for p in available.split(".")[:3]]
            if available_parts > held_parts:
                verdicts["behind"] = verdicts.get("behind", 0) + 1
            else:
                verdicts["catalogue-is-behind"] = verdicts.get("catalogue-is-behind", 0) + 1
                backwards += 1
            continue
        verdicts["unorderable"] = verdicts.get("unorderable", 0) + 1
    return verdicts, backwards


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--claude-home", default=os.path.expanduser("~/.claude"))
    arguments = parser.parse_args()
    root = arguments.claude_home
    if not os.path.isdir(root):
        print(f"no Claude tree at {root}", file=sys.stderr)
        return 2

    skills = measure_skills(root)
    installed = read_installed(root)
    catalogue, provenance = read_marketplaces(root)

    held_shapes = {}
    for records in installed.values():
        shape = version_shape((records or [{}])[0].get("version"))
        held_shapes[shape] = held_shapes.get(shape, 0) + 1

    offered_total = offered_versioned = 0
    for entries in catalogue.values():
        if entries is None:
            continue
        offered_total += len(entries)
        offered_versioned += sum(1 for e in entries.values() if e.get("version"))

    verdicts, backwards = compare(installed, catalogue)

    print(f"claude tree                       {root}")
    print(f"skills directories                {skills['directories']}")
    print(f"  carrying SKILL.md               {skills['with_descriptor']}")
    print(f"  version: in frontmatter         {skills['shapes']}")
    print(f"installed plugin records          {len(installed)}")
    print(f"  version shape                   {held_shapes}")
    print(f"marketplace directories           {len(catalogue)}")
    print(f"  git checkouts                   {sum(1 for v in provenance.values() if v == 'git')}")
    print(f"  not a git checkout              {sum(1 for v in provenance.values() if v != 'git')}")
    print(f"  unreadable manifest             {sum(1 for v in catalogue.values() if v is None)}")
    print(f"plugins offered by a catalogue    {offered_total}")
    print(f"  ...declaring a version          {offered_versioned}")
    print(f"  ...declaring none               {offered_total - offered_versioned}")
    print(f"installed vs offered              {verdicts}")
    print(f"catalogue older than the install  {backwards}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
