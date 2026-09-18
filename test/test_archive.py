"""Archive selection and hash verification; needs no PDK, tools or real run."""

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/archive.py"
SPEC = importlib.util.spec_from_file_location("archive", SCRIPT)
archive = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(archive)

FLOW = "project/runs/asic"
TOP = "tt_um_asic_observable"


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.run = self.root / "run"
        self.output = self.root / "evidence"
        self.manifest = self.put("project/manifest.json",
                                 json.dumps({"top_module": TOP, "identity": "build-1"}))
        self.put("execution.log", "log\n")
        self.put("preflight.json", json.dumps({"ready": True}))
        self.put("project/src/config.json", "{}\n")
        self.put(f"{FLOW}/final/metrics.csv", "route__drc_errors,0\n")
        self.put(f"{FLOW}/final/metrics.json", "{}\n")
        self.put(f"{FLOW}/final/sdc/{TOP}.sdc", "sdc\n")
        self.put(f"{FLOW}/06-yosys-synthesis/reports/stat.rpt", "stat\n")
        self.put(f"{FLOW}/55-openroad-stapostpnr/summary.rpt", "summary\n")
        self.gds = self.put(f"{FLOW}/final/gds/{TOP}.gds", "gds-bytes\n")
        self.netlist = self.put(f"{FLOW}/final/nl/{TOP}.nl.v", "netlist\n")
        self.write_run("completed")

    def put(self, relative, text):
        path = self.run / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def write_run(self, status):
        (self.run / "run.json").write_text(json.dumps({
            "run_id": "attempt-1", "build_identity": "build-1", "status": status,
            "manifest_sha256": digest(self.manifest),
            "outputs": {"flow": FLOW, "project": "project"},
        }))
        (self.run / "results.json").write_text("{}\n")

    def write_check(self, name="check-1", gds=None):
        """One postcheck attempt whose recorded hashes match what is on disk."""
        check = self.run / "checks" / name
        (check / "tt/precheck/reports").mkdir(parents=True)
        (check / "tt/precheck/reports/results.md").write_text("rows\n")
        (check / "postcheck.log").write_text("postcheck\n")
        (check / "gate.out").write_text("compiled simulator, not evidence\n")
        testbench = check / "testbench.v"
        testbench.write_text("testbench\n")
        (check / "postcheck.json").write_text(json.dumps({
            "checks": {"precheck": "pass", "gate_level": "pass"},
            "inputs": {"gds_sha256": gds or digest(self.gds),
                       "netlist_sha256": digest(self.netlist),
                       "testbench_sha256": digest(testbench)}}))
        return check

    def test_selection_and_verification(self):
        self.write_check()
        tarball, selected, omitted = archive.archive(self.run, self.output, force=False)
        names = {name for _, name in selected}
        self.assertIn(f"{FLOW}/final/gds/{TOP}.gds", names)
        self.assertIn(f"{FLOW}/final/nl/{TOP}.nl.v", names)
        self.assertIn("checks/check-1/tt/precheck/reports/results.md", names)
        # The compiled simulator and the intermediate layout formats stay out.
        self.assertNotIn("checks/check-1/gate.out", names)
        self.assertEqual(omitted, [])
        with tarfile.open(tarball) as stream:
            self.assertEqual(sorted(stream.getnames()), sorted(names))
        record = json.loads((self.output / "archive.json").read_text())
        self.assertEqual(record["verified"]["gds_sha256"], digest(self.gds))
        self.assertEqual(record["verified"]["manifest_sha256"], digest(self.manifest))
        self.assertEqual(record["run_id"], "attempt-1")
        for name in ("manifest.json", "run.json", "results.json", "postcheck.json"):
            self.assertTrue((self.output / name).is_file(), name)

    def test_gds_hash_mismatch_fails(self):
        self.write_check(gds="0" * 64)
        with self.assertRaises(archive.phase4.PrerequisiteError) as raised:
            archive.archive(self.run, self.output, force=False)
        self.assertIn("gds_sha256", str(raised.exception))
        # Nothing is written when verification fails; a half-built evidence
        # directory is the thing this check exists to prevent.
        self.assertFalse(self.output.exists())

    def test_modified_manifest_fails(self):
        self.write_check()
        self.manifest.write_text(json.dumps({"top_module": TOP, "identity": "tampered"}))
        with self.assertRaises(archive.phase4.PrerequisiteError) as raised:
            archive.archive(self.run, self.output, force=False)
        self.assertIn("staged manifest", str(raised.exception))

    def test_unfinished_run_refused(self):
        self.write_run("failed")
        with self.assertRaises(archive.phase4.PrerequisiteError) as raised:
            archive.archive(self.run, self.output, force=False)
        self.assertIn("not completed", str(raised.exception))

    def test_synthesis_only_run_reports_absences(self):
        """A synthesis stage run has no final layout and no checks, and still archives."""
        for path in (self.gds, self.netlist):
            path.unlink()
            path.parent.rmdir()
        (self.run / "results.json").unlink()
        _, selected, omitted = archive.archive(self.run, self.output, force=False)
        self.assertIn(f"{FLOW}/final/gds", omitted)
        self.assertIn(f"{FLOW}/final/nl", omitted)
        self.assertIn("results.json", omitted)
        self.assertTrue(selected)
        self.assertEqual(json.loads((self.output / "archive.json").read_text())["omitted"],
                         sorted(omitted))

    def test_empty_directory_counts_as_absent(self):
        """A stage that ran but wrote nothing leaves the directory behind."""
        self.gds.unlink()
        _, selected, omitted = archive.archive(self.run, self.output, force=False)
        self.assertIn(f"{FLOW}/final/gds", omitted)
        self.assertNotIn(f"{FLOW}/final/gds", {name for _, name in selected})

    def test_populated_output_needs_force(self):
        self.write_check()
        self.output.mkdir()
        (self.output / "README.md").write_text("hand-written note\n")
        with self.assertRaises(archive.phase4.PrerequisiteError):
            archive.archive(self.run, self.output, force=False)
        archive.archive(self.run, self.output, force=True)
        # --force replaces what the archiver owns; the README is not its file.
        self.assertTrue((self.output / "README.md").is_file())

    def test_two_checks_keep_distinct_names(self):
        self.write_check("check-1")
        self.write_check("check-2")
        archive.archive(self.run, self.output, force=False)
        self.assertTrue((self.output / "postcheck-check-1.json").is_file())
        self.assertTrue((self.output / "postcheck-check-2.json").is_file())
        self.assertFalse((self.output / "postcheck.json").is_file())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
