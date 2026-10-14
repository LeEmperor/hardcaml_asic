"""Differential/corruption fixtures for the actual installed archive primitives."""
import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import resource
import shutil
import subprocess
import tarfile
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--consumer", required=True)
    parser.add_argument("--installed-prefix", help="Compile this consumer independently against PREFIX/lib first")
    args = parser.parse_args()
    consumer = str(Path(args.consumer).resolve())
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        if args.installed_prefix:
            source = root / "consumer.ml"
            shutil.copyfile(Path(__file__).with_name("archive_encoding_consumer.ml"), source)
            consumer = str(root / "consumer")
            env = dict(os.environ, OCAMLPATH=str(Path(args.installed_prefix).resolve() / "lib"))
            subprocess.run(["ocamlfind", "ocamlopt", "-package", "hardcaml_asic.execution", "-linkpkg",
                            "-o", consumer, str(source)], cwd=root, env=env, check=True)
        scratch = root / "scratch"
        scratch.mkdir()
        inventory = []
        for name, data in [("manifest.json", b'{}\n'), ("empty", b""),
                           ("binary", bytes(range(256)) * 17),
                           ("sub/" + "a" * 220, b"long"),
                           ("unicode/\u03bb\u96ea\U0001f600", b"utf8"),
                           ("line\nbreak", b"newline")]:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            inventory.append((name, path, digest(data)))
        large = root / "large"
        h = hashlib.sha256()
        block = bytes(range(256)) * 4096
        with large.open("wb") as f:
            for _ in range(192):
                f.write(block)
                h.update(block)
        inventory.append(("large", large, h.hexdigest()))

        def run(mode, output, entries=inventory, ok=True, gzip_path="/usr/bin/gzip", timeout=20):
            cmd = [consumer, mode, gzip_path, str(scratch), str(output), str(timeout)]
            for name, path, sha in entries:
                cmd.extend([name, str(path), sha])
            env = dict(os.environ, GZIP="--invalid-inherited-option", LD_PRELOAD="", OCAMLRUNPARAM="s=64k")
            # A whole-file implementation cannot fit the 192 MiB fixture here.
            def bounded():
                resource.setrlimit(resource.RLIMIT_AS, (128 * 1024**2, 128 * 1024**2))
            result = subprocess.run(cmd, capture_output=True, env=env, preexec_fn=bounded)
            assert (result.returncode == 0) == ok, (cmd, result.stdout, result.stderr)
            assert not list(scratch.iterdir()), list(scratch.iterdir())
            return result

        bundle = root / "input.tar.gz"
        run("bundle", bundle)
        run("verify-input", bundle)
        expected = [("bundle/" + n, p, sha) for n, p, sha in inventory]
        # Consumer stdout is actual hash inventory, not a repeat of expected values.
        verified = run("verify", bundle, expected)
        ordered = [inventory[0]] + sorted(inventory[1:])
        actual_inventory = "".join(f"bundle/{n}\t{p.stat().st_size}\t{sha}\n" for n, p, sha in ordered).encode()
        assert verified.stdout == actual_inventory
        with tarfile.open(bundle, "r:gz") as t:
            assert t.getnames() == ["bundle/manifest.json"] + sorted("bundle/" + n for n, _, _ in inventory[1:])
            for m in t:
                assert m.isfile() and m.mode == 0o644 and m.uid == m.gid == 0
                assert m.mtime == 0 and m.uname == m.gname == ""
                h = hashlib.sha256()
                with t.extractfile(m) as f:
                    while data := f.read(65536):
                        h.update(data)
                assert h.hexdigest() == dict((n, sha) for n, _, sha in expected)[m.name]
        first = bundle.read_bytes()
        for _, path, _ in inventory:
            os.chmod(path, 0o751)
            os.utime(path, (1700000000, 1700000000.125))
        second = root / "second.tar.gz"
        run("bundle", second, [inventory[0]] + list(reversed(inventory[1:])))
        assert second.read_bytes() == first

        reports = root / "reports.tar.gz"
        run("reports", reports, inventory[:3])
        run("verify-reports", reports, inventory[:3])
        run("verify", reports, inventory[:3], ok=False)
        with tarfile.open(reports) as t:
            for m in t:
                assert m.mode == 0o751 and m.mtime == 1700000000.125
                assert m.uid == os.getuid() and m.gid == os.getgid()

        # Python-produced PAX tar is accepted including long/Unicode paths.
        python = root / "python.tar.gz"
        with tarfile.open(python, "w:gz", format=tarfile.PAX_FORMAT) as t:
            for name, path, _ in inventory:
                m = tarfile.TarInfo("bundle/" + name)
                m.mode = 0o644
                m.size = path.stat().st_size
                with path.open("rb") as f:
                    t.addfile(m, f)
        run("verify", python, expected)
        run("verify-input", python, inventory, ok=False)  # same inventory, unsorted Python order

        small = [("bundle/manifest.json", inventory[0][1], inventory[0][2])]
        raw = io.BytesIO()
        with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as t:
            m = tarfile.TarInfo(small[0][0])
            m.mode = 0o644
            m.size = 3
            t.addfile(m, io.BytesIO(b'{}\n'))
        valid = raw.getvalue()

        def reject(label, data, entries=small):
            p = root / (label + ".gz")
            p.write_bytes(gzip.compress(data, mtime=0))
            run("verify", p, entries, ok=False)

        def changed_header(offset, replacement):
            b = bytearray(valid)
            b[offset:offset + len(replacement)] = replacement
            b[148:156] = b"        "
            b[148:156] = f"{sum(b[:512]):06o}\0 ".encode()
            return bytes(b)

        reject("checksum", bytes([valid[0] ^ 1]) + valid[1:])
        reject("tar-truncated", valid[:514])
        reject("one-terminator", valid[:1536])
        reject("padding", valid[:515] + b"X" + valid[516:])
        reject("trailing", valid + b"X")
        reject("partial-zero-block", valid + b"\0")
        reject("hash", valid[:512] + b"bad" + valid[515:])
        reject("duplicate", valid[:1024] * 2 + valid[1024:])
        reject("extra", changed_header(0, b"bundle/extra\0"))
        for kind in b"1234567gLKSD":
            reject("type-" + str(kind), changed_header(156, bytes([kind])))
        reject("negative-size", changed_header(124, b"-0000000001\0"))
        reject("oversize", changed_header(124, b"77777777777\0"))
        reject("bad-mode", changed_header(100, b"0000755\0"))
        reject("bad-uid", changed_header(108, b"0000001\0"))
        reject("bad-gid", changed_header(116, b"0000001\0"))
        reject("bad-time", changed_header(136, b"00000000001\0"))
        reject("bad-uname", changed_header(265, b"someone"))
        reject("bad-gname", changed_header(297, b"group"))
        reject("missing", valid, small + [("bundle/missing", root, "0" * 64)])
        reject("unsafe", changed_header(0, b"../escape\0"))
        for label, data in [("gzip-truncated", first[:-5]),
                            ("gzip-crc", first[:-8] + bytes([first[-8] ^ 1]) + first[-7:]),
                            ("not-gzip", b"bad")]:
            p = root / label
            p.write_bytes(data)
            run("verify", p, expected, ok=False)
        run("verify-small", bundle, expected, ok=False)
        for mode in ("verify-pax", "verify-name", "verify-size", "verify-count"):
            run(mode, bundle, expected, ok=False)
        run("verify", bundle, expected + [expected[0]], ok=False)
        run("verify", bundle, [(expected[0][0], root, "X" * 64)], ok=False)

        def pax_archive(data, kind=tarfile.XHDTYPE):
            m = tarfile.TarInfo("PaxHeader")
            m.type = kind
            m.size = len(data)
            return m.tobuf(format=tarfile.USTAR_FORMAT) + data + b"\0" * (-len(data) % 512) + valid

        def pax_record(key, value):
            body = (key + "=" + value + "\n").encode()
            n = len(body) + 2
            while (next_n := len(str(n)) + 1 + len(body)) != n:
                n = next_n
            return str(n).encode() + b" " + body

        reject("pax-length", pax_archive(b"999 path=x\n"))
        reject("pax-duplicate", pax_archive(pax_record("mtime", "0") * 2))
        reject("pax-unknown", pax_archive(pax_record("GNU.sparse.size", "3")))
        reject("pax-global", pax_archive(pax_record("mtime", "0"), tarfile.XGLTYPE))
        reject("pax-size", pax_archive(pax_record("size", "99999999999999999999999")))
        reject("pax-unsafe", pax_archive(pax_record("path", "../escape")))
        reject("pax-sequence", pax_archive(pax_record("mtime", "0"))[:1024] + pax_archive(pax_record("mtime", "0")))

        changed = root / "changed.tar.gz"
        wrong = [(inventory[0][0], inventory[0][1], "0" * 64)]
        run("bundle", changed, wrong, ok=False)
        assert not changed.exists()
        # Regular-only source contract, including symlink parent components.
        link = root / "symlink"
        link.symlink_to(inventory[0][1])
        run("bundle", changed, [("manifest.json", link, inventory[0][2])], ok=False)
        run("bundle", changed, [("manifest.json", root, inventory[0][2])], ok=False)
        run("bundle", bundle, inventory, ok=False)  # exclusive existing output
        assert bundle.read_bytes() == first
        for name, text, timeout, needle in [
                ("failing-gzip", "#!/bin/sh\nprintf 'fixture-error' >&2\nexit 7\n", 1, b"exit 7"),
                ("slow-gzip", "#!/bin/sh\n/bin/sleep 30\n", .05, b"timeout")]:
            script = root / name
            script.write_text(text)
            script.chmod(0o755)
            result = run("bundle", changed, inventory[:1], ok=False, gzip_path=str(script), timeout=timeout)
            assert needle in result.stderr, result.stderr
            assert not changed.exists()
        result = run("bundle", changed, inventory[:1], ok=False, gzip_path=str(root / "absent"))
        assert b"failed" in result.stderr and not changed.exists()
    print("archive encoding: streaming/interoperability/determinism/corruption/supervisor checks passed")


if __name__ == "__main__":
    main()
