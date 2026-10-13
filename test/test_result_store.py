"""Result allocation and durable preflight fixtures: no external tool probes."""

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import unittest
from unittest import mock
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import result_store as store  # noqa: E402


class ResultStoreTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.results = self.root / "_flow_results"
        self.bundle = self.root / "bundle"
        self.instant = datetime(2026, 10, 13, 1, 2, 3, 456789, timezone.utc)
        self.identity = uuid.UUID("12345678-1234-4321-8765-123456789abc")

    def allocate(self, **kwargs):
        return store.allocate(self.results / "runs", clock=lambda: self.instant,
                              id_factory=kwargs.pop("id_factory", lambda: self.identity), **kwargs)

    def operation(self, probe, **kwargs):
        return store.preflight_operation(self.bundle, results_root=self.results, probe=probe,
                                         clock=lambda: self.instant, **kwargs)

    def read(self, path):
        return json.loads(path.read_text())

    def test_utc_sortable_name_and_full_identity(self):
        self.instant = self.instant.astimezone(timezone(timedelta(hours=5)))
        allocated = self.allocate()
        self.assertEqual(allocated.directory.name, "20261013T010203456789Z_12345678")
        self.assertEqual(allocated.identity, self.identity.hex)
        self.assertEqual(allocated.created_at, "2026-10-13T01:02:03.456789+00:00")
        self.assertTrue(allocated.directory.is_absolute())
        self.assertEqual(list(allocated.directory.iterdir()), [])

    def test_clock_rejects_naive_time(self):
        self.instant = self.instant.replace(tzinfo=None)
        with self.assertRaisesRegex(ValueError, "timezone-aware"):
            self.allocate()
        self.assertEqual(list((self.results / "runs").iterdir()), [])

    def test_timestamp_names_sort_chronologically(self):
        first = self.allocate()
        self.instant += timedelta(microseconds=1)
        second = self.allocate()
        self.assertLess(first.directory.name, second.directory.name)

    def test_collision_retries_without_overwriting_directory_or_file(self):
        first = self.allocate()
        marker = first.directory / "owner.txt"
        marker.write_text("owned")
        alternate = uuid.UUID("abcdef01-1234-4321-8765-123456789abc")
        ids = mock.Mock(side_effect=[self.identity, alternate])
        second = self.allocate(id_factory=ids)
        self.assertEqual(ids.call_count, 2)
        self.assertEqual(second.identity, alternate.hex)
        self.assertEqual(marker.read_text(), "owned")
        # A colliding file is also somebody else's output.
        second.directory.rmdir()
        second.directory.write_text("owner file")
        with self.assertRaises(FileExistsError):
            self.allocate(id_factory=lambda: alternate, max_attempts=2)
        self.assertEqual(second.directory.read_text(), "owner file")

    def test_collision_exhaustion_is_bounded_including_short_id_collision(self):
        self.allocate()
        same_prefix = uuid.UUID("12345678-ffff-4321-8765-123456789abc")
        ids = mock.Mock(return_value=same_prefix)
        with self.assertRaisesRegex(FileExistsError, "exhausted 3"):
            self.allocate(id_factory=ids, max_attempts=3)
        self.assertEqual(ids.call_count, 3)
        self.assertEqual(len(list((self.results / "runs").iterdir())), 1)

    def test_invalid_retry_bound_does_not_create_root(self):
        with self.assertRaises(ValueError):
            self.allocate(max_attempts=0)
        self.assertFalse(self.results.exists())

    def test_receipt_maps_to_exact_ready_or_failed_report(self):
        for report, status, code in (({"ready": True, "issues": [], "actual": {"fixture": "1"}}, "ready", 0),
                                     ({"ready": False, "issues": ["not installed"]}, "failed", 1)):
            with self.subTest(status=status):
                def probe():
                    path = next(path for path in (self.results / "operations").glob("*/preflight.json")
                                if self.read(path).get("diagnostic", {}).get("status") == "pending")
                    receipt = self.read(path.parent / "operation.json")
                    self.assertEqual(receipt["status"], "pending")
                    self.assertIsNone(receipt["ended_at"])
                    self.assertFalse(self.read(path)["ready"])
                    return report
                outcome = self.operation(probe)
                self.assertEqual((outcome.status, outcome.exit_code), (status, code))
                self.assertEqual(outcome.result, report)
                self.assertEqual(self.read(outcome.report_path), report)
                receipt = self.read(outcome.receipt_path)
                self.assertEqual(receipt, outcome.receipt)
                self.assertEqual(receipt["record_type"], "preflight_operation")
                self.assertEqual(receipt["schema_version"], 1)
                self.assertEqual(receipt["bundle"], str(self.bundle))
                self.assertEqual(receipt["status"], status)
                self.assertEqual(receipt["exit_code"], code)
                self.assertIsNotNone(receipt["ended_at"])
                self.assertEqual(outcome.report_path, outcome.receipt_path.parent / receipt["report"])
                self.assertEqual(len(receipt["operation_id"]), 32)
                self.assertNotIn("build_identity", receipt)
        self.assertFalse((self.results / "runs").exists())

    def test_same_bundle_repeated_operations_get_unique_identities_and_paths(self):
        probe = lambda: {"ready": True, "issues": []}
        first, second = self.operation(probe), self.operation(probe)
        self.assertNotEqual(first.report_path, second.report_path)
        self.assertNotEqual(first.receipt["operation_id"], second.receipt["operation_id"])

    def test_explicit_file_only_with_atomic_replacement_and_pending_before_probe(self):
        output = self.root / "explicit.json"
        output.write_text("old report")
        report = {"ready": True, "issues": [], "requested": {"fixture": "1"}}
        def probe():
            self.assertEqual(self.read(output)["diagnostic"]["status"], "pending")
            return report
        outcome = self.operation(probe, output=output)
        self.assertIsNone(outcome.receipt)
        self.assertIsNone(outcome.receipt_path)
        self.assertEqual(outcome.report_path, output)
        self.assertEqual(self.read(output), report)
        self.assertFalse(self.results.exists())
        self.assertEqual(list(self.root.iterdir()), [output])

    def test_invalid_explicit_destinations_fail_before_probe(self):
        probe = mock.Mock()
        for output, error in ((self.root / "missing/out.json", FileNotFoundError),
                              (self.root, IsADirectoryError)):
            with self.subTest(output=output), self.assertRaises(error):
                self.operation(probe, output=output)
        output = self.root / "unwritable.json"
        with mock.patch.object(store.os, "access", return_value=False):
            with self.assertRaises(PermissionError):
                self.operation(probe, output=output)
        probe.assert_not_called()
        self.assertFalse(self.results.exists())
        self.assertFalse(output.exists())

    def test_allocation_or_pending_publication_failure_never_probes(self):
        probe = mock.Mock()
        self.results.write_text("owned root")
        with self.assertRaises(OSError):
            self.operation(probe)
        self.results.unlink()
        def save(path, value):
            if path.name == "preflight.json":
                raise OSError("output unavailable")
            store.save_json(path, value)
        with self.assertRaisesRegex(OSError, "unavailable"):
            self.operation(probe, save=save)
        probe.assert_not_called()
        receipt = self.read(next(self.results.glob("operations/*/operation.json")))
        self.assertEqual(receipt["status"], "failed")
        self.assertIsNotNone(receipt["ended_at"])

    def test_probe_exception_and_malformed_results_fail_closed(self):
        for value in (RuntimeError("probe broke"), None, {"ready": "yes", "issues": []},
                      {"ready": True, "issues": None}):
            with self.subTest(value=value):
                probe = mock.Mock(side_effect=value) if isinstance(value, Exception) else mock.Mock(return_value=value)
                outcome = self.operation(probe, provenance={"support_tools": "/fixture/tools"})
                self.assertEqual((outcome.status, outcome.exit_code), ("failed", 1))
                report = self.read(outcome.report_path)
                self.assertFalse(report["ready"])
                self.assertIn("preflight failed:", report["issues"][0])
                self.assertEqual(report["diagnostic"]["bundle"], str(self.bundle))
                self.assertEqual(report["diagnostic"]["support_tools"], "/fixture/tools")
                self.assertNotIn("actual", report)
                self.assertNotIn("build_identity", report)
                self.assertNotIn("execution_binding", report)

    def test_malformed_or_missing_bundle_is_a_failed_operation(self):
        self.bundle.mkdir()
        for content in (None, "{broken", "{}"):
            with self.subTest(content=content):
                manifest = self.bundle / "manifest.json"
                if content is not None:
                    manifest.write_text(content)
                def probe():
                    return {"ready": bool(self.read(manifest)["requested_tools"]), "issues": []}
                outcome = self.operation(probe)
                self.assertEqual(outcome.status, "failed")
                self.assertFalse(outcome.result["ready"])

    def test_scoped_signals_publish_interrupted_report_and_restore_handlers(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signum=signum):
                before = {s: signal.getsignal(s) for s in (signal.SIGINT, signal.SIGTERM)}
                def probe():
                    os.kill(os.getpid(), signum)
                outcome = self.operation(probe)
                self.assertEqual((outcome.status, outcome.exit_code), ("interrupted", 128 + signum))
                self.assertEqual(outcome.result["diagnostic"]["interrupted_by"], signal.Signals(signum).name)
                self.assertEqual(self.read(outcome.report_path), outcome.result)
                self.assertEqual(self.read(outcome.receipt_path)["status"], "interrupted")
                self.assertEqual({s: signal.getsignal(s) for s in before}, before)

    def test_keyboard_interrupt_explicit_file_is_durable(self):
        outcome = self.operation(mock.Mock(side_effect=KeyboardInterrupt()), output=self.root / "report.json")
        self.assertEqual((outcome.status, outcome.exit_code), ("interrupted", 130))
        self.assertFalse(self.read(outcome.report_path)["ready"])
        self.assertFalse(self.results.exists())

    def test_interruption_during_pending_or_final_publication_is_durable(self):
        for interrupted_write in (1, 2):
            with self.subTest(interrupted_write=interrupted_write):
                calls = 0
                def save(path, value):
                    nonlocal calls
                    if path.name == "preflight.json":
                        calls += 1
                        if calls == interrupted_write:
                            raise store.FlowInterrupted(signal.SIGTERM)
                    store.save_json(path, value)
                probe = mock.Mock(return_value={"ready": True, "issues": []})
                outcome = self.operation(probe, save=save)
                self.assertEqual((outcome.status, outcome.exit_code), ("interrupted", 143))
                self.assertEqual(self.read(outcome.report_path)["diagnostic"]["status"], "interrupted")
                self.assertEqual(self.read(outcome.receipt_path)["status"], "interrupted")
                self.assertEqual(probe.call_count, interrupted_write - 1)

    def test_atomic_publication_failure_preserves_previous_good_file(self):
        output = self.root / "report.json"
        output.write_text('{"ready": true, "issues": []}\n')
        before = output.read_bytes()
        probe = mock.Mock()
        with mock.patch.object(store.os, "replace", side_effect=OSError("publication failed")):
            with self.assertRaises(OSError):
                self.operation(probe, output=output)
        self.assertEqual(output.read_bytes(), before)
        self.assertEqual(list(self.root.glob(".report.json.*")), [])
        probe.assert_not_called()

    def test_terminal_publication_failure_retains_pending_and_failed_receipt(self):
        def save(path, value):
            if path.name == "preflight.json" and "diagnostic" not in value:
                with mock.patch.object(store.os, "replace", side_effect=OSError("disk full")):
                    store.save_json(path, value)
            else:
                store.save_json(path, value)
        with self.assertRaisesRegex(OSError, "disk full"):
            self.operation(lambda: {"ready": True, "issues": []}, save=save)
        receipt_path = next(self.results.glob("operations/*/operation.json"))
        self.assertEqual(self.read(receipt_path)["status"], "failed")
        self.assertEqual(self.read(receipt_path.parent / "preflight.json")["diagnostic"]["status"], "pending")


if __name__ == "__main__":
    unittest.main()
