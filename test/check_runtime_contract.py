"""Actual Python/OCaml pure policy and evidence differential, no runtime probes."""
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest import mock

sys.dont_write_bytecode = True

def verify(consumer, fixture_root):
    from hardcaml_asic_flow import runtime_contract as rc, runtime_observation as ro, execution_transport as et
    sys.path.insert(0, str(fixture_root))
    from test_runtime_contract import requested
    from test_runtime_observation import HOST, CONTAINER, IMAGE_ID, IMAGE
    p = subprocess.Popen([str(consumer)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         text=True, env=dict(os.environ, PATH="/unusable", PYTHONPATH="/unusable"))
    counts = [0, 0]
    def check(request, oracle, strict=False):
        try:
            expected = oracle()
        except (ValueError, TypeError, AttributeError, KeyError):
            expected = None
        p.stdin.write(json.dumps(request, allow_nan=False) + "\n")
        p.stdin.flush()
        result = json.loads(p.stdout.readline())
        if expected is None or strict:
            assert isinstance(result, dict) and "error" in result, (request, expected, result)
            counts[1] += 1
        else:
            assert result == expected, (request, expected, result)
            counts[0] += 1
    def policy(value):
        check({"op": "requested", "value": value}, lambda: rc.policy_from_requested(value))
    def mutations(value, path=()):
        node = value
        for k in path:
            node = node[k]
        for key, child in node.items():
            for replacement in (None, True, False, 1, 1.0, "", "wrong", [], {}):
                bad = copy.deepcopy(value)
                target = bad
                for k in path:
                    target = target[k]
                target[key] = replacement
                yield bad
            bad = copy.deepcopy(value)
            target = bad
            for k in path:
                target = target[k]
            del target[key]
            yield bad
            if type(child) is dict:
                yield from mutations(value, path + (key,))
        bad = copy.deepcopy(value)
        target = bad
        for k in path:
            target = target[k]
        target["unknown"] = "extra"
        yield bad
    try:
        new = requested()
        legacy = {"python": "3.11", "librelane": "3.1.0.dev3"}
        for value in [new, legacy, dict(new, unrelated={"future": True}), None, [], True, {}]:
            policy(value)
        for value in mutations(new):
            policy(value)
        for minor in ("0.0", "3.10", "3.14", "99.999999999999999999999", "03.11", "3.011", "3.11.0", "3.11\n"):
            policy(dict(legacy, python=minor))
        for ll in ("2.2.9", "03.01.00.dev03", "1.2.3.rc1", "1.2.3a1", "1.2.3.dev", "1.2.3\n"):
            policy(dict(legacy, librelane=ll))
        for minors in (list(reversed(rc.SUPPORTED_MINORS)), ["3.10"]*5, [], ["3.10", "3.11", "3.12", "3.13", True]):
            value = copy.deepcopy(new)
            value["runtime_policy"]["implementation"]["dockerized"]["python"]["supported_minors"] = minors
            policy(value)
        lock_path = fixture_root / "toolchain.lock"
        if not lock_path.exists():
            lock_path = fixture_root.parent / "toolchain.lock"
        lock = ro.read_lock(lock_path)
        for value in [lock, *mutations(lock), None, []]:
            check({"op": "lock", "value": value}, lambda v=value: rc.policy_from_lock(v))
        contracts = [rc.policy_from_requested(v) for v in (new, legacy)]
        for c in contracts:
            check({"op": "parse", "raw": json.dumps(c)}, lambda: c)
        for raw in ('{} trailing', 'NaN', '{"schema_version":1,"schema_version":1}',
                    '{"source":"\\ud800"}', '{"schema_version":1.0}', '{"x":1e999}'):
            check({"op": "parse", "raw": raw}, lambda: None, strict=True)
        for c in contracts:
            for value in [c, *mutations(c)]:
                check({"op": "contract", "contract": value},
                      lambda v=value: rc.evaluate(v, HOST, CONTAINER)["contract"])
            for native in (False, True):
                for waiver in (False, True):
                    pairs = [(HOST, CONTAINER), ({}, {}), (None, CONTAINER), ([], CONTAINER), (HOST, None)]
                    for role in ("host", "container"):
                        for field in ("python_version", "librelane_version", "requires_python"):
                            for actual in (None, True, 1, 1.0, [], {}, "", "3.11", "03.11.1", "3.13.13rc1",
                                           "3.9.20", "3.10.0", "3.11.9", "3.12.0", "3.13.13", "3.14.0", "3.15.0",
                                           "9.9.9", ">=3.10", ">=3.10,<4"):
                                h, d = copy.deepcopy(HOST), copy.deepcopy(CONTAINER)
                                (h if role == "host" else d)[field] = actual
                                pairs.append((h, d))
                    for ready in (False, None, 1, "true", True):
                        h = copy.deepcopy(HOST)
                        h["tcl"]["ready"] = ready
                        pairs.append((h, CONTAINER))
                    pairs.extend((dict(HOST, tcl=tcl), CONTAINER) for tcl in (None, True, [], {}, "bad"))
                    for h, d in pairs:
                        for op, fn in (("evaluate", rc.evaluate), ("readiness", ro.evaluate_observations)):
                            check({"op": op, "contract": c, "host": h, "container": d, "native": native, "waiver": waiver},
                                  lambda fn=fn: fn(c, h, d, native=native, allow_python_mismatch=waiver))
                        if not native:
                            check({"op": "container", "contract": c, "container": d}, lambda: ro.evaluate_container(c, d))
        for host, base in ((False, CONTAINER), (True, HOST)):
            for value in [base, *mutations(base), None, [], dict(base, future="retained")]:
                raw = json.dumps(value)
                check({"op": "metadata", "raw": raw, "host": host}, lambda: ro.metadata(raw, host=host))
            for raw in ("NaN", "{} trailing", '{"x":1e999}', '{"x":"\\ud800"}', '{"x":1,"x":1}'):
                check({"op": "metadata", "raw": raw, "host": host}, lambda: ro.metadata(raw, host=host), strict=True)
        image = {"binding": "local-image-id", "declared_ref": rc.policy_from_requested(new)["implementation"]["dockerized"]["image_ref"],
                 "image_id": IMAGE_ID, "repo_digests": [], "platform": {"os": "linux", "architecture": "amd64"}}
        engine = {"name": "docker", "executable": "/selected/docker", "rootless": False, "server_version": "29.fixture"}
        observed = dict(CONTAINER, interpreter="python3", interpreter_flags=["-I", "-B"], image_identity=image, engine_identity=engine)
        native_observed = dict(HOST, interpreter="/literal/alias/bin/python", interpreter_flags=["-I", "-B"])
        def binding(v, native):
            return et.from_preflight({"runtime_contract": {"execution_mode": "native" if native else "dockerized",
                "observations": {"host" if native else "container": v}}}, native=native)
        for native, value in ((True, native_observed), (False, observed)):
            for v in [value, *mutations(value)]:
                # Transport's installed public boundary deliberately closes fields;
                # observational extras outside the extracted binding stay additive.
                expected = lambda: binding(v, native)
                try:
                    b = expected()
                    strict = any("unknown" in b.get(k, {}) for k in ("engine_identity", "image_identity"))
                    strict |= "unknown" in b.get("image_identity", {}).get("platform", {})
                except (ValueError, TypeError, AttributeError):
                    strict = False
                check({"op": "binding", "value": v, "native": native}, expected, strict=strict)
        b = binding(observed, False)
        info = {"SecurityOptions": [], "ServerVersion": "29.fixture"}
        for flags in (["-I", "-B"], ["-B"]):
            for section, values in (("inspection", [IMAGE, [], {}, None, [IMAGE[0], IMAGE[0]],
                                      *([v] for v in mutations(IMAGE[0]))]),
                                    ("info", [info, *mutations(info), None, []])):
                for value in values:
                    actual_info = value if section == "info" else info
                    inspection = value if section == "inspection" else IMAGE
                    def inspection_oracle():
                        metadata = dict(CONTAINER, metadata_error=None if "-I" in flags else "missing")
                        outputs = [json.dumps(actual_info), json.dumps(inspection), json.dumps(metadata), ""]
                        if flags == ["-B"]:
                            outputs.extend([json.dumps(CONTAINER), ""])
                        with mock.patch.object(ro.shutil, "which", return_value="/selected/docker"), \
                                mock.patch.object(ro, "output", side_effect=outputs):
                            o = ro.observe_container(image["declared_ref"])
                        return binding(o, False)
                    # Binding closes optional fields that Python validate leaves
                    # unconstrained; these deliberate additions fail here too.
                    strict = (type(inspection) is list and len(inspection) == 1 and
                              type(inspection[0]) is dict and "Variant" in inspection[0] and
                              inspection[0]["Variant"] is not None and type(inspection[0]["Variant"]) is not str)
                    check({"op": "docker_binding", "ref": image["declared_ref"], "executable": "/selected/docker",
                           "info": actual_info, "inspection": inspection,
                           "value": {"interpreter_flags": flags}}, inspection_oracle, strict=strict)
        for actual in (IMAGE_ID, IMAGE_ID + "\n", "sha256:" + "2"*64, image["declared_ref"], "",
                       "\u2003" + IMAGE_ID + "\u0085", "\x1c" + IMAGE_ID + "\u3000",
                       "\u200b" + IMAGE_ID):
            def image_oracle():
                with mock.patch.object(ro, "output", return_value=actual):
                    et.verify_image(b)
                return True
            check({"op": "image", "binding": b, "value": actual}, image_oracle)
        for rootless in (False, True):
            for optional in (None, "daemon"):
                bound = copy.deepcopy(b)
                bound["engine_identity"].update(rootless=rootless, daemon_id=optional, name_on_server=optional)
                info = {"SecurityOptions": ["name=rootless"] if rootless else [], "ServerVersion": "29.fixture",
                        "ID": optional, "Name": optional}
                for value in [info, *mutations(info), None, []]:
                    def engine_oracle():
                        with mock.patch.object(ro, "output", return_value=json.dumps(value)):
                            return et.verify_engine(bound)
                    check({"op": "engine", "binding": bound, "value": value}, engine_oracle)
        print(f"OCaml runtime: {counts[0]} accepted parity cases / {counts[1]} rejected cases")
    finally:
        p.stdin.close()
        p.wait(timeout=5)
        assert p.returncode == 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", type=Path)
    parser.add_argument("--installed", action="store_true")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    if not args.installed:
        sys.path.insert(0, str(repo / "flow"))
        verify(args.consumer.resolve(), Path(__file__).resolve().parent)
        return
    with tempfile.TemporaryDirectory(prefix="runtime-contract-", dir="/tmp/opencode") as temporary:
        root = Path(temporary)
        prefix = root / "prefix"
        subprocess.run(["dune", "install", "-j20", "--prefix", str(prefix)], cwd=repo, check=True, stdout=subprocess.DEVNULL)
        consumer = root / "consumer"
        consumer.mkdir()
        shutil.copyfile(repo / "test/runtime_contract_consumer.ml", consumer / "runtime_contract_consumer.ml")
        (consumer / "dune-project").write_text("(lang dune 3.17)\n(name installed_runtime_consumer)\n")
        (consumer / "dune").write_text("(executable (name runtime_contract_consumer) (libraries hardcaml_asic.execution))\n")
        env = dict(os.environ)
        env["OCAMLPATH"] = str(prefix / "lib") + (":" + env["OCAMLPATH"] if env.get("OCAMLPATH") else "")
        subprocess.run(["dune", "build", "-j20", "runtime_contract_consumer.exe"], cwd=consumer, env=env, check=True)
        fixtures = root / "fixtures"
        fixtures.mkdir()
        for file in ("test_runtime_contract.py", "test_runtime_observation.py"):
            shutil.copyfile(repo / "test" / file, fixtures / file)
        shutil.copyfile(repo / "toolchain.lock", fixtures / "toolchain.lock")
        sys.path.insert(0, str(prefix / "lib/hardcaml_asic/flow"))
        auditing = True
        def audit(event, values):
            if auditing and event == "open" and isinstance(values[0], (str, bytes, os.PathLike)):
                path = Path(os.fsdecode(values[0])).resolve()
                if path.is_relative_to(repo):
                    raise AssertionError("checkout read in installed runtime test: " + str(path))
            if event == "import" and str(values[0]).split(".")[0] in ("librelane", "tkinter", "_tkinter"):
                raise AssertionError("native runtime import in pure runtime test")
        sys.addaudithook(audit)
        try:
            verify(consumer / "_build/default/runtime_contract_consumer.exe", fixtures)
        finally:
            auditing = False
        print("fresh installed runtime consumer passed with checkout reads/native imports denied")

if __name__ == "__main__":
    main()
