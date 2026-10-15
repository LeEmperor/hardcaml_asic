"""Isolated synthetic host evidence; native CLI/library need no Python or EDA.

Optional --real verifies the supplied workspace's content and metadata before and
after all three read-only queries and prints its actual human preview.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

IMAGE = 'sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a'
STAGES = ['synthesis', 'floorplan', 'placement', 'cts', 'routing', 'signoff']
RESTART = dict(synthesis=['floorplan', 'placement'], floorplan=['placement'],
               placement=['cts'], cts=['routing'], routing=['signoff'], signoff=[])

def canonical(v):
    return json.dumps(v, sort_keys=True, separators=(',', ':'), allow_nan=False)

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def record(p):
    return dict(sha256=digest(p), bytes=p.stat().st_size)

def write(p, v):
    p.write_text(canonical(v))

def snapshot(root):
    return {str(p.relative_to(root)): (digest(p), p.stat().st_size, p.stat().st_mtime_ns)
            for p in root.rglob('*') if p.is_file()}

def fixture(root, boundary='synthesis', metrics=None, run_dir='/missing/retained/run'):
    p = root / boundary
    (p / 'views').mkdir(parents=True)
    host = root / 'host'
    host.write_text('host collateral')
    for v in ['nl', 'json_h', 'odb', 'def']:
        (p / 'views' / v).write_text(v)
    write(p / 'state.json', dict(metrics={}, **{v: str(p / 'views' / v) for v in ['nl', 'json_h', 'odb', 'def']}))
    closure = {str(host): record(host)}
    write(p / 'closure.json', closure)
    write(p / 'resolved.json', {})
    if metrics is None:
        metrics = {'design__instance__count': dict(availability='available', value=673),
                   'design__instance__area': dict(availability='available', value=13041.6048),
                    'unknown_metric': dict(availability='available', value=-1.25),
                    'unknown__count': dict(availability='available', value=-2.5),
                   'design__lint_error__count': dict(availability='unavailable', reason='nonfinite_or_nonnumeric', raw='nan'),
                   'design__lint_warning__count': dict(availability='available', value=2.5),
                   'bool_count': dict(availability='unavailable', reason='nonfinite_or_nonnumeric', raw=True)}
    write(p / 'segment.json', dict(boundary=boundary, metrics=metrics,
        metric_origin='cumulative_final_state; not per-step measurement provenance', run_dir=str(run_dir)))
    m = dict(schema_version=2, location=str(p), boundary=boundary, restart_supported=bool(RESTART[boundary]),
             restart_targets=RESTART[boundary], tested_image_id=IMAGE, closure_scope='path_bound',
             compatibility=dict(target=dict(corner='recorded-context'), binding=dict(image_identity=dict(image_id=IMAGE))),
             files={str(f.relative_to(p)): record(f) for f in p.rglob('*') if f.is_file()},
             external=closure, metrics=metrics, acceptance='not_evaluated')
    m['identity'] = hashlib.sha256(canonical(m).encode()).hexdigest()
    write(p / 'manifest.json', m)
    return dict(path=str(p), identity=m['identity'], boundary=boundary, restart_supported=bool(RESTART[boundary]),
                restart_targets=RESTART[boundary], tested_image_id=IMAGE, closure_scope='path_bound', acceptance='not_evaluated')

def execution(refs=(), stages=('synthesis',), status='completed', schema=3):
    occurrences = [dict(occurrence_id='attempt/implementation.' + s, action_key='implementation.' + s,
                        status='completed', exit_code=0, duration_seconds=11.328, best_effort=False,
                        error=None, verdict=None) for s in stages]
    plan = dict(schema_version=3, stages=list(stages), initial_boundary=None) if schema == 3 else dict(schema_version=2, endpoint=stages[-1], resume=False)
    return dict(attempt_id='attempt', plan=plan, occurrences=occurrences, artifacts=list(refs), status=status,
                exit_code=0 if status in ('completed', 'running') else 130 if status == 'interrupted' else 2)

def suite(cli, consumer, public=None, real=None):
    env = dict(os.environ, PATH='/no-python-no-eda', PYTHONPATH='/unusable', PYTHONDONTWRITEBYTECODE='1')
    def call(p, expected=0, value=True, api=False):
        args = [str(consumer), str(p)] if api else ([str(public), 'report', str(p), '--json'] if public else [str(cli), '--target', str(p), '--json'])
        r = subprocess.run(args, text=True, capture_output=True, env=env, cwd='/tmp', timeout=30)
        assert r.returncode == expected, (args, r.returncode, r.stdout, r.stderr)
        if expected == 2:
            assert not r.stdout and r.stderr, r
            return
        return json.loads(r.stdout) if value else r
    with tempfile.TemporaryDirectory(prefix='stage-report-') as tmp:
        root = Path(tmp)
        ref = fixture(root)
        checkpoint = Path(ref['path'])
        workspace = root / 'workspace'; workspace.mkdir()
        file = workspace / 'execution-a.json'
        original = execution([ref]); write(file, original)
        before = snapshot(root)
        human_args = [str(public), 'report', str(workspace)] if public else [str(cli), '--target', str(workspace)]
        human = subprocess.run(human_args, text=True, capture_output=True, env=env, cwd='/tmp', check=True)
        machine = subprocess.run(human_args + ['--json'], text=True, capture_output=True, env=env, cwd='/tmp', check=True)
        assert human.stdout == machine.stderr and human.stderr == ''
        assert '13,041.6048' in human.stdout and 'YOSYS CELL TYPES' not in human.stdout
        assert 'Mapped cells' in human.stdout and '11.328' in human.stdout and 'boundary snapshot' in human.stdout
        for p in [checkpoint, workspace, file]:
            j = call(p)
            assert j['contract'] == 'hardcaml-asic.report' and j['schema_version'] == 1
            assert 'execution_file' not in j and 'methodology' not in j
            assert j['acceptance'] == j['external_postcheck'] == 'not_evaluated'
            cp = j['checkpoints'][0]
            assert cp['validation']['validation'] == 'host_only' and not cp['validation']['runtime_closure_validated']
            assert cp['metric_origin']['scope'] == 'boundary_snapshot' and cp['supplementary'] == []
            ms = {m['raw_key']: m for m in cp['metrics']}
            assert ms['design__instance__area']['value'] == 13041.6048
            assert ms['unknown_metric']['unit'] is None and ms['unknown_metric']['value'] == -1.25
            assert ms['unknown__count']['availability'] == 'available' and ms['unknown__count']['value'] == -2.5
            for key in ['design__lint_error__count', 'design__lint_warning__count', 'bool_count', 'design__instance_unmapped__count']:
                assert ms[key]['availability'] == 'unavailable' and ms[key]['value'] is None and ms[key]['reason']
            assert ms['bool_count']['source']['raw']['raw'] is True
            assert j == call(p, api=True)
            if p == checkpoint:
                assert j['execution'] is None and j['completion'] == dict(requested=None, physical=None)
            else:
                assert j['execution'] == original and j['completion']['physical'] == 'synthesis'
        assert snapshot(root) == before
        other = workspace / 'execution-b.json'; write(other, original)
        call(workspace, 2); call(file); call(other)
        other.unlink()
        write(workspace / 'run.json', {}); call(workspace, 2); (workspace / 'run.json').unlink()
        write(workspace / 'manifest.json', {}); call(workspace, 2); (workspace / 'manifest.json').unlink()
        for status in ['failed', 'interrupted', 'running']:
            j = execution([], status=status)
            o = j['occurrences'][0]; o.update(status=status, exit_code=None if status == 'running' else j['exit_code'], duration_seconds=0 if status == 'running' else 1)
            write(file, j); assert call(file)['checkpoints'] == []
            o.update(status='unreached', exit_code=None, duration_seconds=0)
            write(file, j); call(workspace)
        # Schema 2 is supported, including pre-invocation validation failures.
        j = execution([], status='failed', schema=2)
        j['occurrences'][0].update(status='unreached', exit_code=None, duration_seconds=0)
        write(file, j); call(file)
        mutations = [lambda j: j.update(status='completed', exit_code=2),
                     lambda j: j['occurrences'][0].update(occurrence_id='other/id'),
                     lambda j: j['occurrences'][0].update(action_key='implementation.signoff'),
                     lambda j: j['occurrences'][0].update(duration_seconds=-1),
                     lambda j: j['occurrences'][0].update(exit_code=None),
                     lambda j: j['artifacts'][0].update(identity='0'*64),
                     lambda j: j['artifacts'][0].update(boundary='signoff'),
                     lambda j: j.update(artifacts=None),
                     lambda j: j.update(artifacts=[]),
                     lambda j: j['occurrences'].append(copy.deepcopy(j['occurrences'][0]))]
        for mutate in mutations:
            j = copy.deepcopy(original); mutate(j); write(file, j); call(workspace, 2)
        file.write_text('{'); call(workspace, 2)
        write(file, original)
        # Hash, complete inventory and host closure errors are query errors.
        view = checkpoint / 'views/nl'; saved = view.read_bytes(); view.write_text('corrupt'); call(file, 2); view.write_bytes(saved)
        segment = checkpoint / 'segment.json'; saved = segment.read_bytes(); segment.write_text('{}'); call(checkpoint, 2); segment.write_bytes(saved)
        extra = checkpoint / 'extra'; extra.write_text('extra'); call(checkpoint, 2); extra.unlink()
        host = root / 'host'; host.write_text('changed'); call(file, 2); host.write_text('host collateral')
        observation = root / 'observation'; observation.mkdir(); write(observation / '000000000001.json', {})
        call(observation, 2)
        # No recursive discovery, including a nested valid checkpoint.
        empty = root / 'empty'; empty.mkdir(); (empty / 'nested').mkdir(); call(empty, 2)
        # Completed signoff publication plus selected occurrence supports physical
        # completion without synthesizing acceptance or outer-run completion.
        refs = [ref] + [fixture(root, s) for s in STAGES[1:]]
        # Capture actual Runner persistence after injected hook errors, before
        # the active occurrence is finalized. The earlier artifact stays usable.
        seed = root / 'runner-seed.json'
        write(seed, execution(refs[:2], STAGES[:2]))
        for event in ['clock', 'started', 'published']:
            for status, code in [('failed', 2), ('interrupted', 130)]:
                result = subprocess.run([str(consumer), '--runner-snapshot', str(seed), event, status],
                    env=env, text=True, capture_output=True, check=True)
                captured = json.loads(result.stdout)
                assert captured['status'] == status and captured['exit_code'] == code
                active = captured['occurrences'][1]
                assert active['status'] == 'running' and active['exit_code'] is None and active['duration_seconds'] == 0
                assert len(captured['artifacts']) == (2 if event == 'published' else 1)
                write(file, captured)
                report = call(file)
                assert report == call(file, api=True)
                assert report['execution'] == captured and report['completion']['physical'] == 'synthesis'
                assert report['acceptance'] == report['external_postcheck'] == 'not_evaluated'
                assert report['checkpoints'][0]['reference'] == ref
                human = call(file, value=False).stderr
                assert f'({status}, exit {code})' in human and 'running' in human and 'not recorded' in human
                mutations = [lambda j: j.update(status='completed', exit_code=0),
                             lambda j: j['occurrences'].reverse(),
                             lambda j: j['occurrences'][0].update(status='running', exit_code=None, duration_seconds=0)]
                if event == 'published':
                    mutations += [lambda j: j['occurrences'][1].update(status='unreached'),
                                  lambda j: j['artifacts'].reverse(),
                                  lambda j: j['artifacts'][1].update(acceptance='accepted')]
                for mutate in mutations:
                    invalid = copy.deepcopy(captured); mutate(invalid)
                    write(file, invalid); call(file, 2)
        # A resumed, one-stage signoff recipe is sufficient physical evidence;
        # reporting does not apply finalization's six-stage selection gate.
        resumed = execution([refs[-1]], ['signoff'])
        resumed['plan']['initial_boundary'] = 'routing'
        write(file, resumed); assert call(file)['completion']['physical'] == 'full'
        # A publication can be persisted while its occurrence still runs.
        publishing = execution([ref], status='running')
        publishing['occurrences'][0].update(status='running', exit_code=None, duration_seconds=0)
        write(file, publishing); assert call(file)['completion']['physical'] is None
        complete = execution(refs, STAGES); write(file, complete)
        assert call(file)['completion']['physical'] == 'full'
        complete.update(status='failed', exit_code=2); write(file, complete)
        assert call(file)['completion']['physical'] == 'full'
        # Supplement comes only from the selected inventoried run_dir. A different
        # retained producer and observations must not rescue absent/bad evidence.
        evidence_root = root / 'supplement'; evidence_root.mkdir()
        producer = evidence_root / 'producer'
        stat = producer / '06-yosys-synthesis/reports/stat.json'
        stat.parent.mkdir(parents=True)
        cp = Path(fixture(evidence_root, run_dir=producer)['path'])
        types = {'cell%02d' % i: 1 for i in range(11)}
        types.update({'dfrbpq': 150, 'tiehi': 150, 'mux2': 128, 'a22oi': 56, 'nor2': 29,
                      'o21ai': 28, 'escaped "\\\nμ': 121})
        stat_value = dict(creator='Yosys synthetic μ', design=dict(num_cells=673,
            num_cells_by_type=types, area=13041.6048, sequential_area=7348.32))
        write(stat, stat_value)
        before = snapshot(evidence_root)
        j = call(cp); assert j == call(cp, api=True) and not j['diagnostics']
        s = j['checkpoints'][0]['supplementary'][0]
        assert s['kind'] == 'yosys_stat' and s['path'] == str(stat) and s['sha256'] == digest(stat)
        assert s['evidence_scope'] == 'retained producer report; not checkpoint-inventoried'
        assert s['tool'] == 'Yosys synthetic μ' and s['mapped_cell_types'] == types
        assert list(s['mapped_cell_types']) == sorted(types)
        assert s['sequential_area'] == dict(value=7348.32, unit='µm²')
        args = [str(public), 'report', str(cp)] if public else [str(cli), '--target', str(cp)]
        human = subprocess.run(args, env=env, text=True, capture_output=True, check=True).stdout
        full = subprocess.run(args + ['--verbose'], env=env, text=True, capture_output=True, check=True).stdout
        assert '18 types; 673 cells total' in human and '7,348.32 µm²' in human
        assert '... 8 more types' in human and 'cell10' not in human
        assert 'cell10' in full and 'more types' not in full and '\\n' in full
        assert snapshot(evidence_root) == before
        raw = stat.read_text()
        bad = ['{', raw.replace('7348.32', 'NaN'), raw.replace('7348.32', 'Infinity'),
               raw.replace('7348.32', '1e999'), raw.replace('7348.32', 'true'),
               raw.replace('7348.32', '-1'), raw.replace('13041.6048', 'NaN'),
               raw.replace('"cell00":1', '"cell00":true'),
               raw.replace('"cell00":1', '"cell00":-1'),
               raw.replace('"cell00":1', '"cell00":1.5'),
               raw.replace('"cell00":1', '"cell00":NaN'),
               raw.replace('"cell00":1', '"":1'),
               raw.replace('"num_cells":673', '"num_cells":672'),
               raw.replace('"num_cells":673', '"num_cells":true'),
               raw.replace('"cell00":1', '"cell00":1,"cell00":1'),
               raw.replace('"cell00":1', '"cell00":1,"cell\\u0030\\u0030":1'),
               raw.replace('"cell00":1', '"μ":1,"\\u03bc":1')]
        mismatch = copy.deepcopy(stat_value)
        mismatch['design']['num_cells_by_type']['cell00'] += 1
        mismatch['design']['num_cells'] += 1
        bad.append(canonical(mismatch))
        for invalid in bad:
            stat.write_text(invalid)
            j = call(cp)
            assert j['checkpoints'][0]['supplementary'] == [] and j['diagnostics'], invalid
            assert j['diagnostics'][0]['sha256'] == digest(stat)
            assert next(m for m in j['checkpoints'][0]['metrics'] if m['raw_key'] == 'design__instance__count')['value'] == 673
            assert 'DIAGNOSTIC' in subprocess.run(args, env=env, text=True, capture_output=True, check=True).stdout
        # Raw invalid UTF-8 must remain optional evidence even when embedded in
        # count/duplicate-key errors, or rejected as a creator/name at projection.
        bad_bytes = [
            raw.encode().replace(b'"cell00":1', b'"\xff":1'),
            raw.encode().replace(b'"cell00":1', b'"\xff":true'),
            raw.encode().replace(b'"cell00":1', b'"\xff":1,"\xff":1'),
            raw.encode().replace(b'Yosys synthetic', b'Yosys \xff'),
            raw.encode().replace(b'"cell00":1', b'"' + b'\xff'*2048 + b'":true')]
        for invalid in bad_bytes:
            stat.write_bytes(invalid)
            j = call(cp); assert j == call(cp, api=True)
            assert not j['checkpoints'][0]['supplementary'] and j['diagnostics']
            d = j['diagnostics'][0]
            assert d['sha256'] == hashlib.sha256(invalid).hexdigest() and d['message']
            assert next(m for m in j['checkpoints'][0]['metrics'] if m['raw_key'] == 'design__instance__count')['value'] == 673
            assert stat.read_bytes() == invalid
            assert 'DIAGNOSTIC' in subprocess.run(args, env=env, text=True, capture_output=True, check=True).stdout
        assert len(d['message']) < 4200 and '[truncated]' in d['message']
        # Unix filenames are opaque bytes too: exercise the supplement API with
        # an invalid-byte path, including both projection and Unix-error paths.
        byte_dir = os.fsencode(root) + b'/producer-\xff'
        os.makedirs(byte_dir + b'/06-yosys-synthesis/reports')
        byte_stat = byte_dir + b'/06-yosys-synthesis/reports/stat.json'
        with open(byte_stat, 'wb') as f:
            f.write(raw.encode())
        for unreadable in [False, True]:
            if unreadable:
                os.unlink(byte_stat); os.symlink(b'stat.json', byte_stat)
            r = subprocess.run([os.fsencode(consumer), b'--supplement', byte_dir],
                env=env, text=True, capture_output=True, check=True)
            supplements, diagnostics = json.loads(r.stdout)
            assert not supplements and '\\xff' in diagnostics[0]['path']
            assert diagnostics[0]['message']
            assert diagnostics[0]['sha256'] == (None if unreadable else hashlib.sha256(raw.encode()).hexdigest())
        stat.unlink()
        alternate = producer / '99-newer/reports/stat.json'; alternate.parent.mkdir(parents=True)
        write(alternate, stat_value)
        j = call(cp); assert not j['diagnostics'] and not j['checkpoints'][0]['supplementary']
        # Checkpoint count absent: producer's internally consistent count still usable.
        absent_root = root / 'absent-count'; absent_root.mkdir()
        write(stat, stat_value)
        cp = Path(fixture(absent_root, metrics={}, run_dir=producer)['path'])
        assert call(cp)['checkpoints'][0]['supplementary'][0]['mapped_cell_count'] == 673
    if real:
        root = Path(real)
        before = snapshot(root)
        records = list(root.glob('execution-*.json')); assert len(records) == 1
        e = json.loads(records[0].read_text())
        for p in [root, records[0], Path(e['artifacts'][0]['path'])]:
            j = call(p)
            assert j['checkpoints'][0]['validation']['validation'] == 'host_only'
            supplements = j['checkpoints'][0]['supplementary']
            assert len(supplements) == 1 and not j['diagnostics']
            s = supplements[0]
            assert len(s['mapped_cell_types']) == 23 and sum(s['mapped_cell_types'].values()) == 673
            assert s['sequential_area'] == dict(value=7348.32, unit='µm²')
            for suffix, count in [('dfrbpq', 150), ('tiehi', 150), ('mux2', 128), ('a22oi', 56), ('nor2', 29), ('o21ai', 28)]:
                assert sum(n for name, n in s['mapped_cell_types'].items() if name.endswith('_' + suffix + '_1') or name.endswith('_' + suffix)) == count
        args = [str(public), 'report', str(root)] if public else [str(cli), '--target', str(root)]
        preview = subprocess.run(args, text=True, capture_output=True, env=env, cwd='/tmp', check=True)
        print(preview.stdout)
        assert snapshot(root) == before, 'real evidence changed'
        print(f'Real workspace verified unchanged: {len(before)} files (SHA-256, size, mtime).')
    print('stage reporting CLI/library contract, selection, failure, inventory, provenance: passed')

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--cli', type=Path)
    p.add_argument('--consumer', type=Path); p.add_argument('--public', type=Path); p.add_argument('--real')
    p.add_argument('--installed', action='store_true')
    a = p.parse_args()
    if a.installed:
        repo = Path(__file__).resolve().parents[1]
        from reference_harness import hardlink_prefix, thin_prefix
        with tempfile.TemporaryDirectory(prefix='installed-stage-report-', dir='/tmp/opencode') as tmp:
            root = Path(tmp); prefix = root / 'prefix'
            hardlink_prefix(repo / '_build/install/default', prefix); thin_prefix(prefix)
            driver = root / 'check_stage_report.py'; shutil.copyfile(__file__, driver)
            consumer = root / 'consumer'; consumer.mkdir()
            (consumer / 'dune-project').write_text('(lang dune 3.0)\n')
            (consumer / 'dune').write_text('(executable (name main) (libraries hardcaml_asic.execution))\n')
            shutil.copyfile(repo / 'test/stage_report_consumer.ml', consumer / 'main.ml')
            subprocess.run(['dune', 'build', '-j20', 'main.exe'], cwd=consumer,
                           env=dict(os.environ, OCAMLPATH=str(prefix / 'lib')), check=True)
            launcher = root / 'launch.py'
            launcher.write_text('import sys,runpy\n' + f'checkout={str(repo)!r}\n' +
                'def audit(event,args):\n'
                ' if event=="open" and isinstance(args[0],str) and args[0].startswith(checkout+"/"):\n'
                '  raise AssertionError("checkout read: "+args[0])\n'
                'sys.addaudithook(audit)\n' + f'runpy.run_path({str(driver)!r},run_name="__main__")\n')
            subprocess.run([sys.executable, '-B', str(launcher), '--cli', str(prefix / 'bin/hardcaml-asic-experimental-report'),
                '--public', str(prefix / 'bin/hardcaml-asic-flow'), '--consumer', str(consumer / '_build/default/main.exe')]
                + (['--real', a.real] if a.real else []), cwd=root, check=True)
    else:
        suite(a.cli.resolve(), a.consumer.resolve(), a.public.resolve() if a.public else None, a.real)
