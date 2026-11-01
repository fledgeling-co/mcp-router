"""Mask copied registry string values, retaining authored review text and text coordinates.

This is a field-level distinction, not a corpus exclusion. The two supported subject shapes are
versioned; unknown or malformed inputs refuse a verdict. The lexical walk and the decoded JSON
must agree on every string value and object key before any masking is used.
"""
from __future__ import annotations

import json
import pathlib

# Literal copy of absence_review.FIELDS. New fields require an explicit masking-policy review.
SUBJECT_FIELDS = frozenset((
    "cell", "component", "components", "description", "detail", "evidence", "flow", "flows",
    "name", "note", "oracle", "req", "requirements", "route", "slug", "source", "steps",
    "surface", "surfaces", "text", "title",
))
NO_MASK_RECEIPTS = {
    "review-index.json": {"reviewKind": str, "reviewed": list, "unreviewed": list, "currentCounts": dict},
    "scope-controls.json": {"kind": str, "scopes": list, "directRelevantAdditionsTested": int},
    "candidate-freshness.json": {"kind": str, "candidateVariantsPinned": int, "outsideScopeChanges": list},
}


class MaskRefused(ValueError):
    pass


def strict_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise MaskRefused("duplicate JSON object key: %s" % key)
        out[key] = value
    return out


def bad_constant(value):
    raise MaskRefused("non-JSON constant: %s" % value)


def subject_prefixes(file, data):
    if not isinstance(data, dict) or type(data.get("version")) is not int or data["version"] != 1:
        raise MaskRefused("expected a version1 JSON object")
    prefixes = set()

    def subject(row, prefix, required):
        if not isinstance(row, dict) or any(not isinstance(row.get(k), str) or not row[k] for k in required):
            raise MaskRefused("invalid canonical registry row at %r" % (prefix,))
        fields = row.get("subject")
        if not isinstance(fields, dict):
            raise MaskRefused("missing subject object at %r" % (prefix,))
        unknown = set(fields) - SUBJECT_FIELDS
        if unknown:
            raise MaskRefused("unknown canonical subject fields: %s" % ", ".join(sorted(unknown)))
        prefixes.add(prefix + ("subject",))

    if file == "planning/absence-reviews.json":
        if type(data.get("projectionVersion")) is not int or data["projectionVersion"] != 1 \
                or not isinstance(data.get("entries"), dict):
            raise MaskRefused("expected version1 review entries/projections")
        for key, entry in data["entries"].items():
            if not isinstance(entry, dict) or "projection" not in entry:
                raise MaskRefused("review entry is missing its projection")
            projection = entry["projection"]
            if projection is None:
                continue
            if not isinstance(projection, dict) or type(projection.get("projectionVersion")) is not int \
                    or projection["projectionVersion"] != 1 or not isinstance(projection.get("rows"), list):
                raise MaskRefused("projection.rows must be an array")
            for index, row in enumerate(projection["rows"]):
                subject(row, ("entries", key, "projection", "rows", index), ("id", "kind", "registry"))
        return prefixes, "canonical review projection subjects"

    path = pathlib.PurePosixPath(file)
    if path.parent != pathlib.PurePosixPath("planning/evidence/absence-reviews"):
        raise MaskRefused("unsupported mirrored-artifact path")
    if path.name in NO_MASK_RECEIPTS:
        if "entries" in data or "closestCandidates" in data:
            raise MaskRefused("no-mask receipt unexpectedly carries a subject-bearing shape")
        if any(type(data.get(k)) is not kind for k, kind in NO_MASK_RECEIPTS[path.name].items()):
            raise MaskRefused("unrecognised no-mask receipt shape: %s" % path.name)
        return prefixes, "explicit no-mask receipt"
    if not isinstance(data.get("brief"), str) or not isinstance(data.get("assertionDigest"), str) \
            or not isinstance(data.get("closestCandidates"), list):
        raise MaskRefused("expected a per-brief closestCandidates evidence object")
    for index, candidate in enumerate(data["closestCandidates"]):
        if not isinstance(candidate, dict) or not isinstance(candidate.get("id"), str) \
                or not isinstance(candidate.get("publicRegistryVariants"), list):
            raise MaskRefused("candidate.publicRegistryVariants must be an array")
        for variant_index, variant in enumerate(candidate["publicRegistryVariants"]):
            subject(variant, ("closestCandidates", index, "publicRegistryVariants", variant_index), ("kind", "registry"))
    return prefixes, "canonical candidate registry subjects"


def decoded_strings(value, path=()):
    """All decoded string VALUE leaves, not object keys; other JSON values remain unmasked."""
    if isinstance(value, str):
        return {path: value}, 0
    leaves, keys = {}, 0
    if isinstance(value, dict):
        keys += len(value)
        items = value.items()
    elif isinstance(value, list):
        items = enumerate(value)
    else:
        return leaves, keys
    for key, item in items:
        child, child_keys = decoded_strings(item, path + (key,))
        leaves.update(child)
        keys += child_keys
    return leaves, keys


def string_spans(raw):
    """A scanstring-based JSON walk; offsets are Python character indices in the original text."""
    spans, keys = [], 0
    decoder = json.JSONDecoder(parse_constant=bad_constant)

    def ws(i):
        while i < len(raw) and raw[i] in " \t\r\n":
            i += 1
        return i

    def value(i, path):
        nonlocal keys
        i = ws(i)
        if raw[i] == '"':
            decoded, end = json.decoder.scanstring(raw, i + 1)
            spans.append((path, i + 1, end - 1, decoded))
            return end
        if raw[i] == "{":
            i = ws(i + 1)
            if raw[i] == "}":
                return i + 1
            while True:
                if raw[i] != '"':
                    raise MaskRefused("object-key walk lost its string boundary")
                key, i = json.decoder.scanstring(raw, i + 1)
                keys += 1
                i = ws(i)
                if raw[i] != ":":
                    raise MaskRefused("object-key walk lost its colon")
                i = ws(value(i + 1, path + (key,)))
                if raw[i] == "}":
                    return i + 1
                if raw[i] != ",":
                    raise MaskRefused("object walk lost its separator")
                i = ws(i + 1)
        if raw[i] == "[":
            i, index = ws(i + 1), 0
            if raw[i] == "]":
                return i + 1
            while True:
                i = ws(value(i, path + (index,)))
                if raw[i] == "]":
                    return i + 1
                if raw[i] != ",":
                    raise MaskRefused("array walk lost its separator")
                i, index = ws(i + 1), index + 1
        scalar, end = decoder.raw_decode(raw, i)
        if isinstance(scalar, (str, dict, list)):
            raise MaskRefused("scalar walk encountered an unwalked container/string")
        return end

    end = ws(value(0, ()))
    if end != len(raw):
        raise MaskRefused("JSON walk did not consume the complete input")
    return spans, keys


def mask_strings(file, raw, citation_re):
    try:
        data = json.loads(raw, object_pairs_hook=strict_object, parse_constant=bad_constant)
        prefixes, role = subject_prefixes(file, data)
        expected, expected_keys = decoded_strings(data)
        spans, keys = string_spans(raw)
    except (ValueError, IndexError, RecursionError) as exc:
        raise MaskRefused(str(exc)) from exc
    if len(spans) != len(expected) or keys != expected_keys \
            or any(path not in expected or expected[path] != text for path, _, _, text in spans):
        raise MaskRefused("lexical/decoded JSON string-leaf or object-key counts disagree")
    out = list(raw)
    masked = chars = citations = 0
    for path, start, end, _ in spans:
        # Exact prefixes produced by the two validated schemas; authored neighbouring fields never qualify.
        selected = (len(path) >= 7 and path[:6] in prefixes) or (len(path) >= 6 and path[:5] in prefixes)
        if not selected:
            continue
        masked += 1
        chars += end - start
        citations += len(citation_re.findall(raw[start:end]))
        for index in range(start, end):
            if out[index] not in "\r\n":
                out[index] = " "
    result = "".join(out)
    if len(result) != len(raw) or result.count("\n") != raw.count("\n"):
        raise MaskRefused("mask changed character offsets or line numbers")
    return result, {"file": file, "role": role, "valueStrings": len(spans), "keyStrings": keys,
                    "stringsMasked": masked, "charactersBlanked": chars, "citationsMasked": citations}
