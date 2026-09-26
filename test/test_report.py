"""Run summary fixtures; no PDK, container, or licensed tool is needed."""

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
# The modules under test are the ones Dune installs: `flow/hardcaml_asic_flow/`
# is put on the path and imported as a regular package, so these suites cover the
# installed implementation rather than a checkout-only copy of it.
PACKAGE_ROOT = Path(__file__).resolve().parents[1] / "flow"
sys.path.insert(0, str(PACKAGE_ROOT))
from hardcaml_asic_flow import report  # noqa: E402


def reporter(*arguments):
    """The reporter as a separate process, run exactly as it is installed.

    `-m hardcaml_asic_flow.report` rather than a path to a file: the module's
    package-relative imports are the ones an installed command uses, so running
    it any other way would test a loading mode nothing ships.
    """
    environment = dict(os.environ, PYTHONPATH=str(PACKAGE_ROOT),
                       PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run(
        [sys.executable, "-m", "hardcaml_asic_flow.report", *arguments],
        text=True, capture_output=True, check=False, env=environment)


def metric(value, corner=None):
    return {"value": value, "corner": corner, "unavailable_reason": None}


FULL_RESULTS = {
    "schema_version": 1,
    "run_id": "attempt-1",
    "build_identity": "build-1",
    "process_status": "completed",
    "requested_stage": "full",
    "completed_stage": "full",
    "timing_goal": "pass",
    "timing_unconstrained_modes": [],
    "metrics": {
        "mapped_area": metric(1319.031),
        "mapped_cells": metric(94.0),
        "setup_slack": metric(18.18, "nom_slow_1p08V_125C"),
        "hold_slack": metric(0.12, "nom_fast_1p32V_m40C"),
    },
    "checks": {
        "drc": {"status": "pass"},
        "lvs": {"status": "pass"},
        "antenna": {"status": "pass"},
    },
    "synthesis_checks": {
        "unmapped_instances": metric(0.0),
        "synthesis_errors": metric(0.0),
        "inferred_latches": metric(0.0),
    },
    "postchecks": [{
        "status": "completed",
        "checks": {"precheck": "pass", "gate_level": "pass"},
    }],
    "errors": [],
}


def synthesis_results():
    results = copy.deepcopy(FULL_RESULTS)
    results.update({
        "requested_stage": "synthesis",
        "completed_stage": "synthesis",
        "timing_goal": "unknown",
        "metrics": {
            "mapped_area": metric(349314.9408),
            "mapped_cells": metric(16294.0),
            "setup_slack": {"value": None, "corner": None,
                            "unavailable_reason": "report absent or metric missing"},
            "hold_slack": {"value": None, "corner": None,
                           "unavailable_reason": "report absent or metric missing"},
        },
        "checks": {
            "drc": {"status": "unknown", "reason": "metric missing"},
            "lvs": {"status": "unknown", "reason": "metric missing"},
            "antenna": {"status": "unknown", "reason": "metric missing"},
        },
        "postchecks": [],
    })
    return results


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        flow = self.root / "project/runs/asic"
        (flow / "final").mkdir(parents=True)
        # 1e39 is the sentinel STA writes when it found no hold path at all.
        (flow / "final/metrics.csv").write_text(
            "timing__setup__ws__corner:nom_typ_1p20V_25C,18.42\n"
            "timing__setup_vio__count__corner:nom_typ_1p20V_25C,0\n"
            "timing__hold__ws__corner:nom_typ_1p20V_25C,1.0000000433293989E+39\n"
            "timing__hold_vio__count__corner:nom_typ_1p20V_25C,0\n")
        resizer = flow / "37-openroad-resizertimingpostcts"
        resizer.mkdir()
        (resizer / "openroad-resizertimingpostcts.log").write_text(
            "+ repair_timing -verbose -hold -hold_margin 0.1\n"
            "[INFO RSZ-0033] No hold violations found.\n"
            "unrelated line\n")
        precheck = self.root / "checks/one/tt/precheck/reports"
        precheck.mkdir(parents=True)
        (precheck / "results.md").write_text(
            "| Check | Result |\n|-----|-----|\n| Pin check | OK |\n")

    def run_report(self, results, **record_changes):
        record = {
            "schema_version": 1,
            "run_id": results.get("run_id"),
            "build_identity": results.get("build_identity"),
            "bundle": "/bundle",
            "status": results.get("process_status"),
            "requested_stage": results.get("requested_stage"),
            "completed_stage": results.get("completed_stage"),
            "outputs": {"flow": "project/runs/asic"},
        }
        record.update(record_changes)
        (self.root / "run.json").write_text(json.dumps(record))
        (self.root / "results.json").write_text(json.dumps(results))
        return reporter(str(self.root))

    def test_completed_synthesis_passes_without_physical_results(self):
        completed = self.run_report(synthesis_results())
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("scope      synthesis-only acceptance", completed.stdout)
        self.assertIn("not evaluated / not required for requested synthesis operation",
                      completed.stdout)
        self.assertIn("synthesis acceptance passed", completed.stdout)
        self.assertNotIn("full-flow acceptance passed", completed.stdout)

    def test_missing_or_malformed_synthesis_evidence_fails(self):
        cases = []
        missing_metrics = synthesis_results()
        del missing_metrics["metrics"]
        cases.append(("missing metrics", missing_metrics, "metrics missing or malformed"))
        null_area = synthesis_results()
        null_area["metrics"]["mapped_area"]["value"] = None
        cases.append(("null area", null_area, "mapped_area missing or malformed"))
        malformed_cells = synthesis_results()
        malformed_cells["metrics"]["mapped_cells"]["value"] = "16294"
        cases.append(("malformed cells", malformed_cells, "mapped_cells missing or malformed"))
        nonfinite_area = synthesis_results()
        nonfinite_area["metrics"]["mapped_area"]["value"] = float("inf")
        cases.append(("nonfinite area", nonfinite_area, "mapped_area missing or malformed"))
        missing_checks = synthesis_results()
        del missing_checks["synthesis_checks"]
        cases.append(("missing checks", missing_checks,
                      "synthesis_checks missing or malformed"))
        null_check = synthesis_results()
        null_check["synthesis_checks"]["synthesis_errors"]["value"] = None
        cases.append(("null check", null_check, "synthesis_errors missing or malformed"))
        for name, results, diagnostic in cases:
            with self.subTest(name=name):
                completed = self.run_report(results)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(diagnostic, completed.stdout)

    def test_zero_mapped_area_and_cells_are_valid_evidence(self):
        results = synthesis_results()
        results["metrics"]["mapped_area"]["value"] = 0.0
        results["metrics"]["mapped_cells"]["value"] = 0.0
        completed = self.run_report(results)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_explicitly_unavailable_required_metrics_fail(self):
        cases = []
        mapped = synthesis_results()
        mapped["metrics"]["mapped_area"]["unavailable_reason"] = "report absent"
        cases.append(("mapped area", mapped, "mapped_area unavailable: report absent"))
        synthesis_check = synthesis_results()
        synthesis_check["synthesis_checks"]["synthesis_errors"][
            "unavailable_reason"] = "metric missing"
        cases.append(("synthesis check", synthesis_check,
                      "synthesis_errors unavailable: metric missing"))
        timing = copy.deepcopy(FULL_RESULTS)
        timing["metrics"]["setup_slack"]["unavailable_reason"] = "no constrained paths"
        cases.append(("timing", timing, "setup_slack unavailable: no constrained paths"))
        for name, results, diagnostic in cases:
            with self.subTest(name=name):
                completed = self.run_report(results)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(diagnostic, completed.stdout)

    def test_nonzero_synthesis_checks_fail(self):
        for name in ("unmapped_instances", "synthesis_errors", "inferred_latches"):
            with self.subTest(name=name):
                results = synthesis_results()
                results["synthesis_checks"][name]["value"] = 1.0
                completed = self.run_report(results)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(f"{name} = 1", completed.stdout)

    def test_collection_error_fails_synthesis(self):
        results = synthesis_results()
        results["errors"] = ["malformed mapped-area report"]
        completed = self.run_report(results)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("collection error: malformed mapped-area report", completed.stdout)

    def test_failed_or_interrupted_synthesis_fails(self):
        for status in ("failed", "interrupted"):
            with self.subTest(status=status):
                results = synthesis_results()
                results["process_status"] = status
                results["completed_stage"] = None
                completed = self.run_report(results)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn("process did not complete", completed.stdout)
                self.assertNotIn("synthesis acceptance passed", completed.stdout)

    def test_full_request_stopped_at_synthesis_fails(self):
        results = synthesis_results()
        results["requested_stage"] = "full"
        completed = self.run_report(results, requested_stage="full")
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("scope      full-flow acceptance", completed.stdout)
        self.assertIn("requested full but completed stage", completed.stdout)

    def test_contradictory_or_unknown_stage_fails(self):
        contradictory = synthesis_results()
        completed = self.run_report(contradictory, requested_stage="full")
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("contradictory requested_stage", completed.stdout)
        self.assertIn("scope      invalid/unknown", completed.stdout)

        unknown = synthesis_results()
        unknown["requested_stage"] = "routing"
        unknown["completed_stage"] = "routing"
        completed = self.run_report(unknown)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("unknown requested stage", completed.stdout)

    def test_clean_full_run_passes(self):
        completed = self.run_report(copy.deepcopy(FULL_RESULTS))
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("scope      full-flow acceptance", completed.stdout)
        self.assertIn("full-flow acceptance passed", completed.stdout)
        self.assertIn("Pin check", completed.stdout)
        self.assertIn("RSZ-0033", completed.stdout)
        self.assertNotIn("unrelated line", completed.stdout)
        # The 1e39 sentinel is not a slack; it prints as unavailable.
        self.assertIn("n/a", completed.stdout)
        self.assertIn("18.420", completed.stdout)

    def test_missing_or_failed_physical_evidence_fails(self):
        cases = []
        missing_check = copy.deepcopy(FULL_RESULTS)
        del missing_check["checks"]["lvs"]
        cases.append(("missing lvs", missing_check, "lvs missing"))
        failed_check = copy.deepcopy(FULL_RESULTS)
        failed_check["checks"]["drc"] = {"status": "fail"}
        cases.append(("failed drc", failed_check, "drc fail"))
        missing_postcheck = copy.deepcopy(FULL_RESULTS)
        missing_postcheck["postchecks"][0]["checks"].pop("gate_level")
        cases.append(("missing gate level", missing_postcheck, "gate_level missing"))
        no_postchecks = copy.deepcopy(FULL_RESULTS)
        no_postchecks["postchecks"] = []
        cases.append(("no postchecks", no_postchecks, "required postchecks missing"))
        for name, results, diagnostic in cases:
            with self.subTest(name=name):
                completed = self.run_report(results)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn(diagnostic, completed.stdout)

    def test_unconstrained_or_missing_timing_fails(self):
        unconstrained = copy.deepcopy(FULL_RESULTS)
        unconstrained["timing_unconstrained_modes"] = ["hold"]
        completed = self.run_report(unconstrained)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("UNCONSTRAINED: hold", completed.stdout)

        missing = copy.deepcopy(FULL_RESULTS)
        del missing["metrics"]["setup_slack"]
        completed = self.run_report(missing)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("setup_slack missing or malformed", completed.stdout)

        contradictory = copy.deepcopy(FULL_RESULTS)
        contradictory["metrics"]["hold_slack"]["value"] = -0.1
        completed = self.run_report(contradictory)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("hold_slack missing or malformed", completed.stdout)

    def test_timing_sentinel_cannot_pass_as_slack(self):
        results = copy.deepcopy(FULL_RESULTS)
        results["metrics"]["hold_slack"]["value"] = 1e39
        completed = self.run_report(results)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("hold_slack missing or malformed", completed.stdout)
        self.assertNotIn("full-flow acceptance passed", completed.stdout)

        synthesis = synthesis_results()
        synthesis["metrics"]["hold_slack"] = metric(
            1e39, "nom_fast_1p32V_m40C")
        completed = self.run_report(synthesis)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("synthesis acceptance passed", completed.stdout)

    def test_json_output_is_exact_record_and_keeps_acceptance_verdict(self):
        results = synthesis_results()
        self.run_report(results)
        completed = reporter(str(self.root), "--json")
        self.assertEqual(completed.returncode, 0)
        self.assertEqual(json.loads(completed.stdout), results)

        results["synthesis_checks"]["synthesis_errors"]["value"] = 1.0
        self.run_report(results)
        rejected = reporter(str(self.root), "--json")
        self.assertEqual(rejected.returncode, 1)
        self.assertEqual(json.loads(rejected.stdout), results)
        self.assertIn("synthesis_errors = 1", rejected.stderr)

    def test_newest_run_is_chosen(self):
        runs = self.root / "runs"
        for name in ("aaa", "zzz"):
            (runs / name).mkdir(parents=True)
            (runs / name / "run.json").write_text("{}")
        # Filesystem timestamps are coarse enough that two directories created
        # in the same tick can tie, so make "aaa" newer explicitly.
        newer = (runs / "zzz").stat().st_mtime_ns + 1_000_000_000
        os.utime(runs / "aaa", ns=(newer, newer))
        self.assertEqual(report.newest_run(runs).name, "aaa")


if __name__ == "__main__":
    unittest.main()
