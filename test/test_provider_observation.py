"""Independent assertions for the synthetic observation contract; stdlib only."""

from copy import deepcopy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from provider_observation_contract import (
    Catalog, ContractError, Replay, check_evidence, legacy_observation,
    load_document, replay_document, strict_json, suffix, validate_document,
)


FIXTURES = Path(__file__).parent / "fixtures" / "provider_observation" / "v1"


def patch_pointer(value, pointer, replacement):
    result = deepcopy(value)
    parts = pointer.removeprefix("/").split("/")
    node = result
    for part in parts[:-1]:
        node = node[int(part)] if isinstance(node, list) else node[part]
    last = int(parts[-1]) if isinstance(node, list) else parts[-1]
    node[last] = deepcopy(replacement)
    return result


class ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The implementation never receives the oracle documents as definitions.
        cls.docs = {name: load_document(FIXTURES / f"{name}.json", name) for name in (
            "describe", "scenario", "updates", "expected_snapshots", "queries", "legacy", "replay_cases")}
        cls.descriptor = cls.docs["describe"]
        cls.scenario = cls.docs["scenario"]
        cls.events = cls.docs["updates"]["events"]
        cls.snapshots = {s["cursor"]: s for s in cls.docs["expected_snapshots"]["snapshots"]}

    def setUp(self):
        self.catalog = Catalog(self.descriptor, self.scenario)

    def reader(self, cursor, catalog=None):
        reader = Replay(catalog or self.catalog)
        for event in self.events[:cursor]:
            reader.accept(event)
        return reader

    def assertCode(self, code, function, *args, **kwargs):
        with self.assertRaises(ContractError) as caught:
            function(*args, **kwargs)
        self.assertEqual(caught.exception.code, code, str(caught.exception))

    def reject_event(self, cursor, candidate, code, catalog=None):
        reader = self.reader(cursor, catalog)
        before, journal = reader.state, reader.journal
        self.assertCode(code, reader.accept, candidate)
        self.assertEqual(reader.state, before)
        self.assertEqual(reader.journal, journal)
        return reader

    def mutate(self, collection, identity, field, value):
        scenario = deepcopy(self.scenario)
        for obj in scenario[collection]:
            if (obj["id"] if isinstance(obj, dict) else obj[0]) == identity:
                obj[field] = deepcopy(value)
                return scenario
        self.fail(f"unknown mutation target {identity}")

    def query(self, reader, kind, key=None, **overrides):
        params = dict(scope=self.descriptor["scope"], stream_id=self.descriptor["stream_id"], cursor=reader.state["cursor"], key=key)
        params.update(overrides)
        return reader.query(kind, **params)

    def test_documents_references_and_actual_evidence(self):
        check_evidence(self.catalog, FIXTURES)
        self.assertEqual(len(self.catalog.artifacts), 5)
        self.assertEqual(len(self.events), 34)
        for name in ("updates", "expected_snapshots", "queries"):
            self.assertEqual(self.docs[name]["stream_id"], self.descriptor["stream_id"])
        self.assertEqual(self.docs["queries"]["scope"], self.descriptor["scope"])
        self.assertEqual({r["configuration_id"] for r in self.catalog.runs.values()}, {"config-B"})
        self.assertEqual(self.catalog.operations["op-a"]["intent"], self.catalog.operations["op-b"]["intent"])
        self.assertEqual(self.catalog.operations["op-a"]["intent"], self.catalog.operations["op-reject"]["intent"])

    def test_all_six_complete_hand_authored_snapshots(self):
        self.assertEqual(list(self.snapshots), [3, 7, 13, 15, 27, 34])
        reader = Replay(self.catalog)
        for event in self.events:
            reader.accept(event)
            if event[0] in self.snapshots:
                with self.subTest(cursor=event[0]):
                    self.assertEqual(reader.state, self.snapshots[event[0]])
        self.assertEqual(sum(r[1] for r in reader.state["runs"]), 30)

    def test_journal_envelope_and_prefix_visibility(self):
        self.assertEqual(replay_document(self.catalog, self.docs["updates"]).state, self.snapshots[34])
        self.assertEqual(replay_document(self.catalog, self.docs["updates"], 3).state, self.snapshots[3])
        bad = self.docs["updates"] | {"stream_id": "other-store-stream"}
        self.assertCode("RESET_REQUIRED", replay_document, self.catalog, bad)
        bad = self.docs["updates"] | {"events": self.events[:-1]}
        self.assertCode("INVALID_CURSOR", replay_document, self.catalog, bad)
        self.assertCode("CURSOR_AHEAD", replay_document, self.catalog, self.docs["updates"], 35)
        self.assertCode("INVALID_RECORD", replay_document, self.catalog, self.docs["updates"], True)

    def test_every_checkpoint_recovers_to_every_later_checkpoint(self):
        for start, snapshot in self.snapshots.items():
            for end, expected in self.snapshots.items():
                if end < start:
                    continue
                with self.subTest(start=start, end=end):
                    reader = Replay(self.catalog, snapshot, self.events[:start])
                    for event in self.events[start:end]:
                        reader.accept(event)
                    self.assertEqual(reader.state, expected)

    def test_all_exact_queries(self):
        for q in self.docs["queries"]["queries"]:
            with self.subTest(query=q["id"]):
                if q["kind"] in ("snapshot_and_suffix", "suffix"):
                    start = q.get("snapshot_cursor", q.get("after_cursor"))
                    events = suffix(self.descriptor, self.events, scope=self.descriptor["scope"], stream_id=self.descriptor["stream_id"], after=start, through=q["through_cursor"])
                    self.assertEqual([e[0] for e in events], q["expected_sequences"])
                    reader = Replay(self.catalog, self.snapshots[start], self.events[:start])
                    for event in events:
                        reader.accept(event)
                    self.assertEqual(reader.state, self.snapshots[q["expected_snapshot_cursor"]])
                    self.assertEqual(reader.state, self.reader(q["through_cursor"]).state)
                    continue
                reader = self.reader(q["cursor"])
                before = reader.state, reader.journal
                response = self.query(reader, q["kind"], q.get("request_key", q.get("run_id")))
                envelope = dict(scope=self.descriptor["scope"], stream_id=self.descriptor["stream_id"], cursor=q["cursor"])
                if q["kind"] == "request_lookup":
                    expected = q["expected"]
                else:
                    expected = {k.removeprefix("expected_"): v for k, v in q.items() if k.startswith("expected_")}
                self.assertEqual(response, envelope | expected)
                self.assertEqual((reader.state, reader.journal), before)

    def test_recovery_restores_snapshot_and_applies_only_suffix_to_it(self):
        # Prefix validation uses a separate reader, not this restored instance.
        class SuffixOnly(Replay):
            def _apply(inner, state, event):
                self.assertGreater(event[0], 15)
                super()._apply(state, event)

        snapshot = deepcopy(self.snapshots[15])
        reader = SuffixOnly(self.catalog, snapshot, self.events[:15])
        snapshot["runs"][0][2] = "failed"
        self.assertEqual(reader.state, self.snapshots[15])
        self.assertFalse(reader.accept(self.events[7]))
        for event in self.events[15:]:
            reader.accept(event)
        self.assertEqual(reader.state, self.snapshots[34])

    def test_bad_recovery_cursor_and_snapshot(self):
        for pointer, value, code in (("/cursor", 14, "INVALID_CURSOR"), ("/runs/0/1", 11, "INVALID_CURSOR"), ("/runs/0/2", "failed", "INVALID_CURSOR"), ("/steps/0/1", "running", "INVALID_CURSOR"), ("/operations/1/1", None, "INVALID_CURSOR"), ("/published_results", [], "INVALID_CURSOR")):
            with self.subTest(pointer=pointer):
                bad = patch_pointer(self.snapshots[15], pointer, value)
                self.assertCode(code, Replay, self.catalog, bad, self.events[:15])
        self.assertCode("INVALID_CURSOR", Replay, self.catalog, self.snapshots[15], self.events[:14])
        prefix = deepcopy(self.events[:15])
        prefix[-1][3] = 99
        self.assertCode("INVALID_REVISION", Replay, self.catalog, self.snapshots[15], prefix)

    def test_independent_readers_and_returned_values(self):
        first = Replay(self.catalog, self.snapshots[15], self.events[:15])
        second = Replay(self.catalog, self.snapshots[15], self.events[:15])
        exposed = first.state
        exposed["runs"].clear()
        journal = first.journal
        journal.clear()
        response = self.query(first, "list_runs")
        response["rows"].clear()
        first.accept(self.events[15])
        self.assertEqual(second.state, self.snapshots[15])
        self.assertEqual(first.state["cursor"], 16)
        self.assertEqual(len(first.state["runs"]), 1)

    def test_list_inspect_consistency_every_prefix(self):
        for cursor in range(35):
            reader = self.reader(cursor)
            for row in self.query(reader, "list_runs")["rows"]:
                self.assertEqual(self.query(reader, "inspect", row[0])["row"], row)
        self.assertEqual(len(self.reader(34).state["runs"]), 2)
        self.assertEqual([s for s in self.catalog.steps.values() if s[2] == "op-postcheck"], [])

    def test_no_future_objects_leak(self):
        reader = self.reader(3)
        self.assertEqual(self.query(reader, "inspect", "run-a")["error"], "NOT_FOUND")
        self.assertEqual(self.query(reader, "request_lookup", "req-b")["error"], "NOT_FOUND")
        self.assertEqual(reader.state["published_results"], [])
        observed = self.query(self.reader(15), "inspect", "run-a")
        self.assertEqual(observed["row"][2], "running")
        self.assertNotIn("op-collect", observed["operation_ids"])
        self.assertNotIn("result-a4", observed["result_ids"])

    def test_deferred_error_does_not_finish_current_producer(self):
        reader = self.reader(13)
        state = reader.state
        self.assertEqual(state["steps"][2], ["a-timing-2", "running", None])
        self.assertEqual(state["runs"][0][2:], ["running", None, "result-a2", "failed", "failed"])
        error = self.catalog.errors[state["errors"][0]]
        self.assertEqual((error["step_id"], error["measurement_id"], error["artifact_id"]), ("a-timing-2", "m-timing-1", "artifact-timing-1"))
        self.assertEqual(state["operations"][-1][2], "running")

    def test_equal_values_distinct_explicit_origins_and_inheritance(self):
        m1, m2 = (self.catalog.measurements[k] for k in ("m-timing-1", "m-timing-2"))
        self.assertEqual(m1["value"], m2["value"])
        self.assertNotEqual(m1["producer"], m2["producer"])
        self.assertNotEqual(m1["artifact_ids"], m2["artifact_ids"])
        self.assertEqual((m1["measured_at"], m1["published_at"], m2["measured_at"], m2["published_at"]), (9, 11, 12, 15))
        before = deepcopy(self.catalog.measurements)
        self.reader(34)
        self.assertEqual(self.catalog.measurements, before)
        old, new = self.catalog.results["result-a3"], self.catalog.results["result-a4"]
        for slot in ("resources", "timing_reference", "timing_latest"):
            self.assertEqual(old[7][slot], new[7][slot])
        self.assertEqual(old[7]["final_timing"], ["pending", None, "publication_pending"])
        self.assertEqual(new[7]["final_timing"], ["unavailable", None, "routing_no_final_timing"])
        self.assertEqual(self.reader(34).state["runs"][0][5:], ["failed", "failed"])

    def test_all_replay_cases(self):
        for case in self.docs["replay_cases"]["cases"]:
            with self.subTest(case=case["id"]):
                response = self.run_case(case)
                self.assertEqual({key: response[key] for key in case["expected"]}, case["expected"])

    def run_case(self, case):
        kind = case["kind"]
        reader = self.reader(case.get("start_cursor", case.get("cursor", 0)))
        if "patch_object" in case:
            p = case["patch_object"]
            # Only the candidate's catalog changes; retained state/journal stay put.
            reader.catalog = Catalog(self.descriptor, self.mutate(p["collection"], p["id"], p["field"], p["value"]))
        if kind == "request":
            intent = deepcopy(self.catalog.operations[case["intent_from"]]["intent"])
            if "patch_intent" in case:
                p = case["patch_intent"]
                intent = patch_pointer(intent, p["pointer"], p["value"])
            before = reader.state, reader.journal
            result = reader.request(case["request_key"], intent, case["intent_from"])
            self.assertEqual((reader.state, reader.journal), before)
            return result
        if kind == "retention":
            try:
                suffix(self.descriptor, self.events, scope=self.descriptor["scope"], stream_id=case["request_stream_id"], after=case["after_cursor"], through=34, retired=[case["retired_stream_id"]])
            except ContractError as exc:
                return dict(code=exc.code, events=None, snapshot=None)
            self.fail("retired cursor unexpectedly accepted")
        if kind == "framing":
            data = "".join(json.dumps(self.events[n - 1]) + "\n" for n in case["complete_lines"]) + case["tail_utf8"]
            response = reader.feed(data.encode("utf-8"))
            self.assertEqual(reader.state, self.reader(8).state)
            self.assertTrue(reader.accept(self.events[8]))  # reconnect recovery
            return response
        applied, code = 0, "OK"
        for n in case.get("deliver", [case.get("candidate_sequence")]):
            candidate = deepcopy(self.events[n - 1])
            if "patch_event" in case and case["patch_event"]["sequence"] == n:
                p = case["patch_event"]
                candidate = patch_pointer(candidate, p["pointer"], p["value"])
            before = reader.state, reader.journal
            try:
                applied += reader.accept(candidate, writer=kind == "writer")
            except ContractError as exc:
                code = exc.code
                self.assertEqual((reader.state, reader.journal), before)
                break
        response = dict(code=code, cursor=reader.state["cursor"], applied=applied, appended=applied, next_sequence=reader.state["cursor"] + 1, run_revisions={r[0]: r[1] for r in reader.state["runs"]})
        if code == "GAP":
            reader.accept(self.events[7])
            reader.accept(self.events[8])
            self.assertEqual(reader.state, self.reader(9).state)
        return response

    def test_duplicate_structural_equality_and_precedence(self):
        reader = self.reader(8)
        duplicate = deepcopy(self.events[7])
        duplicate[6] = dict(reversed(list(duplicate[6].items())))
        self.assertFalse(reader.accept(duplicate))
        duplicate[1] = True
        self.assertCode("CONFLICTING_DUPLICATE", reader.accept, duplicate)
        duplicate[1] = float("nan")
        self.assertCode("CONFLICTING_DUPLICATE", reader.accept, duplicate)
        gap = deepcopy(self.events[9])
        gap[5] = "unrecognized"
        self.assertCode("GAP", reader.accept, gap)

    def test_malformed_complete_lines_stop_at_verified_cursor(self):
        for tail in (b'{bad}\n', b'\xff\n', b'[]\n', b'\n', b'[9,7,"run-a",6,"op-a","step",{"step_id":"a-timing-1","status":"running","reason":null,"reason":null}]\n'):
            with self.subTest(tail=tail):
                reader = self.reader(7)
                response = reader.feed(json.dumps(self.events[7]).encode() + b"\n" + tail)
                self.assertEqual(response, dict(code="INVALID_RECORD", cursor=8, applied=1))
                self.assertEqual(reader.state, self.reader(8).state)

    def test_unterminated_even_valid_json_is_not_a_fact(self):
        reader = self.reader(7)
        self.assertEqual(reader.feed(json.dumps(self.events[7]).encode()), dict(code="INCOMPLETE_TAIL", cursor=7, applied=0))
        self.assertEqual(reader.state, self.snapshots[7])

    def test_request_validation_precedes_binding_conflict_and_busy(self):
        reader = self.reader(15)
        intent = deepcopy(self.catalog.operations["op-collect"]["intent"])
        for key, value in (("configuration_id", "other"), ("archive", 0), ("target_run_id", "run-b"), ("stage", "FULL"), ("checks", "full"), ("extra", False)):
            with self.subTest(field=key):
                candidate = intent | {key: value}
                self.assertCode("INVALID_INTENT", reader.request, "req-a", candidate, "op-collect")
        self.assertEqual(reader.request("req-a", intent)["code"], "REQUEST_CONFLICT")
        self.assertEqual(reader.request("req-collect", intent)["code"], "BUSY")
        # Failure of implementation at 18 does not release the operation at 19.
        self.assertEqual(self.reader(18).request("req-collect", intent)["code"], "BUSY")
        self.assertEqual(self.reader(19).request("req-collect", intent, "op-collect")["code"], "ALLOCATE")

    def test_fencing_never_changes_cursor_or_infers_interruption(self):
        reader = self.reader(24)
        stale = deepcopy(self.events[24])
        stale[1] = 6
        self.assertCode("FENCED", reader.accept, stale, writer=True)
        self.assertEqual(reader.state, self.reader(24).state)
        self.assertEqual(self.query(reader, "inspect", "run-b")["step_rows"][1], ["b-active", "running", None])
        # Arbitrarily many reads/disconnects imply unknown liveness, no event.
        for _ in range(10):
            self.query(reader, "inspect", "run-b")
        self.assertEqual(reader.state["runs"][1][2], "running")
        reader.accept(self.events[24], writer=True)
        self.assertEqual(reader.state["steps"][5][1], "interrupted")
        self.assertEqual(reader.state["runs"][1][2], "running")

    def test_legacy_conservative_exact_observation(self):
        doc = self.docs["legacy"]
        self.assertEqual(legacy_observation(doc["record"]), doc["expected_observation"])
        self.assertEqual(self.query(self.reader(34), "inspect", "legacy-run")["error"], "NOT_FOUND")
        bad = doc["record"] | {"schema_version": 2}
        self.assertCode("UNSUPPORTED_CONTRACT", legacy_observation, bad)

    def test_unknown_versions_fields_and_kinds(self):
        for name, original in self.docs.items():
            for field, value, code in (("version", 2, "UNSUPPORTED_CONTRACT"), ("version", True, "UNSUPPORTED_CONTRACT"), ("contract", "run.json", "UNSUPPORTED_CONTRACT"), ("extra", None, "INVALID_RECORD")):
                with self.subTest(document=name, field=field):
                    self.assertCode(code, validate_document, original | {field: value}, name)
        bad = deepcopy(self.events[7])
        bad[5] = "future_event"
        self.reject_event(7, bad, "INVALID_RECORD")
        bad = deepcopy(self.events[7])
        bad[6]["unexpected"] = 1
        self.reject_event(7, bad, "INVALID_RECORD")
        s = deepcopy(self.scenario)
        s["measurements"][0]["producer"]["extra"] = None
        self.assertCode("INVALID_RECORD", Catalog, self.descriptor, s)

    def test_strict_json_duplicate_nonfinite_and_numeric_bounds(self):
        for text in ('{"x":1,"x":2}', '{"x":{"a":1,"a":2}}', '{"x":NaN}', '[Infinity]', '[-Infinity]', '[1e999]', '[9007199254740992]', '[1,]'):
            with self.subTest(text=text):
                self.assertCode("INVALID_RECORD", strict_json, text)
        s = self.mutate("measurements", "m-area", "value", float("nan"))
        self.assertCode("INVALID_RECORD", Catalog, self.descriptor, s)

    def test_boolean_integer_and_bad_row_lengths(self):
        for position in (0, 1, 3):
            bad = deepcopy(self.events[7])
            bad[position] = True
            self.reject_event(7, bad, "INVALID_RECORD")
        for field in ("attempt",):
            s = self.mutate("operations", "op-a", field, True)
            self.assertCode("INVALID_RECORD", Catalog, self.descriptor, s)
        for field, value in (("measured_at", True), ("ready_before", -1), ("published_at", 2**53), ("value", False)):
            s = self.mutate("measurements", "m-area", field, value)
            self.assertCode("INVALID_RECORD", Catalog, self.descriptor, s)
        for table in ("steps", "results"):
            s = deepcopy(self.scenario)
            s[table][0].append(None)
            self.assertCode("INVALID_RECORD", Catalog, self.descriptor, s)
        self.reject_event(7, self.events[7][:-1], "INVALID_RECORD")

    def test_namespace_stream_and_cursor_validation(self):
        reader = self.reader(15)
        self.assertCode("SCOPE_MISMATCH", self.query, reader, "list_runs", scope=self.descriptor["scope"] | {"store_id": "elsewhere"})
        self.assertCode("RESET_REQUIRED", self.query, reader, "list_runs", stream_id="retired")
        self.assertCode("CURSOR_AHEAD", self.query, reader, "list_runs", cursor=16)
        self.assertCode("INVALID_CURSOR", self.query, reader, "list_runs", cursor=14)
        self.assertCode("INVALID_RECORD", self.query, reader, "list_runs", cursor=True)

    def test_retirement_does_not_erase_request_bindings_or_invent_history(self):
        reader = self.reader(34)
        before = reader.state, reader.journal
        self.assertCode("RESET_REQUIRED", suffix, self.descriptor, reader.journal,
            scope=self.descriptor["scope"], stream_id=self.descriptor["stream_id"],
            after=15, through=34, retired=[self.descriptor["stream_id"]])
        self.assertCode("RESET_REQUIRED", suffix, self.descriptor, reader.journal,
            scope=self.descriptor["scope"], stream_id="stream-fixture-2",
            after=0, through=34)
        self.assertEqual(reader.request("req-a", self.catalog.operations["op-a"]["intent"]),
                         dict(code="REUSED", operation_id="op-a", run_id="run-a", appended=0))
        self.assertEqual((reader.state, reader.journal), before)

    def test_duplicate_ids_every_catalog_table(self):
        for table in ("configurations", "operations", "runs", "steps", "errors", "artifacts", "measurements", "results"):
            with self.subTest(table=table):
                s = deepcopy(self.scenario)
                s[table].append(deepcopy(s[table][0]))
                self.assertCode("DUPLICATE_ID", Catalog, self.descriptor, s)
        s = self.mutate("operations", "op-b", "request_key", "req-a")
        self.assertCode("DUPLICATE_ID", Catalog, self.descriptor, s)

    def test_missing_fields_and_unknown_query_case_kinds(self):
        for name, table in (("queries", "queries"), ("replay_cases", "cases")):
            for field in ("id", "kind"):
                doc = deepcopy(self.docs[name])
                del doc[table][0][field]
                self.assertCode("INVALID_RECORD", validate_document, doc, name)
            doc = deepcopy(self.docs[name])
            doc[table][0]["kind"] = "unknown"
            self.assertCode("INVALID_RECORD", validate_document, doc, name)
        for field in self.scenario["measurements"][0]:
            scenario = deepcopy(self.scenario)
            del scenario["measurements"][0][field]
            self.assertCode("INVALID_RECORD", Catalog, self.descriptor, scenario)

    def test_wrong_run_producer_and_cross_table_references(self):
        mutations = [
            ("measurements", "m-area", "run_id", "run-b", "INVALID_PROVENANCE"),
            ("measurements", "m-area", "producer", dict(operation_id="op-b", step_id="a-synth", attempt=1), "INVALID_PROVENANCE"),
            ("measurements", "m-area", "producer", dict(operation_id="op-a", step_id="a-synth", attempt=2), "INVALID_PROVENANCE"),
            ("measurements", "m-area", "tool_id", "absent", "INVALID_REFERENCE"),
            ("measurements", "m-area", "constraints_id", "absent", "INVALID_REFERENCE"),
            ("measurements", "m-area", "artifact_ids", ["m-timing-1"], "INVALID_REFERENCE"),
            ("errors", "error-timing", "artifact_id", "artifact-timing-2", "INVALID_REFERENCE"),
            ("results", "result-a1", 1, "run-b", "INVALID_PROVENANCE"),
            ("results", "result-a1", 6, 2, "INVALID_PROVENANCE"),
        ]
        for table, identity, field, value, code in mutations:
            with self.subTest(table=table, field=field):
                self.assertCode(code, Catalog, self.descriptor, self.mutate(table, identity, field, value))
        bad = deepcopy(self.events[7])
        bad[4] = "op-b"
        self.reject_event(7, bad, "INVALID_REFERENCE")
        bad = deepcopy(self.events[7])
        bad[2] = "run-b"
        self.reject_event(7, bad, "INVALID_REFERENCE")

    def test_protected_build_configuration(self):
        s = deepcopy(self.scenario)
        s["bundle"]["immutable"] = False
        self.assertCode("INVALID_REFERENCE", Catalog, self.descriptor, s)
        s = self.mutate("runs", "run-b", "configuration_id", "other")
        self.assertCode("INVALID_REFERENCE", Catalog, self.descriptor, s)
        s = deepcopy(self.scenario)
        s["operations"][0]["intent"]["configuration_id"] = "other"
        self.assertCode("INVALID_INTENT", Catalog, self.descriptor, s)

    def test_metric_mode_unit_corner_and_origin_required(self):
        for field, value in (("unit", "ns"), ("mode", "setup"), ("corner", "synthetic-typical"), ("stage", "placement")):
            self.assertCode("INVALID_PROVENANCE", Catalog, self.descriptor, self.mutate("measurements", "m-area", field, value))
        s = deepcopy(self.scenario)
        del s["measurements"][2]["producer"]
        self.assertCode("INVALID_RECORD", Catalog, self.descriptor, s)

    def test_illegal_terminal_changes_and_identity_reuse(self):
        bad = deepcopy(self.events[8])
        bad[6]["step_id"] = "a-synth"
        self.reject_event(8, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[18])
        bad[5:7] = ["implementation", dict(status="running", reason=None)]
        self.reject_event(18, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[19])
        bad[4:7] = ["op-a", "operation_outcome", dict(status="failed", reason="routing_failed")]
        self.reject_event(19, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[8])
        bad[5:7] = ["result_published", dict(result_id="result-a1")]
        self.reject_event(8, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[13])
        bad[5:7] = ["deferred_error", dict(error_id="error-timing")]
        self.reject_event(13, bad, "INVALID_TRANSITION")

    def test_bad_revision_and_operation_allocation_order(self):
        for revision in (4, 6):
            bad = deepcopy(self.events[7])
            bad[3] = revision
            self.reject_event(7, bad, "INVALID_REVISION")
        bad = deepcopy(self.events[3])
        bad[0] = 3
        self.reject_event(2, bad, "INVALID_REFERENCE")
        bad = deepcopy(self.events[3])
        bad[3] = 2
        self.reject_event(3, bad, "INVALID_REVISION")

    def test_lifecycle_and_outcome_status_separation(self):
        bad = deepcopy(self.events[13])
        bad[5:7] = ["implementation", dict(status="failed", reason="routing_failed")]
        self.reject_event(13, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[4])
        bad[5:7] = ["step", dict(step_id="a-synth", status="running", reason=None)]
        self.reject_event(4, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[18])
        bad[6] = dict(status="succeeded", reason=None)
        self.reject_event(18, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[28])
        bad[5:7] = ["operation_outcome", dict(status="succeeded", reason=None)]
        self.reject_event(28, bad, "INVALID_TRANSITION")

    def test_execute_outcome_requires_explicit_terminal_implementation(self):
        intent = self.catalog.operations["op-collect"]["intent"]
        for cursor in (3, 4, 5, 7, 17):
            for status in ("failed", "interrupted"):
                with self.subTest(cursor=cursor, status=status):
                    bad = deepcopy(self.events[cursor])
                    if cursor == 3:
                        bad[2:4] = [None, None]
                    bad[5:7] = ["operation_outcome", dict(status=status, reason="routing_failed")]
                    reader = self.reject_event(cursor, bad, "INVALID_TRANSITION")
                    if cursor >= 4:
                        self.assertEqual(reader.request("req-collect", intent)["code"], "BUSY")

    def test_completed_implementation_can_outer_fail_or_interrupt(self):
        for status in ("failed", "interrupted"):
            reader = self.reader(17)
            event = deepcopy(self.events[17])
            event[6] = dict(status="completed", reason=None)
            reader.accept(event)
            self.assertEqual(reader.request("req-collect", self.catalog.operations["op-collect"]["intent"])["code"], "BUSY")
            event = deepcopy(self.events[18])
            event[6] = dict(status=status, reason="routing_failed")
            reader.accept(event)
            self.assertEqual(reader.state["runs"][0][2:4], ["completed", None])
            self.assertEqual(reader.state["operations"][-1][2], status)
            self.assertEqual(reader.request("req-collect", self.catalog.operations["op-collect"]["intent"], "op-collect")["code"], "ALLOCATE")

    def test_collect_completed_step_and_inherited_result_do_not_imply_success(self):
        bad = deepcopy(self.events[30])
        bad[5:7] = ["operation_outcome", dict(status="succeeded", reason=None)]
        reader = self.reject_event(30, bad, "INVALID_TRANSITION")
        self.assertEqual(reader.state["runs"][0][4], "result-a3")
        self.assertEqual(reader.state["steps"][-1][1], "completed")
        self.assertEqual(reader.state["operations"][-1][2], "running")
        reader.accept(self.events[30])
        reader.accept(self.events[31])
        self.assertEqual(reader.state["operations"][-1][2], "succeeded")

    def test_snapshot_integer_fields_reject_boolean_and_float_aliases(self):
        for pointer in ("/cursor", "/runs/0/1"):
            for value in (True, 1.0):
                with self.subTest(pointer=pointer, value=value):
                    snapshot = patch_pointer(self.reader(4).state, pointer, value)
                    self.assertCode("INVALID_RECORD", Replay, self.catalog, snapshot, self.events[:4])

    def test_recovery_rejects_malformed_prefix_even_with_matching_last_facts(self):
        # Last-fact projection alone misses an illegal completion before start.
        prefix = deepcopy(self.events[:7])
        prefix[5][6]["status"] = "completed"
        self.assertCode("INVALID_TRANSITION", Replay, self.catalog, self.snapshots[7], prefix)
        prefix = deepcopy(self.events[:15])
        prefix[5][4] = "op-b"
        self.assertCode("INVALID_REFERENCE", Replay, self.catalog, self.snapshots[15], prefix)
        snapshot = deepcopy(self.snapshots[15])
        snapshot["published_results"].append("result-a3")
        self.assertCode("INVALID_CURSOR", Replay, self.catalog, snapshot, self.events[:15])

    def test_false_skipped_reason_and_explicit_unreached(self):
        bad = deepcopy(self.events[22])
        bad[6]["reason"] = "producer_interrupted"
        self.reject_event(22, bad, "INVALID_TRANSITION")
        bad = deepcopy(self.events[22])
        bad[6]["step_id"] = "b-unreached"
        self.reject_event(22, bad, "INVALID_TRANSITION")
        s = deepcopy(self.scenario)
        s["gates"]["b-gated"]["observed_value"] = True
        self.assertCode("INVALID_REFERENCE", Catalog, self.descriptor, s)
        state = self.reader(27).state
        self.assertEqual(state["steps"][4:], [["b-gated", "skipped", "config_gate_false"], ["b-active", "interrupted", "producer_interrupted"], ["b-unreached", "not_started", None]])

    def test_missing_malformed_unsafe_and_hash_mismatched_evidence(self):
        for path in ("evidence/missing.txt", "evidence", "../outside", "/tmp/outside"):
            with self.subTest(path=path):
                s = self.mutate("artifacts", "artifact-input", "path", path)
                if path.startswith(("..", "/")):
                    self.assertCode("INVALID_EVIDENCE", Catalog, self.descriptor, s)
                else:
                    self.assertCode("INVALID_EVIDENCE", check_evidence, Catalog(self.descriptor, s), FIXTURES)
        for digest in ("ABC", "0" * 64):
            s = self.mutate("artifacts", "artifact-input", "sha256", digest)
            if len(digest) != 64:
                self.assertCode("INVALID_EVIDENCE", Catalog, self.descriptor, s)
            else:
                self.assertCode("INVALID_EVIDENCE", check_evidence, Catalog(self.descriptor, s), FIXTURES)
        s = deepcopy(self.scenario)
        s["artifacts"].pop()
        self.assertCode("INVALID_REFERENCE", Catalog, self.descriptor, s)
        # No filesystem mutations: simulate a symlink at a checked path component.
        with patch.object(Path, "is_symlink", return_value=True):
            self.assertCode("INVALID_EVIDENCE", check_evidence, self.catalog, FIXTURES)

    def test_first_publication_late_publication_and_reattribution(self):
        for mid, field, value, cursor in (("m-area", "published_at", 9, 7), ("m-timing-1", "published_at", 15, 10), ("m-timing-2", "measured_at", 11, 14)):
            with self.subTest(mid=mid, field=field):
                catalog = Catalog(self.descriptor, self.mutate("measurements", mid, field, value))
                self.reject_event(cursor, self.events[cursor], "INVALID_PROVENANCE", catalog)
        s = self.mutate("measurements", "m-timing-2", "producer", dict(operation_id="op-a", step_id="a-timing-1", attempt=1))
        self.reject_event(14, self.events[14], "INVALID_PROVENANCE", Catalog(self.descriptor, s))
        s = self.mutate("results", "result-a1", 3, 9)
        self.reject_event(7, self.events[7], "INVALID_PROVENANCE", Catalog(self.descriptor, s))
        # A later collector cannot replace the origin of inherited evidence.
        s = self.mutate("measurements", "m-area", "producer", dict(operation_id="op-collect", step_id="a-collect", attempt=1))
        self.assertCode("INVALID_PROVENANCE", Catalog, self.descriptor, s)

    def test_data_before_event_root_and_all_transitive_dependencies(self):
        for table, identity, field, boundary, cursor in (
            ("results", "result-a1", 2, 8, 7),
            ("measurements", "m-area", "ready_before", 8, 7),
            ("artifacts", "artifact-resources", "ready_before", 8, 7),
            ("artifacts", "artifact-timing-1", "ready_before", 11, 10),
            ("artifacts", "artifact-timing-2", "ready_before", 15, 14),
            ("artifacts", "artifact-diagnostic", "ready_before", 31, 30),
            ("configurations", "config-B", "ready_before", 1, 0),
            ("artifacts", "artifact-input", "ready_before", 1, 0),
        ):
            with self.subTest(table=table, identity=identity):
                catalog = Catalog(self.descriptor, self.mutate(table, identity, field, boundary))
                self.reject_event(cursor, self.events[cursor], "OBJECT_NOT_READY", catalog)
        for object_name, boundary, cursor in (("bundle", 1, 0), ("tool", 8, 7), ("constraints", 8, 7)):
            s = deepcopy(self.scenario)
            s[object_name]["ready_before"] = boundary
            self.reject_event(cursor, self.events[cursor], "OBJECT_NOT_READY", Catalog(self.descriptor, s))

    def test_deferred_error_requires_published_checked_measurement(self):
        s = self.mutate("errors", "error-timing", "measurement_id", "m-timing-2")
        s["errors"][0]["artifact_id"] = "artifact-timing-2"
        self.reject_event(12, self.events[12], "INVALID_PROVENANCE", Catalog(self.descriptor, s))
        s = self.mutate("errors", "error-timing", "step_id", "a-timing-1")
        self.reject_event(12, self.events[12], "INVALID_TRANSITION", Catalog(self.descriptor, s))
        s = self.mutate("errors", "error-timing", "discovered_at", 11)
        self.reject_event(12, self.events[12], "INVALID_PROVENANCE", Catalog(self.descriptor, s))

    def test_error_readiness_checks_retained_measurement_closure(self):
        original = self.reader(12)
        for target in ("measurement", "evidence", "tool", "constraints", "constraints_artifact"):
            with self.subTest(target=target):
                scenario = deepcopy(self.scenario)
                if target == "measurement":
                    scenario["measurements"][1]["ready_before"] = 13
                elif target == "evidence":
                    scenario["artifacts"][2]["ready_before"] = 13
                elif target == "constraints_artifact":
                    scenario["constraints"]["artifact_id"] = "artifact-diagnostic"
                else:
                    scenario[target]["ready_before"] = 13
                reader = Replay(self.catalog, original.state, original.journal)
                # Candidate-only fault injection after recovery, not a new valid
                # history under rewritten immutable definitions.
                reader.catalog = Catalog(self.descriptor, scenario)
                self.assertCode("OBJECT_NOT_READY", reader.accept, self.events[12])
                self.assertEqual(reader.state, original.state)
                self.assertEqual(reader.journal, original.journal)

    def test_result_publisher_must_have_actually_completed_in_same_run(self):
        scenario = self.mutate("results", "result-a1", 5, "a-timing-1")
        self.reject_event(7, self.events[7], "INVALID_TRANSITION", Catalog(self.descriptor, scenario))
        scenario = self.mutate("results", "result-a4", 5, "a-synth")
        self.assertCode("INVALID_PROVENANCE", Catalog, self.descriptor, scenario)

    def test_recovery_revalidates_provenance_and_readiness_of_prefix(self):
        for scenario, code in (
            (self.mutate("artifacts", "artifact-timing-1", "ready_before", 11), "OBJECT_NOT_READY"),
            (self.mutate("measurements", "m-timing-1", "measured_at", 8), "INVALID_PROVENANCE"),
        ):
            self.assertCode(code, Replay, Catalog(self.descriptor, scenario), self.snapshots[15], self.events[:15])

    def test_constraints_artifact_transitive_readiness(self):
        # Move only the constraints link to the future diagnostic artifact; it is
        # not the bundle artifact, so allocation still succeeds before publication.
        scenario = deepcopy(self.scenario)
        scenario["constraints"]["artifact_id"] = "artifact-diagnostic"
        catalog = Catalog(self.descriptor, scenario)
        self.reject_event(7, self.events[7], "OBJECT_NOT_READY", catalog)

    def test_absent_slots_cannot_smuggle_measurements_or_undefined_reasons(self):
        for value in (["pending", "m-area", "publication_pending"], ["unavailable", None, "unknown_reason"], ["available", None, None], ["available", "m-area", "publication_pending"]):
            scenario = deepcopy(self.scenario)
            scenario["results"][0][7]["resources"] = value
            self.assertCode("INVALID_REFERENCE", Catalog, self.descriptor, scenario)

    def test_future_ready_definitions_are_not_rejected_until_advertised(self):
        scenario = self.mutate("artifacts", "artifact-timing-2", "ready_before", 100)
        catalog = Catalog(self.descriptor, scenario)
        self.assertEqual(self.reader(13, catalog).state, self.snapshots[13])
        self.reject_event(14, self.events[14], "OBJECT_NOT_READY", catalog)

    def test_rejected_postcheck_cannot_execute_steps(self):
        bad = deepcopy(self.events[33])
        bad[5:7] = ["step", dict(step_id="a-collect", status="running", reason=None)]
        self.reject_event(33, bad, "INVALID_PROVENANCE")
        s = deepcopy(self.scenario)
        s["steps"].append(["post-tool", "run-a", "op-postcheck", 1, "timing", "Should never run"])
        self.assertCode("INVALID_TRANSITION", Catalog, self.descriptor, s)
        bad = deepcopy(self.events[33])
        bad[6] = dict(status="succeeded", reason=None)
        self.reject_event(33, bad, "INVALID_TRANSITION")

    def test_failed_collect_preserves_earlier_results_authored_branch(self):
        reader = self.reader(29)
        reader.accept([30, 7, "run-a", 19, "op-collect", "step", dict(step_id="a-collect", status="failed", reason="routing_failed")])
        reader.accept([31, 7, "run-a", 20, "op-collect", "operation_outcome", dict(status="failed", reason="routing_failed")])
        state = reader.state
        self.assertEqual(state["runs"][0], ["run-a", 20, "failed", "routing_failed", "result-a3", "failed", "failed"])
        self.assertEqual(state["published_results"], ["result-a1", "result-a2", "result-a3"])
        self.assertEqual(state["errors"], ["error-timing"])
        self.assertEqual(state["operations"][-1], ["op-collect", "run-a", "failed", "routing_failed"])
        self.assertEqual(state["steps"][-1], ["a-collect", "failed", "routing_failed"])


if __name__ == "__main__":
    unittest.main()
