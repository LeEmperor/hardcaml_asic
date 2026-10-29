"""Explicit macro-free coarse qualification. No native imports on read-only paths.

The implementation entry wraps ordinary Classic only to bound native STA threads.
The analysis entry runs a new Step over retained implementation inputs, never a
Flow prefix or a synthesized replacement for extracted timing.
"""
import inspect
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# Loaded from an explicitly retained sibling, also hash-bound by the provider.
import importlib.util
_spec = importlib.util.spec_from_file_location("pt7_retained_runtime", Path(__file__).with_name("timing_intent_runtime.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
require, load, write, digest, reference, copy = base.require, base.load, base.write, base.digest, base.reference, base.copy

# Closed execution protocol: OpenROAD runs this retained bootstrap, which gives
# the retained native odbpy layout import authority without ambient PYTHONPATH.
FILTER_DRIVER = '''import sys
sys.dont_write_bytecode = True
import runpy
from pathlib import Path
source = Path(__file__).resolve().parents[2] / "native-sources" / "odbpy" / "filter_unannotated.py"
sys.path.insert(0, str(source.parent))
runpy.run_path(str(source), run_name="__main__")
'''


def _bounded_sta_steps(steps, pre, mid, post):
    """Preserve normalized occurrence subclasses, bounding only dedicated STA.

    SequentialFlow normalizes repeated IDs with Step.with_id(), which creates
    subclasses before this hook. Exact-class replacement misses those occurrences.
    """
    def standalone(parent):
        class BoundedSTA(parent):
            id = parent.id

            def get_command(self):
                command = list(super().get_command())
                require(command[0] == "sta" and "-threads" not in command,
                        "unsupported native STA command")
                return [command[0], "-threads", "1", *command[1:]]
        return BoundedSTA

    def middle(parent):
        class BoundedMidSTA(parent):
            id = parent.id

            def get_command(self):
                command = list(super().get_command())
                require(command.count("-threads") == 1, "unsupported native mid-PNR timing command")
                index = command.index("-threads") + 1
                require(index < len(command) and command[index] in ("1", "2", "3", "4", "5", "6"),
                        "unbounded native mid-PNR timing threads")
                command[index] = "1"
                return command
        return BoundedMidSTA

    return [standalone(cls) if issubclass(cls, (pre, post)) else middle(cls) if issubclass(cls, mid) else cls
            for cls in steps]


def implementation():
    from librelane.common import set_tpe
    from librelane.flows.classic import Classic
    from librelane.steps.openroad import STAPrePNR, STAPostPNR, STAMidPNR
    set_tpe(ThreadPoolExecutor(max_workers=6))
    Classic.Steps = _bounded_sta_steps(Classic.Steps, STAPrePNR, STAMidPNR, STAPostPNR)
    sys.argv = [sys.argv[0], *sys.argv[2:]]
    runpy.run_module("librelane", run_name="__main__")


def corners(config):
    values = config["STA_CORNERS"]
    require(isinstance(values, list) and 0 < len(values) <= 64 and
            len(set(values)) == len(values) and all(isinstance(c, str) and c and
            Path(c).name == c and c not in (".", "..") for c in values), "invalid configured corners")
    return values


def ordinal(config_path):
    token = Path(config_path).parent.name.split("-", 1)[0]
    require(token.isdigit() and int(token) > 0, "invalid native producer ordinal")
    return int(token)


def state_views(root, state_path, physical=False, linked=False):
    """Close every claimed non-metric view, including inherited stage views."""
    state = load(state_path)
    require(isinstance(state.get("nl"), str), "required native State netlist missing")
    if physical:
        require(isinstance(state.get("odb"), str), "required physical State ODB missing")
    result = []

    def visit(value):
        if value is None:
            return
        if isinstance(value, dict):
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
        else:
            require(isinstance(value, str), "unsupported State view locator")
            path = Path(value)
            require(path.is_absolute() and (path.is_relative_to(root / "project") or
                    (linked and path.is_relative_to(root / "timing-intent/corners"))), "State view outside retained execution")
            result.append(reference(root, path))

    for key, value in state.items():
        if key != "metrics":
            visit(value)
    return result


def select(root, physical):
    flow = root / "project/runs/asic"
    wanted = "OpenROAD.STAPostPNR" if physical else "Yosys.Synthesis"
    producers = []
    for directory in sorted(flow.iterdir()):
        config = directory / "config.json"
        if directory.is_dir() and config.is_file():
            data = load(config)
            if data.get("meta", {}).get("step") == wanted:
                producers.append(directory)
    require(len(producers) == 1, "missing/ambiguous exact implementation producer")
    producer = producers[0]
    require(load(producer / "config.json")["meta"]["librelane_version"] == "3.1.0.dev3", "unsupported producer version")
    state_path = producer / ("state_in.json" if physical else "state_out.json")
    state = load(state_path)
    require(Path(state["nl"]).is_relative_to(flow), "implementation netlist outside exact run")
    refs = {k: reference(root, p) for k, p in
            (("config", producer / "config.json"), ("state", state_path),
             ("netlist", Path(state["nl"])), ("resolved", flow / "resolved.json"))}
    refs["state_netlist"] = state["nl"]
    if physical:
        # A native Step is complete only after validated state_out AND runtime.
        require((producer / "runtime.txt").is_file(), "physical STA did not complete")
        original_output = load(producer / "state_out.json")
        require(all(original_output.get(key) == state.get(key) for key in ("nl", "odb", "spef")),
                "original STA changed implementation input views")
        refs["output_state"] = reference(root, producer / "state_out.json")
        refs["runtime"] = reference(root, producer / "runtime.txt")
        require(isinstance(state.get("spef"), dict) and state["spef"], "extracted SPEF input required")
    chain = []
    if physical:
        for cls in ("OpenROAD.GlobalPlacement", "OpenROAD.CTS", "OpenROAD.DetailedRouting", "OpenROAD.RCX"):
            matches = [p for p in flow.iterdir() if (p / "config.json").is_file() and
                       load(p / "config.json").get("meta", {}).get("step") == cls]
            require(len(matches) == 1, "missing/ambiguous physical chain producer: " + cls)
            p = matches[0]
            chain.append(dict(class_id=cls, **{k: reference(root, p / name) for k, name in
                         (("config", "config.json"), ("input_state", "state_in.json"),
                          ("output_state", "state_out.json"), ("runtime", "runtime.txt"))}))
        rcx = load(root / chain[-1]["output_state"]["path"])
        require(rcx["spef"] == state["spef"] and rcx["nl"] == state["nl"] and
                rcx.get("odb") is not None and rcx["odb"] == state.get("odb"), "RCX/physical STA nl/SPEF/ODB input mismatch")
        require(all(Path(p).is_relative_to(flow) for p in state["spef"].values()), "SPEF outside exact implementation run")
    return refs, state_path, chain


def hook(manifest, physical):
    lines = ["set endpoints [::hc_pt7::checked_endpoints]",
             "source [file join $::env(PT7_AUDIT_DIR) native-producer.tcl]",
             "::hc_pt7_native::write $::env(PT7_AUDIT_DIR)"]
    for mode in ("min", "max"):
        filename = "downstream_" + mode + ".rpt"
        lines += [f'set f [open [file join $::env(PT7_AUDIT_DIR) {filename}] w]',
                  'puts $f "Bounded checked-map downstream timing witnesses"', "close $f"]
        for stage in manifest["timing_intent"]["stages"]:
            if stage["index"] == 0:
                continue
            previous = [s for s in manifest["timing_intent"]["stages"] if
                        s["chain"] == stage["chain"] and s["index"] == stage["index"] - 1]
            require(len(previous) == 1, "invalid checked-map chain")
            lines += ['set q [dict get $endpoints ' + base.tcl_word(previous[0]["id"]) + ' q]',
                      'set d [dict get $endpoints ' + base.tcl_word(stage["id"]) + ' data]',
                      f'report_checks -from $q -to $d -path_delay {mode} -format full_clock_expanded -digits 6 >> [file join $::env(PT7_AUDIT_DIR) {filename}]']
    if physical:
        lines += ['report_parasitic_annotation -report_unannotated > [file join $::env(PT7_AUDIT_DIR) parasitic-annotation.rpt]',
                  'set f [open [file join $::env(PT7_AUDIT_DIR) clock-state.json] w]',
                  'set propagated 1; set names {}',
                  'foreach clock [sta::all_clocks] {',
                  '  if {![get_property $clock is_propagated]} { set propagated 0 }',
                  '  lappend names [::hc_pt7::json_string [get_full_name $clock]]',
                  '}',
                  'if {[llength $names] == 0} { error "no native clocks" }',
                  r'puts $f "{\"schema\":1,\"all_propagated\":$propagated,\"clocks\":\[[join $names ,]\]}"',
                  'close $f']
    return "\n".join(lines) + "\n"


def execute(request_path):
    request = load(request_path)
    root = Path(request["execution_root"])
    out = root / "timing-intent"
    require(request_path.resolve() == out / "request.json", "wrong analysis request root")
    manifest = load(root / "project/manifest.json")
    require(request["manifest_sha256"] == digest(root / "project/manifest.json") and
            request["build_identity"] == manifest["identity"], "request/build mismatch")
    require(manifest.get("timing_physical_qualification", {}).get("analysis_corners") == "all_configured" and
            not manifest.get("macro_contract"), "explicit macro-free physical timing contract required")
    physical = request["stage"] == "post_pnr"
    require(physical or request["stage"] == "synthesized_netlist", "unsupported analysis stage")
    refs, state_path, chain = select(root, physical)
    resolved = load(root / refs["resolved"]["path"])
    requested = corners(resolved)
    originating_synthesis = base.select_synthesis(root)[0] if physical else refs
    if physical:
        order = [ordinal(root / originating_synthesis["config"]["path"])] + [ordinal(root / r["config"]["path"]) for r in chain] + [ordinal(root / refs["config"]["path"])]
        require(all(a < b for a, b in zip(order, order[1:])), "noncausal synthesis/placement/CTS/routing/RCX/STA producer order")
    producer_dirs = {root / refs["config"]["path"]}
    producer_dirs.add(root / originating_synthesis["config"]["path"])
    producer_dirs.update(root / row["config"]["path"] for row in chain)
    producer_files = []
    for config_path in sorted(producer_dirs):
        for source in sorted(config_path.parent.rglob("*")):
            if source.is_file():
                producer_files.append(reference(root, source))
                require(len(producer_files) <= 384, "implementation producer source count bound")
    states = [(root / originating_synthesis["state"]["path"], False), (state_path, physical)]
    if physical:
        states += [(root / refs["output_state"]["path"], True)]
        states += [(root / row[key]["path"], True) for row in chain for key in ("input_state", "output_state")]
    if physical:
        for path, needs_odb in states:
            producer_files += state_views(root, path, physical=needs_odb)
    producer_files = list({r["path"]: r for r in producer_files}.values())
    require(len(producer_files) <= 384, "implementation State view source count bound")
    write(out / "input-selection.json", dict(schema=2, stage=request["stage"], implementation=refs,
          originating_synthesis=originating_synthesis, retained_producer_files=producer_files,
          physical_chain=chain, configured_corners=requested))
    require(not resolved.get("EXTRA_LIBS") and not resolved.get("EXTRA_VERILOG_MODELS") and
            not resolved.get("EXTRA_SPEFS"), "extra models outside bounded macro-free route")
    sdc_key = "SIGNOFF_SDC_FILE" if physical else "PNR_SDC_FILE"
    require(resolved[sdc_key] == str(root / "project/constraints/top.sdc"), "analysis SDC differs from emitted SDC")
    from librelane.steps.openroad import STAPrePNR, STAPostPNR
    from librelane.common import Toolbox, set_tpe, get_script_dir
    from librelane.steps.tclstep import TclStep
    set_tpe(ThreadPoolExecutor(max_workers=1))
    parent = STAPostPNR if physical else STAPrePNR
    effective = dict(resolved)
    effective.update(STA_CORNERS=requested, STA_THREADS=1, OPENROAD_THREADS=1,
                     STA_EXTRA_CORNER_TCL_FILE=str(out / "hook.tcl"))
    keys = {v.name for v in parent.get_all_config_variables()}
    effective = {k: v for k, v in effective.items() if k in keys or k == "meta"}
    effective["meta"] = dict(step=parent.id, librelane_version="3.1.0.dev3")
    write(out / "effective-config.json", effective)
    write(out / "configuration-delta.json", {k: dict(requested=resolved.get(k), effective=effective[k])
          for k in ("STA_CORNERS", "STA_THREADS", "OPENROAD_THREADS", "STA_EXTRA_CORNER_TCL_FILE")})
    (out / "hook.tcl").write_text(hook(manifest, physical))
    (out / "driver.tcl").write_text(base.DRIVER)
    # Retain native Tcl dependencies, in addition to immutable-image association.
    scripts = Path(get_script_dir())
    closure = out / "native-sources"
    closure.mkdir()
    for source in sorted((scripts / "openroad/common").glob("*.tcl")):
        copy(source, closure / source.name)
    odbpy = closure / "odbpy"
    odbpy.mkdir()
    dependencies = sorted((scripts / "odbpy").glob("*.py"))
    require(0 < len(dependencies) <= 128, "native odbpy dependency bound")
    for source in dependencies:
        copy(source, odbpy / source.name)
    (closure / "step-classes.py").write_text("\n\n".join(inspect.getsource(cls) for cls in parent.__mro__ if cls.__module__.startswith("librelane.")))
    audits = []

    class LinkedSTA(parent):
        id = parent.id

        def run(self, state_in, **kwargs):
            selections = []
            for corner in requested:
                _, files = self._get_corner_files(corner, prioritize_nl=self.config["STA_MACRO_PRIORITIZE_NL"])
                selections.append(dict(corner=corner, libs=list(files.libs), netlists=list(files.netlists),
                    spefs=list(files.spefs), extra_spefs_backcompat=files.extra_spefs_backcompat,
                    current_corner_spef=files.current_corner_spef))
            write(out / "corner-selections.json", selections)
            # Native MultiCornerSTA schedules futures before awaiting them. Drain
            # its one-worker executor even when an earlier future fails, so the
            # final retained progress cannot race later native corner processes.
            import librelane.steps.openroad as native
            previous = getattr(native, "ThreadPoolExecutor", ThreadPoolExecutor)
            executors = []

            def serial_executor(*args, **kw):
                workers = kw.get("max_workers", args[0] if args else None)
                require(workers == 1, "native STA executor exceeded one worker")
                executor = ThreadPoolExecutor(max_workers=1)
                executors.append(executor)
                return executor

            native.ThreadPoolExecutor = serial_executor
            try:
                return super().run(state_in, **kwargs)
            finally:
                try:
                    for executor in executors:
                        executor.shutdown(wait=True)
                finally:
                    native.ThreadPoolExecutor = previous

        def get_script_path(self):
            return str(out / "driver.tcl")

        def get_command(self):
            return ["sta", "-threads", "1", "-no_splash", "-exit", self.get_script_path()]

        def run_subprocess(self, command, *args, **kwargs):
            """Retain actual STA and annotation-filter processes independently."""
            directory = Path(kwargs["report_dir"])
            command = list(map(str, command))
            if command[0] != "sta":
                require(physical and "-python" in command and "-threads" not in command,
                        "unexpected nested analysis command")
                command[1:1] = ["-threads", "1"]
                # Execute only the retained bootstrap and dependency layout.
                script = Path(command[command.index("-python") + 1])
                require(script == scripts / "odbpy/filter_unannotated.py" and
                        digest(script) == digest(odbpy / "filter_unannotated.py"), "unexpected image annotation filter source")
                driver = directory / "filter-driver.py"
                driver.write_text(FILTER_DRIVER)
                command[command.index("-python") + 1] = str(driver)
                checks = Path(command[command.index("--checks-report") + 1])
                require(checks == directory / "checks.rpt", "unexpected actual annotation checks report")
                checks_ref = reference(root, checks)
                lef_index = 0
                filter_inputs = []
                for i in range(1, len(command)):
                    if command[i - 1] == "--input-lef" or command[i].endswith(".odb"):
                        source = Path(command[i])
                        name = f"filter-lef-{lef_index}.lef" if command[i - 1] == "--input-lef" else "filter-input.odb"
                        target = directory / name
                        copy(source, target)
                        filter_inputs.append(dict(original_path=str(source), actual_path=str(target),
                                             retained=reference(root, target), bytes=target.stat().st_size))
                        command[i] = str(target)
                        lef_index += 1
                write(directory / "filter-inputs.json", dict(driver_profile="retained_odbpy_v1", script_path=str(driver),
                      script=reference(root, driver), filter_source=reference(root, odbpy / "filter_unannotated.py"),
                      dependencies=[reference(root, odbpy / p.name) for p in dependencies],
                      checks_report=checks_ref, inputs=filter_inputs))
            serial = self._process_serial.get(str(directory), 0)
            self._process_serial[str(directory)] = serial + 1
            code = None
            try:
                result = super().run_subprocess(command, *args, **kwargs)
                code = 0
                return result
            except subprocess.CalledProcessError as exc:
                code = exc.returncode
                raise
            finally:
                write(directory / f"native-process-{serial}.json", dict(argv=command, exit_code=code))

        def run_corner(self, state_in, current_env, actual_corner, corner_dir):
            require(actual_corner in requested and actual_corner not in [a["corner"] for a in audits], "unexpected/duplicate actual corner")
            directory = Path(corner_dir)
            _, files = self._get_corner_files(actual_corner, prioritize_nl=self.config["STA_MACRO_PRIORITIZE_NL"])
            require(not files.netlists and not files.spefs and not files.extra_spefs_backcompat,
                    "hierarchical analysis outside bounded route")
            require(bool(files.current_corner_spef) == physical, "wrong stage parasitic input")
            inputs, associations = [], []

            def retain(role, source, name):
                source = Path(source)
                target = directory / name
                copy(source, target)
                inputs.append(dict(role=role, path=name, sha256=digest(target)))
                associations.append(dict(role=role, original_path=str(source),
                     actual_path=str(target), retained=reference(root, target), bytes=target.stat().st_size))

            retain("manifest", root / "project/manifest.json", "manifest.json")
            retain("sdc", root / "project/constraints/top.sdc", "top.sdc")
            retain("netlist", root / refs["netlist"]["path"], "mapped.v")
            for i, library in enumerate(files.libs):
                retain("liberty", library, f"library-{i}.lib")
            require(bool(files.libs), "no actual native libraries")
            retain("driver", out / "driver.tcl", "driver.tcl")
            retain("native_producer", root / "project" / base.PRODUCER, "native-producer.tcl")
            if physical:
                require(files.current_corner_spef in load(state_path)["spef"].values(), "selected SPEF not in exact input State")
                retain("spef", files.current_corner_spef, "extracted.spef")
                current_env["_CURRENT_SPEF_BY_CORNER"] = str(directory / "extracted.spef")
            version = subprocess.run(["sta", "-version"], text=True, capture_output=True, timeout=20, check=True)
            require(version.stdout.strip() == "2.7.0" and not version.stderr.strip(), "unsupported actual native version")
            (directory / "producer-version.txt").write_text(version.stdout)
            write(directory / "version-process.json", dict(argv=["sta", "-version"], exit_code=0, stderr=version.stderr,
                  stdout_sha256=digest(directory / "producer-version.txt")))
            producer = dict(tool="OpenSTA", version="2.7.0")
            write(directory / "receipt.json", dict(schema=1, build_identity=request["build_identity"],
                  audit_id=request["analysis_id"], stage=request["stage"], producer=producer, corner=actual_corner, inputs=inputs))
            retain_script = directory / "librelane-corner.tcl"
            copy(Path(parent.get_script_path(self)), retain_script)
            current_env.update(PT7_RECEIPT=str(directory / "receipt.json"), PT7_CORNER_SCRIPT=str(retain_script),
                               PT7_AUDIT_DIR=str(directory), _CURRENT_CORNER_NAME=actual_corner,
                               CURRENT_NL=str(directory / "mapped.v"), _SDC_IN=str(directory / "top.sdc"),
                                _CURRENT_CORNER_LIBS=TclStep.value_to_tcl(tuple(str(directory / f"library-{i}.lib") for i in range(len(files.libs)))))
            current_env["STA_EXTRA_CORNER_TCL_FILE"] = str(out / "hook.tcl")
            current_env["_EXTRA_CORNER_TCL_FILE"] = str(out / "hook.tcl")
            write(directory / "native-inputs.json", dict(associations=associations, corner_script=reference(root, retain_script),
                  environment={k: str(v) for k, v in current_env.items() if k in
                    ("CURRENT_NL", "_SDC_IN", "_CURRENT_CORNER_LIBS", "_CURRENT_SPEF_BY_CORNER", "OPENLANE_SDC_IDEAL_CLOCKS",
                      "_CURRENT_CORNER_NAME", "PT7_RECEIPT", "PT7_CORNER_SCRIPT", "PT7_AUDIT_DIR", "STA_EXTRA_CORNER_TCL_FILE", "_EXTRA_CORNER_TCL_FILE")}))
            exit_code = None
            try:
                result = super().run_corner(state_in, current_env, actual_corner, corner_dir)
                exit_code = 0
            except subprocess.CalledProcessError as exc:
                exit_code = exc.returncode
                raise
            finally:
                write(directory / "process-result.json", dict(schema=1, receipt_sha256=digest(directory / "receipt.json"),
                      exit_code=exit_code, argv=self.get_command()))
            raw = (directory / "sta.log").read_text()
            (directory / "resolution.jsonl").write_text("".join(line + "\n" for line in raw.splitlines() if line.startswith("HC_ASIC_TIMING_V1\t")))
            copy(directory / "native-state.sdc", directory / "exceptions.rpt")
            copy(directory / "native-checks.rpt", directory / "unconstrained.rpt")
            outputs = [("receipt", "receipt.json"), ("log", "sta.log"), ("resolution", "resolution.jsonl"),
                ("exceptions", "exceptions.rpt"), ("unconstrained", "unconstrained.rpt"),
                ("downstream_min", "downstream_min.rpt"), ("downstream_max", "downstream_max.rpt"),
                ("process_result", "process-result.json"), ("producer_version", "producer-version.txt"),
                ("native_sdc", "native-state.sdc"), ("native_data", "native-data.json"),
                ("native_checks", "native-checks.rpt"), ("native_endpoints", "native-endpoints.rpt")]
            if physical:
                outputs += [("parasitic_annotation", "parasitic-annotation.rpt"), ("clock_state", "clock-state.json")]
            sources = inputs + [dict(role=role, path=name, sha256=digest(directory / name)) for role, name in outputs]
            write(directory / "audit.json", dict(schema=3 if physical else 2, kind="hardcaml-asic.timing-intent-audit",
                  scope="standalone_extracted_netlist_sta" if physical else "standalone_synthesized_netlist_sta",
                  build_identity=request["build_identity"], audit_id=request["analysis_id"], stage=request["stage"],
                  producer=producer, corner=actual_corner, sources=sources))
            audits.append(dict(corner=actual_corner, audit=reference(root, directory / "audit.json")))
            return result

    step = LinkedSTA.load(config=str(out / "effective-config.json"), state_in=str(state_path), pdk_root=request["pdk_root"])
    step._process_serial = {}
    step_completed = False
    try:
        step.start(toolbox=Toolbox(str(out / "toolbox")), step_dir=str(out / "corners"))
        step_completed = True
    finally:
        observations = []
        selections = load(out / "corner-selections.json") if (out / "corner-selections.json").exists() else []
        equivalents = []
        for corner in requested:
            process = out / "corners" / corner / "native-process-0.json"
            record = load(process) if process.exists() else None
            observations.append(dict(corner=corner, process=reference(root, process) if record is not None else None,
                 exit_code=record["exit_code"] if record is not None else None,
                 audit=next((a["audit"] for a in audits if a["corner"] == corner), None)))
        executed = [row["corner"] for row in observations if row["exit_code"] is not None]
        for selection in selections:
            if selection["corner"] in executed:
                continue
            inputs = {k: v for k, v in selection.items() if k != "corner"}
            equivalent = next((s["corner"] for s in selections if s["corner"] in executed and
                              {k: v for k, v in s.items() if k != "corner"} == inputs), None)
            if equivalent is not None:
                equivalents.append(dict(corner=selection["corner"], equivalent_to=equivalent, inputs=inputs))
        write(out / "corner-progress.json", dict(schema=2, stage=request["stage"], configured_corners=requested,
              requested_corners=requested, executed_corners=executed, equivalent_corners=equivalents,
              not_observed_corners=[c for c in requested if c not in executed],
              step_completed=step_completed, observations=observations))
    require(set(a["corner"] for a in audits) == set(requested), "required configured corner was not actually executed (missing/equivalent)")
    if physical:
        state_views(root, out / "corners/state_in.json", physical=True, linked=True)
        state_views(root, out / "corners/state_out.json", physical=True, linked=True)
    write(out / "runtime-result.json", dict(schema=2, status="completed", run_id=request["run_id"],
          build_identity=request["build_identity"], analysis_id=request["analysis_id"], stage=request["stage"],
          implementation=refs, physical_chain=chain, effective_config=reference(root, out / "effective-config.json"),
          originating_synthesis=originating_synthesis, retained_producer_files=producer_files,
          configured_corners=requested, requested_corners=requested, executed_corners=[a["corner"] for a in audits],
          equivalent_corners=[], audits=audits))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "implementation":
        implementation()
    else:
        require(len(sys.argv) == 2, "one immutable request required")
        execute(Path(sys.argv[1]))
