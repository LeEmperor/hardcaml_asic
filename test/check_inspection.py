"""Synthetic supplementary evidence: public contract, provenance and read-only IO.

No EDA or provider runtime is needed. This suite is run only by the parent.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from check_stage_report import fixture, execution, write, record, canonical, snapshot


def main(cli, public=None):
    env = dict(os.environ, PATH='/no-eda-or-python', PYTHONDONTWRITEBYTECODE='1')
    if public:
        result = subprocess.run([public, '--version', '--json'], env=env, text=True,
                                capture_output=True, check=True, timeout=30)
        capabilities = json.loads(result.stdout)['cli_contract']['capabilities']
        assert capabilities['inspection1'] is True and 'inspect' in capabilities['json_commands']
    with tempfile.TemporaryDirectory(prefix='inspection-fixture-') as temp:
        root = Path(temp)
        # Exercise the 2MiB bound with realistic absolute retained-path lengths.
        run = root / ('retained-' + 'x' * 160) / 'project/src/runs/signoff-fixture'
        producer = run / '01-openroad-stapostpnr'
        producer.mkdir(parents=True)
        config = {'meta': {'step': 'OpenROAD.STAPostPNR'},
                  'STA_CORNERS': ['fast', 'typ', 'slow'],
                  'PNR_SDC_FILE': '/recorded/constraints.sdc'}
        write(producer / 'config.json', config)
        write(producer / 'state_in.json', {'nl': '/recorded/design.nl.v', 'sdc': '/recorded/constraints.sdc'})
        path_text = ('Startpoint: input (input port clocked by clk)\n'
                     'Endpoint: flop/D (rising edge-triggered flip-flop clocked by clk)\n'
                     'Path Group: clk\nPath Type: max\n'
                     ' 1.25 data arrival time\n 2.5 data required time\n'
                     ' 1.25 slack (MET)\n\n')
        for corner in config['STA_CORNERS']:
            d = producer / corner
            d.mkdir()
            (d / 'generated.lib').write_bytes(b'library (fixture) {\n time_unit : "1ns";\n}\x00')
            for name in ['max.rpt', 'min.rpt']:
                (d / name).write_text(path_text * 170)
            (d / 'clock.rpt').write_text('Clock: clk\nVirtual: yes\nPropagated: no\n'
                'Period: 20\nrise -> rise\n0.1 0.2 latency\n0.1 skew\n'
                'fall -> fall\n0.3 0.5 latency\n0.2 skew\n'
                'clk period_min = 4 fmax = 250\n')
            (d / 'skew.max.rpt').write_text('0.35 setup skew\n')
            (d / 'skew.min.rpt').write_text('-0.1 hold skew\n')
            for name in ['checks.rpt', 'violator_list.rpt', 'unpropagated.rpt']:
                (d / name).write_text('report body\n')
            (d / 'sta.log').write_text('[INFO] propagating all clocks\n')
        write(producer / 'state_out.json', {'lib': {
            corner: str(producer / corner / 'generated.lib') for corner in config['STA_CORNERS']}})
        ref = fixture(root, 'signoff', run_dir=run)
        cp = Path(ref['path'])
        segment = json.loads((cp / 'segment.json').read_text())
        segment['returned_steps'] = ['OpenROAD.STAPostPNR-1']
        write(cp / 'segment.json', segment)
        manifest = json.loads((cp / 'manifest.json').read_text())
        manifest['files']['segment.json'] = record(cp / 'segment.json')
        del manifest['identity']
        manifest['identity'] = hashlib.sha256(canonical(manifest).encode()).hexdigest()
        write(cp / 'manifest.json', manifest)
        ref['identity'] = manifest['identity']
        value = execution([ref], ['signoff'])
        value['plan']['initial_boundary'] = 'routing'
        file = root / 'execution.json'
        write(file, value)

        def call(domain='timing', extra=(), expected=0, stage='signoff'):
            prefix = [public, 'inspect', str(file)] if public else [cli, '--execution', str(file)]
            args = [*prefix, '--domain', domain, '--stage', stage, '--json', *extra]
            result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=60)
            assert result.returncode == expected, (result.stdout, result.stderr)
            if expected:
                assert not result.stdout and result.stderr
                return result
            assert len(result.stdout.encode()) <= 2 * 1024 * 1024
            return json.loads(result.stdout)

        before = snapshot(root)
        index = call()
        assert index['contract'] == 'hardcaml-asic.inspection' and index['schema_version'] == 1
        assert index['execution_file'] == str(file.resolve()) and index['attempt_id'] == 'attempt'
        assert index['execution_sha256'] == hashlib.sha256(file.read_bytes()).hexdigest()
        paths = [r for r in index['rows'] if r['category'] == 'timing_path']
        assert len(paths) == 1020 and not index['truncated'], (len(paths), index['diagnostics'])
        assert len({r['id'] for r in paths}) == 1020
        row = paths[0]
        assert row['unit'] == 'ns' and row['value'] == 1.25
        source = json.loads(row['source'])
        assert source['file']['sha256'] == hashlib.sha256(Path(source['file']['path']).read_bytes()).hexdigest()
        assert source['span']['first_line'] == 1 and source['step_id'] == 'OpenROAD.STAPostPNR-1'
        assert source['units_source'][0]['declaration'] == 'time_unit : "1ns";'
        detail = call(extra=['--row-id', row['id'], '--expected-digest', index['source_digest']])
        assert detail['source_digest'] == index['source_digest'] and detail['row_id'] == row['id']
        assert '1: Startpoint:' in detail['detail'] and '6: ' in detail['detail']
        assert len(detail['detail'].encode()) <= 65536
        clocks = call('clocks')
        names = {r['name']: r for r in clocks['rows']}
        assert any(r['value'] == 250 and r['unit'] == 'MHz' for r in names.values())
        assert any(r['category'] == 'clock_check_skew' and r['value'] == .35 for r in names.values())
        assert any('clock header' in d for d in clocks['diagnostics'])
        assert snapshot(root) == before
        clock_file = producer / 'fast/clock.rpt'
        original_clock = clock_file.read_bytes()
        clock_file.write_text('Clock: a\nSources: pin_a\nGenerated: no\n'
            'Clock: b\nSources: pin_b\nGenerated: yes\nMaster Clock: a\nDivide By: 2\n'
            'Clock a\nrise -> rise\n0.1 0.2 latency\n'
            'Clock b\n9 9 latency\nfall -> fall\n0.3 0.4 latency\n')
        multi = call('clocks')
        latency = [r for r in multi['rows'] if r['corner'] == 'fast' and
                   dict(r['fields']).get('quantity') in ('latency_min', 'latency_max')]
        assert len(latency) == 4
        assert all(dict(r['fields'])['clock'] == ('a' if r['value'] in (.1, .2) else 'b') for r in latency)
        generated = [r for r in latency if dict(r['fields'])['clock'] == 'b']
        assert all(dict(r['fields'])['sources'] == 'pin_b' and
                   dict(r['fields'])['master_clock'] == 'a' and
                   dict(r['fields'])['generated'] == 'yes' for r in generated)
        assert any('missing transition context' in d for d in multi['diagnostics'])
        clock_file.write_bytes(original_clock)
        clock_file.write_bytes(b'================ typ Corner ================\n' + original_clock)
        clock_mismatch = call('clocks')
        quarantined_clocks = [r for r in clock_mismatch['rows'] if r['corner'] == 'fast' and r['category'] == 'clock_network']
        assert quarantined_clocks and all(r['value'] is None and r['unit'] is None and
            r['status'] == 'unavailable' and dict(r['fields'])['corner_conflict'] == 'quarantined'
            and json.loads(r['source'])['units_source'] is None for r in quarantined_clocks)
        clock_file.write_bytes(original_clock)
        # Bound before unit lookup or corner iteration, rather than retaining
        # an arbitrarily large producer config/working set.
        original_config = (producer / 'config.json').read_bytes()
        write(producer / 'config.json', dict(config, STA_CORNERS=[f'corner{i}' for i in range(65)]))
        capped = call()
        assert capped['truncated'] and any('corner count bound exceeded' in d for d in capped['diagnostics'])
        (producer / 'config.json').write_bytes(original_config)
        lib = producer / 'fast/generated.lib'
        # A quoted Liberty comment is not a declaration. Exercise the native
        # padded/quoted attribute form, then conflicting and malformed units.
        lib.write_text('/* time_unit : "1ps"; */\n'
                       'time_unit                      : "1ns";\n')
        commented_units = call()
        fast = [r for r in commented_units['rows'] if r['category'] == 'timing_path' and r['corner'] == 'fast']
        assert len(fast) == 340 and all(r['unit'] == 'ns' for r in fast)
        assert commented_units['source_digest'] != index['source_digest']
        lib.write_text('time_unit : "1ns";\ntime_unit : "1ps";\n')
        conflicting_units = call()
        fast = [r for r in conflicting_units['rows'] if r['category'] == 'timing_path' and r['corner'] == 'fast']
        assert len(fast) == 340 and all(r['unit'] is None for r in fast)
        assert any('conflicting retained timing units' in d for d in conflicting_units['diagnostics'])
        lib.write_text('time_unit : "1ns";\ntime_unit : 1ps;\n')
        malformed_units = call()
        fast = [r for r in malformed_units['rows'] if r['category'] == 'timing_path' and r['corner'] == 'fast']
        assert len(fast) == 340 and all(r['unit'] is None for r in fast)
        assert any('malformed Liberty time_unit' in d for d in malformed_units['diagnostics'])
        lib.write_text('library (fixture) {}')
        missing_units = call()
        assert any('missing retained timing unit' in d for d in missing_units['diagnostics'])
        assert all(r['unit'] is None for r in missing_units['rows'] if r['corner'] == 'fast')
        call(extra=['--row-id', row['id'], '--expected-digest', index['source_digest']], expected=2)
        report = producer / 'fast/max.rpt'
        lib.write_text('time_unit : "1ns";\n')
        original_report = report.read_bytes()
        report.write_text('================ typ Corner ================\n' + path_text)
        mismatch = call()
        quarantined = [r for r in mismatch['rows'] if dict(r['fields']).get('corner_conflict') == 'quarantined']
        assert len(quarantined) == 1
        conflict = quarantined[0]
        assert conflict['corner'] == 'typ' and dict(conflict['fields'])['directory_corner'] == 'fast'
        assert conflict['status'] == 'unavailable' and conflict['value'] is None and conflict['unit'] is None
        assert json.loads(conflict['source'])['units_source'] is None
        assert any('conflicting report/directory corner' in d for d in mismatch['diagnostics'])
        report.write_bytes(original_report)
        report.write_text('Startpoint: broken\n NaN slack (MET)\n')
        malformed = call()
        assert any('malformed timing' in d for d in malformed['diagnostics'])
        report.unlink()
        missing = call()
        assert any('missing retained source:' in d for d in missing['diagnostics'])
        outside = root / 'outside.rpt'
        outside.write_text(path_text)
        report.symlink_to(outside)
        escaped = call()
        assert any('symlink escape' in d for d in escaped['diagnostics'])
        assert all(json.loads(r['source'])['file']['path'] != str(outside) for r in escaped['rows'])
        # Corrupt inventoried evidence is a hard validation failure.
        (cp / 'views/nl').write_text('corrupted')
        call(expected=2)

        # Independently inventoried native fixtures exercise repeated keys,
        # nonfinite quantities and placement/routing semantic separation.
        def native_fixture(boundary, steps, label=None):
            nonlocal file
            base = root / ('native-' + (label or boundary))
            base.mkdir()
            native_run = base / 'run'
            native_run.mkdir()
            for i, (step, metrics, log) in enumerate(steps, 1):
                d = native_run / f'{i:02d}-producer'
                d.mkdir()
                registered = step.rsplit('-', 1)[0] if step.rpartition('-')[2].isdigit() else step
                write(d / 'config.json', {'meta': {'step': registered}})
                write(d / 'state_in.json', {'nl': '/retained/design.nl.v'})
                (d / 'or_metrics_out.json').write_text(metrics)
                (d / 'native.log').write_text(log)
                if step.startswith('OpenROAD.STA'):
                    (d / 'generated.lib').write_text('time_unit : "1ns";\n')
                    write(d / 'state_out.json', {'lib': str(d / 'generated.lib')})
                    (d / 'max.rpt').write_text(path_text)
                    (d / 'min.rpt').write_text(path_text)
            native_ref = fixture(base, boundary, run_dir=native_run)
            native_cp = Path(native_ref['path'])
            segment = json.loads((native_cp / 'segment.json').read_text())
            segment['returned_steps'] = [step for step, _, _ in steps]
            write(native_cp / 'segment.json', segment)
            manifest = json.loads((native_cp / 'manifest.json').read_text())
            manifest['files']['segment.json'] = record(native_cp / 'segment.json')
            del manifest['identity']
            manifest['identity'] = hashlib.sha256(canonical(manifest).encode()).hexdigest()
            write(native_cp / 'manifest.json', manifest)
            native_ref['identity'] = manifest['identity']
            value = execution([native_ref], [boundary])
            value['plan']['initial_boundary'] = {'placement': 'floorplan', 'routing': 'cts'}[boundary]
            file = base / 'execution.json'
            write(file, value)
            return native_run

        placement_run = native_fixture('placement', [
            ('OpenROAD.Floorplan-1', '{\n"design__die__bbox": "0 0 10 20"\n}\n', ''),
            ('OpenROAD.Floorplan-2', '{\n"design__die__bbox": "1 2 11 22"\n}\n', ''),
            ('OpenROAD.DetailedPlacement-1',
            '{\n"design__instance__area__stdcell": 10,\n'
            '"design__instance__area__stdcell": 12,\n'
            '"design__core__bbox": "1 2 11 22",\n'
            '"design__rows": 186,\n"route__wirelength__estimated": 21,\n'
            '"design__instance__utilization": 0.125\n}\n',
            'legalized HPWL 21 u\n[INFO DPL-0022] HPWL after 20 u\n'),
            ('OpenROAD.DetailedPlacement-2', '{\n"design__instance__count": 7\n}\n', '')])
        native = call('physical', stage='placement')
        areas = [r for r in native['rows'] if r['name'] == 'design__instance__area__stdcell']
        assert [r['value'] for r in areas] == [10, 12] and areas[0]['id'] != areas[1]['id']
        assert all(r['unit'] == 'µm²' for r in areas)
        bbox = next(r for r in native['rows'] if r['name'] == 'design__core__bbox')
        assert float(dict(bbox['fields'])['width']) == 10 and float(dict(bbox['fields'])['height']) == 20
        estimated = next(r for r in native['rows'] if r['name'] == 'route__wirelength__estimated')
        assert 'before mirroring' in dict(estimated['fields'])['measurement_scope']
        assert any(r['value'] == 20 and 'post-mirroring' in dict(r['fields']).get('semantics', '') for r in native['rows'])
        assert any('repeated key preserved' in d for d in native['diagnostics'])
        assert {json.loads(r['source'])['step_id'] for r in native['rows']} == {
            'OpenROAD.Floorplan-1', 'OpenROAD.Floorplan-2',
            'OpenROAD.DetailedPlacement-1', 'OpenROAD.DetailedPlacement-2'}
        # More than 256 logs is rejected from the directory listing, before
        # loading any of their contents.
        log_dir = placement_run / '01-producer'
        for i in range(257):
            (log_dir / f'overflow-{i}.log').write_text('retained log\n')
        capped = call('physical', stage='placement')
        assert capped['truncated'] and any('log count bound exceeded' in d for d in capped['diagnostics'])

        routing_run = native_fixture('routing', [
            ('OpenROAD.STAMidPNR-1', '{}', ''),
            ('OpenROAD.STAMidPNR-2', '{}', ''),
            ('OpenROAD.STAMidPNR-3', '{}', ''),
            ('OpenROAD.GlobalRouting-1', '{\n"route__wirelength": 45\n}\n',
             'Metal2 159079 1553 0.98% 0 / 0 / 0\n'
             '[INFO GRT-0018] Total wirelength: 45504 um\n'
             '[INFO GRT-0014] Routed nets: 1045\n'
             '[INFO GRT-0102] Start extra iteration 1/50\n'),
            ('OpenROAD.DetailedRouting-1', '{\n"route__drc_errors": 0,\n'
             '"route__wirelength": Infinity,\n"antenna__violating__nets": 0\n}\n', ''),
            ('OpenROAD.CheckAntennas-1', '{\n"antenna__violating__nets": 2\n}\n', ''),
            ('OpenROAD.RepairAntennas-2', '{\n"antenna__violating__nets": 1\n}\n', ''),
            ('Misc.Irrelevant', '{}', '')])
        # A config not selected by the recorded class must never be decoded.
        (routing_run / '08-producer/config.json').write_text('{malformed irrelevant config')
        native = call('routing', stage='routing')
        congestion = next(r for r in native['rows'] if r['category'] == 'global_congestion')
        assert dict(congestion['fields'])['resource'] == '159079'
        assert dict(congestion['fields'])['usage_percent'] == '0.98'
        assert any(r['category'] == 'detailed_drc' and r['value'] == 0 for r in native['rows'])
        assert any(r['category'] == 'antenna' and r['value'] == 0 for r in native['rows'])
        assert any(r['status'] == 'unavailable' and r['value'] is None for r in native['rows'])
        assert any('nonfinite' in d for d in native['diagnostics'])
        assert not any('irrelevant config' in d for d in native['diagnostics'])
        assert any(r['category'] == 'antenna' and r['value'] == 2 and r['producer'].startswith('OpenROAD.CheckAntennas-1@') for r in native['rows'])
        assert any(r['category'] == 'antenna' and r['value'] == 1 and r['producer'].startswith('OpenROAD.RepairAntennas-2@') for r in native['rows'])
        timing = call('timing', stage='routing')
        paths = [r for r in timing['rows'] if r['category'] == 'timing_path']
        assert len(paths) == 6 and len({r['producer'] for r in paths}) == 3
        assert {json.loads(r['source'])['step_id'] for r in paths} == {
            'OpenROAD.STAMidPNR-1', 'OpenROAD.STAMidPNR-2', 'OpenROAD.STAMidPNR-3'}
        # Sparse oversize source: rejection must happen before a 32MiB read or
        # parser allocation, and must retain an explicit truncated diagnostic.
        large = routing_run / '04-producer/native.log'
        with large.open('wb') as stream:
            stream.truncate(32 * 1024 * 1024 + 1)
        capped = call('routing', stage='routing')
        assert capped['truncated'] and any('per-source byte bound exceeded' in d for d in capped['diagnostics'])
        native_fixture('routing', [(f'OpenROAD.DetailedRouting-{i}', '{}', '') for i in range(257)], label='producer-cap')
        capped = call('routing', stage='routing')
        assert capped['truncated'] and any('producer count bound exceeded' in d for d in capped['diagnostics'])
        # Admission must enforce the aggregate limit before decoding checkpoint
        # metadata, even when oversized metadata is malformed. Sparse files
        # exercise actual stat sizes without allocating 72MiB of fixture data.
        for name in ('state.json', 'resolved.json', 'closure.json'):
            with (file.parent / 'routing' / name).open('wb') as stream:
                stream.truncate(24 * 1024 * 1024)
        error = call('routing', stage='routing', expected=2)
        assert 'aggregate input byte bound exceeded' in error.stderr


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cli', required=True)
    parser.add_argument('--public')
    args = parser.parse_args()
    main(args.cli, args.public)
