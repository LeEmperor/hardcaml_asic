"""Host experiment driver: reuse provider preflight and owned Docker transport.

No provisioning, Dune invocation, consumer writes, or copied orchestration.
All raw evidence is retained in a fresh /tmp/opencode directory.
"""

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "flow"))
from hardcaml_asic_flow import execution_transport as transport, phase4


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--physical-to", default="OpenROAD.Floorplan")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    consumer = args.consumer.resolve()
    tools = consumer / "_flow_tools"
    root = Path(tempfile.mkdtemp(prefix="librelane-slice2-", dir="/tmp/opencode"))
    print(f"SCRATCH={root}", flush=True)
    report = phase4.preflight(args.bundle.resolve(), tools / "tt", tools / "pdk",
                             tools / ".venv/bin/python")
    phase4.save(root / "preflight.json", report)
    if not report["ready"]:
        raise RuntimeError(report["issues"])
    binding = transport.from_preflight(report, native=False)
    transport.verify_engine(binding)
    transport.verify_image(binding)
    project = root / "project"
    shutil.copytree(args.bundle, project)
    manifest = phase4.read_json(project / "manifest.json")
    for ref in manifest["target"]["external_references"]:
        if ref["source"] == "Support_tools":
            source = phase4.safe_child(tools / "tt", ref["path"])
            target = phase4.safe_child(project / "tt", ref["path"])
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    bridge = project / "bridge"
    bridge.mkdir()
    for name in ("backend_probe.py", "probe.py", "fixture.py"):
        shutil.copy2(Path(__file__).with_name(name), bridge / name)
    record = {"binding": binding, "bundle": str(args.bundle.resolve()),
              "manifest_sha256": phase4.digest(project / "manifest.json"),
              "bridge": {p.name: phase4.digest(p) for p in bridge.iterdir()},
              "commands": [], "containers": []}
    record_path = root / "transport.json"
    phase4.save(record_path, record)

    def launch(script, arguments, label):
        name = transport.owned_name()
        record["containers"].append({"name": name, "label": label})
        argv = transport.docker_command(binding, project, tools / "pdk", name=name,
                                        pdk=manifest["target"]["technology"])
        argv += [*binding["interpreter_flags"], str(bridge / script), *arguments]
        code = phase4.run_logged(argv, project, transport.environment(), root / (label + ".log"),
                                 record, record_path, timeout=args.timeout,
                                 cleanup=lambda: transport.cleanup(binding, name))
        if code:
            raise RuntimeError(f"{label} exited {code}; see {root / (label + '.log')}")

    launch("probe.py", ["--scratch-parent", str(project)], "synthetic")
    common = ["--project", str(project), "--pdk-root", str(tools / "pdk"),
              "--physical-to", args.physical_to]
    launch("backend_probe.py", ["synthesis", *common], "synthesis")
    # Prove copied views suffice: all original absolute synthesis paths disappear.
    (project / "src/runs/synthesis").rename(project / "retained-synthesis")
    launch("backend_probe.py", ["physical", *common], "physical")
    synthesis = phase4.read_json(project / "synthesis.json")
    physical = phase4.read_json(project / "physical.json")
    assert synthesis["resolved_config_sha256"] == physical["resolved_config_sha256"]
    assert synthesis["runtime"]["bridge_sha256"] == physical["runtime"]["bridge_sha256"]
    assert phase4.digest(project / "manifest.json") == record["manifest_sha256"]
    phase4.save(root / "summary.json", {
        "status": "passed", "designation": "REAL synthesis -> copied checkpoint -> fresh physical segment",
        "scratch": str(root), "bundle_identity": manifest["identity"],
        "synthesis_to": synthesis["synthesis_to"], "physical_from": physical["physical_from"],
        "physical_to": physical["physical_to"], "physical_artifacts": physical["physical_artifacts"],
        "same_resolved_configuration": True, "same_bridge": True,
        "original_synthesis_run_absent": True,
        "limits": ["not full-flow/signoff acceptance", "not a durable journal",
                   "checkpoint still requires staged config/collateral paths and compatible runtime",
                   "no real signal/descendant cancellation experiment"]})
    print(f"PASSED {root / 'summary.json'}", flush=True)


if __name__ == "__main__":
    with phase4.interruption_handlers():
        main()
