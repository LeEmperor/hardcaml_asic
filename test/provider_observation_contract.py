"""PROVISIONAL SYNTHETIC FIXTURE-ONLY observation model.

No provider imports, execution, writes or transport. File access is confined to
load_document/check_evidence. Everything else operates on copied JSON values.
Readiness/fencing are logical assertions, not locks, fsync or liveness proofs.
"""

from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import re


CONTRACT = "hardcaml-asic.provider-observation-fixture"
MAX_INT = 2**53 - 1


class ContractError(ValueError):
    def __init__(self, code, detail=""):
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


def require(condition, code="INVALID_RECORD", detail=""):
    if not condition:
        raise ContractError(code, detail)


def strict_json(text):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, detail=f"duplicate key: {key}")
            result[key] = value
        return result

    def constant(value):
        raise ContractError("INVALID_RECORD", f"nonfinite: {value}")

    try:
        value = json.loads(text, object_pairs_hook=pairs, parse_constant=constant)
        primitives(value)
        return value
    except (ValueError, UnicodeError) as exc:
        if isinstance(exc, ContractError):
            raise
        raise ContractError("INVALID_RECORD", str(exc)) from exc


def load_document(path, kind):
    try:
        value = strict_json(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as exc:
        raise ContractError("INVALID_RECORD", str(exc)) from exc
    validate_document(value, kind)
    return value


def primitives(value):
    if type(value) is int:
        require(-MAX_INT <= value <= MAX_INT)
    elif type(value) is float:
        require(math.isfinite(value))
    elif type(value) is list:
        for item in value:
            primitives(item)
    elif type(value) is dict:
        for key, item in value.items():
            require(type(key) is str)
            primitives(item)
    else:
        require(value is None or type(value) in (str, bool))


# Small closed structural grammar. Tuples are positional rows; lists are arrays;
# dicts have exact keys. This is deliberately not a general schema framework.
def shape(value, schema):
    if isinstance(schema, dict):
        require(type(value) is dict and value.keys() == schema.keys(), detail="fields")
        for key, spec in schema.items():
            shape(value[key], spec)
    elif isinstance(schema, tuple):
        require(type(value) is list and len(value) == len(schema), detail="row length")
        for item, spec in zip(value, schema):
            shape(item, spec)
    elif isinstance(schema, list):
        require(type(value) is list)
        for item in value:
            shape(item, schema[0])
    elif schema.startswith("?"):
        if value is not None:
            shape(value, schema[1:])
    elif schema in ("int", "positive", "number"):
        if schema == "number":
            require(type(value) in (int, float) and math.isfinite(value))
        else:
            require(type(value) is int and (1 if schema == "positive" else 0) <= value <= MAX_INT)
    elif schema == "bool":
        require(type(value) is bool)
    elif schema == "null":
        require(value is None)
    elif schema == "text":
        require(type(value) is str and bool(value))
    elif schema == "id":
        require(type(value) is str and bool(value) and value.isascii())
    elif schema == "object":
        require(type(value) is dict)
    else:
        require(type(value) is str and value in schema.split("|"), detail=f"enum {schema}")


SCOPE = dict.fromkeys(("project_id", "provider_id", "store_id"), "id")
INTENT = dict(action="execute|collect|postcheck", build_identity="id", target_run_id="?id",
              stage="full", configuration_id="id", checks="full|none", archive="bool")
PRODUCER = dict(operation_id="id", step_id="id", attempt="positive")
STEP = ("id", "id", "id", "positive", "synthesis|timing|routing|collection", "text")
SLOT = ("available|pending|unavailable|not_requested|unsupported", "?id", "?id")
SLOTS = dict.fromkeys(("resources", "timing_reference", "timing_latest", "final_timing", "power", "cts"), SLOT)
RESULT = ("id", "id", "int", "int", "id", "id", "positive", SLOTS, ["id"])
OP_ROW = ("id", "?id", "running|succeeded|failed|interrupted|rejected", "?id")
RUN_ROW = ("id", "positive", "not_started|running|completed|failed|interrupted", "?id", "?id", "not_evaluated|failed", "pending|failed")
STEP_ROW = ("id", "not_started|running|completed|failed|interrupted|skipped", "?id")
STATE = dict(cursor="int", operations=[OP_ROW], runs=[RUN_ROW], steps=[STEP_ROW], errors=["id"], published_results=["id"])
EVENT_DATA = {
    "operation_allocated": {}, "run_allocated": {},
    "implementation": dict(status="running|completed|failed|interrupted", reason="?id"),
    "step": dict(step_id="id", status="running|completed|failed|interrupted|skipped", reason="?id"),
    "deferred_error": dict(error_id="id"), "result_published": dict(result_id="id"),
    "operation_outcome": dict(status="succeeded|failed|interrupted|rejected", reason="?id"),
}
SCENARIO = {
    "bundle": dict(build_identity="id", configuration_id="id", immutable="bool", ready_before="int", artifact_id="id", description="text"),
    "tool": dict(id="id", name="text", installed_version="null", identity_status="text", ready_before="int"),
    "constraints": dict(id="id", ready_before="int", clock="id", period_ns="number", input_delay_ns="number", output_delay_ns="number", artifact_id="id"),
    "configurations": [dict(id="id", ready_before="int", enable_optional_timing="bool")],
    "operations": [dict(id="id", attempt="positive", request_key="id", intent=INTENT)],
    "runs": [dict(id="id", build_identity="id", implementation_operation_id="id", configuration_id="id", requested_stage="full", completed_stage="null")],
    "step_columns": ["id"], "steps": [STEP], "reasons": "object", "gates": "object",
    "errors": [dict(id="id", run_id="id", operation_id="id", step_id="id", attempt="positive", discovered_at="int", recorded_at="int", verdict="failed", deferred="bool", reason="id", measurement_id="id", artifact_id="id")],
    "artifacts": [dict(id="id", path="text", sha256="text", ready_before="int", media_type="text/plain", synthetic="bool")],
    "measurements": [dict(id="id", ready_before="int", run_id="id", producer=PRODUCER, tool_id="id", metric="mapped_area|setup_slack", value="number", unit="um^2|ns", stage="synthesis|placement", corner="?id", mode="mapped|setup", constraints_id="id", artifact_ids=["id"], measured_at="int", published_at="int")],
    "result_columns": ["id"], "results": [RESULT],
}
DESCRIBE = dict(capability_status="text", scope=SCOPE, stream_id="id", writer_generation="positive",
    cursor=dict(first_sequence="positive", head="int", minimum_replay_cursor="int"),
    modeled_capabilities=["id"], readers=dict(execution_acknowledgments="bool", mutations="bool"),
    mutator_policy=dict(same_run="BUSY", store_journal_and_allocation="short_serialization", stale_generation="FENCED"),
    retention=dict(minimum="text", expiry="text"), time_model=dict(epoch="text", unit="integer_seconds", event_recorded_at="sequence", wall_clock_claim="bool"), resume="text")
LEGACY_RECORD = dict(schema_version="positive", run_id="id", build_identity="id", status="completed", requested_stage="full", completed_stage="full")
LEGACY_OBSERVATION = dict(run_id="id", build_identity="id", implementation_status="completed", requested_stage="full", completed_stage="full", requested_operation="null", requested_operation_outcome="unknown", request_key="null", operation_id="null", stream_id="null", cursor="null", run_revision="null", history_status="unknown", steps="null", check_status="unknown", acceptance_status="unknown", latest_result_id="null", reason="text")


def event_shape(event):
    shape(event, ("positive", "positive", "?id", "?int", "id", "id", "object"))
    require(event[5] in EVENT_DATA, detail="unknown event kind")
    shape(event[6], EVENT_DATA[event[5]])
    require((event[2] is None) == (event[3] is None))
    if event[3] is not None:
        shape(event[3], "positive")


def validate_document(doc, kind):
    require(type(doc) is dict)
    require(doc.get("contract") == CONTRACT and type(doc.get("version")) is int and doc["version"] == 1, "UNSUPPORTED_CONTRACT")
    primitives(doc)
    common = dict(contract="text", version="positive", designation="text")
    schemas = {
        "describe": DESCRIBE, "scenario": SCENARIO,
        "updates": dict(stream_id="id", columns=["id"], events=[("positive", "positive", "?id", "?int", "id", "id", "object")]),
        "expected_snapshots": dict(stream_id="id", columns=dict(operations=["id"], runs=["id"], steps=["id"]), snapshots=[STATE]),
        "queries": dict(scope=SCOPE, stream_id="id", queries=["object"], consistency_assertions=dict(list_equals_inspect_run_rows_at_same_cursor="bool", read_queries_append_events="int", reader_disconnect_changes_state="bool", final_run_count="int", postcheck_tool_step_count="int")),
        "legacy": dict(record=LEGACY_RECORD, expected_observation=LEGACY_OBSERVATION, in_main_stream="bool"),
        "replay_cases": dict(cases=["object"]),
    }
    require(kind in schemas)
    shape(doc, common | schemas[kind])
    require(doc["designation"].startswith("PROVISIONAL SYNTHETIC FIXTURE-ONLY"))
    if kind == "scenario":
        require(doc["step_columns"] == ["id", "run_id", "operation_id", "attempt", "type", "display_name"])
        require(doc["result_columns"] == ["id", "run_id", "ready_before", "published_at", "publisher_operation_id", "publisher_step_id", "publisher_attempt", "slots", "artifact_ids"])
        for key, text in doc["reasons"].items():
            shape(key, "id")
            shape(text, "text")
        for key, gate in doc["gates"].items():
            shape(key, "id")
            shape(gate, dict(configuration_id="id", condition="enable_optional_timing == true", observed_value="bool", reason="id"))
    elif kind == "updates":
        require(doc["columns"] == ["sequence", "writer_generation", "run_id", "run_revision", "operation_id", "kind", "data"])
        for event in doc["events"]:
            event_shape(event)
    elif kind == "expected_snapshots":
        require(doc["columns"] == dict(operations=["id", "run_id", "status", "reason"], runs=["id", "revision", "implementation_status", "implementation_reason", "latest_result_id", "check_status", "acceptance_status"], steps=["id", "status", "reason"]))
        cursors = [s["cursor"] for s in doc["snapshots"]]
        require(len(set(cursors)) == len(cursors), "DUPLICATE_ID")
    elif kind == "legacy":
        require(doc["record"]["schema_version"] == 1, "UNSUPPORTED_CONTRACT")
        require(doc["in_main_stream"] is False)
    elif kind == "queries":
        for query in doc["queries"]:
            validate_query(query)
        index(doc["queries"])
    elif kind == "replay_cases":
        for case in doc["cases"]:
            validate_case(case)
        index(doc["cases"])


def validate_query(query):
    base = dict(id="id", kind="id")
    kinds = {
        "request_lookup": dict(cursor="int", request_key="id", expected="object"),
        "list_runs": dict(cursor="int", expected_rows=[RUN_ROW]),
        "inspect": dict(cursor="int", run_id="id", expected_row=RUN_ROW, expected_result_availability=("available|pending|unavailable", "?id"), expected_step_rows=[STEP_ROW], expected_operation_ids=["id"], expected_error_ids=["id"], expected_result_ids=["id"]),
        "snapshot_and_suffix": dict(snapshot_cursor="int", through_cursor="int", expected_sequences=["positive"], expected_snapshot_cursor="int"),
        "suffix": dict(after_cursor="int", through_cursor="int", expected_sequences=["positive"], expected_snapshot_cursor="int"),
    }
    require(query.get("kind") in kinds)
    shape(query, base | kinds[query["kind"]])
    if query["kind"] == "request_lookup":
        expected = query["expected"]
        shape(expected, dict(error="NOT_FOUND") if "error" in expected else dict(operation_id="id", run_id="?id", status="running|rejected|failed|interrupted|succeeded", reason="?id"))


def validate_case(case):
    kinds = {
        "delivery": dict(start_cursor="int", deliver=["positive"]),
        "readiness": dict(start_cursor="int", deliver=["positive"]),
        "framing": dict(start_cursor="int", complete_lines=["positive"], tail_utf8="text"),
        "retention": dict(request_stream_id="id", after_cursor="int", retired_stream_id="id", replacement_stream_id="id"),
        "writer": dict(start_cursor="int", candidate_sequence="positive"),
        "request": dict(cursor="int", request_key="id", intent_from="id"),
    }
    require(case.get("kind") in kinds)
    spec = dict(id="id", kind="id", expected="object", recovery="text") | kinds[case["kind"]]
    for key, patch_spec in {
        "patch_event": dict(sequence="positive", pointer="text", value=None),
        "patch_object": dict(collection="id", id="id", field="id", value=None),
        "patch_intent": dict(pointer="text", value=None),
    }.items():
        if key in case:
            require((key == "patch_event" and case["kind"] in ("delivery", "writer")) or (key == "patch_object" and case["kind"] == "readiness") or (key == "patch_intent" and case["kind"] == "request"))
            patch = case[key]
            require(type(patch) is dict and patch.keys() == patch_spec.keys())
            for field, field_spec in patch_spec.items():
                if field_spec is not None:
                    shape(patch[field], field_spec)
            spec[key] = "object"
    shape(case, spec)
    allowed = dict(code="id", cursor="int", run_revisions="object", applied="int", next_sequence="positive", events="null", snapshot="null", appended="int", operation_id="?id", run_id="?id", operation_attempt="positive", allocation_sequence="positive", run_allocation_sequence="positive", eventual_run_id="id", busy_operation_id="id", key_reserved="bool")
    require("code" in case["expected"])
    for key, value in case["expected"].items():
        require(key in allowed)
        shape(value, allowed[key])
    for key, value in case["expected"].get("run_revisions", {}).items():
        shape(key, "id")
        shape(value, "positive")


def index(rows):
    result = {}
    for row in rows:
        key = row["id"] if isinstance(row, dict) else row[0]
        require(key not in result, "DUPLICATE_ID", key)
        result[key] = row
    return result


def ref(table, key):
    require(key in table, "INVALID_REFERENCE", str(key))
    return table[key]


class Catalog:
    def __init__(self, descriptor, scenario):
        validate_document(descriptor, "describe")
        validate_document(scenario, "scenario")
        self.descriptor = deepcopy(descriptor)
        self.data = deepcopy(scenario)
        for name in ("configurations", "operations", "runs", "steps", "errors", "artifacts", "measurements", "results"):
            setattr(self, name, index(self.data[name]))
        s = self.data
        require(s["bundle"]["immutable"] is True, "INVALID_REFERENCE")
        ref(self.configurations, s["bundle"]["configuration_id"])
        require(descriptor["cursor"]["first_sequence"] == 1 and descriptor["cursor"]["minimum_replay_cursor"] == 0)
        require(not any(descriptor["readers"].values()) and descriptor["time_model"]["wall_clock_claim"] is False)
        c = s["constraints"]
        require(c["period_ns"] > 0 and c["input_delay_ns"] >= 0 and c["output_delay_ns"] >= 0)
        used = {s["bundle"]["artifact_id"], c["artifact_id"]}
        keys = set()
        for op in self.operations.values():
            require(op["request_key"] not in keys, "DUPLICATE_ID")
            keys.add(op["request_key"])
            self.intent(op["intent"], self.runs)
        for run in self.runs.values():
            op = ref(self.operations, run["implementation_operation_id"])
            require(op["intent"]["action"] == "execute" and run["build_identity"] == s["bundle"]["build_identity"] and run["configuration_id"] == s["bundle"]["configuration_id"], "INVALID_REFERENCE")
        for step in self.steps.values():
            run = ref(self.runs, step[1])
            op = ref(self.operations, step[2])
            require(op["intent"]["action"] != "postcheck", "INVALID_TRANSITION")
            require((op["intent"]["action"] == "execute" and run["implementation_operation_id"] == step[2]) or op["intent"]["target_run_id"] == step[1], "INVALID_REFERENCE")
        for sid, gate in s["gates"].items():
            step = ref(self.steps, sid)
            config = ref(self.configurations, gate["configuration_id"])
            require(self.runs[step[1]]["configuration_id"] == config["id"] and gate["observed_value"] is config["enable_optional_timing"] and gate["observed_value"] is False and gate["reason"] in s["reasons"], "INVALID_REFERENCE")
        for m in self.measurements.values():
            self.producer(m["run_id"], m["producer"])
            require(m["tool_id"] == s["tool"]["id"] and m["constraints_id"] == c["id"], "INVALID_REFERENCE")
            expected = ("um^2", "synthesis", None, "mapped", "synthesis") if m["metric"] == "mapped_area" else ("ns", "placement", "synthetic-typical", "setup", "timing")
            require((m["unit"], m["stage"], m["corner"], m["mode"], self.steps[m["producer"]["step_id"]][4]) == expected, "INVALID_PROVENANCE")
            require(m["artifact_ids"] and len(set(m["artifact_ids"])) == len(m["artifact_ids"]), "INVALID_REFERENCE")
            require(m["measured_at"] <= m["ready_before"] and m["measured_at"] <= m["published_at"], "INVALID_PROVENANCE")
            used.update(m["artifact_ids"])
        for r in self.results.values():
            self.producer(r[1], dict(operation_id=r[4], step_id=r[5], attempt=r[6]))
            used.update(r[8])
            require(len(set(r[8])) == len(r[8]), "DUPLICATE_ID")
            for slot, (availability, mid, reason) in r[7].items():
                if availability == "available":
                    m = ref(self.measurements, mid)
                    require(reason is None and m["run_id"] == r[1], "INVALID_REFERENCE")
                    require(m["metric"] == ("mapped_area" if slot == "resources" else "setup_slack") and slot not in ("power", "cts"), "INVALID_PROVENANCE")
                else:
                    require(mid is None and reason in s["reasons"], "INVALID_REFERENCE")
        for e in self.errors.values():
            self.producer(e["run_id"], {key: e[key] for key in PRODUCER})
            m = ref(self.measurements, e["measurement_id"])
            require(e["deferred"] is True and e["reason"] in s["reasons"] and e["run_id"] == m["run_id"] and e["artifact_id"] in m["artifact_ids"], "INVALID_REFERENCE")
            require(e["discovered_at"] <= e["recorded_at"] and m["metric"] == "setup_slack" and m["value"] < 0, "INVALID_PROVENANCE")
        for aid in used:
            ref(self.artifacts, aid)
        require(used == set(self.artifacts), "INVALID_REFERENCE", "evidence closure")
        for a in self.artifacts.values():
            require(a["synthetic"] is True and re.fullmatch(r"[0-9a-f]{64}", a["sha256"]), "INVALID_EVIDENCE")
            p = Path(a["path"])
            require(not p.is_absolute() and ".." not in p.parts and p.parts, "INVALID_EVIDENCE")

    def producer(self, run_id, producer):
        ref(self.runs, run_id)
        ref(self.operations, producer["operation_id"])
        step = ref(self.steps, producer["step_id"])
        require(step[1:4] == [run_id, producer["operation_id"], producer["attempt"]], "INVALID_PROVENANCE")

    def intent(self, intent, visible_runs):
        try:
            shape(intent, INTENT)
        except ContractError as exc:
            raise ContractError("INVALID_INTENT", exc.detail) from exc
        bundle = self.data["bundle"]
        action, target = intent["action"], intent["target_run_id"]
        require(intent["archive"] is False and intent["build_identity"] == bundle["build_identity"] and intent["configuration_id"] == bundle["configuration_id"], "INVALID_INTENT")
        require(intent["checks"] == ("none" if action == "collect" else "full"), "INVALID_INTENT")
        require((target is None) if action == "execute" else target in visible_runs, "INVALID_INTENT")
        if target is not None:
            run = ref(self.runs, target)
            require(run["configuration_id"] == intent["configuration_id"] and run["build_identity"] == intent["build_identity"], "INVALID_INTENT")

    def ready(self, kind, key, sequence):
        if kind == "build":
            obj = self.data["bundle"]
            self.ready("configurations", obj["configuration_id"], sequence)
            self.ready("artifacts", obj["artifact_id"], sequence)
        elif kind in ("tool", "constraints"):
            obj = self.data[kind]
            if kind == "constraints":
                self.ready("artifacts", obj["artifact_id"], sequence)
        else:
            obj = ref(getattr(self, kind), key)
        boundary = obj[2] if kind == "results" else obj["ready_before"]
        require(boundary < sequence, "OBJECT_NOT_READY", str(key))
        if kind == "measurements":
            self.ready("tool", obj["tool_id"], sequence)
            self.ready("constraints", obj["constraints_id"], sequence)
            for aid in obj["artifact_ids"]:
                self.ready("artifacts", aid, sequence)
        if kind == "results":
            for availability, mid, _ in obj[7].values():
                if availability == "available":
                    self.ready("measurements", mid, sequence)
            for aid in obj[8]:
                self.ready("artifacts", aid, sequence)


def check_evidence(catalog, directory):
    root = Path(directory).resolve()
    for artifact in catalog.artifacts.values():
        path = root
        for part in Path(artifact["path"]).parts:
            path = path / part
            require(not path.is_symlink(), "INVALID_EVIDENCE", str(path))
        require(path.is_file() and path.resolve().is_relative_to(root), "INVALID_EVIDENCE", str(path))
        try:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError as exc:
            raise ContractError("INVALID_EVIDENCE", str(exc)) from exc
        require(digest == artifact["sha256"], "INVALID_EVIDENCE", str(path))


def empty_state():
    return dict(cursor=0, operations=[], runs=[], steps=[], errors=[], published_results=[])


def same(a, b):
    # JSON equality must distinguish true from 1 (including inside arrays).
    if type(a) is not type(b):
        return False
    if type(a) is dict:
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if type(a) is list:
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def replay_document(catalog, updates, through=None):
    """Validate a journal envelope and replay its requested committed prefix.

    Structural validation covers the supplied document; visibility and semantic
    application stop at `through`. Future catalog definitions never become state.
    """
    validate_document(updates, "updates")
    descriptor = catalog.descriptor
    require(updates["stream_id"] == descriptor["stream_id"], "RESET_REQUIRED")
    events = updates["events"]
    require(len(events) == descriptor["cursor"]["head"], "INVALID_CURSOR")
    cursor = len(events) if through is None else through
    validate_cursor(descriptor, descriptor["scope"], updates["stream_id"], cursor, len(events))
    reader = Replay(catalog)
    for event in events[:cursor]:
        reader.accept(event)
    return reader


class Replay:
    """Copy-on-accept reader. A rejected candidate changes neither state nor journal.

    Snapshot recovery copies the supplied state directly. The retained prefix is
    independently validated; its projection checks, but never replaces, that copy.
    """
    def __init__(self, catalog, snapshot=None, retained=()):
        self.catalog = catalog
        self._state = deepcopy(empty_state() if snapshot is None else snapshot)
        self._journal = deepcopy(list(retained))
        self._validate_snapshot()

    @property
    def state(self):
        return deepcopy(self._state)

    @property
    def journal(self):
        return deepcopy(self._journal)

    def _validate_snapshot(self):
        s = self._state
        shape(s, STATE)
        require(s["cursor"] == len(self._journal), "INVALID_CURSOR")
        require(s["cursor"] <= self.catalog.descriptor["cursor"]["head"], "CURSOR_AHEAD")
        # Validate untrusted history as well as the supplied projection. This is
        # deliberately not a fast/durable checkpoint path: the full prefix is needed.
        if not self._journal:
            require(same(s, empty_state()), "INVALID_CURSOR")
            return
        verified = Replay(self.catalog)
        for seq, event in enumerate(self._journal, 1):
            event_shape(event)
            require(event[0] == seq, "INVALID_CURSOR")
            verified.accept(event)
        require(same(s, verified.state), "INVALID_CURSOR")

    def accept(self, event, writer=False):
        candidate = deepcopy(event)
        # Identity ordering precedes semantic validation; admission fencing precedes
        # journal acceptance for a writer (as opposed to duplicate reader delivery).
        require(type(candidate) is list and len(candidate) == 7)
        shape(candidate[0], "positive")
        if writer:
            require(type(candidate[1]) is int and candidate[1] == self.catalog.descriptor["writer_generation"], "FENCED")
        seq = candidate[0]
        if seq <= self._state["cursor"]:
            require(same(candidate, self._journal[seq - 1]), "CONFLICTING_DUPLICATE")
            return False
        require(seq == self._state["cursor"] + 1, "GAP")
        event_shape(candidate)
        require(candidate[1] == self.catalog.descriptor["writer_generation"], "FENCED")
        new_state = deepcopy(self._state)
        self._apply(new_state, candidate)
        new_state["cursor"] = seq
        self._state = new_state
        self._journal.append(candidate)
        return True

    def _measurement(self, mid, state, sequence):
        c = self.catalog
        m = ref(c.measurements, mid)
        c.ready("measurements", mid, sequence)
        p = m["producer"]
        step = ref(index(state["steps"]), p["step_id"])
        require(step[1] == "completed", "INVALID_PROVENANCE")
        facts = [e for e in self._journal if e[5] == "step" and e[6]["step_id"] == p["step_id"]]
        starts = [e[0] for e in facts if e[6]["status"] == "running"]
        ends = [e[0] for e in facts if e[6]["status"] == "completed"]
        require(len(starts) == len(ends) == 1 and starts[0] <= m["measured_at"] <= ends[0] <= m["published_at"], "INVALID_PROVENANCE")
        previous = [c.results[r][3] for r in state["published_results"] if any(slot[1] == mid for slot in c.results[r][7].values())]
        require(m["published_at"] == (min(previous) if previous else sequence), "INVALID_PROVENANCE", "first publication")

    def _apply(self, s, event):
        seq, _, rid, revision, oid, kind, data = event
        c = self.catalog
        definition = ref(c.operations, oid)
        ops, runs, steps = index(s["operations"]), index(s["runs"]), index(s["steps"])
        if kind == "run_allocated":
            require(rid not in runs and rid is not None, "INVALID_TRANSITION")
            require(revision == 1, "INVALID_REVISION")
        elif rid is not None:
            run = ref(runs, rid)
            require(revision == run[1] + 1, "INVALID_REVISION")
        if kind == "operation_allocated":
            require(oid not in ops, "INVALID_TRANSITION")
            c.intent(definition["intent"], runs)
            require(rid == definition["intent"]["target_run_id"], "INVALID_REFERENCE")
            require(not any(o[1] == rid and o[2] == "running" for o in ops.values()) if rid else True, "BUSY")
            c.ready("build", None, seq)
            s["operations"].append([oid, rid, "running", None])
            if rid is not None:
                s["steps"].extend([x[0], "not_started", None] for x in c.steps.values() if x[2] == oid)
        else:
            op = ref(ops, oid)
            require(op[2] == "running", "INVALID_TRANSITION")
            if kind == "run_allocated":
                rd = ref(c.runs, rid)
                require(op[1] is None and definition["intent"]["action"] == "execute" and rd["implementation_operation_id"] == oid, "INVALID_REFERENCE")
                c.ready("build", None, seq)
                op[1] = rid
                s["runs"].append([rid, 1, "not_started", None, None, "not_evaluated", "pending"])
                s["steps"].extend([x[0], "not_started", None] for x in c.steps.values() if x[2] == oid)
            else:
                require(op[1] == rid, "INVALID_REFERENCE")
                if kind in ("implementation", "step"):
                    require(rid is not None, "INVALID_TRANSITION")
                    run = runs[rid]
                    status, reason = data["status"], data["reason"]
                    self._reason(status, reason)
                    if kind == "implementation":
                        require(c.runs[rid]["implementation_operation_id"] == oid, "INVALID_REFERENCE")
                        row, pos = run, 2
                        require(status != "skipped", "INVALID_TRANSITION")
                        if status != "running":
                            require(not any(x[1] == "running" and c.steps[x[0]][2] == oid for x in steps.values()), "INVALID_TRANSITION")
                    else:
                        sd = ref(c.steps, data["step_id"])
                        require(sd[1:3] == [rid, oid], "INVALID_PROVENANCE")
                        row, pos = ref(steps, sd[0]), 1
                        require(definition["intent"]["action"] != "postcheck", "INVALID_TRANSITION")
                        if status == "running" and definition["intent"]["action"] == "execute":
                            require(run[2] == "running", "INVALID_TRANSITION")
                        if status == "skipped":
                            gate = c.data["gates"].get(sd[0])
                            require(gate is not None and gate["reason"] == reason and gate["observed_value"] is False, "INVALID_TRANSITION")
                    require((row[pos] == "not_started" and status in ("running", "skipped")) or (row[pos] == "running" and status in ("completed", "failed", "interrupted")), "INVALID_TRANSITION")
                    row[pos:pos + 2] = [status, reason]
                    if kind == "implementation" and status in ("failed", "interrupted"):
                        run[6] = "failed"
                elif kind == "deferred_error":
                    e = ref(c.errors, data["error_id"])
                    require(e["id"] not in s["errors"], "INVALID_TRANSITION")
                    require([e["run_id"], e["operation_id"]] == [rid, oid], "INVALID_PROVENANCE")
                    require(ref(steps, e["step_id"])[1] == "running", "INVALID_TRANSITION")
                    require(e["recorded_at"] == seq, "INVALID_PROVENANCE")
                    starts = [fact[0] for fact in self._journal if fact[5] == "step" and fact[6]["step_id"] == e["step_id"] and fact[6]["status"] == "running"]
                    require(len(starts) == 1 and starts[0] <= e["discovered_at"] <= seq, "INVALID_PROVENANCE")
                    m = c.measurements[e["measurement_id"]]
                    require(m["published_at"] < seq, "INVALID_PROVENANCE")
                    require(any(any(slot[1] == m["id"] for slot in c.results[r][7].values()) for r in s["published_results"]), "INVALID_PROVENANCE")
                    self._measurement(m["id"], s, seq)
                    s["errors"].append(e["id"])
                    runs[rid][5:7] = ["failed", "failed"]
                elif kind == "result_published":
                    r = ref(c.results, data["result_id"])
                    require(r[0] not in s["published_results"], "INVALID_TRANSITION")
                    require([r[1], r[4]] == [rid, oid], "INVALID_PROVENANCE")
                    require(r[3] == seq, "INVALID_PROVENANCE")
                    require(ref(steps, r[5])[1] == "completed", "INVALID_TRANSITION")
                    c.ready("results", r[0], seq)
                    for availability, mid, _ in r[7].values():
                        if availability == "available":
                            self._measurement(mid, s, seq)
                    s["published_results"].append(r[0])
                    runs[rid][4] = r[0]
                elif kind == "operation_outcome":
                    status, reason = data["status"], data["reason"]
                    self._reason(status, reason)
                    action = definition["intent"]["action"]
                    if action == "postcheck":
                        require(status == "rejected" and reason == "full_run_required" and (runs[rid][2] != "completed" or c.runs[rid]["completed_stage"] != "full"), "INVALID_TRANSITION")
                    if status == "rejected" and action == "execute":
                        require(rid is None, "INVALID_TRANSITION")
                    if action == "execute" and status in ("failed", "interrupted"):
                        require(rid is not None and runs[rid][2] in ("completed", "failed", "interrupted"), "INVALID_TRANSITION")
                    if status == "succeeded":
                        if action == "execute":
                            require(rid is not None and runs[rid][2] == "completed" and runs[rid][6] == "passed", "INVALID_TRANSITION")
                        if action == "collect":
                            own = [x for x in steps.values() if c.steps[x[0]][2] == oid]
                            require(own and all(x[1] == "completed" for x in own), "INVALID_TRANSITION")
                            require(any(c.results[result][4] == oid for result in s["published_results"]), "INVALID_TRANSITION")
                    require(not any(x[1] == "running" and c.steps[x[0]][2] == oid for x in steps.values()), "INVALID_TRANSITION")
                    op[2:4] = [status, reason]
        if rid is not None:
            index(s["runs"])[rid][1] = revision

    def _reason(self, status, reason):
        require(reason is None if status in ("running", "completed", "succeeded") else reason in self.catalog.data["reasons"], "INVALID_TRANSITION")

    def request(self, key, intent, operation_id=None):
        """Pure admission projection; ALLOCATE is a proposal, never a reservation."""
        shape(key, "id")
        c, s = self.catalog, self._state
        c.intent(intent, index(s["runs"]))
        for op in s["operations"]:
            old = c.operations[op[0]]
            if old["request_key"] == key:
                return dict(code="REUSED" if same(old["intent"], intent) else "REQUEST_CONFLICT", operation_id=op[0], run_id=op[1], appended=0)
        target = intent["target_run_id"]
        for op in s["operations"]:
            if target is not None and op[1] == target and op[2] == "running":
                return dict(code="BUSY", busy_operation_id=op[0], operation_id=None, run_id=target, appended=0, key_reserved=False)
        definition = ref(c.operations, operation_id)
        require(definition["request_key"] == key and same(definition["intent"], intent), "INVALID_INTENT")
        result = dict(code="ALLOCATE", operation_id=operation_id, operation_attempt=definition["attempt"], run_id=target, allocation_sequence=s["cursor"] + 1)
        if intent["action"] == "execute":
            candidates = [r["id"] for r in c.runs.values() if r["implementation_operation_id"] == operation_id]
            if candidates:
                require(len(candidates) == 1, "INVALID_REFERENCE")
                result.update(run_allocation_sequence=s["cursor"] + 2, eventual_run_id=candidates[0])
        return result

    def query(self, kind, *, scope, stream_id, cursor, key=None):
        validate_cursor(self.catalog.descriptor, scope, stream_id, cursor, self._state["cursor"])
        require(cursor == self._state["cursor"], "INVALID_CURSOR", "use a reader at the exact prefix")
        s, c = self._state, self.catalog
        if kind == "list_runs":
            payload = dict(rows=s["runs"])
        elif kind == "request_lookup":
            found = next((o for o in s["operations"] if c.operations[o[0]]["request_key"] == key), None)
            payload = dict(error="NOT_FOUND") if found is None else dict(zip(("operation_id", "run_id", "status", "reason"), found))
        elif kind == "inspect":
            run = next((r for r in s["runs"] if r[0] == key), None)
            if run is None:
                payload = dict(error="NOT_FOUND")
            else:
                availability = ["available", None] if run[4] else (["unavailable", run[3]] if run[2] in ("failed", "interrupted") else ["pending", "publication_pending"])
                payload = dict(row=run, result_availability=availability,
                    step_rows=[x for x in s["steps"] if c.steps[x[0]][1] == key],
                    operation_ids=[o[0] for o in s["operations"] if o[1] == key],
                    error_ids=[eid for eid in s["errors"] if c.errors[eid]["run_id"] == key],
                    result_ids=[r for r in s["published_results"] if c.results[r][1] == key])
        else:
            raise ContractError("INVALID_RECORD", "query kind")
        return deepcopy(dict(scope=scope, stream_id=stream_id, cursor=cursor, **payload))

    def feed(self, data):
        """Read LF framing in memory; never repair a producer journal."""
        require(type(data) is bytes)
        applied = 0
        lines = data.split(b"\n")
        try:
            for line in lines[:-1]:
                applied += self.accept(strict_json(line.decode("utf-8")))
            code = "INCOMPLETE_TAIL" if lines[-1] else "OK"
        except UnicodeError:
            code = "INVALID_RECORD"
        except ContractError as exc:
            code = exc.code
        return dict(code=code, cursor=self._state["cursor"], applied=applied)


def validate_cursor(descriptor, scope, stream_id, cursor, head, retired=()):
    shape(scope, SCOPE)
    require(scope == descriptor["scope"], "SCOPE_MISMATCH")
    shape(stream_id, "id")
    require(stream_id == descriptor["stream_id"] and stream_id not in retired, "RESET_REQUIRED")
    shape(cursor, "int")
    require(cursor <= head, "CURSOR_AHEAD")


def suffix(descriptor, events, *, scope, stream_id, after, through, retired=()):
    validate_cursor(descriptor, scope, stream_id, after, len(events), retired)
    validate_cursor(descriptor, scope, stream_id, through, len(events), retired)
    require(after <= through, "INVALID_CURSOR")
    return deepcopy(events[after:through])


def legacy_observation(record):
    shape(record, LEGACY_RECORD)
    require(record["schema_version"] == 1, "UNSUPPORTED_CONTRACT")
    return dict(run_id=record["run_id"], build_identity=record["build_identity"],
        implementation_status=record["status"], requested_stage=record["requested_stage"], completed_stage=record["completed_stage"],
        requested_operation=None, requested_operation_outcome="unknown", request_key=None,
        operation_id=None, stream_id=None, cursor=None, run_revision=None, history_status="unknown",
        steps=None, check_status="unknown", acceptance_status="unknown", latest_result_id=None,
        reason="Legacy implementation completion does not establish execute completion, step history or signoff")
