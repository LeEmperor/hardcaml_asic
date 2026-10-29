"""Independent actual helper/native-reader checks; no methodology codec workaround."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

EMITTER, CONSUMER, HELPER = map(lambda x: Path(x).resolve(), sys.argv[1:])
spec = importlib.util.spec_from_file_location("engine", Path(__file__).with_name("engine.py"))
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
read, write, sha = engine.read, engine.write, engine.sha

with tempfile.TemporaryDirectory(prefix="named-core-", dir="/tmp/opencode") as temp:
    temp = Path(temp)
    bundle = temp / "bundle"
    emitted = subprocess.run([EMITTER, bundle, "--bundle-only"], text=True, capture_output=True)
    assert emitted.returncode == 0, emitted.stderr
    for mode in ("good", "later_failure", "unexecuted", "wrong_state", "wrong_netlist", "wrong_position", "duplicate_producer"):
        root = temp / mode
        root.mkdir()
        shutil.copytree(bundle, root / "project")
        out = root / "timing-intent/attempt"
        out.mkdir(parents=True)
        candidate = root / "project/candidates/synthesis-tag"
        candidate.mkdir(parents=True)
        producer = root / "project/src/runs/synthesis-tag/06-yosys-synthesis"
        producer.mkdir(parents=True)
        (producer / "mapped.v").write_text("// original\n")
        state = dict(nl=str(producer / "mapped.v"), metrics={"infinite": float("inf")})
        write(producer / "state_out.json", state)
        write(candidate / "state.json", state)
        write(producer / "config.json", dict(meta=dict(step="Yosys.Synthesis", librelane_version="3.1.0.dev3")))
        checkpoint = root / "checkpoints/synthesis-publication"
        (checkpoint / "views").mkdir(parents=True)
        shutil.copyfile(producer / "mapped.v", checkpoint / "views/00001-mapped.v")
        write(checkpoint / "state.json", dict(state, nl=str(checkpoint / "views/00001-mapped.v")))
        write(checkpoint / "resolved.json", dict(DEFAULT_CORNER="typ", STA_CORNERS=["fast", "typ", "slow"],
            STA_THREADS=6, OPENROAD_THREADS=6, PNR_SDC_FILE=str(root / "project/constraints/top.sdc"),
            STA_EXTRA_CORNER_TCL_FILE=None, STA_MACRO_PRIORITIZE_NL=True, EXTRA_LIBS=None, EXTRA_VERILOG_MODELS=None,
            DESIGN_NAME="tt_um_pt7_flow_fixture"))
        write(checkpoint / "manifest.json", dict(identity="a" * 64,
              files={"views/00001-mapped.v": dict(sha256=sha(checkpoint / "views/00001-mapped.v"))}))
        ref = lambda p: dict(path=str(p), sha256=sha(p))
        cp = dict(path=str(checkpoint), identity="a" * 64, boundary="synthesis")
        expectation = dict(attempt_id="attempt", occurrence_id="attempt/implementation.synthesis")
        publication = dict(expectation=expectation, checkpoint=cp,
            request=dict(operation="execute_segment", boundary="synthesis", checkpoint=None, tag="synthesis-tag", candidate=str(candidate)),
            segment=dict(run_dir=str(producer.parent), returned_steps=["lint", "lint2", "lint3", "lint4", "Yosys.JsonHeader", "Yosys.Synthesis"]),
            sources=[ref(checkpoint / "state.json"), ref(checkpoint / "views/00001-mapped.v")])
        write(out / "publication.json", publication)
        manifest = read(root / "project/manifest.json")
        request = dict(schema=1, kind="hardcaml-asic.named-timing-request", execution_root=str(root),
            project=str(root / "project"),
            analysis_directory=str(out), expectation=expectation, publication=ref(out / "publication.json"), checkpoint=cp,
            synthesis_run_dir=str(producer.parent), state_path=str(checkpoint / "state.json"), resolved_path=str(checkpoint / "resolved.json"),
            manifest_sha256=sha(root / "project/manifest.json"), build_identity=manifest["identity"],
            producer_sha256=sha(root / "project/constraints/pt7-native-coverage.tcl"), pdk_root=str(temp / "pdk"),
            attempt_id="attempt", occurrence_id=expectation["occurrence_id"], analysis_id="attempt/pre-pnr-sta")
        if mode == "wrong_state":
            request["state_path"] = str(candidate / "state.json")
        elif mode == "wrong_netlist":
            (producer / "mapped.v").write_text("// unrelated\n")
        elif mode == "wrong_position":
            producer.rename(producer.with_name("05-yosys-synthesis"))
        elif mode == "duplicate_producer":
            shutil.copytree(producer, producer.with_name("07-yosys-synthesis"))
        write(out / "request.json", request)
        before = {p: sha(p) for p in checkpoint.rglob("*") if p.is_file()}
        failed = False
        original_run = subprocess.run
        try:
            engine.native(HELPER, out / "request.json", mode)
        except (ValueError, subprocess.CalledProcessError):
            failed = True
        finally:
            subprocess.run = original_run
        assert failed == (mode != "good"), mode
        assert all(sha(p) == h for p, h in before.items()), mode
        if mode == "good":
            audit = out / "corners/typ"
            inspected = subprocess.run([CONSUMER, "audit", audit], text=True, capture_output=True)
            assert inspected.returncode == 0, inspected.stderr
            result = json.loads(inspected.stdout)
            assert result["verdict"] == "unavailable"
            assert read(out / "runtime-result.json")["synthesis"]["state"]["path"] == str((checkpoint / "state.json").relative_to(root))
    print("7 independent native-core cases pass: actual published State, schema2/profile2 inspection, immutable checkpoint, process/corner and exact producer negatives; fixture native boundary, no EDA")
