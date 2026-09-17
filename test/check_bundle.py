"""Integration check for deterministic TT bundles, using only a temporary Git repo."""

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)


def manifest(directory):
    result = json.loads((directory / "manifest.json").read_text())
    for entry in result["files"]:
        path = directory / entry["path"]
        assert path.is_file(), path
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], path
    for entry in result["source_inputs"]:
        assert (directory / entry["copy"]).is_file(), entry
    return result


def simulate(directory, kind, bench):
    if not shutil.which("iverilog") or not shutil.which("vvp"):
        print("Icarus unavailable: generated RTL simulation skipped")
        return
    for source_set in ("synthesis_sources", "simulation_sources"):
        rtl = [str(directory / path) for path in manifest(directory)[source_set]]
        output = directory / (source_set + ".out")
        run("iverilog", "-g2012", "-s", "tb_" + kind, "-o", str(output),
            str(bench), *rtl)
        run("vvp", str(output))


def toolchain_lock(source_root, requested):
    """Assert toolchain.lock still agrees with the pins the bundle was built from.

    scripts/toolchain.sh provisions the flow before anything in this repository can be
    built, so it is plain shell and cannot ask the library what to fetch; it reads
    toolchain.lock instead. That makes the lockfile a second place each revision is
    written down. This check is the only thing keeping it honest: "requested_tools" comes
    straight from lib/target.ml and lib/bundle.ml, so a pin changed in one place and not
    the other fails here, naming both values.

    The repository and branch entries have no counterpart in a manifest and are not
    checked. A bundle pins revisions, not where to fetch them from, on purpose.
    """
    pins = {}
    for line in (source_root / "toolchain.lock").read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            pins[key] = value
    for lock_key, manifest_key in (("support_tools_revision", "support_tools_revision"),
                                   ("pdk_revision", "pdk_revision"),
                                   ("librelane_version", "librelane"),
                                   ("python", "python")):
        assert pins[lock_key] == requested[manifest_key], (
            "toolchain.lock %s=%s, manifest requested_tools %s=%s; the lockfile is a copy "
            "of lib/, update it" %
            (lock_key, pins[lock_key], manifest_key, requested[manifest_key]))
    return pins


def main(executable, source_root):
    with tempfile.TemporaryDirectory(prefix="asic-bundle-test-") as temp:
        base = pathlib.Path(temp)
        source = base / "source"
        source.mkdir()
        for name in ("lib", "examples"):
            shutil.copytree(source_root / name, source / name)
        shutil.copy2(source_root / "dune-project", source / "dune-project")
        for path in source.rglob("*"):
            if path.is_file():
                path.chmod(path.stat().st_mode | 0o200)
        run("git", "init", "-q", str(source))
        run("git", "add", ".", cwd=source)
        run("git", "-c", "user.name=Bundle test", "-c",
            "user.email=bundle@test.invalid", "commit", "-qm", "baseline", cwd=source)

        def emit(kind, label):
            output = base / label
            run(str(executable), kind, str(output), str(source))
            return output, manifest(output)

        obs, obs_manifest = emit("observable", "observable")
        mem, mem_manifest = emit("memory", "memory")
        mem_repeat, repeat_manifest = emit("memory", "memory-repeat")
        assert (mem / "manifest.json").read_bytes() == (mem_repeat / "manifest.json").read_bytes()
        assert mem_manifest["identity"] == repeat_manifest["identity"]
        assert mem_manifest["source_revision"] == obs_manifest["source_revision"]
        pins = toolchain_lock(source_root, obs_manifest["requested_tools"])
        assert pins["pdk"] == obs_manifest["target"]["technology"]
        assert obs_manifest["requested_tools"] == mem_manifest["requested_tools"]

        for directory, data, kind in ((obs, obs_manifest, "observable"),
                                      (mem, mem_manifest, "memory")):
            config = json.loads((directory / "src/config.json").read_text())
            top = data["top_module"]
            assert config["DESIGN_NAME"] == top
            assert config["VERILOG_FILES"] == ["dir::" + top + ".v"]
            assert config["PNR_SDC_FILE"] == "dir::../constraints/top.sdc"
            assert config["SIGNOFF_SDC_FILE"] == config["PNR_SDC_FILE"]
            assert config["CLOCK_PORT"] == "clk"
            assert abs(config["CLOCK_PERIOD"] - 1e9 / 48e6) < 1e-9
            assert config["DIE_AREA"] == "0 0 1289.28 710.64"
            info = (directory / "info.yaml").read_text()
            assert 'top_module: "' + top + '"' in info
            assert '    - "' + top + '.v"' in info
            assert "clock_hz: 48000000" in info
            sdc = (directory / "constraints/top.sdc").read_text()
            assert ("create_clock -name clk -period " +
                    format(config["CLOCK_PERIOD"], ".17g")) in sdc
            # The constraint environment: without these the flow analyses an input path
            # with no slew, no variation margin and no uncertainty, so hold looks met and
            # the post-CTS resizer repairs nothing. LibreLane's base.sdc would have
            # applied them, but PNR_SDC_FILE stops it from running at all.
            assert ("set_clock_uncertainty " +
                    format(config["CLOCK_UNCERTAINTY_CONSTRAINT"], ".17g") +
                    " [get_clocks {clk}]") in sdc
            assert ("set_clock_transition " +
                    format(config["CLOCK_TRANSITION_CONSTRAINT"], ".17g") +
                    " [get_clocks {clk}]") in sdc
            derate = config["TIME_DERATING_CONSTRAINT"] / 100.0
            assert ("set_timing_derate -early " + format(1 - derate, ".17g")) in sdc
            assert ("set_timing_derate -late " + format(1 + derate, ".17g")) in sdc
            assert ("set_max_fanout %d [current_design]" %
                    config["MAX_FANOUT_CONSTRAINT"]) in sdc
            cell, pin = config["SYNTH_DRIVING_CELL"].split("/")
            drive = "set_driving_cell -lib_cell %s -pin %s [get_ports " % (cell, pin)
            assert (drive + "{ena rst_n ui_in uio_in}]") in sdc
            assert (drive + "{clk}]") in sdc
            # set_load is read in the Liberty capacitive_load_unit (pF); OUTPUT_CAP_LOAD
            # is in fF, the same conversion base.sdc does.
            assert ("set_load " + format(config["OUTPUT_CAP_LOAD"] / 1000.0, ".17g") +
                    " [get_ports {uio_oe uio_out uo_out}]") in sdc
            # LibreLane's read_current_sdc greps for these and picks ideal clocks pre-CTS
            # and propagated clocks afterwards when it finds neither.
            assert "propagated_clock" not in sdc
            # Every key the SDC now owns must be unreachable by a raw override.
            for key in ("CLOCK_UNCERTAINTY_CONSTRAINT", "CLOCK_TRANSITION_CONSTRAINT",
                        "TIME_DERATING_CONSTRAINT", "SYNTH_DRIVING_CELL",
                        "OUTPUT_CAP_LOAD", "MAX_FANOUT_CONSTRAINT"):
                owner = next(entry["owner"] for entry in data["resolved_settings"]
                             if entry["key"] == key)
                assert owner == "Target", (key, owner)
            if kind == "observable":
                for port in ("ena", "rst_n", "ui_in"):
                    assert ("set_input_delay -max 1 -clock clk [get_ports {" +
                            port + "}]") in sdc
                    assert ("set_input_delay -min 0 -clock clk [get_ports {" +
                            port + "}]") in sdc
                assert "set_output_delay -max 2 -clock clk [get_ports {uo_out}]" in sdc
                assert "set_output_delay -min 0 -clock clk [get_ports {uo_out}]" in sdc
            synth = data["synthesis_sources"]
            sim = data["simulation_sources"]
            assert len(synth) == len(sim) == 1 and synth != sim
            assert data["flow_configuration"] == config
            assert "initial begin" not in (directory / synth[0]).read_text()
            references = data["target"]["external_references"]
            assert len(references) == 7
            assert references[0]["sha256"] == (
                "b46d9a0ee8352160e48dbc8312f092f985629061df736c7f46d58686535a76f4")
            assert all(len(ref["revision"]) == 40 and ".." not in ref["path"]
                       for ref in references)
            simulate(directory, kind, source_root / "test/tt_bundle_tb.v")

        assert len(mem_manifest["resources"]) == 1
        assert "Explicit_flops" in mem_manifest["resources"][0]["selection"]
        assert "Generated_synthesis_rtl" in mem_manifest["resources"][0]["source_roles"]
        assert obs_manifest["resources"] == []

        with (source / "lib/build.ml").open("a") as stream:
            stream.write("\n(* provenance change *)\n")
        _, changed = emit("memory", "memory-dirty")
        assert changed["identity"] != mem_manifest["identity"]
        assert any(entry["path"] == "lib/build.ml" and entry["git_status"].startswith(" M")
                   for entry in changed["source_inputs"])

        (source / "lib/untracked_probe.ml").write_text("(* new source input *)\n")
        _, untracked = emit("memory", "memory-untracked")
        assert untracked["identity"] != changed["identity"]
        assert any(entry["path"] == "lib/untracked_probe.ml" and
                   entry["git_status"].startswith("??")
                   for entry in untracked["source_inputs"])

        (source / "dune-project").unlink()
        missing = subprocess.run((str(executable), "memory", str(base / "missing"),
                                  str(source)), capture_output=True, text=True)
        assert missing.returncode != 0
        assert "source input is missing" in missing.stderr
        print("bundle determinism, provenance, staging, hashes, RTL and "
              "toolchain.lock passed")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve())
