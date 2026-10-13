"""Bounded, stdlib-only PBS archive acquisition (host Python >= 3.9).

describe() loads installed provider data; inspect(root) is read-only;
acquire(root, offline=False) explicitly mutates. All return JSON-compatible
objects; inspect/acquire return {interpreter, receipt}. Errors carry CLI status:
2 invalid pin/platform/path/arguments, 3 missing or unready, 4 archive/network,
5 writer contention, 6 runtime probe. Inject probe(interpreter, pin) in fixtures.

Internal shell entry (P is the installed .../hardcaml_asic/flow directory):
  entry='import sys; sys.path.insert(0, sys.argv.pop(1)); from hardcaml_asic_flow.managed_python import main; sys.exit(main())'
  hostpython -I -B -c "$entry" "$P" --root "$R" --check
Use --offline for explicit acquisition from verified cache; no flag acquires
online. --describe needs no root. No provisioning selection is performed here.
The receipt is the publication marker, written only after the final probe.
New acquisition shares a 180-second budget across download, validation and probes;
individual network reads/connects are capped at 20 seconds, probes at 30 seconds.
"""

import argparse
from collections import deque
import contextlib
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

from . import paths

try:
    import fcntl
except ImportError:  # Unsupported hosts must still get the platform diagnostic.
    fcntl = None

COMPRESSED_CAP = 64 * 1024 * 1024
EXTRACTED_CAP = 512 * 1024 * 1024
MEMBER_CAP = 50000
DEADLINE = 180
IO_TIMEOUT = 20
PROBE_TIMEOUT = 30
REDIRECT_HOSTS = frozenset(("github.com", "release-assets.githubusercontent.com",
                            "objects.githubusercontent.com"))


class Error(Exception):
    def __init__(self, message, status=2):
        super().__init__(message)
        self.status = status


def _url(url):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in REDIRECT_HOSTS
            or parsed.username or parsed.password or parsed.port not in (None, 443)
            or parsed.fragment):
        raise Error("archive URL/redirect must use HTTPS official GitHub release infrastructure", 4)
    return url


def describe():
    """Load the package's pin and enforce its relation to the shipped lock."""
    try:
        pin = json.loads(paths.require(paths.MANAGED_PYTHON, "managed Python pin").read_text())
        lock = dict(line.split("=", 1) for line in
                    paths.require(paths.TOOLCHAIN_LOCK, "toolchain lock").read_text().splitlines()
                    if line and not line.startswith("#"))
        if (pin["schema"] != 1 or not re.fullmatch(r"3\.11\.\d+", pin["version"])
                or ".".join(pin["version"].split(".")[:2]) != lock["python"]
                or not re.fullmatch(r"\d{8}", pin["build"])
                or pin["target"] != "x86_64-unknown-linux-gnu"
                or pin["flavor"] != "install_only_stripped"
                or type(pin["size"]) is not int or not 0 < pin["size"] <= COMPRESSED_CAP
                or not re.fullmatch(r"[0-9a-f]{64}", pin["sha256"])):
            raise ValueError("invalid pin or Python major.minor differs from toolchain.lock")
        filename = ("cpython-" + pin["version"] + "%2B" + pin["build"] + "-"
                    + pin["target"] + "-" + pin["flavor"] + ".tar.gz")
        expected = ("https://github.com/astral-sh/python-build-standalone/releases/download/"
                    + pin["build"] + "/" + filename)
        if pin["url"] != expected:
            raise ValueError("pin URL does not match official artifact identity")
        _url(pin["url"])
        return pin
    except (OSError, ValueError, KeyError, TypeError, paths.MissingRuntimeData) as exc:
        raise Error("invalid installed managed Python data: " + str(exc)) from exc


def _platform():
    libc, version = platform.libc_ver()
    try:
        supported = (platform.system() == "Linux" and platform.machine() == "x86_64"
                     and libc == "glibc" and tuple(map(int, version.split("."))) >= (2, 17))
    except ValueError:
        supported = False
    if not supported:
        raise Error("managed Python supports Linux glibc x86_64 >= 2.17 only; "
                    "use the provisioning --python external override")


def _layout(root, pin):
    root = Path(os.path.abspath(root))
    identity = ("cpython-" + pin["version"] + "-" + pin["build"] + "-"
                + pin["target"] + "-" + pin["flavor"] + "-" + pin["sha256"])
    base = root / "python"
    generation = base / identity
    return base, generation, generation / "python/bin/python3.11"


def _safe_path(path, directory=False):
    """Reject symlinks and unexpected existing ancestors, without resolving them."""
    path = Path(path)
    for item in reversed((path,) + tuple(path.parents)):
        try:
            mode = item.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode) or (item != path or directory) and not stat.S_ISDIR(mode):
            raise Error("unexpected/symlink managed path: " + str(item))
        if item == path and not directory and not stat.S_ISREG(mode):
            raise Error("expected regular managed file: " + str(item))


def child_env():
    """Local probe environment; never export changes to the caller."""
    excluded = {"PYTHONHOME", "PYTHONPATH", "TCL_LIBRARY", "TK_LIBRARY", "TCLLIBPATH",
                "LD_LIBRARY_PATH", "LD_PRELOAD", "LD_AUDIT", "LD_DEBUG",
                "LD_DEBUG_OUTPUT", "LD_PROFILE", "GCONV_PATH", "GLIBC_TUNABLES"}
    env = {key: value for key, value in os.environ.items()
           if key not in excluded and not key.startswith(("DYLD_", "LD_"))}
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


PROBE_CODE = r'''
import json, sys, ssl, venv, ensurepip, tkinter, _tkinter
t = tkinter.Tcl()
assert t.eval('expr {6 * 7}') == '42'
print(json.dumps(dict(version='.'.join(map(str, sys.version_info[:3])),
    executable=sys.executable, base_prefix=sys.base_prefix,
    tcl_patchlevel=t.eval('info patchlevel'), tcl_library=t.eval('info library'))))
'''


def runtime_probe(interpreter, pin, *, deadline=None):
    try:
        timeout = PROBE_TIMEOUT
        if deadline is not None:
            _remaining(deadline)
            timeout = min(timeout, deadline - time.monotonic())
        completed = subprocess.run([str(interpreter), "-I", "-B", "-c", PROBE_CODE],
                                   env=child_env(), capture_output=True, text=True,
                                   timeout=timeout, check=True)
        return json.loads(completed.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        raise Error("managed Python runtime probe failed: " + str(exc), 6) from exc


def _probe(interpreter, pin, probe, deadline=None):
    runtime = interpreter.parent.parent
    # Executable aliases within the verified archive are allowed.
    try:
        if not interpreter.is_file() or not os.access(interpreter, os.X_OK):
            raise ValueError("missing executable")
        interpreter.resolve().relative_to(runtime.resolve())
        if deadline is not None:
            _remaining(deadline)
        result = (runtime_probe(interpreter, pin, deadline=deadline)
                  if probe is runtime_probe else probe(interpreter, pin))
        if deadline is not None:
            _remaining(deadline)
        if result["version"] != pin["version"]:
            raise ValueError("Python patch version mismatch")
        if Path(result["base_prefix"]).resolve() != runtime.resolve():
            raise ValueError("sys.base_prefix is outside this runtime")
        if Path(result["executable"]).resolve() != interpreter.resolve():
            raise ValueError("sys.executable mismatch")
        resource = Path(result["tcl_library"])
        resource.resolve().relative_to(runtime.resolve())
        if not resource.is_dir() or not result["tcl_patchlevel"]:
            raise ValueError("missing Tcl resources/patchlevel")
        return result
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise Error("managed Python readiness failed: " + str(exc), 6) from exc


def inspect(root, *, probe=runtime_probe):
    """Read-only readiness check; no cache, lock, directories or receipts created."""
    pin = describe()
    _platform()
    base, generation, interpreter = _layout(root, pin)
    _safe_path(generation, directory=True)
    marker = generation / "receipt.json"
    _safe_path(marker)
    try:
        receipt = json.loads(marker.read_text())
    except (OSError, ValueError) as exc:
        raise Error("managed Python receipt missing/invalid; acquire this exact artifact: "
                    + str(marker), 3) from exc
    if (not isinstance(receipt, dict) or receipt.get("schema") != 1 or receipt.get("pin") != pin
            or receipt.get("interpreter") != str(interpreter)):
        raise Error("managed Python receipt does not match installed pin/path", 3)
    _safe_path(generation / "python", directory=True)
    _safe_path(interpreter.parent, directory=True)
    _probe(interpreter, pin, probe)
    return {"interpreter": str(interpreter), "receipt": receipt}


class _Redirects(urllib.request.HTTPRedirectHandler):
    def __init__(self, deadline):
        self.deadline = deadline

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        req.timeout = _remaining(self.deadline)
        _url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _remaining(deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise Error("archive acquisition deadline exceeded", 4)
    return min(IO_TIMEOUT, remaining)


def _download(pin, output, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + DEADLINE
    opener = urllib.request.build_opener(_Redirects(deadline))
    try:
        with opener.open(_url(pin["url"]), timeout=_remaining(deadline)) as response:
            _url(response.geturl())
            length = response.headers.get("Content-Length")
            if length is not None and int(length) != pin["size"]:
                raise Error("archive Content-Length differs from pin", 4)
            total = 0
            while True:
                timeout = _remaining(deadline)
                if response.isclosed():
                    break
                # HTTPResponse.read1 performs at most one underlying read. Set the
                # socket timeout each iteration, including the remaining deadline.
                response.fp.raw._sock.settimeout(timeout)
                chunk = response.read1(min(65536, pin["size"] + 1 - total))
                _remaining(deadline)
                if not chunk:
                    break
                total += len(chunk)
                if total > pin["size"] or total > COMPRESSED_CAP:
                    raise Error("archive compressed size exceeds pin/cap", 4)
                output.write(chunk)
            if total != pin["size"]:
                raise Error("archive download truncated", 4)
    except (OSError, ValueError, urllib.error.URLError) as exc:
        raise Error("archive download failed: " + str(exc), 4) from exc


def _verify(archive, pin, deadline=None):
    _safe_path(archive)
    try:
        if archive.stat().st_size != pin["size"] or pin["size"] > COMPRESSED_CAP:
            raise Error("cached archive size mismatch; remove only this cache file explicitly", 4)
        digest = hashlib.sha256()
        total = 0
        with archive.open("rb") as source:
            for chunk in iter(lambda: source.read(65536), b""):
                if deadline is not None:
                    _remaining(deadline)
                total += len(chunk)
                if total > pin["size"] or total > COMPRESSED_CAP:
                    raise Error("cached archive grew beyond compressed size bound", 4)
                digest.update(chunk)
        if total != pin["size"] or digest.hexdigest() != pin["sha256"]:
            raise Error("cached archive SHA256 mismatch; remove only this cache file explicitly", 4)
    except OSError as exc:
        raise Error("cannot verify archive: " + str(exc), 4) from exc


def _name(name):
    if (not name or len(name) > 4096 or name.count("/") > 256
            or name.startswith("/") or "\\" in name
            or ".." in name.split("/") or "\x00" in name):
        raise Error("unsafe archive path: " + repr(name), 4)
    name = posixpath.normpath(name)
    if name != "python" and not name.startswith("python/"):
        raise Error("archive must have only python/ root", 4)
    return name


def _members(tar, deadline=None):
    entries = {}
    size = 0
    for member in tar:
        if deadline is not None:
            _remaining(deadline)
        name = _name(member.name)
        size += member.size
        if len(entries) >= MEMBER_CAP or size > EXTRACTED_CAP or member.size < 0:
            raise Error("archive member/extracted size bound exceeded", 4)
        if (name in entries or member.mode & 0o7000 or member.sparse is not None
                or any(key.startswith("GNU.sparse") for key in member.pax_headers)
                or not (member.isdir() or member.isfile() or member.issym() or member.islnk())):
            raise Error("archive duplicate/special/sparse/privileged member: " + name, 4)
        if name == "python" and not member.isdir():
            raise Error("archive python root must be a directory", 4)
        entries[name] = member
    # Include implicit directories, then reject all non-directory parents. This
    # prohibits writes through links even when their resolved target is safe.
    for name in list(entries):
        parent = posixpath.dirname(name)
        while parent:
            if parent in entries and not entries[parent].isdir():
                raise Error("archive parent collision/link: " + parent, 4)
            if parent not in entries:
                if len(entries) >= MEMBER_CAP:
                    raise Error("archive implicit directory/member bound exceeded", 4)
                entries[parent] = tarfile.TarInfo(parent)
                entries[parent].type = tarfile.DIRTYPE
                entries[parent].mode = 0o755
            parent = posixpath.dirname(parent)

    def resolve(name, seen):
        # Walk actual path components. Collapsing '..' before expanding symlinks
        # would incorrectly accept targets such as link-to-dir/../missing.
        pending = deque(name.split("/"))
        resolved = []
        while pending:
            if deadline is not None:
                _remaining(deadline)
            part = pending.popleft()
            if part in ("", "."):
                continue
            if part == "..":
                if len(resolved) <= 1:
                    raise Error("archive link escapes python root", 4)
                resolved.pop()
                continue
            prefix = _name("/".join(resolved + [part]))
            member = entries.get(prefix)
            if member is None:
                raise Error("archive broken link: " + name, 4)
            if member.issym() or member.islnk():
                if prefix in seen or len(seen) >= 40:
                    raise Error("archive link cycle/too many link resolutions", 4)
                seen.add(prefix)
                target = member.linkname
                if (not target or target.startswith("/") or "\\" in target or "\x00" in target
                        or len(target) > 4096 or target.count("/") > 256):
                    raise Error("archive absolute/invalid link", 4)
                if member.islnk():
                    resolved = []  # tar hardlinks are archive-root-relative
                pending.extendleft(reversed(target.split("/")))
            else:
                if pending and not member.isdir():
                    raise Error("archive link target parent is not a directory", 4)
                resolved.append(part)
        return "/".join(resolved)

    targets = {}
    for name, member in entries.items():
        if member.issym() or member.islnk():
            targets[name] = resolve(name, set())
            if member.islnk() and not entries[targets[name]].isfile():
                raise Error("archive hardlink must resolve to a regular file", 4)
    return entries, targets


def _extract(archive, stage, deadline=None):
    # Bound *all* decompressed tar bytes, including padding/extended headers, not
    # only member payloads. Spool privately before tarfile parses any metadata.
    try:
        with tempfile.TemporaryFile(dir=stage) as spool:
            total = 0
            with gzip.open(archive, "rb") as source:
                while True:
                    if deadline is not None:
                        _remaining(deadline)
                    chunk = source.read(min(65536, EXTRACTED_CAP + 1 - total))
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > EXTRACTED_CAP:
                        raise Error("archive decompressed size bound exceeded", 4)
                    spool.write(chunk)
            spool.seek(0)
            with tarfile.open(fileobj=spool, mode="r:") as tar:
                entries, targets = _members(tar, deadline)  # entire set before writes
                for name, member in sorted(entries.items(), key=lambda pair: pair[0].count("/")):
                    if deadline is not None:
                        _remaining(deadline)
                    destination = stage / name
                    if member.isdir():
                        destination.mkdir(mode=0o755)
                    elif member.isfile():
                        with tar.extractfile(member) as source, destination.open("xb") as output:
                            for chunk in iter(lambda: source.read(65536), b""):
                                if deadline is not None:
                                    _remaining(deadline)
                                output.write(chunk)
                        destination.chmod(member.mode & 0o777)
                for name, target in targets.items():
                    if deadline is not None:
                        _remaining(deadline)
                    member = entries[name]
                    if member.islnk():
                        os.link(stage / target, stage / name)
                    else:
                        os.symlink(member.linkname, stage / name)
    except (OSError, EOFError, tarfile.TarError) as exc:
        raise Error("invalid managed Python archive: " + str(exc), 4) from exc


@contextlib.contextmanager
def _writer(base):
    lock = base / ".writer.lock"
    _safe_path(lock)
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise Error("writer lock is not a regular file")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise Error("managed Python writer busy; retry after acquisition completes", 5) from exc
        yield
    finally:
        os.close(fd)


def _publish_generation(stage, generation):
    """Linux atomic rename-without-replacement, including empty user directories.

    Our sole supported target is x86_64 Linux; syscall 316 is renameat2 there.
    Using the syscall also supports glibc 2.17, before its named wrapper existed.
    An older kernel lacking it fails explicitly rather than using clobbering rename.
    """
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    result = libc.syscall(ctypes.c_long(316), ctypes.c_int(-100),
                          ctypes.c_char_p(os.fsencode(stage)), ctypes.c_int(-100),
                          ctypes.c_char_p(os.fsencode(generation)), ctypes.c_uint(1))
    if result != 0:
        error = ctypes.get_errno()
        raise Error("cannot publish absent managed generation (no replacement): "
                    + os.strerror(error))


def acquire(root, *, offline=False, probe=runtime_probe):
    """Acquire only this pin; retain generations and refuse occupied destinations."""
    pin = describe()
    _platform()
    base, generation, interpreter = _layout(root, pin)
    _safe_path(base, directory=True)
    _safe_path(generation, directory=True)
    if generation.exists():
        return inspect(root, probe=probe)
    deadline = time.monotonic() + DEADLINE
    base.mkdir(parents=True, exist_ok=True)
    with _writer(base):
        if generation.exists():
            return inspect(root, probe=probe)
        cache_dir = base / ".cache"
        _safe_path(cache_dir, directory=True)
        cache = cache_dir / (pin["sha256"] + ".tar.gz")
        _safe_path(cache)
        if not cache.exists():
            if offline:
                raise Error("offline managed Python archive cache miss: " + str(cache), 4)
            cache_dir.mkdir(exist_ok=True)
            fd, partial = tempfile.mkstemp(prefix=".partial-", dir=cache_dir)
            partial = Path(partial)
            try:
                with os.fdopen(fd, "wb") as output:
                    _download(pin, output, deadline)
                _verify(partial, pin, deadline)
                # No clobber, even if another actor ignored our writer lock.
                os.link(partial, cache)
            finally:
                partial.unlink()
        _verify(cache, pin, deadline)  # before extraction or interpreter execution
        stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=base))
        try:
            _extract(cache, stage, deadline)
            _probe(stage / "python/bin/python3.11", pin, probe, deadline)
            if generation.exists() or generation.is_symlink():
                raise Error("managed Python destination appeared during acquisition")
            _publish_generation(stage, generation)
            result = _probe(interpreter, pin, probe, deadline)
            receipt = {"schema": 1, "pin": pin, "interpreter": str(interpreter), "probe": result}
            # Owned generation has no receipt until the relocated probe succeeds.
            marker = generation / "receipt.json"
            temporary = generation / ".receipt.pending"
            with temporary.open("x") as output:
                json.dump(receipt, output, sort_keys=True, indent=2)
                output.write("\n")
            os.rename(temporary, marker)
            return {"interpreter": str(interpreter), "receipt": receipt}
        finally:
            if stage.exists():
                shutil.rmtree(stage)  # only our unique private stage, never a generation


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--offline", action="store_true")
    modes.add_argument("--describe", action="store_true")
    args = parser.parse_args(argv)
    if not args.describe and not args.root:
        parser.error("--root is required for inspection/acquisition")
    try:
        result = (describe() if args.describe else inspect(args.root) if args.check
                  else acquire(args.root, offline=args.offline))
        print(json.dumps(result, sort_keys=True))
        return 0
    except Error as exc:
        print(str(exc), file=sys.stderr)
        return exc.status
    except OSError as exc:
        print("managed Python filesystem operation failed: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
