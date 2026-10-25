"""Actual typed consumer and public inspector; PDK/EDA-free durable acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile


def main(consumer, public):
    env = dict(os.environ, PATH='/no-tools', PYTHONDONTWRITEBYTECODE='1')
    def invoke(argv, code=0, execution=False):
        r = subprocess.run(argv, env=os.environ if execution else env, text=True, capture_output=True, timeout=40)
        assert r.returncode == code, (argv, r.returncode, r.stdout, r.stderr)
        return r
    caps = json.loads(invoke([public, '--version', '--json']).stdout)['cli_contract']['capabilities']
    assert caps['preparation1'] and 'preparation-inspect' in caps['json_commands']
    # A observes Git context read-only; place fixtures beneath the existing
    # checkout rather than creating/mutating a temporary Git repository.
    with tempfile.TemporaryDirectory(prefix='asic-preparation-', dir=os.getcwd()) as tmp:
        root = Path(tmp)
        source = root / 'source'
        source.mkdir()
        (source / 'design.ml').write_text('declared source fixture\n')
        store = root / 'operations'
        def launch(mode, code=0):
            r = invoke([consumer, mode, str(store), str(source)], code, execution=True)
            if mode in ('terminal-fail', 'terminal-corrupt', 'snapshot-fail', 'snapshot-mutate', 'publication-cancel', 'phase-order'):
                return Path(r.stdout.strip()), None
            lines = [json.loads(s) for s in r.stdout.splitlines()]
            assert len(lines) == 2 and lines[0]['event'] == 'allocated' and lines[1]['event'] == 'terminal'
            assert lines[0]['attempt'] == lines[1]['attempt']
            return Path(lines[0]['attempt']), lines[1]['record']
        def inspect(path, current=None, code=0, human=False):
            args = [public, 'preparation-inspect', str(path)]
            if not human:
                args += ['--json']
            if current is not None:
                args += ['--current-identity', current]
            r = invoke(args, code)
            return json.loads(r.stdout) if code == 0 and not human else r
        good, record = launch('flops')
        assert record['status'] == 'completed'
        descriptor = record['operation']
        assert descriptor['schema_version'] == 2
        assert descriptor['phases'][5:8] == ['circuit', 'snapshot', 'source_after']
        phase_order, _ = launch('phase-order')
        assert inspect(phase_order)['operation']['status'] == 'completed'
        snapshot = (good / 'resources.json').read_bytes()
        assert record['snapshot']['sha256'] == hashlib.sha256(snapshot).hexdigest()
        view = inspect(good)
        identity = view['preparation']['identity']
        assert view['comparison']['state'] == 'not_requested'
        assert inspect(good, identity)['comparison']['state'] == 'matches'
        assert inspect(good, '0'*64)['comparison']['state'] == 'differs'
        assert 'program' in inspect(good, human=True).stdout
        human = invoke([consumer, 'flops', str(store), str(source), '--human'], execution=True)
        assert 'Resource' in human.stdout and 'program' in human.stdout and 'completed' in human.stdout
        second, _ = launch('flops')
        assert second != good and (second / 'resources.json').read_bytes() == snapshot
        empty, _ = launch('empty')
        assert inspect(empty)['preparation'] is not None
        for mode in ('construct-fail', 'reject', 'invalid-result', 'invalid-source', 'malformed-failure'):
            failed, rec = launch(mode, 1)
            assert rec['status'] == 'failed' and rec['snapshot'] is None and rec['diagnostic']
            failed_view = inspect(failed, identity)
            assert failed_view['preparation'] is None and failed_view['comparison']['state'] == 'unavailable'
            assert not (failed / 'resources.json').exists()
            if mode == 'malformed-failure':
                assert rec['diagnostic']['code'] == 'preparation_exception'
                assert rec['diagnostic']['detail'] is None
        # Initial allocation is delivered while the constructor is still blocked.
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
            proc = subprocess.Popen([consumer, 'wait', str(store), str(source)], env=os.environ,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            allocated = json.loads(proc.stdout.readline())
            attempt = Path(allocated['attempt'])
            assert json.loads((attempt/'operation.json').read_text())['status'] == 'running'
            proc.send_signal(sig)
            out, err = proc.communicate(timeout=40)
            if sig == signal.SIGKILL:
                assert proc.returncode == -sig and not out
                assert inspect(attempt)['operation']['status'] == 'running'
            else:
                assert proc.returncode == 128+sig, (out, err)
                assert inspect(attempt)['operation']['status'] == 'interrupted'
        # Actual external child signals at both sides of the terminal cutoff.
        # The save hook announces entry while signals are blocked, before write.
        for mode in ('precutoff-window', 'commit-window', 'commit-default-window'):
            for sig in (signal.SIGINT, signal.SIGTERM):
                proc = subprocess.Popen([consumer, mode, str(store), str(source)], env=os.environ,
                                        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                attempt = Path(proc.stdout.readline().strip())
                marker = proc.stdout.readline().strip()
                assert marker == ('before-cutoff' if mode == 'precutoff-window' else 'commit')
                assert json.loads((attempt/'operation.json').read_text())['status'] == 'running'
                proc.send_signal(sig)
                out, err = proc.communicate(timeout=5)
                expected = 128+sig if mode == 'precutoff-window' else -sig if mode == 'commit-default-window' else 0
                assert proc.returncode == expected, (mode, sig, proc.returncode, out, err)
                # Custom commit handler must run exactly once (fixture asserts),
                # default handler terminates AFTER verified terminal publication.
                assert inspect(attempt)['operation']['status'] == ('interrupted' if mode == 'precutoff-window' else 'completed')
        terminal_failed, _ = launch('terminal-fail', 2)
        assert (terminal_failed/'resources.json').exists()
        v = inspect(terminal_failed, identity)
        assert v['operation']['status'] == 'running' and v['preparation'] is None
        corrupted_terminal, _ = launch('terminal-corrupt', 2)
        assert (corrupted_terminal/'operation.json').read_text() == '{}\n'
        inspect(corrupted_terminal, code=2)
        snapshot_failed, _ = launch('snapshot-fail', 1)
        assert inspect(snapshot_failed)['operation']['status'] == 'failed'
        mutated, _ = launch('snapshot-mutate', 1)
        assert inspect(mutated)['operation']['status'] == 'failed'
        cancelled, _ = launch('publication-cancel', 143)
        assert (cancelled/'resources.json').exists()
        assert inspect(cancelled)['operation']['status'] == 'interrupted'
        # Exact historical descriptor v1 remains readable without normalizing or
        # rewriting its originally advertised phase order. Arbitrary variants fail.
        legacy = root/'legacy-v1'
        shutil.copytree(good, legacy)
        legacy_record = json.loads((legacy/'operation.json').read_text())
        legacy_record['operation']['schema_version'] = 1
        phases = legacy_record['operation']['phases']
        phases[6:8] = ['source_after', 'snapshot']
        legacy_bytes = json.dumps(legacy_record).encode()
        (legacy/'operation.json').write_bytes(legacy_bytes)
        assert inspect(legacy)['operation'] == legacy_record
        assert (legacy/'operation.json').read_bytes() == legacy_bytes
        for version, order in [(3, phases), (2, phases), (1, descriptor['phases'])]:
            changed = json.loads(legacy_bytes)
            changed['operation'].update(schema_version=version, phases=order)
            (legacy/'operation.json').write_text(json.dumps(changed))
            inspect(legacy, code=2)
        (legacy/'operation.json').write_bytes(legacy_bytes)
        # Evidence policy: leaf symlinks and all nonregular files are rejected,
        # with bounded subprocess deadlines so a FIFO regression fails quickly.
        for filename in ('operation.json', 'resources.json'):
            for kind in ('symlink', 'fifo', 'directory', 'oversized'):
                attempt = root/f'{kind}-{filename}'
                shutil.copytree(good, attempt)
                path = attempt/filename
                path.unlink()
                if kind == 'symlink':
                    path.symlink_to(good/filename)
                elif kind == 'fifo':
                    os.mkfifo(path)
                elif kind == 'directory':
                    path.mkdir()
                else:
                    with path.open('wb') as output:
                        output.truncate((4 if filename == 'operation.json' else 64)*1024*1024+1)
                r = subprocess.run([public, 'preparation-inspect', str(attempt), '--json'],
                                   env=env, text=True, capture_output=True, timeout=3)
                assert r.returncode == 2 and not r.stdout, (filename, kind, r)
        for kind in ('fifo', 'symlink'):
            leaf = root/f'open-race-{kind}'
            leaf.write_text('regular at lstat\n')
            r = subprocess.run([consumer, f'open-race-{kind}', str(leaf), str(good/'operation.json')],
                               env=env, text=True, capture_output=True, timeout=3)
            assert r.returncode == 2 and not r.stdout, (kind, r)
        # Reader independence and nonmutation, including explicit comparison.
        (source/'design.ml').unlink()
        source.rmdir()
        before = {p: p.read_bytes() for p in store.rglob('*') if p.is_file()}
        assert inspect(good, identity)['comparison']['state'] == 'matches'
        assert before == {p: p.read_bytes() for p in store.rglob('*') if p.is_file()}
        inspect(good, 'BAD', 2)
        operation_path = good/'operation.json'
        original = operation_path.read_bytes()
        malformed = json.loads(original)
        malformed['status'] = 'failed'
        operation_path.write_text(json.dumps(malformed))
        inspect(good, code=2)
        operation_path.write_bytes(original)
        for key, value in [('phase', 'synthesis'), ('schema_version', 99),
                           ('exit_code', 1), ('ended_at', None),
                           ('started_at', '2026-02-30T00:00:00Z'), ('extra', True)]:
            malformed = json.loads(original)
            malformed[key] = value
            operation_path.write_text(json.dumps(malformed))
            inspect(good, code=2)
        operation_path.write_bytes(original)
        operation_path.write_bytes(original.rstrip()[:-1]+b',"status":"completed"}')
        inspect(good, code=2)
        operation_path.write_bytes(original)
        (good/'resources.json').write_bytes(snapshot+b' ')
        inspect(good, code=2)
        # Even if the byte digest is updated, A's content identity remains authoritative.
        changed = json.loads(snapshot)
        changed['identity'] = '0'*64
        data = json.dumps(changed).encode()
        (good/'resources.json').write_bytes(data)
        malformed = json.loads(original)
        malformed['snapshot'].update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
        operation_path.write_text(json.dumps(malformed))
        inspect(good, code=2)
    print('preparation: typed launch, public inspection, failures, integrity, signals and publication checks passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--consumer', required=True)
    parser.add_argument('--public', required=True)
    args = parser.parse_args()
    main(args.consumer, args.public)
