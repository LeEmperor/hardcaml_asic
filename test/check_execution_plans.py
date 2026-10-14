"""Actual Python Plan/StagePlan parity via the production installed command."""
import argparse
import copy
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def verify(command, consumer, flow, workdir):
    sys.path.insert(0, str(flow))
    from hardcaml_asic_flow import execution_plan as py

    caps = py.boundary_capabilities()
    accepted = rejected = 0
    # The native inspector needs neither PATH tools nor a Python module search path.
    command_env = dict(os.environ, PATH='/nonexistent', PYTHONPATH='/nonexistent')

    def check(value):
        nonlocal accepted, rejected
        text = json.dumps(value, ensure_ascii=True)
        try:
            plan = (py.Plan if isinstance(value, dict) and value.get('schema_version') == 1
                    else py.StagePlan).from_dict(value)
        except (ValueError, TypeError, KeyError, IndexError):
            expected = None
        else:
            expected = {'plan': plan.as_dict(), 'actions': [a.as_dict() for a in plan.actions],
                        'capabilities': caps,
                        'sequence': list(plan.sequence) if isinstance(plan, py.StagePlan) else None,
                        'source_boundary': plan.source_boundary if isinstance(plan, py.StagePlan) else None}
        result = subprocess.run([str(command)], input=text, text=True,
                                capture_output=True, cwd=workdir, env=command_env)
        if expected is None:
            assert result.returncode == 2 and not result.stdout and result.stderr, (value, result)
            rejected += 1
        else:
            assert result.returncode == 0 and not result.stderr, (value, result)
            actual = json.loads(result.stdout)
            groups = actual.pop('operation_groups')
            operations = actual.pop('operation_sequence')
            assert set(groups) == set(py.STAGE_ORDER)
            for name in py.STAGE_ORDER:
                assert groups[name][-1]['backend']['id'] == caps[name]['endpoint']
                assert all(o['stage'] == name and o['execution_evidence'] is None
                           and o['durable_checkpoint'] is False for o in groups[name])
            assert operations == (None if not isinstance(plan, py.StagePlan) else
                                  [o for name in plan.sequence for o in groups[name]])
            assert actual == expected, (value, actual, expected)
            # Normalization is stable and uses the shared identity codec bytes.
            assert result.stdout == json.dumps(json.loads(result.stdout), sort_keys=True, separators=(',', ':'),
                                               ensure_ascii=True) + '\n'
            accepted += 1

    emitted = subprocess.run([str(consumer)], cwd=workdir, text=True, capture_output=True, check=True)
    assert not emitted.stderr
    resolved = [json.loads(line) for line in emitted.stdout.splitlines()]
    expected_resolved = []
    for endpoint in ('synthesis', 'full'):
        for archive in (False, True):
            p = py.resolve(endpoint, archive=archive).as_dict()
            expected_resolved.append(p)
            p = copy.deepcopy(p)
            for a, label in zip(p['actions'], ['', 'same', 'same', '\0\n', 'λ😀']):
                a['label'] = label
            expected_resolved.append(p)
    for endpoint in py.STAGE_ORDER:
        for resume in (False, True):
            if not (resume and endpoint == 'synthesis'):
                expected_resolved.append(py.resolve_stages(endpoint, resume=resume).as_dict())
    for source in (None, *py.STAGE_ORDER):
        for endpoint in py.STAGE_ORDER:
            try:
                p = py.resolve_stages(endpoint, initial_boundary=source)
            except ValueError:
                continue
            # None uses schema 2 in Python; the OCaml through API is schema 3.
            expected_resolved.append(py.resolve_sequence(p.sequence, initial_boundary=source).as_dict())
    expected_resolved.append(py.resolve_sequence(py.STAGE_ORDER).as_dict())
    assert resolved == expected_resolved, (resolved, expected_resolved)
    for value in resolved:
        check(value)

    for endpoint in ('synthesis', 'full'):
        for archive in (False, True):
            base = py.resolve(endpoint, archive=archive).as_dict()
            check(base)
            # Every field is closed and every executable contract is fixed.
            for i, action in enumerate(base['actions']):
                for field in action:
                    for replacement in (None, False, True, 0, 1, 1.0, '', 'wrong', [], {}, ['wrong']):
                        changed = copy.deepcopy(base)
                        changed['actions'][i][field] = replacement
                        check(changed)
                for field in action:
                    changed = copy.deepcopy(base)
                    del changed['actions'][i][field]
                    check(changed)
                changed = copy.deepcopy(base)
                changed['actions'][i]['unknown'] = None
                check(changed)
            for actions in ([], base['actions'][:-1], base['actions'] + base['actions'][:1],
                            list(reversed(base['actions'])), {}, None):
                check(dict(base, actions=actions))

    for source in (None, *py.STAGE_ORDER, 'unknown', False, 1):
        for length in range(4):
            for stages in itertools.product(py.STAGE_ORDER, repeat=length):
                check({'schema_version': 3, 'stages': list(stages), 'initial_boundary': source})
    for source in (None, *py.STAGE_ORDER):
        for endpoint in py.STAGE_ORDER:
            end = py.STAGE_ORDER.index(endpoint) + 1
            start = 0 if source is None else py.STAGE_ORDER.index(source) + 1
            check({'schema_version': 3, 'stages': list(py.STAGE_ORDER[start:end]),
                   'initial_boundary': source})
    for endpoint in (*py.STAGE_ORDER, 'full', 'unknown', None, False, 1, [], {}):
        for resume in (False, True, None, 0, 1, 'false', [], {}):
            check({'schema_version': 2, 'endpoint': endpoint, 'resume': resume})

    bases = [py.resolve('full').as_dict(), py.resolve_stages('placement', resume=True).as_dict(),
             py.resolve_sequence(py.STAGE_ORDER).as_dict()]
    for base in bases:
        for schema in (False, True, 0, 1, 2, 3, 4, 1.0, 2.0, 3.0, '1', None, [], {}):
            check(dict(base, schema_version=schema))
        for field in base:
            changed = dict(base)
            del changed[field]
            check(changed)
        check(dict(base, unknown=None))
    for stages in (None, 'synthesis', {}, [True], [1], ['unknown'], ['synthesis', None]):
        check({'schema_version': 3, 'stages': stages, 'initial_boundary': None})
    for stages in (list(py.STAGE_ORDER) + ['signoff'], list(reversed(py.STAGE_ORDER)),
                   list(py.STAGE_ORDER) + ['synthesis']):
        check({'schema_version': 3, 'stages': stages, 'initial_boundary': None})
    for value in (None, True, 1, 'plan', [], {}):
        check(value)

    # Literal assertions make important semantics independent of differential equality.
    synth = py.resolve('synthesis').as_dict()
    check(synth)
    assert synth['actions'][1]['enabled'] is False
    assert synth['actions'][2]['requires'] == ['implementation.librelane']
    assert synth['actions'][2]['gate'] == 'run_available'
    assert synth['actions'][4]['enabled'] is False and synth['actions'][4]['gate'] == 'accepted'
    resumed = py.resolve_stages('placement', resume=True)
    assert resumed.sequence == ('floorplan', 'placement') and resumed.source_boundary == 'synthesis'
    assert resumed.actions[0].inputs == ('synthesis_checkpoint',)
    assert resumed.actions[0].requires == ()
    assert 'placement' in caps['synthesis']['restart_targets']
    check({'schema_version': 3, 'stages': ['placement'], 'initial_boundary': 'synthesis'})

    for text in ('', 'NaN', '{', '{"schema_version":2,"schema_version":2,"endpoint":"synthesis","resume":false}',
                 '{"schema_version":3,"stages":["synthesis"],"initial_boundary":null,"stages":["synthesis"]}',
                 json.dumps(bases[0]).replace('"LibreLane"', '"\\ud800"'),
                 json.dumps(bases[0]) + ' null'):
        result = subprocess.run([str(command), '-'], input=text, text=True, capture_output=True,
                                cwd=workdir, env=command_env)
        assert result.returncode == 2 and not result.stdout and result.stderr
        rejected += 1
    fixture = workdir / 'plan with spaces.json'
    fixture.write_text(json.dumps(bases[2]))
    file_result = subprocess.run([str(command), str(fixture)], text=True, capture_output=True,
                                 cwd=workdir, env=command_env)
    stdin_result = subprocess.run([str(command), '-'], input=fixture.read_text(), text=True,
                                  capture_output=True, cwd=workdir, env=command_env)
    assert file_result.returncode == stdin_result.returncode == 0
    assert file_result.stdout == stdin_result.stdout
    assert subprocess.run([str(command), '--help'], capture_output=True, cwd=workdir,
                          env=command_env).returncode == 0
    for args in (['--unknown'], ['a', 'b'], ['missing.json']):
        result = subprocess.run([str(command), *args], capture_output=True, cwd=workdir, env=command_env)
        assert result.returncode == 2 and not result.stdout and result.stderr
    print(f'execution plan parity: {accepted} accepted; {rejected} rejected; API resolution and command checks passed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--command', type=Path)
    parser.add_argument('--consumer', type=Path)
    parser.add_argument('--installed', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='execution-plans-', dir='/tmp/opencode') as tmp:
        root = Path(tmp)
        if not args.installed:
            verify(args.command.resolve(), args.consumer.resolve(), repo / 'flow', root)
            return
        prefix = root / 'prefix'
        subprocess.run(['dune', 'install', '-j', '20', '--prefix', str(prefix)], cwd=repo,
                       check=True, stdout=subprocess.DEVNULL)
        consumer = root / 'consumer'
        consumer.mkdir()
        shutil.copyfile(repo / 'test/execution_plan_consumer.ml', consumer / 'execution_plan_consumer.ml')
        (consumer / 'dune-project').write_text('(lang dune 3.17)\n(name installed_plan_consumer)\n')
        (consumer / 'dune').write_text('(executable (name execution_plan_consumer) (libraries hardcaml_asic.execution))\n')
        env = dict(os.environ)
        env['OCAMLPATH'] = str(prefix / 'lib') + (':' + env['OCAMLPATH'] if env.get('OCAMLPATH') else '')
        subprocess.run(['dune', 'build', '-j', '20', 'execution_plan_consumer.exe'], cwd=consumer,
                       env=env, check=True)
        meta = (prefix / 'lib/hardcaml_asic/META').read_text()
        execution = meta.split('package "execution" (', 1)[1].split('\n)', 1)[0]
        assert 'requires = "cryptokit hardcaml_asic spawn unix zarith"' in execution, execution
        hardware = meta.split('package "execution" (', 1)[0]
        assert 'hardcaml_asic.execution' not in hardware
        auditing = True
        def audit(event, values):
            if not auditing:
                return
            if event == 'open' and isinstance(values[0], (str, bytes, os.PathLike)):
                path = Path(os.fsdecode(values[0])).resolve()
                if path.is_relative_to(repo):
                    raise AssertionError(f'checkout read in installed plan test: {path}')
            if event == 'import' and (values[0].startswith('librelane') or
                                      values[0].endswith('librelane_bridge')):
                raise AssertionError(f'backend import in plan test: {values[0]}')
        sys.addaudithook(audit)
        try:
            verify(prefix / 'bin/hardcaml-asic-experimental-plan-inspect',
                   consumer / '_build/default/execution_plan_consumer.exe',
                   prefix / 'lib/hardcaml_asic/flow', root)
        finally:
            auditing = False
        print('independently installed consumer and experimental command passed outside checkout')


if __name__ == '__main__':
    main()
