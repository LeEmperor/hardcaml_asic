"""Report collection fixtures require no PDK or licensed tools."""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/phase4.py"
SPEC = importlib.util.spec_from_file_location("phase4", SCRIPT)
phase4 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(phase4)


class CollectorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "project/runs/asic").mkdir(parents=True)
        (self.root / "run.json").write_text(json.dumps({
            "run_id": "attempt-1", "build_identity": "build-1", "status": "completed",
            "requested_stage": "full", "completed_stage": "full",
            "outputs": {"flow": "project/runs/asic"},
            "environment": {"actual": {"librelane": "3.1.0.dev3"}},
        }))

    def put(self, relative, text):
        path = self.root / "project/runs/asic" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_complete(self):
        self.put("06-yosys-synthesis/reports/stat.json", json.dumps({
            "design": {"area": 123.5, "sequential_area": 40,
                       "num_cells": 15, "num_cells_by_type": {"sg13cmos5l_dfrbpq_1": 5}}
        }))
        self.put("final/metrics.csv", "timing__setup__ws__corner:slow,0.3\n"
                 "timing__hold__ws__corner:fast,0.1\nroute__drc_errors,0\n"
                 "design__lvs_error__count,0\nantenna__violating__nets,0\n"
                 "antenna__violating__pins,0\n")
        self.put("06-yosys-synthesis/state_out.json", json.dumps({
            "metrics": {"design__instance_unmapped__count": 0,
                        "synthesis__check_error__count": 0,
                        "design__inferred_latch__count": 0}}))
        result = phase4.collect(self.root)
        self.assertEqual(result["metrics"]["mapped_area"]["value"], 123.5)
        self.assertEqual(result["metrics"]["setup_slack"]["corner"], "slow")
        self.assertEqual(result["timing_goal"], "pass")
        self.assertEqual(result["checks"]["lvs"]["status"], "pass")
        self.assertEqual(result["mapped_cell_types"]["sg13cmos5l_dfrbpq_1"], 5)
        self.assertEqual(result["synthesis_checks"]["unmapped_instances"]["value"], 0)

    def test_partial_and_absent(self):
        self.put("06-yosys-synthesis/reports/stat.json", json.dumps({
            "design": {"area": 12, "num_cells": 2}}))
        partial = phase4.collect(self.root)
        self.assertEqual(partial["metrics"]["mapped_area"]["value"], 12)
        self.assertIsNone(partial["metrics"]["setup_slack"]["value"])
        self.assertEqual(partial["timing_goal"], "unknown")
        self.assertEqual(partial["checks"]["drc"]["status"], "unknown")
        (self.root / "project/runs/asic/06-yosys-synthesis/reports/stat.json").unlink()
        absent = phase4.collect(self.root)
        self.assertIn("absent", absent["metrics"]["mapped_area"]["unavailable_reason"])

    def test_unconstrained_hold_sentinel(self):
        self.put("final/metrics.csv", "timing__setup__ws__corner:slow,18.0\n"
                 "timing__hold__ws__corner:slow,1.0000000433293989E+39\n")
        result = phase4.collect(self.root)
        hold = result["metrics"]["hold_slack"]
        self.assertIsNone(hold["value"])
        self.assertEqual(hold["unavailable_reason"], "no constrained timing paths reported")
        self.assertEqual(result["timing_unconstrained_modes"], ["hold"])
        self.assertEqual(result["timing_goal"], "pass")
        self.put("final/metrics.csv", "timing__setup__ws__corner:slow,-0.5\n"
                 "timing__hold__ws__corner:slow,1.0000000433293989E+39\n")
        self.assertEqual(phase4.collect(self.root)["timing_goal"], "fail")

    def test_malformed_reports_and_failed_process(self):
        self.put("06-yosys-synthesis/reports/stat.json", "{bad")
        self.put("final/metrics.csv", "timing__setup__ws,not-a-number\ninvalid-row\n")
        record = json.loads((self.root / "run.json").read_text())
        record["status"] = "failed"
        (self.root / "run.json").write_text(json.dumps(record))
        result = phase4.collect(self.root)
        self.assertEqual(result["process_status"], "failed")
        self.assertIsNone(result["metrics"]["mapped_area"]["value"])
        self.assertEqual(len(result["errors"]), 2)


if __name__ == "__main__":
    unittest.main()
