"""Freshness of a reviewed absence, separate from citations and from proof that absence is true.

A scope is a declared set of registry kinds and literal subject terms. It is not inferred from a
brief and never creates a join. Reviewers must choose a sufficient scope and record their evidence.
The projection includes relevant rows even without back-references, plus rows explicitly naming the
brief. Checking only reads; proposal commands emit unreviewed data and cannot certify a review.
"""
from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import re

from input_accounting import Tally

VERSION = 1
CONFIG = "planning/absence-review-scopes.json"
REVIEWS = "planning/absence-reviews.json"
BASELINE = "planning/absence-review-unreviewed-baseline.json"
KINDS = ("case", "requirement", "surface", "defect", "flow", "component")
SUBJECT_FIELDS = ("title", "text", "name", "description", "slug", "oracle", "cell", "steps", "route")
REFERENCE_FIELDS = ("note", "title", "evidence", "source", "detail")
RELATION_FIELDS = ("req", "surface", "flow", "component", "surfaces", "requirements", "components", "flows")
FIELDS = tuple(sorted(set(SUBJECT_FIELDS + REFERENCE_FIELDS + RELATION_FIELDS)))
REGISTRY_ID = re.compile(r"\b(?:REQ|CASE|DEF|SURF|FLOW|CMP|COMP)-\d+\b")
REGISTRIES = (("cases.json", "case"), ("cases.in.json", "case"),
              ("requirements.in.json", "requirement"), ("surfaces.in.json", "surface"),
              ("defects.in.json", "defect"), ("flows.in.json", "flow"),
              ("components.in.json", "component"))


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def normalized(value):
    return " ".join(value.split())


def strings(value):
    """String leaves, accounted by the caller's row; ordering of arrays/maps is not semantic here."""
    if isinstance(value, str):
        return [normalized(value)]
    if isinstance(value, list):
        return sorted({s for item in value for s in strings(item)})
    if isinstance(value, dict):
        return sorted({s for item in value.values() for s in strings(item)})
    return []


def normalized_field(value):
    """Preserve field structure and ordered steps; ignore only string whitespace and object order."""
    if isinstance(value, str):
        return normalized(value)
    if isinstance(value, dict):
        return {k: normalized_field(v) for k, v in value.items()}
    if isinstance(value, list):
        return [normalized_field(v) for v in value]
    return value


def assertion_digest(parsed):
    # The body is included so replacing a brief's subject cannot retain its old reason's review.
    return digest({"version": VERSION, "target": parsed["meta"].get("registry-target", "").lower(),
                   "reason": normalized(parsed["meta"].get("no-target-reason", "")),
                   "body": normalized(parsed["body"])})


def key_for(brief, assertion):
    return brief + "#" + assertion


def read_json(root, name):
    path = repo_path(root, name)
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("version") != VERSION:
        raise ValueError("%s needs object schema version %d" % (name, VERSION))
    return value


def repo_path(root, relative):
    if not isinstance(relative, str) or pathlib.PurePosixPath(relative).is_absolute() or "\\" in relative:
        raise ValueError("review paths must be repository-relative POSIX paths")
    if ".." in pathlib.PurePosixPath(relative).parts:
        raise ValueError("review paths may not traverse outside the repository")
    root = root.resolve()
    path = (root / relative).resolve()
    if not path.is_relative_to(root):
        raise ValueError("review path escapes repository: %s" % relative)
    return path


def validate_config(config):
    if config.get("version") != VERSION or config.get("projectionVersion") != VERSION:
        raise ValueError("unsupported absence scope/projection version")
    pattern = config.get("projectIdPattern")
    if not isinstance(pattern, str) or not pattern or re.compile(pattern).match(""):
        raise ValueError("projectIdPattern must be explicit and cannot match empty text")
    if not isinstance(config.get("scopes"), dict):
        raise ValueError("scopes must be an explicitly declared map")
    for name in config["scopes"]:
        scope_for(config, name)


def scope_for(config, name):
    scope = config.get("scopes", {}).get(name) if isinstance(name, str) else None
    if not isinstance(scope, dict):
        raise ValueError("missing or unknown subject scope: %r" % name)
    if not re.fullmatch(r"[a-z][a-z0-9-]{2,63}", name):
        raise ValueError("subject scope needs a stable lowercase key")
    if set(scope) != {"description", "kinds", "anyText"}:
        raise ValueError("scope supports exactly description, kinds and anyText")
    if not isinstance(scope["description"], str) or len(normalized(scope["description"])) < 24:
        raise ValueError("scope needs a description of the subject it covers")
    kinds, terms = scope["kinds"], scope["anyText"]
    if not isinstance(kinds, list) or not kinds or any(k not in KINDS for k in kinds):
        raise ValueError("scope kinds must explicitly name supported registry kinds")
    if not isinstance(terms, list) or not terms or any(
        not isinstance(t, str) or len(normalized(t)) < 3 or not re.search(r"\w{3}", t)
        for t in terms
    ):
        raise ValueError("scope anyText needs nonempty literal subject terms (at least three letters)")
    return {"description": normalized(scope["description"]), "kinds": sorted(set(kinds)),
            "anyText": sorted({normalized(t).casefold() for t in terms})}


def project_id(config, brief):
    match = re.compile(config["projectIdPattern"]).match(pathlib.PurePosixPath(brief).stem)
    return match.group(0) if match else None


def references(config, row):
    pattern = re.compile(config["projectIdPattern"])
    return {field: sorted({m.group(0) for text in strings(row.get(field)) for m in pattern.finditer(text)})
            for field in REFERENCE_FIELDS}


def registry_rows(root):
    """Strictly read the same eight registries whose union the citation resolver reads."""
    camp = root / "planning/test-campaign"
    tally = Tally("absence projection registry", "seven seed/live arrays and inventory kind arrays")
    out = []

    def add(rows, where, kind):
        if not isinstance(rows, list):
            raise ValueError("%s is not a registry array" % where)
        for position, row in enumerate(rows):
            label = "%s[%d]" % (where, position)
            if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"]:
                raise ValueError("%s has no usable registry id; cannot certify its absence" % label)
            tally.keep(label)
            out.append({"where": where, "kind": kind, "row": row})

    for filename, kind in REGISTRIES:
        add(json.loads((camp / filename).read_text(encoding="utf-8")), filename, kind)
    inventory = json.loads((camp / "inventory.json").read_text(encoding="utf-8"))
    if not isinstance(inventory, dict):
        raise ValueError("inventory.json is not an object")
    for kind, rows in inventory.items():
        if kind not in KINDS:
            raise ValueError("unknown inventory kind %s; declare its projection semantics first" % kind)
        add(rows, "inventory." + kind, kind)
    if tally.measured_nothing():
        raise ValueError("absence projection read no registry rows")
    return out, tally


def advisory(config, rows, brief):
    ident = project_id(config, brief)
    hits, tally = [], Tally("advisory reverse references", "all registry rows; allowed reference fields only")
    for item in rows:
        fields = [field for field, ids in references(config, item["row"]).items() if ident and ident in ids]
        if fields:
            tally.keep((item["where"], item["row"]["id"]))
            hits.append({"id": item["row"]["id"], "registry": item["where"], "fields": fields})
        else:
            tally.drop((item["where"], item["row"]["id"]),
                       "no exact project ID in allowed fields" if ident else "brief has no declared-pattern project ID")
    return {"hits": sorted(hits, key=canonical), "accounting": tally.line()}


def projection(config, rows, brief, scope_name):
    scope = scope_for(config, scope_name)
    ident = project_id(config, brief)
    selected, omitted = [], Tally("subject projection", "all registry rows")
    prepared, selected_ids = [], set()
    for item in rows:
        row = item["row"]
        refs = references(config, row)
        text = " ".join(s for field in FIELDS for s in strings(row.get(field))).casefold()
        subject = item["kind"] in scope["kinds"] and any(
            re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", text) for term in scope["anyText"])
        backref = ident is not None and any(ident in ids for ids in refs.values())
        links = {match.group(0) for field in RELATION_FIELDS for text in strings(row.get(field))
                 for match in REGISTRY_ID.finditer(text)}
        if subject or backref:
            selected_ids.add(row["id"])
        prepared.append((item, refs, links))
    # A case's oracle can be generic while its exact surface/requirement link names the subject.
    # Follow these existing inbound registry relations, without inferring a citation to the brief
    # and without pulling a selected row's other/outgoing subjects into the scope.
    while True:
        related = {item["row"]["id"] for item, _, links in prepared
                   if item["kind"] in scope["kinds"] and links & selected_ids}
        if related <= selected_ids:
            break
        selected_ids.update(related)
    for item, refs, _ in prepared:
        row = item["row"]
        if row["id"] in selected_ids:
            omitted.keep((item["where"], row["id"]))
            selected.append({"id": row["id"], "kind": item["kind"], "registry": item["where"],
                             "subject": {field: normalized_field(row.get(field)) for field in FIELDS},
                             "backrefs": refs})
        else:
            omitted.drop((item["where"], row["id"]), "outside declared subject, exact back-references and inbound registry relations")
    # Physical array order, object order and string whitespace do not affect this projection.
    value = {"projectionVersion": VERSION, "scopeKey": scope_name, "scope": scope,
             "projectIdPattern": config["projectIdPattern"], "briefId": ident,
             "rows": sorted(selected, key=canonical)}
    return {"digest": digest(value), "value": value, "accounting": omitted.line()}


def proposal(config, rows, brief, parsed, scope_name=None, require_scope=False):
    if require_scope or scope_name is not None:
        projected = projection(config, rows, brief, scope_name)
    else:
        projected = None
    return {"brief": brief, "assertionDigest": assertion_digest(parsed), "state": "unreviewed",
            "scope": scope_name, "projectionVersion": VERSION,
            "projectionDigest": projected["digest"] if projected else None,
            "projection": projected["value"] if projected else None, "review": None}


def evidence_valid(root, review):
    if not isinstance(review, dict) or set(review) != {"reviewer", "reviewedAt", "rationale", "evidence"}:
        return False
    if any(not isinstance(review.get(k), str) for k in ("reviewer", "reviewedAt", "rationale")):
        return False
    if len(normalized(review["reviewer"])) < 3 or len(normalized(review["rationale"])) < 24:
        return False
    try:
        stamp = datetime.datetime.fromisoformat(review["reviewedAt"].replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            return False
    except ValueError:
        return False
    artifacts = review["evidence"]
    if not isinstance(artifacts, list) or not artifacts:
        return False
    for artifact in artifacts:
        if not isinstance(artifact, dict) or set(artifact) != {"path", "sha256"}:
            return False
        try:
            data = repo_path(root, artifact["path"]).read_bytes()
        except (OSError, ValueError):
            return False
        if not data or artifact["sha256"] != hashlib.sha256(data).hexdigest():
            return False
    return True


def assess(root, config, rows, brief, parsed, reviews, baseline):
    assertion = assertion_digest(parsed)
    key = key_for(brief, assertion)
    record = reviews.get("entries", {}).get(key)
    suggestions = advisory(config, rows, brief)
    result = {"brief": brief, "key": key, "class": "STALE_ABSENCE", "carriedUnknown": False,
              "reason": "missing review for this exact brief/assertion", "advisory": suggestions["hits"],
              "advisoryAccounting": suggestions["accounting"]}
    if not isinstance(record, dict):
        return result
    if set(record) != {"brief", "assertionDigest", "state", "scope", "projectionVersion", "projectionDigest", "projection", "review"}:
        result["reason"] = "invalid review record shape"
        return result
    if record["brief"] != brief or record["assertionDigest"] != assertion:
        result["reason"] = "review key does not match brief/assertion"
        return result
    if record["state"] == "unreviewed":
        result["reason"] = "unreviewed proposal; absence is unknown, not verified"
        carried = baseline.get("carriedUnreviewed", {}).get(key, {})
        result["carriedUnknown"] = (record["scope"] is None and record["projectionDigest"] is None
                                     and record["projection"] is None
                                     and record["review"] is None and record["projectionVersion"] == VERSION
                                     and isinstance(carried, dict) and carried.get("proposalDigest") == digest(record))
        return result
    if record["state"] != "reviewed" or record["projectionVersion"] != VERSION:
        result["reason"] = "unsupported review state or projection version"
        return result
    try:
        current = projection(config, rows, brief, record["scope"])
    except ValueError as exc:
        result["reason"] = str(exc)
        return result
    result["projectionAccounting"] = current["accounting"]
    result["currentProjectionDigest"] = current["digest"]
    pinned = record["projection"]
    if not isinstance(pinned, dict) or record["projectionDigest"] != digest(pinned):
        result["reason"] = "review projection snapshot is missing or does not match its digest"
    elif record["projectionDigest"] != current["digest"]:
        result["reason"] = "declared subject projection changed; review reopened"
        def indexed(value):
            return {(r["registry"], r["kind"], r["id"]): r for r in value.get("rows", [])}
        before, after = indexed(pinned), indexed(current["value"])
        result["delta"] = {"added": [list(k) for k in sorted(set(after) - set(before))],
                           "removed": [list(k) for k in sorted(set(before) - set(after))],
                           "changed": [list(k) for k in sorted(set(before) & set(after)) if before[k] != after[k]],
                           "scopeChanged": pinned.get("scope") != current["value"]["scope"]}
    elif not evidence_valid(root, record["review"]):
        result["reason"] = "review provenance/evidence is missing, changed or invalid"
    else:
        result.update({"class": "REVIEWED_ABSENCE", "reason": "recorded review is current within its declared scope"})
    return result


def load(root):
    config, reviews, baseline = (read_json(root, name) for name in (CONFIG, REVIEWS, BASELINE))
    validate_config(config)
    if reviews.get("projectionVersion") != VERSION or not isinstance(reviews.get("entries"), dict):
        raise ValueError("absence reviews need entries and the current projectionVersion")
    if not isinstance(baseline.get("carriedUnreviewed"), dict):
        raise ValueError("unreviewed baseline needs exact keyed proposals")
    rows, tally = registry_rows(root)
    return config, reviews, baseline, rows, tally
