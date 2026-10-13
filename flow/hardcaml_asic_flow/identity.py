"""What this installed command can honestly say about itself.

P6.4a packages the existing implementation; it does not implement P6.5's source
stamping. So the only fact here that is actually *evidence* is the package
version, and even that is a useful API label rather than proof of an exact
source revision. Everything P6.5 owns -- the full Git revision, clean/dirty
state, the source-inventory digest, and whether the linked OCaml library was
built from the same artifact as this CLI -- is reported as unknown, with a
`stamped: false` flag and a note saying why.

That distinction is the whole point of the module. A `--version` that printed a
revision it inferred from the package version, or claimed a library/executor
identity match it never checked, would be exactly the false provenance the
migration brief is trying to remove. Reporting `null` is not a placeholder to be
tidied away later; it is the correct answer until a stamp exists to read.

Nothing here runs Git, opam, Docker, a PDK probe, or the provisioner. `--version`
and `--help` must work on a host that has none of them.
"""

import json
from pathlib import Path

from . import paths


#: Bumped with the record formats, not with the package version. The runner,
#: collector, reporter and archiver all read and write `schema_version: 1`.
IDENTITY_SCHEMA = 1
SUPPORTED_RECORD_SCHEMAS = (1,)

#: Version declared in `dune-project`, mirrored here so the source tree and a
#: `-I`-isolated installed process answer identically without parsing build
#: metadata at runtime. `test/test_identity.py` asserts the two agree.
DECLARED_VERSION = "0.1.0"

#: Written by the Dune rule in `flow/dune` from `%{version:hardcaml_asic}`, so a
#: `dune subst` release build reports the substituted version rather than the
#: literal above. Absent in a plain source checkout.
VERSION_FILE = paths.DATA_DIR / "version.txt"

UNSTAMPED_NOTE = (
    "source-artifact identity is not implemented until P6.5: this build carries "
    "no stamp, so the revision, checkout state and source-inventory digest are "
    "unknown and the library/executor artifact match is unverified")


def package_version():
    """(version, where it came from).

    The generated file wins when present because it is the version Dune actually
    installed under; the declared literal is the source-tree answer.
    """
    try:
        text = VERSION_FILE.read_text().strip()
    except OSError:
        return DECLARED_VERSION, "source-tree-declaration"
    return (text, "installed-package-metadata") if text else (
        DECLARED_VERSION, "source-tree-declaration")


def source_identity():
    """The P6.5-owned facts, every one of them explicitly not yet established."""
    return {
        "stamped": False,
        "revision": None,
        "state": "unknown",
        "inventory_digest": None,
        "library_artifact_match": None,
        "note": UNSTAMPED_NOTE,
    }


def describe():
    version, version_source = package_version()
    return {
        "tool": "hardcaml-asic-flow",
        "identity_schema": IDENTITY_SCHEMA,
        "package_version": version,
        "package_version_source": version_source,
        "supported_record_schemas": list(SUPPORTED_RECORD_SCHEMAS),
        "cli_contract": {
            "version": 4,
            "default_output": "human",
            "json_option": "--json",
            "results_defaults": {
                "root": "<caller-cwd>/_flow_results",
                "operations": "<results-root>/operations",
                "runs": "<results-root>/runs",
                "stage_observations": "<resolved-workspace-parent>/observations",
            },
            "capabilities": {
                "json_commands": ["preflight", "run", "postcheck", "collect",
                                  "report", "execute", "archive", "stages", "checkpoint-inspect",
                                   "observation describe", "observation inspect", "observation read-updates", "observation watch",
                                  "finalize", "finalization-inspect"],
                "json_lines_commands": ["stages", "finalize", "observation watch"],
                "observation_watch": {"incremental": True, "interval_seconds": 0.5,
                                      "envelopes": ["updates", "status"], "records_flushed": True,
                                      "reconnect": "stream-id_and_after_together",
                                      "exit_codes": {"terminal": 0, "writer_lost_or_unknown": 3,
                                                     "query_error": 2, "reader_interrupt": 130}},
                "stage_observation_default": True,
                "stage_observation_schemas": {"write": 2, "read": [1, 2]},
                "producer_event_timestamps": True,
                "monotonic_elapsed_seconds": True,
                "stage_observation_opt_out": "--no-observation",
                "stage_terminal_error_event": "observation_terminal",
                "stage_json_records_flushed": True,
                "json_flag_placements": ["global", "command", "observation-query"],
                "verbose_diagnostics": "stderr",
                "runs_override": True,
                "preflight_explicit_output": "file-existing-parent",
                "collect_json_writes_results": True,
                "collect_stdout": "legacy-read-only-json",
                "archive_json_list": False,
                "provision_json": False,
            },
        },
        "source": source_identity(),
        "module_dir": str(paths.PACKAGE_DIR),
        "data_dir": str(paths.DATA_DIR),
        "toolchain_lock": str(paths.TOOLCHAIN_LOCK),
        "toolchain_lock_present": paths.TOOLCHAIN_LOCK.is_file(),
    }


def report(as_json=False, output=print):
    """`--version`, optionally `--json`. Exit status is always 0.

    An unknown development identity is a visible fact, not a failure: the caller
    asked what this build is, and "unstamped" is the answer.
    """
    described = describe()
    if as_json:
        output(json.dumps(described, indent=2, sort_keys=True))
        return 0
    output(f"hardcaml-asic-flow {described['package_version']} "
           f"(hardcaml_asic package version, {described['package_version_source']})")
    output(f"source identity   unstamped; revision unknown, "
           f"library artifact match unverified (P6.5)")
    output(f"record schemas    "
            f"{', '.join(str(v) for v in described['supported_record_schemas'])}")
    output("CLI contract      4; human output by default, --json for machine output")
    output(f"modules           {described['module_dir']}")
    output(f"runtime data      {described['data_dir']}")
    return 0
