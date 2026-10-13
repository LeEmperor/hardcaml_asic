"""Synthetic archives and injected probes only: no PBS binary/network acceptance."""

import fcntl
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "flow"))
from hardcaml_asic_flow import managed_python as m, paths  # noqa: E402


def member(name, data=b"", kind=tarfile.REGTYPE, link="", mode=0o755, pax=None):
    info = tarfile.TarInfo(name)
    info.type = kind
    info.linkname = link
    info.mode = mode
    info.size = len(data) if kind == tarfile.REGTYPE else 0
    info.pax_headers = pax or {}
    return info, data


def archive_bytes(extra=(), base=True):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.PAX_FORMAT) as tar:
        entries = ([member("python", kind=tarfile.DIRTYPE),
                    member("python/bin/python3.11", b"fixture, never executed\n"),
                    member("python/lib/tcl9.0", kind=tarfile.DIRTYPE)] if base else [])
        for info, data in entries + list(extra):
            tar.addfile(info, io.BytesIO(data) if info.isfile() else None)
    return gzip.compress(output.getvalue(), mtime=0)


def fake_probe(interpreter, pin):
    runtime = interpreter.parent.parent
    return {"version": pin["version"], "executable": str(interpreter),
            "base_prefix": str(runtime), "tcl_patchlevel": "9.0.fixture",
            "tcl_library": str(runtime / "lib/tcl9.0")}


class PinTest(unittest.TestCase):
    def test_exact_audited_pin_and_shipped_minor(self):
        pin = m.describe()
        self.assertEqual((pin["version"], pin["build"], pin["size"]),
                         ("3.11.17", "20261009", 30808475))
        self.assertEqual(pin["sha256"],
                         "89db7607ebadb77a64709d159b86555d995368ec385a2ab33b00477790c543b0")
        self.assertEqual(pin["provenance"]["asset_id"], 625538076)
        self.assertIn("runtime validation is mandatory for every acquisition",
                      pin["provenance"]["compatibility"])
        self.assertIn("python=3.11", paths.TOOLCHAIN_LOCK.read_text())

    def test_pin_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            lock = Path(temporary) / "lock"
            lock.write_text("python=3.12\n")
            with mock.patch.object(paths, "TOOLCHAIN_LOCK", lock):
                with self.assertRaises(m.Error):
                    m.describe()

    def test_invalid_data_is_rejected(self):
        pin = m.describe()
        for key, value in (("url", "https://evil.invalid/python.tar.gz"),
                           ("size", m.COMPRESSED_CAP + 1), ("sha256", "bad"),
                           ("version", "3.12.1"), ("target", "aarch64")):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                data = Path(temporary) / "pin"
                data.write_text(json.dumps(dict(pin, **{key: value})))
                with mock.patch.object(paths, "MANAGED_PYTHON", data):
                    with self.assertRaises(m.Error):
                        m.describe()

    def test_platform_support_boundary(self):
        for system, machine, libc, version, supported in (
                ("Linux", "x86_64", "glibc", "2.17", True),
                ("Linux", "x86_64", "glibc", "2.39", True),
                ("Linux", "x86_64", "glibc", "2.16", False),
                ("Linux", "aarch64", "glibc", "2.39", False),
                ("Linux", "x86_64", "musl", "1.2", False),
                ("Darwin", "x86_64", "", "", False)):
            with self.subTest(system=system, machine=machine, version=version), \
                    mock.patch.object(m.platform, "system", return_value=system), \
                    mock.patch.object(m.platform, "machine", return_value=machine), \
                    mock.patch.object(m.platform, "libc_ver", return_value=(libc, version)):
                if supported:
                    m._platform()
                else:
                    with self.assertRaisesRegex(m.Error, "--python external override"):
                        m._platform()

    def test_unsupported_platform_never_creates_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "absent"
            with mock.patch.object(m.platform, "machine", return_value="aarch64"):
                for operation in (m.inspect, m.acquire):
                    with self.assertRaises(m.Error):
                        operation(root)
                    self.assertFalse(root.exists())


class ArchiveTest(unittest.TestCase):
    def extract(self, data):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "archive.gz"
            archive.write_bytes(data)
            stage = root / "stage"
            stage.mkdir()
            m._extract(archive, stage)
            return {p.relative_to(stage).as_posix():
                    (os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
                    for p in stage.rglob("*")}

    def test_safe_relative_symlinks_and_hardlinks(self):
        found = self.extract(archive_bytes([
            member("python/bin/python", kind=tarfile.SYMTYPE, link="python3.11"),
            member("python/alias", kind=tarfile.LNKTYPE, link="python/bin/python3.11"),
            member("python/tcl", kind=tarfile.SYMTYPE, link="lib/tcl9.0")]))
        self.assertEqual(found["python/bin/python"], "python3.11")
        self.assertEqual(found["python/alias"], found["python/bin/python3.11"])

    def test_forward_chained_links(self):
        found = self.extract(archive_bytes([
            member("python/a", kind=tarfile.SYMTYPE, link="b"),
            member("python/b", kind=tarfile.SYMTYPE, link="bin/python3.11"),
            member("python/c", kind=tarfile.LNKTYPE, link="python/a")]))
        self.assertEqual(found["python/c"], found["python/bin/python3.11"])

    def test_link_parent_components_resolved_before_dotdot(self):
        # Lexical normalization would falsely claim this points at bin/python3.11;
        # the real path points at lib/bin/python3.11, which is missing.
        with self.assertRaises(m.Error):
            self.extract(archive_bytes([
                member("python/b", kind=tarfile.SYMTYPE, link="lib/tcl9.0"),
                member("python/a", kind=tarfile.SYMTYPE, link="b/../bin/python3.11")]))
        found = self.extract(archive_bytes([
            member("python/lib/alias", kind=tarfile.SYMTYPE, link="../bin/python3.11")]))
        self.assertEqual(found["python/lib/alias"], "../bin/python3.11")

    def test_overlong_and_deep_paths_and_link_chains_rejected(self):
        for name in ("python/" + "a" * 4096, "python/" + "a/" * 257 + "file"):
            with self.subTest(name=name[:30]), self.assertRaises(m.Error):
                self.extract(archive_bytes([member(name)]))
        chain = [member("python/a" + str(i), kind=tarfile.SYMTYPE,
                        link="a" + str(i + 1)) for i in range(100)]
        chain.append(member("python/a100", b"end"))
        with self.assertRaisesRegex(m.Error, "too many link"):
            self.extract(archive_bytes(chain))

    def test_paths_traversal_absolute_unexpected_root(self):
        for name in ("/python/evil", "python/../evil", "other/evil", "python/../../evil",
                     "python\\evil"):
            with self.subTest(name=name), self.assertRaises(m.Error):
                self.extract(archive_bytes([member(name)]))

    def test_normalized_duplicates(self):
        for name in ("python/bin/./python3.11", "python//bin/python3.11",
                     "python/bin/python3.11"):
            with self.subTest(name=name), self.assertRaises(m.Error):
                self.extract(archive_bytes([member(name)]))

    def test_file_directory_collisions(self):
        with self.assertRaises(m.Error):
            self.extract(archive_bytes([member("python/bin"), member("python/bin/child")]))

    def test_symlink_parent_write_through_rejected(self):
        with self.assertRaises(m.Error):
            self.extract(archive_bytes([
                member("python/alias", kind=tarfile.SYMTYPE, link="lib"),
                member("python/alias/child")]))

    def test_links_escaping_broken_cyclic_absolute(self):
        cases = [
            [member("python/a", kind=tarfile.SYMTYPE, link="../../outside")],
            [member("python/a", kind=tarfile.SYMTYPE, link="/python/bin/python3.11")],
            [member("python/a", kind=tarfile.SYMTYPE, link="missing")],
            [member("python/a", kind=tarfile.SYMTYPE, link="b"),
             member("python/b", kind=tarfile.SYMTYPE, link="a")],
            [member("python/a", kind=tarfile.LNKTYPE, link="../outside")],
            [member("python/a", kind=tarfile.LNKTYPE, link="python/lib")],
            [member("python/a", kind=tarfile.LNKTYPE, link="/python/bin/python3.11")],
            [member("python/a", kind=tarfile.SYMTYPE, link="b/child"),
             member("python/b", kind=tarfile.SYMTYPE, link="../../outside")]]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(m.Error):
                self.extract(archive_bytes(case))

    def test_special_sparse_privileged_members(self):
        for entry in (member("python/a", kind=tarfile.FIFOTYPE),
                      member("python/a", kind=tarfile.CHRTYPE),
                      member("python/a", kind=tarfile.BLKTYPE),
                      member("python/a", kind=tarfile.GNUTYPE_SPARSE),
                      member("python/a", mode=0o4755), member("python/a", mode=0o2755),
                      member("python/a", pax={"GNU.sparse.size": "0"})):
            with self.subTest(kind=entry[0].type, mode=entry[0].mode), self.assertRaises(m.Error):
                self.extract(archive_bytes([entry]))

    def test_member_and_decompressed_bounds(self):
        with mock.patch.object(m, "MEMBER_CAP", 2), self.assertRaises(m.Error):
            self.extract(archive_bytes())
        with mock.patch.object(m, "EXTRACTED_CAP", 100), self.assertRaises(m.Error):
            self.extract(archive_bytes())
        tar = mock.Mock()
        tar.__iter__ = mock.Mock(return_value=iter([member("python/a", b"12345")[0]]))
        with mock.patch.object(m, "EXTRACTED_CAP", 4), self.assertRaises(m.Error):
            m._members(tar)
        with mock.patch.object(m, "MEMBER_CAP", 3), self.assertRaises(m.Error):
            self.extract(archive_bytes([member("python/a/b/c")], base=False))

    def test_all_members_validated_before_runtime_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "archive.gz"
            archive.write_bytes(archive_bytes([member("../../evil")]))
            stage = root / "stage"
            stage.mkdir()
            with self.assertRaises(m.Error):
                m._extract(archive, stage)
            self.assertEqual(list(stage.iterdir()), [])

    def test_truncated_gzip_is_rejected(self):
        with self.assertRaises(m.Error):
            self.extract(archive_bytes()[:-12])


class AcquisitionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "toolroot"
        self.data = archive_bytes()
        self.pin = dict(m.describe(), size=len(self.data), sha256=hashlib.sha256(self.data).hexdigest())
        self.patch = mock.patch.object(m, "describe", return_value=self.pin)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        patch = mock.patch.object(m, "_platform")
        patch.start()
        self.addCleanup(patch.stop)
        network = mock.patch.object(m.urllib.request, "build_opener",
                                    side_effect=AssertionError("fixture attempted network"))
        network.start()
        self.addCleanup(network.stop)
        self.base, self.generation, self.interpreter = m._layout(self.root, self.pin)
        self.probe = mock.Mock(side_effect=fake_probe)

    def cache(self, data=None):
        path = self.base / ".cache" / (self.pin["sha256"] + ".tar.gz")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.data if data is None else data)
        return path

    def acquire(self):
        return m.acquire(self.root, offline=True, probe=self.probe)

    def test_cache_match_offline_acquire_stage_and_final_probes(self):
        self.cache()
        result = self.acquire()
        self.assertEqual(result["interpreter"], str(self.interpreter))
        calls = [call.args[0] for call in self.probe.call_args_list]
        self.assertIn(".stage-", str(calls[0]))
        self.assertEqual(calls[1], self.interpreter)
        self.assertEqual(result["receipt"]["probe"]["base_prefix"], str(self.generation / "python"))
        self.assertEqual(json.loads((self.generation / "receipt.json").read_text()), result["receipt"])
        self.assertFalse(list(self.base.glob(".stage-*")))

    def test_offline_cache_miss_no_network(self):
        with self.assertRaisesRegex(m.Error, "cache miss") as raised:
            self.acquire()
        self.assertEqual(raised.exception.status, 4)
        self.probe.assert_not_called()

    def test_corrupt_hash_before_extract_or_execution(self):
        corrupted = bytes([self.data[0] ^ 1]) + self.data[1:]
        cache = self.cache(corrupted)
        with mock.patch.object(m, "_extract") as extract:
            for offline in (True, False):
                with self.assertRaisesRegex(m.Error, "SHA256"):
                    m.acquire(self.root, offline=offline, probe=self.probe)
            extract.assert_not_called()
        self.probe.assert_not_called()
        self.assertEqual(cache.read_bytes(), corrupted)

    def test_wrong_size_before_extract_or_execution(self):
        self.cache(self.data[:-1])
        with mock.patch.object(m, "_extract") as extract, self.assertRaises(m.Error):
            self.acquire()
        extract.assert_not_called()
        self.probe.assert_not_called()

    def test_online_unique_partial_atomic_verified_cache(self):
        def download(pin, output, deadline):
            self.assertFalse((self.base / ".cache" / (pin["sha256"] + ".tar.gz")).exists())
            self.assertEqual(len(list((self.base / ".cache").glob(".partial-*"))), 1)
            output.write(self.data)
        with mock.patch.object(m, "_download", side_effect=download):
            m.acquire(self.root, probe=self.probe)
        self.assertEqual((self.base / ".cache" / (self.pin["sha256"] + ".tar.gz")).read_bytes(), self.data)
        self.assertFalse(list((self.base / ".cache").glob(".partial-*")))

    def test_failed_download_never_publishes_cache(self):
        with mock.patch.object(m, "_download", side_effect=lambda pin, output, deadline: output.write(b"bad")):
            with self.assertRaises(m.Error):
                m.acquire(self.root, probe=self.probe)
        self.assertEqual(list((self.base / ".cache").iterdir()), [])
        self.probe.assert_not_called()

    def test_contention_nonblocking(self):
        self.cache()
        with (self.base / ".writer.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            started = time.monotonic()
            with self.assertRaises(m.Error) as raised:
                self.acquire()
            self.assertEqual(raised.exception.status, 5)
            self.assertLess(time.monotonic() - started, 1)
        self.probe.assert_not_called()

    def test_missing_readonly_check_has_no_side_effects(self):
        with self.assertRaises(m.Error) as raised:
            m.inspect(self.root, probe=self.probe)
        self.assertEqual(raised.exception.status, 3)
        self.assertFalse(self.root.exists())
        self.probe.assert_not_called()

    def test_ready_readonly_check_no_lock_cache_or_rewrite(self):
        self.cache()
        result = self.acquire()
        (self.base / ".writer.lock").unlink()
        cache = self.base / ".cache" / (self.pin["sha256"] + ".tar.gz")
        cache.unlink()
        cache.parent.rmdir()
        before = {str(p): (p.lstat().st_mode, p.lstat().st_mtime_ns, p.read_bytes() if p.is_file() else None)
                  for p in self.root.rglob("*")}
        with mock.patch.object(m, "_writer", side_effect=AssertionError("read-only lock")):
            self.assertEqual(m.inspect(self.root, probe=self.probe), result)
        after = {str(p): (p.lstat().st_mode, p.lstat().st_mtime_ns, p.read_bytes() if p.is_file() else None)
                 for p in self.root.rglob("*")}
        self.assertEqual(before, after)

    def test_stage_probe_failure_preserves_old_generations(self):
        self.cache()
        old = self.base / "old-generation/python"
        old.mkdir(parents=True)
        (old / "keep").write_text("existing venv/runtime")
        self.probe.side_effect = m.Error("fixture stage failure", 6)
        with self.assertRaises(m.Error):
            self.acquire()
        self.assertFalse(self.generation.exists())
        self.assertEqual((old / "keep").read_text(), "existing venv/runtime")
        self.assertFalse(list(self.base.glob(".stage-*")))

    def test_final_probe_failure_has_no_receipt_or_success(self):
        self.cache()
        good = self.acquire()
        good_marker = self.generation / "receipt.json"
        original = good_marker.read_bytes()
        new_pin = dict(self.pin, version="3.11.18")
        self.base, self.generation, self.interpreter = m._layout(self.root, new_pin)
        self.probe.side_effect = lambda interpreter, pin: (
            fake_probe(interpreter, pin) if ".stage-" in str(interpreter)
            else (_ for _ in ()).throw(m.Error("fixture relocation failure", 6)))
        with mock.patch.object(m, "describe", return_value=new_pin):
            with self.assertRaisesRegex(m.Error, "relocation"):
                self.acquire()
            with self.assertRaisesRegex(m.Error, "receipt"):
                m.inspect(self.root, probe=self.probe)
            with self.assertRaisesRegex(m.Error, "receipt"):
                self.acquire()
        self.assertTrue(self.generation.is_dir())
        self.assertFalse((self.generation / "receipt.json").exists())
        self.assertEqual(good_marker.read_bytes(), original)
        self.assertTrue(Path(good["interpreter"]).is_file())

    def test_acquisition_deadline_covers_validation_before_execution(self):
        self.cache()
        with mock.patch.object(m, "DEADLINE", 0), self.assertRaisesRegex(m.Error, "deadline"):
            self.acquire()
        self.probe.assert_not_called()
        self.assertFalse(self.generation.exists())

    def test_existing_unreceipted_generation_never_overwritten(self):
        self.generation.mkdir(parents=True)
        (self.generation / "user").write_text("keep")
        with self.assertRaises(m.Error):
            self.acquire()
        self.assertEqual((self.generation / "user").read_text(), "keep")

    def test_atomic_publication_never_replaces_empty_user_directory(self):
        self.base.mkdir(parents=True)
        stage = self.base / ".stage-fixture"
        stage.mkdir()
        self.generation.mkdir()
        with self.assertRaisesRegex(m.Error, "no replacement"):
            m._publish_generation(stage, self.generation)
        self.assertTrue(stage.exists())
        self.assertTrue(self.generation.exists())

    def test_destination_appearing_after_stage_probe_is_retained(self):
        self.cache()
        def probe(interpreter, pin):
            self.generation.mkdir()
            (self.generation / "keep").write_text("user")
            return fake_probe(interpreter, pin)
        with self.assertRaisesRegex(m.Error, "destination appeared"):
            m.acquire(self.root, offline=True, probe=probe)
        self.assertEqual((self.generation / "keep").read_text(), "user")
        self.assertFalse(list(self.base.glob(".stage-*")))

    def test_symlink_cache_directory_and_lock_rejected(self):
        self.base.mkdir(parents=True)
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        for name in (".cache", ".writer.lock"):
            link = self.base / name
            link.unlink(missing_ok=True)  # prior fixture acquisition may create its lock
            link.symlink_to(outside)
            with self.subTest(name=name), self.assertRaises(m.Error):
                self.acquire()
            link.unlink()
        self.assertEqual(list(outside.iterdir()), [])

    def test_readonly_check_rejects_symlink_runtime_root(self):
        self.cache()
        self.acquire()
        runtime = self.generation / "python"
        outside = Path(self.temp.name) / "relocated"
        runtime.rename(outside)
        runtime.symlink_to(outside)
        with self.assertRaisesRegex(m.Error, "symlink"):
            m.inspect(self.root, probe=self.probe)

    def test_symlink_parents_and_special_cache_rejected(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        self.root.symlink_to(outside, target_is_directory=True)
        for operation in (m.acquire, m.inspect):
            with self.assertRaises(m.Error):
                operation(self.root, probe=self.probe)
        self.assertEqual(list(outside.iterdir()), [])
        self.root.unlink()
        cache = self.cache()
        cache.unlink()
        os.mkfifo(cache)
        with self.assertRaises(m.Error):
            self.acquire()

    def test_receipt_pin_mismatch_and_missing_executable(self):
        self.cache()
        self.acquire()
        marker = self.generation / "receipt.json"
        receipt = json.loads(marker.read_text())
        receipt["pin"]["version"] = "3.11.1"
        marker.write_text(json.dumps(receipt))
        with self.assertRaises(m.Error) as raised:
            m.inspect(self.root, probe=self.probe)
        self.assertEqual(raised.exception.status, 3)
        receipt["pin"]["version"] = self.pin["version"]
        marker.write_text(json.dumps(receipt))
        self.interpreter.unlink()
        with self.assertRaises(m.Error) as raised:
            m.inspect(self.root, probe=self.probe)
        self.assertEqual(raised.exception.status, 6)

    def test_retained_explicit_path_when_new_pin_changes(self):
        self.cache()
        first = self.acquire()
        new_pin = dict(self.pin, version="3.11.18")
        with mock.patch.object(m, "describe", return_value=new_pin):
            second = self.acquire()
        self.assertNotEqual(first["interpreter"], second["interpreter"])
        self.assertTrue(Path(first["interpreter"]).exists())
        self.assertEqual(json.loads((self.generation / "receipt.json").read_text()), first["receipt"])


class NetworkTest(unittest.TestCase):
    def response(self, data, length=None, url=None):
        body = io.BytesIO(data)
        response = mock.MagicMock()
        response.headers = {} if length is None else {"Content-Length": str(length)}
        response.geturl.return_value = url or m.describe()["url"]
        response.read1.side_effect = body.read1
        response.isclosed.return_value = False
        response.__enter__.return_value = response
        return response

    def download(self, data, size, length=None, url=None):
        response = self.response(data, length, url)
        opener = mock.Mock()
        opener.open.return_value = response
        output = io.BytesIO()
        pin = dict(m.describe(), size=size)
        with mock.patch.object(m.urllib.request, "build_opener", return_value=opener):
            m._download(pin, output)
        return output.getvalue(), response, opener

    def test_bounded_download_read1_and_timeout(self):
        output, response, opener = self.download(b"12345", 5, 5)
        self.assertEqual(output, b"12345")
        self.assertLessEqual(opener.open.call_args.kwargs["timeout"], 20)
        self.assertTrue(response.fp.raw._sock.settimeout.called)
        self.assertFalse(response.read.called)

    def test_truncated_oversized_and_content_length(self):
        for data, size, length in ((b"123", 5, None), (b"123456", 5, None),
                                   (b"12345", 5, 6), (b"12345", 5, "bad")):
            with self.subTest(data=data, length=length), self.assertRaises(m.Error):
                self.download(data, size, length)
        with mock.patch.object(m, "COMPRESSED_CAP", 4), self.assertRaises(m.Error):
            self.download(b"12345", 5)

    def test_overall_deadline_stops_slow_reads(self):
        response = self.response(b"12345")
        opener = mock.Mock()
        opener.open.return_value = response
        with mock.patch.object(m.urllib.request, "build_opener", return_value=opener), \
                mock.patch.object(m.time, "monotonic", side_effect=[0, 0, 179, 181]), \
                self.assertRaisesRegex(m.Error, "deadline"):
            m._download(dict(m.describe(), size=5), io.BytesIO())

    def test_strict_https_redirect_policy(self):
        for host in m.REDIRECT_HOSTS:
            self.assertEqual(m._url("https://" + host + "/asset"), "https://" + host + "/asset")
        for url in ("http://github.com/asset", "https://evil.invalid/asset",
                    "https://github.com.evil.invalid/asset", "https://user@github.com/asset",
                    "https://github.com:444/asset", "file:///tmp/archive"):
            with self.subTest(url=url), self.assertRaises(m.Error):
                m._url(url)
            handler = m._Redirects(time.monotonic() + 180)
            request = urllib.request.Request("https://github.com/asset")
            with self.assertRaises(m.Error):
                handler.redirect_request(request, None, 302, "Found", {}, url)

    def test_final_url_is_checked(self):
        with self.assertRaises(m.Error):
            self.download(b"12345", 5, url="https://evil.invalid/asset")


class ProbeTest(unittest.TestCase):
    def test_sanitized_child_env_preserves_host_path(self):
        dirty = {key: "bad" for key in ("PYTHONHOME", "PYTHONPATH", "TCL_LIBRARY", "TK_LIBRARY",
                                       "TCLLIBPATH", "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT",
                                       "DYLD_INSERT_LIBRARIES", "GLIBC_TUNABLES")}
        dirty["PATH"] = "/host/path"
        with mock.patch.dict(os.environ, dirty, clear=True):
            env = m.child_env()
            self.assertEqual(env, {"PATH": "/host/path", "PYTHONDONTWRITEBYTECODE": "1"})
            self.assertEqual(os.environ, dirty)

    def test_probe_invocation_isolated_deadline_no_gui(self):
        result = {"fixture": "subprocess mocked, no binary executed"}
        with mock.patch.object(m.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(result))) as run:
            self.assertEqual(m.runtime_probe(Path("/fixture/python"), {}), result)
        self.assertEqual(run.call_args.args[0][:3], ["/fixture/python", "-I", "-B"])
        self.assertEqual(run.call_args.kwargs["timeout"], 30)
        for dependency in ("ssl", "venv", "ensurepip", "tkinter", "_tkinter", "tkinter.Tcl()"):
            self.assertIn(dependency, m.PROBE_CODE)
        self.assertNotIn("Tk()", m.PROBE_CODE)

    def test_probe_timeout_becomes_status_six(self):
        with mock.patch.object(m.subprocess, "run", side_effect=subprocess.TimeoutExpired("fixture", 30)):
            with self.assertRaises(m.Error) as raised:
                m.runtime_probe(Path("/fixture/python"), {})
        self.assertEqual(raised.exception.status, 6)

    def test_probe_exact_patch_prefix_executable_and_tcl_resource(self):
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary) / "python"
            interpreter = runtime / "bin/python3.11"
            interpreter.parent.mkdir(parents=True)
            interpreter.write_text("fixture")
            interpreter.chmod(0o755)
            (runtime / "lib/tcl9.0").mkdir(parents=True)
            pin = {"version": "3.11.17"}
            for key, value in (("version", "3.11.16"), ("base_prefix", "/outside"),
                               ("executable", "/outside/python"), ("tcl_library", "/tmp"),
                               ("tcl_patchlevel", "")):
                result = dict(fake_probe(interpreter, pin), **{key: value})
                with self.subTest(key=key), self.assertRaises(m.Error):
                    m._probe(interpreter, pin, lambda *_: result)

    def test_cli_json_and_missing_check_status(self):
        with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
            self.assertEqual(m.main(["--describe"]), 0)
            self.assertEqual(json.loads(stdout.getvalue()), m.describe())
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(m, "_platform"), \
                mock.patch("sys.stderr", new_callable=io.StringIO) as stderr:
            root = Path(temporary) / "missing"
            self.assertEqual(m.main(["--root", str(root), "--check"]), 3)
            self.assertIn("receipt", stderr.getvalue())
            self.assertFalse(root.exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
