"""Run summary fixtures; no PDK, container, or licensed tool is needed."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/report.py"
SPEC = importlib.util.spec_from_file_location("report", SCRIPT)
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


RESULTS = {
    "run_id": "attempt-1", "process_status": "completed",
    "requested_stage": "full", "completed_stage": "full",
    "timing_goal": "pass", "timing_unconstrained_modes": [],
    "metrics": {
        "setup_slack": {"value": 18.18, "corner": "nom_slow_1p08V_125C",
                        "unavailable_reason": None},
        "hold_slack": {"value": 0.12, "corner": "nom_fast_1p32V_m40C",
                       "unavailable_reason": None},
    },
    "checks": {"drc": {"status": "pass"}, "lvs": {"status": "pass"},
               "antenna": {"status": "pass"}},
    "synthesis_checks": {"unmapped_instances": {"value": 0}},
    "postchecks": [{"checks": {"precheck": "pass", "gate_level": "pass"}}],
    "errors": [],
}


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        flow = self.root / "project/runs/asic"
        (flow / "final").mkdir(parents=True)
        (self.root / "run.json").write_text(json.dumps({
            "run_id": "attempt-1", "bundle": "/bundle",
            "outputs": {"flow": "project/runs/asic"},
        }))
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

    def run_report(self, results):
        (self.root / "results.json").write_text(json.dumps(results))
        record, source = report.results_for(self.root)
        self.assertEqual(source, "results.json")
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            code = report.report(self.root, record, source)
        return code, stream.getvalue()

    def test_clean_run_passes(self):
        code, text = self.run_report(RESULTS)
        self.assertEqual(code, 0)
        self.assertIn("all reported checks passed", text)
        self.assertIn("Pin check", text)
        self.assertIn("RSZ-0033", text)
        self.assertNotIn("unrelated line", text)
        # The 1e39 sentinel is not a slack; it prints as unavailable.
        self.assertIn("n/a", text)
        self.assertIn("18.420", text)

    def test_unconstrained_mode_is_a_problem(self):
        results = dict(RESULTS, timing_unconstrained_modes=["hold"])
        code, text = self.run_report(results)
        self.assertEqual(code, 1)
        self.assertIn("UNCONSTRAINED: hold", text)

    def test_failing_check_and_status_are_problems(self):
        results = dict(RESULTS, process_status="failed",
                       checks=dict(RESULTS["checks"], drc={"status": "fail"}),
                       postchecks=[{"checks": {"precheck": "fail"}}])
        code, text = self.run_report(results)
        self.assertEqual(code, 1)
        for expected in ("process status failed", "drc fail", "precheck fail"):
            self.assertIn(expected, text)

    def test_newest_run_is_chosen(self):
        runs = self.root / "runs"
        for name in ("aaa", "zzz"):
            (runs / name).mkdir(parents=True)
            (runs / name / "run.json").write_text("{}")
        # Filesystem timestamps are coarse enough that two directories created
        # in the same tick can tie, so make "aaa" newer explicitly rather than
        # by touching it.
        newer = (runs / "zzz").stat().st_mtime_ns + 1_000_000_000
        os.utime(runs / "aaa", ns=(newer, newer))
        self.assertEqual(report.newest_run(runs).name, "aaa")


if __name__ == "__main__":
    unittest.main()
