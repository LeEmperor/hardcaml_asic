"""Dedicated STA launch policy, including normalized/derived occurrence classes.

No Flow/Step is started and no native executable is run. Optional installed API
mode calls actual LibreLane get_command methods on inert command-only instances.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
from unittest.mock import patch


def helper(path):
    spec = importlib.util.spec_from_file_location("launch_policy_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def instance(cls, threads=6):
    value = object.__new__(cls)
    value.config = {"OPENROAD_THREADS": threads}
    value.step_dir = "/not-launched/" + cls.id
    return value


def check_family(runtime, steps, pre, mid, post):
    bounded = runtime._bounded_sta_steps(steps, pre, mid, post)
    rows = []
    assert len(bounded) == len(steps)
    for original, forward in zip(steps, bounded):
        before = original.get_command(instance(original))
        command = forward.get_command(instance(forward))
        assert original.id == forward.id
        assert original.get_implementation_id() == forward.get_implementation_id()
        if issubclass(original, (pre, mid, post)):
            assert issubclass(forward, original)
            assert command.count("-threads") == 1 and command[command.index("-threads") + 1] == "1", (original.id, command)
            if issubclass(original, mid):
                expected = list(before); expected[expected.index("-threads") + 1] = "1"
            else:
                expected = [before[0], "-threads", "1", *before[1:]]
            assert command == expected, (original.id, command, before)
        else:
            assert original is forward and before == command
        rows.append(dict(id=original.id, implementation_id=original.get_implementation_id(), before=before, forward=command))
    return bounded, rows


def model(runtime):
    class Step:
        @classmethod
        def get_implementation_id(cls):
            return getattr(cls, "_implementation_id", cls.id)

        @classmethod
        def with_id(cls, name):
            return type(cls.__name__, (cls,), dict(id=name, _implementation_id=cls.get_implementation_id()))

    class Pre(Step):
        id = "OpenROAD.STAPrePNR"
        def get_script_path(self): return "pre.tcl"
        def get_command(self): return ["sta", "-no_splash", "-exit", self.get_script_path()]
    class Post(Pre):
        id = "OpenROAD.STAPostPNR"
        def get_script_path(self): return "post.tcl"
    class Mid(Step):
        id = "OpenROAD.STAMidPNR"
        def get_script_path(self): return "mid.tcl"
        def get_command(self):
            return ["openroad", "-exit", "-threads", str(self.config["OPENROAD_THREADS"]), "-no_splash",
                    "-metrics", self.step_dir + "/metrics.json", self.get_script_path()]
    class Repair(Step):
        id = "OpenROAD.ResizerTimingPostCTS"
        def get_command(self): return ["openroad", "-threads", str(self.config["OPENROAD_THREADS"]), "postcts-repair.tcl"]
    class OtherRepair(Repair):
        id = "OpenROAD.ResizerTimingPostGRT"
    class MisleadingName(Repair):
        id = "OpenROAD.STAMidPNR-lookalike-not-a-subclass"

    class CustomizedMid(Mid.with_id("OpenROAD.STAMidPNR-9")):
        def get_script_path(self): return "qualified-alias-script.tcl"

    steps = [Pre, Pre.with_id(Pre.id + "-1"), Mid, *[Mid.with_id(Mid.id + "-" + str(n)) for n in (1, 2, 3)],
             CustomizedMid, Post, Post.with_id(Post.id + "-1"), Repair, OtherRepair, MisleadingName]
    bounded, rows = check_family(runtime, steps, Pre, Mid, Post)
    assert sum(issubclass(cls, Mid) for cls in steps) == 5
    # Aliases made after policy installation must inherit the bound command too.
    for cls in bounded[:10]:
        if issubclass(cls, (Pre, Mid, Post)):
            alias = cls.with_id(cls.id + "-later")
            assert alias.get_command(instance(alias))[alias.get_command(instance(alias)).index("-threads") + 1] == "1"
            assert alias.get_implementation_id() == cls.get_implementation_id()
    # Repeat a class before normalization, then apply the same with_id rule used
    # by SequentialFlow. Every resulting occurrence remains bounded.
    repeated = runtime._bounded_sta_steps([Mid, Mid, Mid, Mid], Pre, Mid, Post)
    normalized, used = [], set()
    for cls in repeated:
        name, counter = cls.get_implementation_id(), 0
        while name in used:
            counter += 1; name = cls.get_implementation_id() + "-" + str(counter)
        normalized.append(cls if cls.id == name else cls.with_id(name)); used.add(name)
    assert [cls.id for cls in normalized] == [Mid.id, Mid.id + "-1", Mid.id + "-2", Mid.id + "-3"]
    assert all(cls.get_command(instance(cls))[3] == "1" for cls in normalized)
    # Preserve fail-closed native command qualification for aliases as well.
    bad_commands = [[], ["openroad", "mid.tcl"], ["openroad", "-threads"],
                    ["openroad", "-threads", "20"], ["openroad", "-threads", "6", "-threads", "1"]]
    for command in bad_commands:
        class BadMid(Mid.with_id("OpenROAD.STAMidPNR-5")):
            def get_command(self): return list(command)
        wrapped = runtime._bounded_sta_steps([BadMid], Pre, Mid, Post)[0]
        try:
            wrapped.get_command(instance(wrapped))
            raise AssertionError("unqualified alias command accepted")
        except ValueError:
            pass
    for command in (["openroad", "-exit", "pre.tcl"], ["sta", "-threads", "20", "pre.tcl"]):
        class BadPre(Pre.with_id("OpenROAD.STAPrePNR-3")):
            def get_command(self): return list(command)
        wrapped = runtime._bounded_sta_steps([BadPre], Pre, Mid, Post)[0]
        try:
            wrapped.get_command(instance(wrapped))
            raise AssertionError("unqualified standalone alias command accepted")
        except ValueError:
            pass
    return dict(mode="modeled_native_command_policy", rows=rows, malformed_alias_commands_rejected=len(bad_commands) + 2,
                aliases_after_installation="pass", normalization_after_installation="pass")


def installed(runtime):
    import importlib.metadata
    from librelane.flows.classic import Classic
    from librelane.steps.openroad import STAPrePNR, STAMidPNR, STAPostPNR, ResizerTimingPostCTS, ResizerTimingPostGRT
    version = importlib.metadata.version("librelane")
    assert version == "3.1.0.dev3", version
    selected = [cls for cls in Classic.Steps if issubclass(cls, (STAPrePNR, STAMidPNR, STAPostPNR, ResizerTimingPostCTS, ResizerTimingPostGRT))]
    _, rows = check_family(runtime, selected, STAPrePNR, STAMidPNR, STAPostPNR)
    assert sum(issubclass(cls, STAMidPNR) for cls in selected) == 4
    for cls, row in zip(selected, rows):
        if issubclass(cls, (ResizerTimingPostCTS, ResizerTimingPostGRT)):
            assert row["forward"][row["forward"].index("-threads") + 1] == "6"
    return dict(mode="installed_librelane_API_command_construction_only", version=version, rows=rows,
                native_execution="none; no Flow.start, Step.start or subprocess")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--installed-librelane", action="store_true")
    args = parser.parse_args()
    runtime = helper(args.runtime)
    # Even an accidental native launcher call makes this non-EDA test fail.
    with patch.object(subprocess, "Popen", side_effect=AssertionError("native/process launch forbidden")), \
         patch.object(subprocess, "run", side_effect=AssertionError("native/process launch forbidden")):
        result = installed(runtime) if args.installed_librelane else model(runtime)
    result["runtime_sha256"] = hashlib.sha256(args.runtime.read_bytes()).hexdigest()
    result["qualification"] = "forward policy test only; not executed by the original captured provider"
    print(json.dumps(result, indent=2))
