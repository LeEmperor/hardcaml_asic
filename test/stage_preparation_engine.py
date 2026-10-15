#!/usr/bin/python3
"""Disposable revision/runtime engine fixture. Native bridge execution stays real."""
import json
import os
from pathlib import Path
import subprocess
import sys

args = sys.argv[1:]
root = Path(os.environ["SERVICE_ENGINE_ROOT"])
if os.environ.get("ASSERT_JOURNAL_BEFORE_PROBE"):
    allocations = list((root / "observations").glob("*/000000000001.json"))
    assert len(allocations) == 1, allocations
    allocation = json.loads(allocations[0].read_text())
    assert allocation["event"] == "allocated" and allocation["schema_version"] == 2
    assert Path(allocation["data"]["preflight_record"]).is_file()
    named = allocation["data"]["request"].get("methodology_launch")
    if named:
        snapshot = json.loads(Path(named["snapshot_path"]).read_text())
        assert snapshot["plan_identity"] == named["expected_plan_identity"]
mode = os.environ.get("PREPARATION_MODE", "success")
name = Path(sys.argv[0]).name
with (root / "preparation-events.jsonl").open("a") as stream:
    stream.write(json.dumps([name, args]) + "\n")
# Keep the fixture's ID supplied by the checked capability, not a second authority.
image = os.environ["PREPARATION_IMAGE"]
if name == "git":
    revisions = json.loads(os.environ.get('PREPARATION_REVISIONS', '{}'))
    revision = revisions.get(args[args.index('-C')+1], os.environ.get('PREPARATION_REVISION', 'revision')) if '-C' in args else os.environ.get('PREPARATION_REVISION', 'revision')
    print(revision if "rev-parse" in args else (" M fixture" if mode == "dirty" else ""))
elif name == "python" or ("-c" in args and args[-1] == "container"):
    role = "host" if name == "python" else "container"
    if mode == "probe_failure":
        sys.exit(17)
    if mode == "probe_timeout":
        import time
        time.sleep(10)
    isolated_failure = mode == "fallback" and role == "container" and "-I" in args
    metadata = {"python_version": "3.11.17" if role == "host" else "3.13.13",
                "librelane_version": None if isolated_failure else "3.1.0.dev3",
                "requires_python": None if isolated_failure else ">=3.10",
                "metadata_error": "isolated missing" if isolated_failure else None}
    if role == "host":
        metadata["tcl"] = {"ready": mode != "tcl_failure", "version": "8.6", "error": None}
        if mode == "host_mismatch":
            metadata["python_version"] = "3.10.0"
    elif not isolated_failure and mode != "classic_missing":
        metadata["classic_inventory"] = json.loads((root / "classic-inventory.json").read_text())
        metadata["classic_settings"] = json.loads((root / "classic-settings.json").read_text())
        if mode == "classic_settings_drift":
            metadata["classic_settings"]["OpenROAD.DetailedPlacement"][0]["default"] = "false"
        if mode.startswith("synth_"):
            settings = metadata["classic_settings"]["Yosys.Synthesis"]
            if mode == "synth_missing":
                settings.pop(0)
            elif mode == "synth_type":
                settings[0]["kind"] = "string"
            elif mode == "synth_default":
                settings[0]["default"] = "DELAY 1"
            elif mode == "synth_domain":
                settings[0]["allowed_values"].append("DELAY 5")
            elif mode == "synth_domain_missing":
                del settings[0]["allowed_values"]
            elif mode == "synth_bool_type":
                settings[1]["kind"] = "integer"
            elif mode == "synth_bool_default":
                settings[1]["default"] = "true"
        if mode == "classic_drift":
            metadata["classic_inventory"][0]["id"] = "unsupported.drift"
    print(json.dumps({"protocol_version": 2 if mode == "protocol_version" else 1,
                      "kind": "stage_runtime_metadata", "role": role, "metadata": metadata}))
elif args[0] == "info":
    mutation = os.environ.get("NAMED_BETWEEN_STAGES")
    if mutation and list(root.glob("workspace*/checkpoints/synthesis-*")):
        (root / "workspace/project" / mutation).write_text("changed between stages")
    events = (root / "preparation-events.jsonl").read_text()
    changed = ((mode == "engine_changed" and events.count('"info"') > 1)
               or (mode == "engine_changed_after_execute" and list(root.glob("workspace*/project/candidates/*"))))
    print(json.dumps({"ServerVersion": "changed" if changed else "fixture", "SecurityOptions": [],
                      "ID": "fixture-daemon", "Name": "fixture-server"}))
elif args[:2] == ["image", "inspect"]:
    print(json.dumps([{"Id": "sha256:" + "0" * 64 if mode == "wrong_image" else image,
                       "RepoDigests": [], "Os": "linux", "Architecture": "amd64"}]))
else:
    if args[0] == 'run' and os.environ.get('PREPARATION_RELEASE'):
        import time
        (root / 'backend-waiting').touch()
        while not Path(os.environ['PREPARATION_RELEASE']).exists():
            time.sleep(.02)
    if args[0] == "run" and os.environ.get("PUBLICATION_STORAGE_FAULT"):
        store = next(root.glob("workspace*/checkpoints"))
        store.rmdir()
        store.write_text("retained storage obstruction")
    if args[0] == "run" and os.environ.get("EXECUTION_STORAGE_FAULT"):
        summary = next(root.glob("workspace*/execution-*.json"))
        summary.unlink()
        summary.mkdir()
    if os.environ.get("JOURNAL_COLLISION") and args[0] == "run":
        journals = list((root / "observations").glob("*/000000000001.json"))
        if journals:
            (journals[0].parent / "000000000005.json").write_text("retained conflict")
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("segment_service_engine.py")), *args])
    sys.exit(result.returncode)
