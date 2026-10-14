"""Actual bridge call corpus + strict OCaml/Python request/reply differential."""
import argparse
import copy
import hashlib
import itertools
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
from reference_harness import copy_reference, hardlink_prefix, thin_prefix, ENTRY


def verify(emitter, package_root, root, fixture):
    if Path(package_root).parts[-3:] == ("lib", "hardcaml_asic", "flow"):
        from reference_harness import activate
        activate(runtime_root=package_root)
    else:
        sys.path.insert(0, str(package_root))
    from hardcaml_asic_flow import backend_protocol as p, stages, checkpoint as cp, execution_plan, runner
    cases = []
    counts = [0, 0]
    def check(request, reply=None, *, valid=None):
        envelope = {"request": request, "reply": reply}
        raw = json.dumps(envelope, ensure_ascii=True, separators=(",", ":"))
        try:
            decoded = p.loads(raw)
            req = p.validate_request(decoded["request"])
            output = req if reply is None else p.validate_reply(decoded["reply"], req)
            expected = p.canonical(output)
        except (ValueError, TypeError, KeyError, OverflowError, RecursionError):
            expected = None
        if valid is not None:
            assert (expected is not None) == valid, envelope
        counts[expected is None] += 1
        cases.append((raw, expected))

    project = root / "project with spaces"
    project.mkdir()
    (project / "src").mkdir()
    (project / "src/config.json").write_text('{"CLOCK_PERIOD":10}')
    (project / "manifest.json").write_text(json.dumps({"files": [], "target": {
        "technology": "fixture", "external_references": []}}))
    pdk = root / "pdk"
    (pdk / "fixture").mkdir(parents=True)
    (pdk / "fixture/tech.lef").write_text("fixture collateral")
    bridge = project / "bridge/librelane_bridge.py"
    bridge.parent.mkdir()
    for name in ("librelane_bridge.py", "backend_protocol.py"):
        shutil.copyfile(package_root / "hardcaml_asic_flow" / name, bridge.with_name(name))
    bridge_hash = cp.digest(bridge)
    serial = itertools.count()
    def request(operation="execute_segment", boundary="synthesis", source=None, checkpoint=None):
        tag = "wire-" + str(next(serial))
        return {"protocol_version": 1, "operation": operation, "request_id": tag,
                "reply_path": str(project / (tag + "-reply.json")), "boundary": boundary,
                "checkpoint": str(checkpoint) if checkpoint else None, "source_boundary": source,
                "candidate": str(project / tag), "project": str(project), "pdk_root": str(pdk),
                "tag": tag, "bridge_sha256": bridge_hash}
    def call(req, mode="success", *, text=None):
        request_file = project / ("call-" + str(next(serial)) + ".json")
        request_file.write_text(p.canonical(req) if text is None else text)
        env = dict(os.environ, BRIDGE_FIXTURE_MODE=mode)
        result = subprocess.run([sys.executable, "-I", "-B", str(fixture), str(bridge), str(request_file)],
                                cwd=root, env=env, text=True, capture_output=True)
        return result

    fresh = request()
    assert call(fresh).returncode == 0
    completed = p.read_reply(fresh)
    check(fresh, completed, valid=True)
    lexical = request()
    lexical["candidate"] = lexical["candidate"].replace("/wire-", "//wire-") + "/"
    assert call(lexical).returncode == 0
    check(lexical, p.read_reply(lexical), valid=True)
    assert completed["outcome"] == "completed"
    report = cp.read(Path(fresh["candidate"]) / "segment.json")
    assert report["status"] == "completed" and report["acceptance"] == "not_evaluated"
    assert report["metrics"]["backend_nonfinite"]["raw"] == "inf"
    assert "Infinity" in (Path(fresh["candidate"]) / "state.json").read_text()
    source = Path(fresh["candidate"])
    (source / "manifest.json").write_text('{"boundary":"synthesis"}')
    for boundary in ("floorplan", "placement"):
        req = request(boundary=boundary, source="synthesis", checkpoint=source)
        assert call(req).returncode == 0
        check(req, p.read_reply(req), valid=True)
        assert cp.read(Path(req["candidate"]) / "segment.json")["from"] == "Checker.YosysUnmappedCells"
    previous, previous_boundary = source, "synthesis"
    for boundary in ("floorplan", "placement", "cts", "routing", "signoff"):
        req = request(boundary=boundary, source=previous_boundary, checkpoint=previous)
        assert call(req).returncode == 0
        check(req, p.read_reply(req), valid=True)
        report = cp.read(Path(req["candidate"]) / "segment.json")
        assert report["from"] == execution_plan.SUCCESSORS[previous_boundary]
        assert report["to"] == execution_plan.BOUNDARIES[boundary]
        assert report["returned_steps"][0] == report["from"]
        assert report["returned_steps"][-1] == report["to"]
        previous, previous_boundary = Path(req["candidate"]), boundary
        (previous / "manifest.json").write_text(json.dumps({"boundary": boundary}))
    for mode in ("failure", "invalid_state"):
        req = request() if mode == "failure" else request(boundary="floorplan", source="synthesis", checkpoint=source)
        assert call(req, mode).returncode != 0
        failed = p.validate_reply(p.loads(Path(req["reply_path"]).read_text()), req)
        check(req, failed, valid=True)
        assert failed["outcome"] == "failed" and failed["artifacts"] == {}
        assert not (Path(req["candidate"]) / "segment.json").exists()
    for mode in ("interrupt", "signal"):
        req = request()
        result = call(req, mode)
        assert result.returncode != 0
        if mode == "signal":
            assert result.returncode == -signal.SIGTERM
        assert not Path(req["reply_path"]).exists()
        assert not (Path(req["candidate"]) / "segment.json").exists()

    validation = request("validate_publication")
    validation["candidate"] = fresh["candidate"]
    (project / "started").unlink()
    assert call(validation).returncode == 0
    validated = p.read_reply(validation)
    check(validation, validated, valid=True)
    assert validated["outcome"] == "validated" and not (project / "started").exists()
    assert set(validated["artifacts"]) == {"resolved.json", "closure.json"}
    broken = request("validate_publication")
    broken["candidate"] = fresh["candidate"]
    resolved = source / "resolved.json"
    original = resolved.read_text()
    resolved.write_text("changed")
    assert call(broken).returncode != 0
    check(broken, p.loads(Path(broken["reply_path"]).read_text()), valid=True)
    resolved.write_text(original)

    # The full standalone transition domain, independent of recipe contiguity.
    boundaries = tuple(p.TRANSITIONS)
    for operation in p.OPERATIONS:
        for boundary in boundaries:
            for source_boundary in (None, *boundaries, "unknown"):
                for checkpoint in (None, "/checkpoint"):
                    req = request(operation, boundary, source_boundary, checkpoint)
                    check(req)
    base = request()
    for key in base:
        changed = copy.deepcopy(base)
        del changed[key]
        check(changed, valid=False)
        for value in (None, True, False, 0, 1, 1.0, 2, "", "unknown", [], {}, "\0", "\ud800"):
            changed = copy.deepcopy(base)
            changed[key] = value
            check(changed)
    check(dict(base, extra=True), valid=False)
    for key in ("reply_path", "project", "pdk_root", "candidate", "checkpoint"):
        check(dict(base, **{key: "relative/path"}), valid=False)
    for version in (0, 2, -1, True, 1.0, "1"):
        check(dict(base, protocol_version=version), valid=False)
    for tag in (".", "..", "a/b"):
        check(dict(base, tag=tag), valid=False)
    unicode_req = dict(base, request_id="wire-é-😀", tag="标签")
    check(unicode_req, valid=True)
    # Responses generated by actual calls seed response mutations.
    for req, reply in ((fresh, completed), (validation, validated)):
        for key in reply:
            changed = copy.deepcopy(reply)
            del changed[key]
            check(req, changed, valid=False)
            for value in (None, True, False, 0, 1, 1.0, 2, "", "unknown", [], {}, "\0", "\ud800"):
                changed = copy.deepcopy(reply)
                changed[key] = value
                check(req, changed)
        for key in ("request_id", "candidate", "bridge_sha256", "boundary", "project", "pdk_root", "tag", "reply_path"):
            changed = dict(req, **{key: ("signoff" if key == "boundary" else "0" * 64
                                      if key == "bridge_sha256" else "/different")})
            check(changed, reply, valid=False)
        check(req, dict(reply, extra=True), valid=False)
        for name in reply["artifacts"]:
            removed = copy.deepcopy(reply)
            del removed["artifacts"][name]
            check(req, removed, valid=False)
            for key in ("path", "sha256", "bytes"):
                removed = copy.deepcopy(reply)
                del removed["artifacts"][name][key]
                check(req, removed, valid=False)
                for value in (None, True, False, -1, 0, 1.0, "bad", [], {}, "A" * 64, "f" * 63):
                    changed = copy.deepcopy(reply)
                    changed["artifacts"][name][key] = value
                    check(req, changed)
            changed = copy.deepcopy(reply)
            changed["artifacts"][name]["bytes"] = 10 ** 100
            check(req, changed, valid=True)
            changed["artifacts"][name]["extra"] = 0
            check(req, changed, valid=False)
        failed = dict(reply, outcome="failed", error="backend failure", artifacts={})
        check(req, failed, valid=True)
        check(req, dict(failed, error=None), valid=False)
        check(req, dict(failed, error=""), valid=False)
        check(req, dict(failed, artifacts=reply["artifacts"]), valid=False)

    for raw in ("", "{", "NaN", '{"request":{},"request":{},"reply":null}',
                json.dumps({"request": base, "reply": None}).replace('"protocol_version": 1',
                    '"protocol_version": 1, "protocol_version": 1'),
                json.dumps({"request": base, "reply": None}) + " null",
                '{"request":1e999,"reply":null}'):
        try:
            decoded = p.loads(raw)
            p.validate_request(decoded["request"])
        except (ValueError, TypeError, KeyError):
            cases.append((raw, None))
            counts[1] += 1
        else:
            raise AssertionError(raw)
    # Execute malformed/version/source cases through the real bridge as well.
    for change in ({"protocol_version": 2}, {"operation": "unknown"}, {"extra": 1},
                   {"source_boundary": "synthesis"}, {"boundary": "routing"},
                   {"protocol_version": True}, {"protocol_version": 1.0}, {"checkpoint": []}):
        req = dict(request(), **change)
        assert call(req).returncode != 0 and not Path(req["reply_path"]).exists()
    for invalid in ("{", p.canonical(base) + " null", p.canonical(base).replace(
            '"protocol_version":1', '"protocol_version":1,"protocol_version":1')):
        req = request()
        assert call(req, text=invalid).returncode != 0 and not Path(req["reply_path"]).exists()
    # Legacy bytes remain readable as evidence but are rejected for execution.
    legacy = {key: value for key, value in request().items()
              if key not in ("protocol_version", "operation", "request_id", "reply_path")}
    assert call(legacy).returncode != 0
    assert call(fresh).returncode != 0  # retained reply/candidate cannot be reused
    support = bridge.with_name("backend_protocol.py")
    original_support = support.read_bytes()
    support.write_bytes(original_support + b"\nraise RuntimeError('unverified code')\n")
    req = request()
    result = call(req)
    assert result.returncode != 0 and "protocol hash mismatch" in result.stderr
    assert "unverified code" not in result.stderr and not Path(req["reply_path"]).exists()
    support.write_bytes(original_support)

    # Real host adapter + bridge: publication failure is fail-closed, even with
    # a zero exit and a success-looking segment. No changes to the storage writer.
    compat = {"target": "fixture", "binding": {"image_identity": {"image_id": execution_plan.TESTED_IMAGE}},
              "bridge_sha256": bridge_hash, "project": str(project)}
    store = root / "checkpoints"
    store.mkdir()
    def adapter(mode="success", mutate=None):
        def launch(bridge_arg, path, tag):
            req = p.validate_request(p.loads(path.read_text()))
            result = subprocess.run([sys.executable, "-I", "-B", str(fixture), str(bridge_arg), str(path)],
                                    cwd=root, env=dict(os.environ, BRIDGE_FIXTURE_MODE=mode),
                                    capture_output=True)
            if mutate and result.returncode == 0:
                reply = p.loads(Path(req["reply_path"]).read_text())
                mutate(req, reply)
                Path(req["reply_path"]).write_text(p.canonical(reply))
            return result.returncode
        return stages.SegmentAdapter(project=project, pdk_root=pdk, compatibility=compat,
                                     launch=launch, checkpoint_store=store)
    for mode, mutate in (("failure", None), ("signal", None),
                         ("success", lambda req, rep: rep.update(request_id="mismatched")),
                         ("success", lambda req, rep: rep.update(protocol_version=2)),
                         ("success", lambda req, rep: rep.update(outcome="failed", artifacts={}, error="failed")),
                         ("success", lambda req, rep: rep.update(extra=True))):
        result = runner.execute(execution_plan.resolve_stages("synthesis"), adapter(mode, mutate))
        assert result.exit_code != 0 and result.artifacts == [] and list(store.iterdir()) == []
    good_adapter = adapter()
    segment = good_adapter.run_segment("synthesis")
    candidate_report = segment.candidate / "segment.json"
    candidate_report.write_text(candidate_report.read_text() + " ")
    try:
        good_adapter.publish(execution_plan.resolve_stages("synthesis").actions[0], segment)
    except ValueError:
        pass
    else:
        raise AssertionError("mutated candidate was published")
    assert list(store.iterdir()) == []
    good = runner.execute(execution_plan.resolve_stages("synthesis"), adapter())
    assert good.exit_code == 0 and len(good.artifacts) == 1
    cp.validate(good.artifacts[0]["path"], compatibility=compat)

    result = subprocess.run([str(emitter)], input="\n".join(raw for raw, _ in cases) + "\n",
                            text=True, capture_output=True, cwd=root, check=True)
    outputs = result.stdout.splitlines()
    assert len(outputs) == len(cases), result.stderr
    for (raw, expected), actual in zip(cases, outputs):
        assert (actual.startswith("ERR:") if expected is None else actual == expected), (raw, expected, actual)
    print(f"backend protocol parity: {counts[0]} accepted / {counts[1]} rejected; actual bridge and no-publication checks passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--emitter", type=Path)
    parser.add_argument("--provider-prefix", type=Path)
    parser.add_argument("--installed", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="backend-protocol-", dir="/tmp/opencode") as tmp:
        root = Path(tmp)
        if not args.installed:
            package = args.provider_prefix / "lib/hardcaml_asic/flow" if args.provider_prefix else repo / "flow"
            verify(args.emitter.resolve(), package, root, Path(__file__).with_name("bridge_protocol_fixture.py"))
            return
        prefix = root / "prefix"
        subprocess.run(["dune", "build", "-j20", "@install"], cwd=repo,
                        check=True, stdout=subprocess.DEVNULL)
        hardlink_prefix(repo / "_build/install/default", prefix)
        package = prefix / "lib/hardcaml_asic/flow"
        reference = copy_reference(repo / "flow", root / "oracle", package)
        thin_prefix(prefix)
        consumer = root / "consumer"
        consumer.mkdir()
        shutil.copyfile(repo / "test/backend_protocol_driver.ml", consumer / "backend_protocol_driver.ml")
        (consumer / "dune-project").write_text("(lang dune 3.17)\n(name installed_protocol_consumer)\n")
        (consumer / "dune").write_text("(executable (name backend_protocol_driver) (libraries hardcaml_asic.execution))\n")
        env = dict(os.environ)
        env["OCAMLPATH"] = str(prefix / "lib") + (":" + env["OCAMLPATH"] if env.get("OCAMLPATH") else "")
        subprocess.run(["dune", "build", "-j20", "backend_protocol_driver.exe"], cwd=consumer, env=env, check=True)
        fixture = root / "bridge_protocol_fixture.py"
        shutil.copyfile(repo / "test/bridge_protocol_fixture.py", fixture)
        for name in ("check_backend_protocol.py", "reference_harness.py"):
            shutil.copyfile(repo / "test" / name, root / name)
        env.update(FLOW_TEST_REFERENCE_ROOT=str(reference), FLOW_TEST_RUNTIME_ROOT=str(package))
        subprocess.run([sys.executable, "-I", "-B", "-c", ENTRY, str(repo),
                        str(root / "check_backend_protocol.py"), "--emitter",
                        str(consumer / "_build/default/backend_protocol_driver.exe"),
                        "--provider-prefix", str(prefix)], cwd=root, env=env, check=True)
        print("independently installed protocol consumer and isolated bridge passed outside checkout")


if __name__ == "__main__":
    main()
