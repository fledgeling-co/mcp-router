"""Hermetic controls for absence-review freshness. No product/campaign verdict is rewritten."""
import copy
import hashlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest

import absence_review as A


def item(ident, title, **fields):
    return {"where": "inventory.surface", "kind": "surface", "row": {"id": ident, "title": title, **fields}}


class AbsenceReviewControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.evidence = self.root / "review.json"
        self.evidence.write_text('{"fixture":"reviewed registry search"}\n', encoding="utf-8")
        self.config = {"version": 1, "projectionVersion": 1, "projectIdPattern": r"\b[A-Z]+\d+[A-Z]?\b",
                       "scopes": {"windows-client": {"description": "Windows client surfaces and their runtime integration",
                                                      "kinds": list(A.KINDS), "anyText": ["windows", "winui"]}}}
        self.brief = "planning/features-to-triage/WIN3-shell.md"
        self.parsed = {"meta": {"registry-target": "none", "no-target-reason": "No Windows shell surface currently settles this requirement."},
                       "body": "# Windows shell\n\nA client shell is required.\n"}
        self.rows = [item("SURF-001", "Windows shell"), item("SURF-002", "Mac settings")]
        record = A.proposal(self.config, self.rows, self.brief, self.parsed, "windows-client", require_scope=True)
        record["state"] = "reviewed"
        record["review"] = {"reviewer": "Fixture reviewer", "reviewedAt": "2026-11-01T00:00:00Z",
                            "rationale": "Fixture scope checked against each registry subject and reference.",
                            "candidateEvidence": "review.json",
                            "candidateRows": [{"registry": "inventory.surface", "kind": "surface", "id": "SURF-002",
                                               "canonicalRowSha256": A.digest(self.rows[1]["row"])}],
                            "evidence": [{"path": "review.json", "sha256": hashlib.sha256(self.evidence.read_bytes()).hexdigest()}]}
        self.key = A.key_for(self.brief, A.assertion_digest(self.parsed))
        self.reviews = {"version": 1, "projectionVersion": 1, "entries": {self.key: record}}
        self.baseline = {"version": 1, "carriedUnreviewed": {}}
        self.pin_candidate_assessment()

    def pin_candidate_assessment(self):
        """Fixture authoring seam: explicit rows and their immutable assessment must agree."""
        review = self.reviews["entries"][self.key]["review"]
        by_id = {}
        for pin in review["candidateRows"]:
            candidate = by_id.setdefault(pin["id"], {"id": pin["id"],
                "assessment": "Fixture candidate is a different platform and observable.", "publicRegistryVariants": []})
            candidate["publicRegistryVariants"].append({"registry": pin["registry"], "kind": pin["kind"],
                "canonicalRowSha256": pin["canonicalRowSha256"], "subject": {"title": "Mac settings"}})
        document = {"version": 1, "decision": "scoped absence supported", "brief": self.brief,
                    "assertionDigest": A.assertion_digest(self.parsed), "closestCandidates": list(by_id.values())}
        self.evidence.write_text(json.dumps(document), encoding="utf-8")
        review["evidence"][0]["sha256"] = hashlib.sha256(self.evidence.read_bytes()).hexdigest()

    def assess(self, **changes):
        values = dict(root=self.root, config=self.config, rows=self.rows, brief=self.brief,
                      parsed=self.parsed, reviews=self.reviews, baseline=self.baseline)
        values.update(changes)
        return A.assess(**values)

    def test_reviewed_fingerprint_matches(self):
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_missing_review_reopens(self):
        self.reviews["entries"].clear()
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.assertFalse(self.assess()["carriedUnknown"])

    def test_new_relevant_subject_without_backref_reopens(self):
        self.rows.append(item("SURF-003", "WinUI keyboard navigation"))
        result = self.assess()
        self.assertEqual(result["class"], "STALE_ABSENCE")
        self.assertEqual(result["delta"]["added"], [["inventory.surface", "surface", "SURF-003"]])

    def test_unrelated_row_is_silent(self):
        self.rows.append(item("SURF-003", "Mac document panel"))
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_dismissed_candidate_outside_scope_edits_reopen_and_restore(self):
        before = copy.deepcopy(self.rows)
        scope = self.config["scopes"]["windows-client"]["anyText"]
        self.assertFalse(any(term in self.rows[1]["row"]["title"].lower() for term in scope))
        for field, value in (("title", "Mac document panel"), ("component", "CMP-999"),
                             ("status", "fail"), ("id", "SURF-009")):
            with self.subTest(field=field):
                self.rows = copy.deepcopy(before)
                self.rows[1]["row"][field] = value
                self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
                self.rows = copy.deepcopy(before)
                self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_dismissed_candidate_removal_variant_and_duplicate_reopen(self):
        before = copy.deepcopy(self.rows)
        self.rows.pop(1)
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.rows = copy.deepcopy(before)
        self.rows.append({"where": "surfaces.in.json", "kind": "surface", "row": copy.deepcopy(self.rows[1]["row"])})
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.rows = copy.deepcopy(before) + [copy.deepcopy(before[1])]
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.rows = before
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_candidate_contract_is_required_and_strict(self):
        review = self.reviews["entries"][self.key]["review"]
        original = copy.deepcopy(review["candidateRows"])
        invalid = [None, [], [None], [{}], [dict(original[0], extra=True)], original * 2,
                   original + [dict(original[0], canonicalRowSha256="0" * 64)],
                   [dict(original[0], registry="../outside.json")],
                   [dict(original[0], kind="defect")], [dict(original[0], id="DEF-002")],
                   [dict(original[0], canonicalRowSha256="not-a-hash")],
                   [dict(original[0], canonicalRowSha256=42)]]
        for value in invalid:
            with self.subTest(value=value):
                review["candidateRows"] = value
                self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
                self.assertFalse(A.evidence_valid(self.root, review))
        del review["candidateRows"]
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        review["candidateRows"] = original
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_evidence_extra_fields_cannot_override_candidate_contract(self):
        self.rows[1]["row"]["title"] = "Mac document panel"
        # Even repinning an artifact with a new suggested hash cannot silently restamp the
        # explicit review contract. Its per-candidate explanations are historical evidence.
        document = json.loads(self.evidence.read_text())
        document["suggestedCandidateRows"] = [{"id": "SURF-002", "canonicalRowSha256": A.digest(self.rows[1]["row"])}]
        self.evidence.write_text(json.dumps(document), encoding="utf-8")
        review = self.reviews["entries"][self.key]["review"]
        review["evidence"][0]["sha256"] = hashlib.sha256(self.evidence.read_bytes()).hexdigest()
        self.assertTrue(A.evidence_valid(self.root, review))
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_partial_copied_contract_cannot_forget_a_dismissal(self):
        self.rows.append(item("SURF-003", "Mac document panel"))
        review = self.reviews["entries"][self.key]["review"]
        review["candidateRows"].append({"registry": "inventory.surface", "kind": "surface", "id": "SURF-003",
                                        "canonicalRowSha256": A.digest(self.rows[-1]["row"])})
        self.pin_candidate_assessment()
        original = copy.deepcopy(review["candidateRows"])
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")
        review["candidateRows"] = original[1:]  # Nonempty, but forgets all variants of one ID.
        self.assertIsNone(A.candidate_freshness(self.rows, review))
        self.assertFalse(A.evidence_valid(self.root, review))
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        review["candidateRows"] = original
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_candidate_assessment_source_and_identity_are_bound(self):
        review = self.reviews["entries"][self.key]["review"]
        review["candidateEvidence"] = "missing.json"
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        review["candidateEvidence"] = "review.json"
        review["evidence"].append(copy.deepcopy(review["evidence"][0]))
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        review["evidence"].pop()
        for field in ("brief", "assertionDigest", "decision"):
            self.pin_candidate_assessment()
            document = json.loads(self.evidence.read_text())
            document[field] = "a different claim"
            self.evidence.write_text(json.dumps(document), encoding="utf-8")
            review["evidence"][0]["sha256"] = hashlib.sha256(self.evidence.read_bytes()).hexdigest()
            self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.pin_candidate_assessment()
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_candidate_hash_cannot_be_restamped_without_the_assessment(self):
        self.rows[1]["row"]["description"] = "A different observable after the review."
        review = self.reviews["entries"][self.key]["review"]
        review["candidateRows"][0]["canonicalRowSha256"] = A.digest(self.rows[1]["row"])
        self.assertIsNone(A.candidate_freshness(self.rows, review))
        self.assertFalse(A.evidence_valid(self.root, review))
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_actual_case_oracle_subject_without_backref_reopens(self):
        self.rows.append({"where": "cases.json", "kind": "case", "row": {
            "id": "CASE-003", "oracle": "The Windows shell presents the requested navigation."}})
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_generic_case_linked_to_scoped_surface_reopens_without_join(self):
        self.rows.append({"where": "cases.json", "kind": "case", "row": {
            "id": "CASE-003", "surface": "SURF-001", "oracle": "The requested navigation appears."}})
        result = self.assess()
        self.assertEqual(result["class"], "STALE_ABSENCE")
        self.assertEqual(result["advisory"], [], "registry links do not manufacture brief back-references")

    def test_actual_cmp_component_dependency_and_comp_compatibility(self):
        # inventory.component uses CMP-001..CMP-008; keep the older COMP spelling usable too.
        for prefix in ("CMP", "COMP"):
            with self.subTest(prefix=prefix):
                config = copy.deepcopy(self.config)
                config["scopes"]["windows-client"]["anyText"].append("await scanner")
                component = {"where": "inventory.component", "kind": "component", "row": {
                    "id": prefix + "-999", "name": "Await scanner"}}
                rows = self.rows + [component]
                record = copy.deepcopy(self.reviews["entries"][self.key])
                pinned = A.projection(config, rows, self.brief, "windows-client")
                record["projectionDigest"], record["projection"] = pinned["digest"], pinned["value"]
                rows.append({"where": "cases.json", "kind": "case", "row": {
                    "id": "CASE-9999", "component": prefix + "-999", "oracle": "A generic check."}})
                result = self.assess(config=config, rows=rows, reviews={"entries": {self.key: record}})
                self.assertEqual(result["class"], "STALE_ABSENCE")
                self.assertEqual(result["delta"]["added"], [["cases.json", "case", "CASE-9999"]])
                self.assertEqual(result["advisory"], [])

    def test_generic_case_linked_to_unrelated_surface_is_silent(self):
        self.rows.append({"where": "cases.json", "kind": "case", "row": {
            "id": "CASE-003", "surface": "SURF-002", "oracle": "The requested navigation appears."}})
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_case_relation_retarget_reopens(self):
        case = {"where": "cases.json", "kind": "case", "row": {
            "id": "CASE-003", "surface": "SURF-001", "oracle": "The requested navigation appears."}}
        self.rows.append(case)
        record = self.reviews["entries"][self.key]
        pinned = A.projection(self.config, self.rows, self.brief, "windows-client")
        record["projectionDigest"], record["projection"] = pinned["digest"], pinned["value"]
        case["row"]["surface"] = "SURF-002"
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_relevant_removal_reopens(self):
        self.rows.pop(0)
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_subject_retarget_with_same_id_reopens(self):
        self.rows[0]["row"]["title"] = "Mac shell"
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_explicit_backref_outside_terms_reopens(self):
        self.rows[1]["row"]["note"] = "WIN3. This row describes the requested shell."
        got = self.assess()
        self.assertEqual(got["class"], "STALE_ABSENCE")
        self.assertEqual(got["advisory"][0]["id"], "SURF-002")

    def test_backref_retarget_reopens(self):
        self.rows[0]["row"]["note"] = "WIN3."
        record = self.reviews["entries"][self.key]
        pinned = A.projection(self.config, self.rows, self.brief, "windows-client")
        record["projectionDigest"], record["projection"] = pinned["digest"], pinned["value"]
        self.rows[0]["row"]["note"] = "WIN4."
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_reorder_and_whitespace_are_silent(self):
        self.rows.reverse()
        self.rows[1]["row"] = {"title": "  Windows\n  shell  ", "id": "SURF-001"}
        self.assertEqual(self.assess()["class"], "REVIEWED_ABSENCE")

    def test_changed_assertion_cannot_borrow_review(self):
        self.parsed["meta"]["no-target-reason"] = "No Windows installer surface currently settles this requirement."
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_changed_brief_subject_cannot_borrow_review(self):
        self.parsed["body"] = "# Windows installer\n\nAn installer is required."
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_unknown_scope_refuses_proposal_and_review(self):
        with self.assertRaises(ValueError):
            A.proposal(self.config, self.rows, self.brief, self.parsed, "not-declared", require_scope=True)
        self.reviews["entries"][self.key]["scope"] = "not-declared"
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_no_scope_cannot_create_review_proposal(self):
        with self.assertRaises(ValueError):
            A.proposal(self.config, self.rows, self.brief, self.parsed, require_scope=True)
        self.config["scopes"]["invalid-scope"] = {"description": "A scope with no subject selector at all", "kinds": ["surface"], "anyText": []}
        with self.assertRaises(ValueError):
            A.validate_config(self.config)

    def test_scope_definition_change_reopens(self):
        self.config["scopes"]["windows-client"]["anyText"].append("iphone")
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_changed_or_missing_review_evidence_reopens(self):
        self.evidence.write_text('changed evidence', encoding="utf-8")
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.evidence.unlink()
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")

    def test_project_ids_are_exact_and_only_advisory_fields_count(self):
        rows = [item("SURF-001", "Mac panel", note="WIN30 is different", controls=["WIN3"]),
                item("SURF-002", "Mac document", source=["WIN3."])]
        self.assertEqual(A.advisory(self.config, rows, self.brief)["hits"],
                         [{"id": "SURF-002", "registry": "inventory.surface", "fields": ["source"]}])

    def test_proposal_remains_unreviewed_even_with_current_fingerprint(self):
        record = A.proposal(self.config, self.rows, self.brief, self.parsed, "windows-client", require_scope=True)
        self.reviews["entries"][self.key] = record
        self.assertEqual(record["state"], "unreviewed")
        self.assertIsNone(record["review"])
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.assertFalse(self.assess()["carriedUnknown"])

    def test_exact_historical_proposal_is_carried_as_unknown_only(self):
        record = A.proposal(self.config, self.rows, self.brief, self.parsed)
        self.reviews["entries"][self.key] = record
        self.baseline["carriedUnreviewed"][self.key] = {"proposalDigest": A.digest(record)}
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")
        self.assertTrue(self.assess()["carriedUnknown"])
        self.parsed["meta"]["no-target-reason"] += " The assertion changed."
        self.assertFalse(self.assess()["carriedUnknown"])

    def test_missing_or_altered_proposal_cannot_borrow_legacy_allowance(self):
        record = A.proposal(self.config, self.rows, self.brief, self.parsed)
        self.reviews["entries"][self.key] = record
        self.baseline["carriedUnreviewed"][self.key] = {"proposalDigest": A.digest(record)}
        del self.reviews["entries"][self.key]
        self.assertFalse(self.assess()["carriedUnknown"])
        record["scope"] = "windows-client"
        self.reviews["entries"][self.key] = record
        self.assertFalse(self.assess()["carriedUnknown"])

    def test_new_brief_cannot_borrow_legacy_allowance(self):
        record = A.proposal(self.config, self.rows, self.brief, self.parsed)
        self.reviews["entries"][self.key] = record
        self.baseline["carriedUnreviewed"][self.key] = {"proposalDigest": A.digest(record)}
        self.assertFalse(self.assess(brief="planning/features-to-triage/WIN3-another.md")["carriedUnknown"])

    def test_checking_does_not_mutate_review_or_registry(self):
        before = copy.deepcopy((self.config, self.rows, self.reviews, self.baseline))
        self.assess()
        self.assertEqual(before, (self.config, self.rows, self.reviews, self.baseline))

    def test_missing_registry_is_not_an_empty_verified_projection(self):
        with self.assertRaises(FileNotFoundError):
            A.registry_rows(self.root)

    def test_old_semantic_mechanism_misses_new_subject(self):
        spec = importlib.util.spec_from_file_location("brief_target_legacy_control", pathlib.Path(__file__).with_name("brief-target-gate.py"))
        gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
        raw = "---\nregistry-target: none\nno-target-reason: " + self.parsed["meta"]["no-target-reason"] + "\n---\n" + self.parsed["body"]
        self.assertEqual(gate.classify(raw, {"SURF-001": {}}, {})[0], "NO_TARGET")
        self.rows.append(item("SURF-003", "Windows keyboard"))
        self.assertEqual(gate.classify(raw, {"SURF-001": {}, "SURF-003": {}}, {})[0], "NO_TARGET")
        self.assertEqual(self.assess()["class"], "STALE_ABSENCE")


def control(verbose=True):
    output = io.StringIO()
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(AbsenceReviewControls))
    print("ABSENCE REVIEW CONTROL — %d tests, %d failures, %d errors; %s" %
          (result.testsRun, len(result.failures), len(result.errors), "ALL PLANTS FIRED" if result.wasSuccessful() else "MISSED"))
    if verbose or not result.wasSuccessful():
        print(output.getvalue())
    return result.wasSuccessful()


if __name__ == "__main__":
    raise SystemExit(0 if control() else 1)
