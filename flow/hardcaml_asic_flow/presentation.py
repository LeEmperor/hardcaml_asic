"""Plain-text views of operation results; no probing, validation or persistence.

Renderers accept the existing public payload plus explicit command context. Shared
fields/sections can also serve execution and finalization presentation.
"""

from .report import number


def allocation(payload, output=print):
    report = Report(output)
    report.field("allocation", payload["event"])
    report.field("attempt", payload.get("attempt"))
    report.field("stream" if "stream_id" in payload else "attempt id",
                 payload.get("stream_id", payload.get("attempt_id")))
    output("Requested operation has not completed; this is an allocation receipt.")


def observation_description(payload, output=print):
    report = Report(output)
    for label, key in (("contract", "contract"), ("schema", "schema_version"),
                       ("scope", "scope"), ("cursor", "cursor")):
        report.field(label, payload.get(key))
    report.field("events", " -> ".join(payload.get("events") or []))
    report.section("CAPABILITIES")
    for name, value in payload.get("capabilities", {}).items():
        report.field(name, value)
    for key in ("writer_policy", "retention", "lost_writer"):
        report.field(key, payload.get(key))
    output("\nUse --json for the complete event and response schemas.")


def observation_updates(payload, *, path, output=print):
    report = Report(output)
    report.field("observation", path)
    report.field("stream", payload.get("stream_id"))
    report.field("requested after", payload.get("after"))
    report.field("cursor", payload.get("cursor"))
    events = payload.get("events") or []
    report.field("updates returned", len(events))
    report.section("UPDATES (recorded events; not a current readiness check)")
    if not events:
        output("  none after the requested cursor; no new outcome is implied")
    # Preserve chronological order while bounding human logs. The cursor refers
    # to the complete returned prefix, including events omitted from this view.
    selected = events if len(events) <= 20 else events[:10] + events[-10:]
    for index, event in enumerate(selected):
        if len(events) > 20 and index == 10:
            output(f"  ... {len(events) - 20} events omitted; use --json for all events")
        data = event.get("data") or {}
        occurrence = data.get("occurrence") or {}
        artifact = data.get("artifact") or {}
        detail = ""
        if occurrence:
            detail = f" {text(occurrence.get('action_key'))}: {text(occurrence.get('status'))}"
        elif event.get("event") == "outcome":
            detail = f" {text(data.get('status'))}; exit {text(data.get('exit_code'))}"
        elif event.get("event") == "planned":
            plan = data.get("plan") or {}
            detail = " " + (" -> ".join(plan.get("stages") or []) or text(plan.get("endpoint")))
        output(f"  {text(event.get('sequence')):>4} {text(event.get('event'))}{detail}")
        if artifact:
            output(f"       published {text(artifact.get('boundary'))}: {text(artifact.get('path'))}")
        if data.get("error") or occurrence.get("error"):
            output(f"       error: {text(data.get('error') or occurrence.get('error'))}")
    output("\nCursor covers all returned events. Use this stream and cursor for the next read;\n"
           "a recorded interruption is not an acceptance rejection.")


def stage_execution(payload, *, workspace, output=print):
    # Reuse the inspector's stage/publication view without additional journal reads.
    plan = payload.get("plan") or {}
    artifacts = payload.get("artifacts") or []
    physical = (any(a.get("boundary") == "signoff" for a in artifacts) and
                any(o.get("action_key") == "implementation.signoff" and o.get("status") == "completed"
                    for o in payload.get("occurrences") or []))
    report = Report(output)
    report.field("execution attempt", payload.get("attempt_id"))
    report.field("execution record", str(workspace / ("execution-" + payload["attempt_id"] + ".json")))
    sequence = plan.get("stages")
    report.field("requested endpoint", sequence[-1] if sequence else plan.get("endpoint"))
    report.field("recorded plan", " -> ".join(sequence) if sequence else "through " + text(plan.get("endpoint")))
    report.field("initial boundary", plan.get("initial_boundary") or ("synthesis" if plan.get("resume") else None), missing="none recorded")
    report.field("status", payload.get("status"))
    report.field("exit", payload.get("exit_code"))
    stage_occurrences(payload.get("occurrences") or [], report, output)
    artifact_references(artifacts, report, output)
    report.section("COMPLETION AND ACCEPTANCE")
    report.field("requested completion", "completed" if payload.get("status") == "completed" else "not established")
    report.field("full physical flow", "completed" if physical else "not_recorded")
    report.field("acceptance", "not_evaluated")
    report.field("external postcheck", "not_evaluated")
    output("\nEndpoint completion does not establish acceptance. Interrupted is not an acceptance rejection.")


def finalization(payload, *, path, output=print):
    report = Report(output)
    report.field("finalization", path)
    report.field("attempt id", payload.get("attempt_id"))
    report.field("operation receipt", str(path / "operation.json"))
    report.field("status", payload.get("status"), missing="not recorded (nonterminal)")
    report.field("phase", payload.get("phase"))
    report.field("exit", payload.get("exit_code"), missing="not recorded (nonterminal)")
    request = payload.get("request") or {}
    report.field("requested execution", request.get("execution"))
    report.field("acceptance requested", request.get("accept"))
    report.field("runtime validation", payload.get("runtime_validation"), missing="not established")
    report.section("SELECTED CHECKPOINTS (historical publication)")
    selected = payload.get("selected_checkpoints") or []
    if not selected:
        output("  none recorded")
    for item in selected:
        output(f"  {text(item.get('boundary'))}: {text(item.get('path'))}")
    report.section("RESULTS AND ACCEPTANCE")
    report.field("results", (payload.get("results") or {}).get("path"), missing="not published")
    report.field("external postcheck", payload.get("external_postcheck"))
    report.field("postcheck record", payload.get("postcheck_record"))
    report.field("acceptance", payload.get("acceptance"))
    report.field("acceptance report", (payload.get("acceptance_report") or {}).get("path"))
    if payload.get("error") is not None:
        report.field("operation error", payload["error"])
    output("\nCompletion of collection alone does not establish acceptance.\n"
           "Interrupted means cancellation/interruption, not an acceptance rejection.")


def text(value, missing="not recorded"):
    if value is None:
        return missing
    if value is True:
        return "yes"
    if value is False:
        return "no"
    return str(value) if value != "" else "empty"


class Report:
    def __init__(self, output):
        self.output = output

    def field(self, label, value, *, missing="not recorded"):
        self.output(f"{label:<22} {text(value, missing)}")

    def section(self, title):
        self.output("\n" + title)


def inspection_error(kind, path, payload, output=print):
    report = Report(output)
    report.field(kind, path)
    report.field("inspection", "failed")
    error = payload["error"]
    if isinstance(error, dict):
        report.field("error code", error.get("code"))
        error = error.get("detail")
    report.field("error", error)
    output("\nNo successful inspection or readiness conclusion is available.")


def observation(payload, *, path, output=print):
    report = Report(output)
    state = payload["state"]
    plan = state.get("plan") or {}
    sequence = plan.get("stages")
    endpoint = sequence[-1] if sequence else plan.get("endpoint")
    request = state.get("request") or {}
    outcome = state.get("outcome") or {}
    report.field("observation", path)
    report.field("stream", payload.get("stream_id"))
    report.field("cursor", payload.get("cursor"))
    report.field("requested endpoint", endpoint or request.get("endpoint"))
    report.field("requested plan file", request.get("plan"))
    report.field("recorded plan", " -> ".join(sequence) if sequence else
                 f"through {endpoint}" if endpoint else None)
    report.field("initial boundary", plan.get("initial_boundary") or
                 ("synthesis" if plan.get("resume") else None), missing="none recorded")
    report.field("outcome", outcome.get("status"), missing="not recorded (nonterminal prefix)")
    report.field("execution exit", outcome.get("exit_code"))
    report.field("observation status", payload.get("observation_status"))
    report.field("writer active", payload.get("writer_active"), missing="unknown")
    report.field("phase", state.get("phase"))
    if outcome.get("error") is not None:
        report.field("execution error", outcome["error"])
    stage_occurrences(state.get("occurrences") or [], report, output)
    artifact_references(state.get("artifacts") or [], report, output)
    report.field("workspace", state.get("workspace"))
    report.field("checkpoint store", state.get("checkpoint_store"))
    report.field("preflight reference", state.get("preflight_record"))
    report.field("runtime reference", state.get("runtime_record"))
    report.section("COMPLETION AND ACCEPTANCE")
    report.field("requested completion", "completed (recorded outcome)" if outcome.get("status") == "completed"
                 else "not established by recorded outcome")
    final = payload.get("final_results") or {}
    report.field("full physical flow", final.get("physical_completion"))
    report.field("acceptance", final.get("acceptance"))
    report.field("external postcheck", final.get("external_postcheck"))
    output("\nRecorded endpoint completion does not establish full-flow acceptance or current runtime readiness.")


def stage_occurrences(occurrences, report, output):
    report.section("STAGES (recorded durations)")
    if not occurrences:
        output("  none recorded")
    for item in occurrences:
        status = item.get("status")
        duration = (number(item.get("duration_seconds")) + " s"
                    if status in ("completed", "failed", "interrupted") else "n/a (no finished duration)")
        output(f"  {text(item.get('action_key')):<28} {text(status):<12} {duration}"
               f"   exit {text(item.get('exit_code'))}")
        if item.get("error") is not None:
            output(f"    error: {text(item['error'])}")


def artifact_references(artifacts, report, output):
    report.section("ARTIFACT REFERENCES (historical publication, not current readiness)")
    if not artifacts:
        output("  none recorded")
    for artifact in artifacts:
        output(f"  {text(artifact.get('boundary'))}: {text(artifact.get('path'))}")
        output(f"    identity {text(artifact.get('identity'))}")


def checkpoint(payload, *, path, restart_to=None, output=print):
    report = Report(output)
    manifest = payload["manifest"]
    report.field("checkpoint", path)
    report.field("identity", manifest.get("identity"))
    report.field("boundary", manifest.get("boundary"))
    report.field("bound location", manifest.get("location"))
    report.section("VALIDATION AND CONTINUATION")
    report.field("host validation", "passed (host_only)")
    report.field("compatibility source", payload.get("compatibility_source"))
    report.field("runtime validated", payload.get("runtime_closure_validated"))
    report.field("closure scope", manifest.get("closure_scope"), missing="path-bound (schema 1)")
    report.field("restart supported", manifest.get("restart_supported"))
    targets = manifest.get("restart_targets")
    if targets is None and manifest.get("schema_version") == 1:
        targets = ["floorplan", "placement"] if manifest.get("boundary") == "synthesis" else []
    report.field("supported targets", ", ".join(targets) if targets else "none")
    report.field("requested restart-to", restart_to, missing="not requested")
    if restart_to is not None:
        report.field("transition validation", "passed; no execution performed")
    report.field("tested image", manifest.get("tested_image_id"))
    report.section("INVENTORIES")
    files = manifest.get("files") or {}
    external = manifest.get("external") or {}
    image_count = sum(name.startswith("/nix/store/") for name in external)
    report.field("checkpoint files", len(files))
    report.field("external dependencies", len(external))
    report.field("host dependencies", len(external) - image_count)
    report.field("image-only dependencies", image_count)
    report.section("ACCUMULATED METRICS (not fresh boundary measurements)")
    metrics = manifest.get("metrics") or {}
    available = sum(item.get("availability") == "available" for item in metrics.values())
    unavailable = [(name, item) for name, item in metrics.items() if item.get("availability") == "unavailable"]
    report.field("available values", available)
    report.field("unavailable values", len(unavailable))
    for name, item in sorted(unavailable)[:5]:
        output(f"  {name}: unavailable ({text(item.get('reason') or item.get('unavailable_reason'), 'reason not recorded')})")
    if len(unavailable) > 5:
        output(f"  {len(unavailable) - 5} more unavailable values; use --json for complete evidence")
    report.section("ACCEPTANCE")
    report.field("acceptance", manifest.get("acceptance"))
    output("\nHost inspection passed; runtime/image closure and full-flow acceptance are not established.")
