"""PDK-free public bundle and execution-contract checks; no EDA imports/runs."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

consumer, bridge = map(lambda p: Path(p).resolve(), sys.argv[1:])


def run(*args, ok=True):
    p = subprocess.run([str(consumer), *map(str, args)], capture_output=True, text=True)
    assert (p.returncode == 0) == ok, p.stdout + p.stderr


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    # Empty-tree commit without changing any Git configuration or staging files.
    tree = subprocess.run(["git", "-C", str(root), "mktree"], input="", text=True,
                          capture_output=True, check=True).stdout.strip()
    import os
    env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
               GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    commit = subprocess.run(["git", "-C", str(root), "commit-tree", tree, "-m", "fixture"],
                            env=env, capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run(["git", "-C", str(root), "update-ref", "HEAD", commit], check=True)
    (root / "generator.ml").write_text("(* fixture source inventory *)\n")
    bundle = root / "bundle"
    run("emit", root, bundle)
    run("validate", bundle)
    manifest = json.loads((bundle / "manifest.json").read_text())
    config_bytes = (bundle / "src/config.json").read_bytes()
    config = json.loads(config_bytes)
    contract = manifest["macro_contract"]
    assert contract["execution"] == "synthesis_only"
    assert len(contract["macros"]) == 2
    assert len({m["instance"] for m in contract["macros"]}) == 2
    assert all(m["physical_intent"]["power"]["VDDARRAY!"] == "VPWR" for m in contract["macros"])
    stub = bundle / contract["blackbox_sources"][0]
    assert "(* blackbox *)" in stub.read_text()
    assert stub.relative_to(bundle).as_posix() not in manifest["simulation_sources"]
    assert contract["implementation_simulation"]["defines"] == ["FUNCTIONAL"]
    macro = next(iter(config["MACROS"].values()))
    assert set(macro["lib"]) == set(config["STA_CORNERS"])
    assert "m55C.lib" in macro["lib"]["nom_fast_1p32V_m40C"][0]
    # Load only this pure validator: importing the bridge requires real LibreLane.
    tree = ast.parse(bridge.read_text())
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "validate_macro_bundle")
    ns = {"json": json}
    exec(compile(ast.Module(body=[fn], type_ignores=[]), str(bridge), "exec"), ns)
    assert ns["validate_macro_bundle"](bundle)
    original = copy.deepcopy(manifest)
    def write_resealed(value, raw):
        # Exercise semantic validation rather than stale identity/file hashes.
        (bundle / "src/config.json").write_text(json.dumps(raw))
        for entry in value["files"]:
            if entry["path"] == "src/config.json":
                entry["sha256"] = hashlib.sha256((bundle / entry["path"]).read_bytes()).hexdigest()
        payload = {k:v for k,v in value.items() if k != "identity"}
        value["identity"] = hashlib.sha256(json.dumps(payload, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
        (bundle / "manifest.json").write_text(json.dumps(value))

    def swap_instances(m):
        a, b = m["macro_contract"]["macros"]
        a["instance"], b["instance"] = b["instance"], a["instance"]

    linkage_cases = [
        ("unknown resource", lambda m: m["macro_contract"]["macros"][0].update(resource="nonexistent_resource")),
        ("unknown resource with canonical name", lambda m: m["macro_contract"]["macros"][0].update(resource="nonexistent_resource",instance="hc_resource_20_nonexistent_resource")),
        ("unknown instance", lambda m: m["macro_contract"]["macros"][0].update(instance="nonexistent_instance")),
        ("swapped distinct instances", swap_instances),
        ("duplicate resource", lambda m: m["macro_contract"]["macros"][0].update(resource=m["macro_contract"]["macros"][1]["resource"])),
        ("omitted resource", lambda m: m["macro_contract"]["macros"].pop()),
        ("wrong registered request", lambda m: m["resources"][0].update(request=m["resources"][0]["request"].replace("width 16", "width 8"))),
        ("registered flops", lambda m: m["resources"][0].update(selection="((implementation Flops) (reason Explicit_flops))")),
        ("duplicate registration", lambda m: m["resources"].append(copy.deepcopy(m["resources"][0]))),
        ("behavioral registration", lambda m: m["resources"][0].update(elaborated_as="Behavioral_model")),
        ("unknown config instance", lambda m: next(iter(m["flow_configuration"]["MACROS"].values()))["instances"].update(nonexistent_instance={"location":[42.0,81.0],"orientation":"R0"})),
        ("missing config placement", lambda m: next(iter(m["flow_configuration"]["MACROS"].values()))["instances"].pop(m["macro_contract"]["macros"][0]["instance"])),
    ]
    for label, mutate in linkage_cases:
        bad = copy.deepcopy(original)
        mutate(bad)
        write_resealed(bad, bad["flow_configuration"])
        run("validate", bundle, ok=False)
        try:
            ns["validate_macro_bundle"](bundle)
        except ValueError:
            pass
        else:
            raise AssertionError("Python bridge accepted " + label)
    # Synthesis may declare only a subset of placements, but every declared intent
    # must correspond exactly to its config entry; both distinct resources remain.
    for omit in (1, 2):
        partial = copy.deepcopy(original)
        for m in partial["macro_contract"]["macros"][:omit]:
            m["physical_intent"] = None
            next(iter(partial["flow_configuration"]["MACROS"].values()))["instances"].pop(m["instance"])
        write_resealed(partial, partial["flow_configuration"])
        run("validate", bundle)
        assert ns["validate_macro_bundle"](bundle)
    (bundle / "src/config.json").write_bytes(config_bytes)
    for mutate in (lambda m: m["macro_contract"].update(execution="physical"),
                   lambda m: m["flow_configuration"].update(STA_CORNERS=["nom_*"]),
                   lambda m: m["macro_contract"]["macros"][0].update(module="unknown")):
        bad = copy.deepcopy(original)
        mutate(bad)
        (bundle / "manifest.json").write_text(json.dumps(bad))
        run("validate", bundle, ok=False)
        try:
            ns["validate_macro_bundle"](bundle)
        except ValueError:
            pass
        else:
            raise AssertionError("bridge accepted malformed macro contract")
    (bundle / "manifest.json").write_text(json.dumps(original))
    # Exercise real OCaml preflight against synthetic external files/runtimes.
    # The technology exposure may link to shared collateral within the PDK checkout.
    import importlib.util
    spec = importlib.util.spec_from_file_location("preflight_fixture", Path(__file__).parent.parent / "check_preflight.py")
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    bin_dir, tools, pdk, probes = [root / n for n in ("bin", "tools", "pdk", "probes")]
    for p in (bin_dir, tools, pdk, probes):
        p.mkdir()
    for name in ("git", "python"):
        p = bin_dir / name
        p.write_text(fixture.FAKE.replace("INTERPRETER", sys.executable))
        p.chmod(0o755)
    (root / "mode.json").write_text("{}")
    runtime_manifest = copy.deepcopy(original)
    runtime_manifest["requested_tools"].update(support_tools_revision="revision", pdk_revision="revision")
    for reference in runtime_manifest["target"]["external_references"]:
        base = tools if reference["source"] == "Support_tools" else pdk / "ihp-sg13cmos5l"
        p = base / reference["path"]
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("synthetic reference")
        reference["sha256"] = None
    shared = pdk / "shared_sram"
    shared.mkdir()
    (pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram").symlink_to(shared, target_is_directory=True)
    external = set()
    for macro in contract["macros"]:
        for c in macro["collateral"]:
            if c["reference"].startswith("pdk_dir::"):
                p = pdk / "ihp-sg13cmos5l" / c["reference"][9:]
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text("synthetic macro collateral")
                external.add(p)
    (bundle / "manifest.json").write_text(json.dumps(runtime_manifest))
    env = dict(os.environ, PATH=str(bin_dir), FIXTURE=str(root))
    def preflight():
        fresh = Path(tempfile.mkdtemp(dir=probes))
        result = subprocess.run([str(consumer), "preflight", str(bundle), str(tools), str(pdk),
                                 str(bin_dir / "python"), str(bridge.parent), str(fresh)],
                                env=env, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    report = preflight()
    assert report["ready"], report
    assert len([r for r in report["references"] if r["role"].startswith("macro:")]) >= 8
    missing = next(p for p in external if p.suffix == ".cdl")
    missing.unlink()
    report = preflight()
    assert not report["ready"] and any("missing macro Spice_netlist" in i for i in report["issues"]), report
    missing.write_text("synthetic macro collateral")
    (root / "mode.json").write_text('{"dirty":true}')
    report = preflight()
    assert not report["ready"] and any("modified macro" in i for i in report["issues"]), report
    (root / "mode.json").write_text('{}')
    launch_fixture = r'''
if '-m' in a and a[a.index('-m')+1] == 'librelane':
    assert a[a.index('--jobs')+1] == '6'
    assert a[a.index('--to')+1] == 'Yosys.Synthesis'
    assert all(x in a for x in ('OPENROAD_THREADS=6', 'STA_THREADS=1', 'KLAYOUT_DRC_THREADS=6'))
    assert os.environ['OMP_NUM_THREADS'] == '6'
    project = pathlib.Path.cwd()
    manifest = json.loads((project/'manifest.json').read_text())
    assert (project/manifest['macro_contract']['blackbox_sources'][0]).is_file()
    config = json.loads((project/'src/config.json').read_text())
    assert config['MACROS']
    if mode.get('mutate_macro_path'):
        pathlib.Path(mode['mutate_macro_path']).write_text('changed during execution')
    if mode.get('mutate_stub'):
        (project/manifest['macro_contract']['blackbox_sources'][0]).write_text('changed stub during execution')
    print('synthetic SRAM synthesis launch; no EDA')
    sys.exit(0)
'''
    fake = fixture.FAKE.replace("if pathlib.Path(sys.argv[0]).name == 'docker':",
                                launch_fixture + "\nif pathlib.Path(sys.argv[0]).name == 'docker':", 1)
    (bin_dir / "python").write_text(fake.replace("INTERPRETER", sys.executable))
    launches = root / "launches"
    launches.mkdir()
    cmd = [str(bundle), str(tools), str(pdk), str(bin_dir / "python"), str(bridge.parent), str(launches)]
    result = subprocess.run([str(consumer), "coarse-synthesis", *cmd], env=env,
                            capture_output=True, text=True, check=True)
    outcome = json.loads(result.stdout)
    assert outcome["status"] == "completed", outcome
    record = json.loads(Path(outcome["run_record"]).read_text())
    assert record["commands"][-1][-1] == "src/config.json"
    liberty_for_mutation = next(p for p in external if p.suffix == ".lib")
    for mode in ({"mutate_macro_path":str(liberty_for_mutation)}, {"mutate_stub":True}):
        (root / "mode.json").write_text(json.dumps(mode))
        failed = subprocess.run([str(consumer), "coarse-synthesis", *cmd], env=env,
                                capture_output=True, text=True)
        assert failed.returncode == 1, failed.stderr
        failed_outcome = json.loads(failed.stdout)
        assert failed_outcome["status"] == "failed"
        evidence = json.loads(Path(failed_outcome["run_record"]).read_text())
        assert "changed during execution" in evidence["error"], evidence
        liberty_for_mutation.write_text("synthetic macro collateral")
    (root / "mode.json").write_text("{}")
    rejected = subprocess.run([str(consumer), "coarse-full", *cmd], env=env,
                              capture_output=True, text=True)
    assert rejected.returncode and "physical execution" in rejected.stderr
    assert len(list(launches.iterdir())) == 3  # full rejected before allocating a run
    for reference in runtime_manifest["target"]["external_references"]:
        if reference["source"] == "Support_tools":
            p = bundle / "tt" / reference["path"]
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("synthetic reference")
    functions = [n for n in ast.parse(bridge.read_text()).body if isinstance(n, ast.FunctionDef)
                 and n.name in ("digest", "record", "closure", "validate_macro_bundle")]
    ns = {"json": json, "hashlib": hashlib, "Path": Path, "ToolPath": Path}
    exec(compile(ast.Module(body=functions, type_ignores=[]), str(bridge), "exec"), ns)
    before = ns["closure"]({}, bundle, pdk)
    assert str(stub) in before
    assert any(p.endswith(".cdl") for p in before)
    liberty = next(p for p in external if p.suffix == ".lib")
    liberty.write_text("changed macro Liberty")
    assert ns["closure"]({}, bundle, pdk) != before
    execute = next(n for n in ast.parse(bridge.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == "execute")
    exec(compile(ast.Module(body=[execute], type_ignores=[]), str(bridge), "exec"), ns)
    candidate = root / "must-not-publish"
    try:
        ns["execute"]({"project":str(bundle), "pdk_root":str(pdk), "candidate":str(candidate),
                       "boundary":"synthesis", "operation":"execute_segment", "checkpoint":None})
    except ValueError as e:
        assert "segmented checkpoints are unsupported" in str(e)
    else:
        raise AssertionError("macro checkpoint capability must not be minted")
    assert not candidate.exists()
    liberty.write_text("synthetic macro collateral")
    assert ns["closure"]({}, bundle, pdk) == before
    stub.write_text(stub.read_text() + "// changed stub\n")
    assert ns["closure"]({}, bundle, pdk) != before
    print(f"Public SRAM bundle: {len(linkage_cases)} resealed linkage rejections in OCaml/Python; two-resource and partial-placement positives; deterministic emission, preflight, launch and closure checks passed")
