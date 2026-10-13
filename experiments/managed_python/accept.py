"""Opt-in real acceptance. Run with host python -I -B; never a Dune test.

Only the managed Python root and a unique ignored example .dev directory mutate.
No support tools, PDK, containers, or physical flow are acquired or invoked.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

ENTRY = "import sys; sys.path.insert(0, sys.argv.pop(1)); from hardcaml_asic_flow.managed_python import main; sys.exit(main())"
VENV_PROBE = r'''
import json, sys, ssl, venv, ensurepip, tkinter, _tkinter
from pathlib import Path
t = tkinter.Tcl()
assert sys.prefix != sys.base_prefix
assert sys.version_info[:3] == (3, 11, 17)
assert t.eval('expr {6 * 7}') == '42'
Path(t.eval('info library')).resolve().relative_to(Path(sys.base_prefix).resolve())
print(json.dumps(dict(executable=sys.executable, prefix=sys.prefix,
    base_prefix=sys.base_prefix, version=sys.version, ssl=ssl.OPENSSL_VERSION,
    ensurepip=ensurepip.version(), tcl=t.eval('info patchlevel'),
    tcl_library=t.eval('info library'), tk=_tkinter.TK_VERSION)))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--example', required=True, type=Path)
    parser.add_argument('--acquire-and-install', required=True, action='store_true')
    args = parser.parse_args()
    provider = Path(__file__).resolve().parents[2]
    source = provider / 'flow'
    root = args.example.absolute() / '_flow_tools'
    parent = args.example.absolute() / '.dev' / 'managed-python-acceptance'
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='real-', dir=parent))
    print('Acceptance directory: ' + str(work), flush=True)
    sys.path.insert(0, str(source))
    from hardcaml_asic_flow import managed_python as mp
    env = mp.child_env()
    env.update(PIP_CONFIG_FILE=os.devnull, PIP_DISABLE_PIP_VERSION_CHECK='1')
    evidence = dict(scope='SYNTHETIC Tcl smoke only; no precheck or physical-flow readiness',
                    work=str(work), root=str(root), host_python=sys.version,
                    host_executable=sys.executable, platform=platform.platform(),
                    commands=[], pin=mp.describe())

    def run(name, command, timeout):
        evidence['commands'].append(dict(name=name, argv=list(map(str, command)), timeout=timeout))
        result = subprocess.run(list(map(str, command)), env=env, capture_output=True,
                                text=True, timeout=timeout)
        (work / (name + '.stdout.log')).write_text(result.stdout)
        (work / (name + '.stderr.log')).write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f'{name} exited {result.returncode}: {result.stderr[-4000:]}')
        return result.stdout

    def snapshot():
        result = {}
        for path in [root, *sorted(root.rglob('*'))]:
            s = path.lstat()
            result[str(path.relative_to(root))] = [s.st_mode, s.st_ino, s.st_dev,
                s.st_nlink, s.st_uid, s.st_gid, s.st_size, s.st_mtime_ns, s.st_ctime_ns]
        return result

    try:
        acquired = json.loads(run('acquire', [sys.executable, '-I', '-B', '-c', ENTRY,
                                     source, '--root', root], 240))
        evidence['acquisition'] = acquired
        interpreter = acquired['interpreter']
        receipt = Path(interpreter).parents[2] / 'receipt.json'
        evidence['receipt_path'] = str(receipt)
        evidence['receipt_sha256'] = hashlib.sha256(receipt.read_bytes()).hexdigest()
        cache = root / 'python' / '.cache' / (mp.describe()['sha256'] + '.tar.gz')
        evidence['archive_size'] = cache.stat().st_size
        evidence['archive_sha256'] = hashlib.sha256(cache.read_bytes()).hexdigest()
        before = snapshot()
        # Audit denies even attempted networking in inspect/offline and their probes.
        # Child probes are fixed -I -B stdlib-only code, with no networking calls.
        def no_network(event, values):
            if event in ('socket.connect', 'socket.getaddrinfo', 'socket.bind'):
                raise RuntimeError('network forbidden during inspect/offline: ' + event)
        sys.addaudithook(no_network)
        assert mp.inspect(root) == acquired
        after_inspect = snapshot()
        assert before == after_inspect, 'inspect mutated metadata (excluding atime)'
        assert mp.acquire(root, offline=True) == acquired
        assert before == snapshot(), 'offline reuse mutated metadata (excluding atime)'
        evidence['readonly'] = dict(inspect=True, offline_reuse=True,
                                   metadata_entries=len(before), excludes='atime', network='audit denied')
        (work / 'metadata-before.json').write_text(json.dumps(before, indent=2))
        (work / 'metadata-after.json').write_text(json.dumps(after_inspect, indent=2))
        evidence['venvs'] = []
        for name in ('precheck-smoke', 'librelane-smoke'):
            directory = work / name
            run('create-' + name, [interpreter, '-I', '-B', '-m', 'venv', directory], 120)
            python = directory / 'bin' / 'python'
            probe = json.loads(run('probe-' + name, [python, '-I', '-B', '-c', VENV_PROBE], 30))
            probe['literal_interpreter'] = str(python)
            evidence['venvs'].append(probe)
        python = work / 'librelane-smoke' / 'bin' / 'python'
        run('pip-install', [python, '-I', '-B', '-m', 'pip', '--isolated',
            '--disable-pip-version-check', '--no-input', '--cache-dir', work / 'pip-cache',
            'install', '--only-binary=:all:', '--timeout', '20', '--retries', '1',
            'librelane==3.1.0.dev3'], 300)
        evidence['dependencies'] = json.loads(run('pip-list', [python, '-I', '-B', '-m',
            'pip', '--isolated', '--disable-pip-version-check', 'list', '--format=json'], 30))
        smoke = r'''
import json, importlib.metadata, tkinter, librelane
from librelane.common import TclUtils
assert importlib.metadata.version('librelane') == '3.1.0.dev3'
result = TclUtils._eval_env({'ACCEPTANCE_INPUT': '6'},
    'set ::env(ACCEPTANCE_RESULT) [expr {$::env(ACCEPTANCE_INPUT) * 7}]')
assert result['ACCEPTANCE_RESULT'] == '42', result
print(json.dumps(dict(version=importlib.metadata.version('librelane'),
    tcl=tkinter.Tcl().eval('info patchlevel'), result=result,
    scope='SYNTHETIC authored environment expression; no config/probe/physical flow')))
'''
        evidence['librelane'] = json.loads(run('librelane-tcl-smoke',
            [python, '-I', '-B', '-c', smoke], 30))
        evidence['success'] = True
        target = provider / 'evidence' / 'managed-python' / 'actual-runtime.json'
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            target.write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')
            print('Success; provider evidence: ' + str(target), flush=True)
        else:
            print('Success; repeat evidence: ' + str(work / 'acceptance.json'), flush=True)
    except Exception as exc:
        evidence.update(success=False, blocker=str(exc))
        raise
    finally:
        (work / 'acceptance.json').write_text(json.dumps(evidence, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
