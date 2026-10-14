"""Trusted grouping and actual import-only selected Classic inventory checks."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def verify(consumer, inspector, payload, selected=False):
    inventory = json.loads(subprocess.check_output([consumer], text=True))
    plan = {"schema_version": 3, "stages": ["synthesis", "floorplan", "placement", "cts", "routing", "signoff"],
            "initial_boundary": None}
    discovery = json.loads(subprocess.run([inspector], input=json.dumps(plan), text=True,
        capture_output=True, check=True).stdout)
    groups = discovery["operation_groups"]
    flat = [o for stage in plan["stages"] for o in groups[stage]]
    assert [o["backend"] for o in flat] == inventory
    assert discovery["operation_sequence"] == flat
    assert len(inventory) == 80 and [len(groups[s]) for s in plan["stages"]] == [6, 7, 21, 1, 12, 33]
    assert len({o["occurrence_id"] for o in flat}) == 80
    for i, stage in enumerate(plan["stages"]):
        cap = discovery["capabilities"][stage]
        assert groups[stage][-1]["backend"]["id"] == cap["endpoint"]
        assert cap["successor"] == (None if i == 5 else groups[plan["stages"][i+1]][0]["backend"]["id"])
        assert all(o["execution_evidence"] is None and not o["durable_checkpoint"] for o in groups[stage])
    sta = [o for o in flat if o["operation"] == "timing.mid_pnr"]
    assert [o["backend"]["id"] for o in sta] == ["OpenROAD.STAMidPNR", *[f"OpenROAD.STAMidPNR-{n}" for n in range(1,4)]]
    assert [o["stage"] for o in sta] == ["placement", "routing", "routing", "routing"]
    assert {o["operation"] for o in groups["placement"]} == {
        "placement.setup", "placement.pdn", "placement.io", "placement.global", "placement.header_checks",
        "timing.mid_pnr", "placement.design_repair", "placement.manual", "placement.detailed"}
    negatives = [inventory[:-1], inventory[1:], list(reversed(inventory)), inventory + inventory[:1]]
    for field, value in (("id", "drift"), ("implementation", "drift"), ("inputs", []),
                         ("outputs", []), ("gates", [{"name":"RUN_NEW", "default":True}])):
        changed = copy.deepcopy(inventory)
        changed[27][field] = value
        negatives.append(changed)
    for value in (False, 1, None, "true"):
        changed = copy.deepcopy(inventory)
        changed[0]["gates"][0]["default"] = value
        negatives.append(changed)
    changed = copy.deepcopy(inventory)
    changed[0]["extra"] = None
    negatives.append(changed)
    for changed in negatives:
        result = subprocess.run([consumer, "validate"], input=json.dumps(changed), text=True, capture_output=True)
        assert result.returncode == 2 and result.stderr and not result.stdout
    assert subprocess.run([consumer, "validate"], input=json.dumps(inventory), text=True,
                          capture_output=True).returncode == 0
    settings = {o["backend"]["implementation"]: o["settings"] for o in flat if o["settings"]}
    assert subprocess.run([consumer, "settings"], input=json.dumps(settings), text=True, capture_output=True).returncode == 0
    for field in ('kind', 'units', 'default', 'pdk'):
        changed = copy.deepcopy(settings)
        changed['OpenROAD.DetailedPlacement'][0][field] = 'unsupported'
        assert subprocess.run([consumer, 'settings'], input=json.dumps(changed), text=True,
                              capture_output=True).returncode == 2
    changed = copy.deepcopy(settings)
    changed['OpenROAD.DetailedPlacement'].append(changed['OpenROAD.DetailedPlacement'][0])
    assert subprocess.run([consumer, 'settings'], input=json.dumps(changed), text=True,
                          capture_output=True).returncode == 2
    if selected:
        image = discovery["capabilities"]["synthesis"]["tested_image_id"]
        code = payload.read_text()
        # The consumer's selected host and exact bound image, network disabled.
        host_python = Path('/home/wayne/devel/jane/hardcaml_asic_example/_flow_tools/.venv/bin/python')
        host = json.loads(subprocess.check_output([host_python, '-I', '-B', '-c', code, 'container'], text=True))
        selected = json.loads(subprocess.check_output(['docker', 'run', '--rm', '--network', 'none',
            '--entrypoint', 'python3', image, '-I', '-B', '-c', code, 'container'], text=True))
        for observed in (host, selected):
            actual = observed['metadata']['classic_inventory']
            result = subprocess.run([consumer, 'validate'], input=json.dumps(actual), text=True, capture_output=True)
            assert result.returncode == 0, (result.stderr, actual)
            assert actual == inventory
            assert subprocess.run([consumer, 'settings'], input=json.dumps(observed['metadata']['classic_settings']),
                text=True, capture_output=True).returncode == 0
        print(f"selected image {image}: 80 identifiers/implementations/artifact contracts and gates/defaults verified; "
              f"container LibreLane {selected['metadata']['librelane_version']}, "
              f"Python {selected['metadata']['python_version']}; payload sha256 {hashlib.sha256(payload.read_bytes()).hexdigest()}")
    print(f"six exact groups, 80 unique occurrences, shared STA, {len(negatives)} inventory and 5 setting drift negatives passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--consumer', type=Path)
    parser.add_argument('--inspector', type=Path)
    parser.add_argument('--selected', action='store_true')
    parser.add_argument('--installed', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    if not args.installed:
        verify(str(args.consumer.resolve()), str(args.inspector.resolve()),
               repo / 'flow/hardcaml_asic_flow/stage_metadata_probe.py', args.selected)
        return
    with tempfile.TemporaryDirectory(prefix='stage-domain-', dir='/tmp/opencode') as tmp:
        root = Path(tmp)
        prefix = root / 'prefix'
        subprocess.run(['dune', 'install', '-j20', '--prefix', str(prefix)], cwd=repo, check=True,
                       stdout=subprocess.DEVNULL)
        consumer = root / 'consumer'
        consumer.mkdir()
        shutil.copyfile(repo / 'test/stage_domain_consumer.ml', consumer / 'stage_domain_consumer.ml')
        (consumer / 'dune-project').write_text('(lang dune 3.17)\n(name stage_domain_install)\n')
        (consumer / 'dune').write_text('(executable (name stage_domain_consumer) (libraries hardcaml_asic.execution hardcaml_asic.flow_domain))\n')
        env = dict(os.environ, OCAMLPATH=str(prefix / 'lib') + ':' + os.environ.get('OCAMLPATH', ''))
        subprocess.run(['dune', 'build', '-j20', 'stage_domain_consumer.exe'], cwd=consumer, env=env, check=True)
        verify(str(consumer / '_build/default/stage_domain_consumer.exe'),
               str(prefix / 'bin/hardcaml-asic-experimental-plan-inspect'),
               prefix / 'lib/hardcaml_asic/flow/hardcaml_asic_flow/stage_metadata_probe.py', args.selected)
        print('independently installed domain API consumer passed outside checkout')


if __name__ == '__main__':
    main()
