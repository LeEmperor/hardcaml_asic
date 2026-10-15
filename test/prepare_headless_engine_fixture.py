"""Prepare external engine test collateral; never imported by the headless client.

Usage: python3 -B test/prepare_headless_engine_fixture.py PREFIX NEW_DIRECTORY TT_ROOT
The native inventory helper is used only at fixture setup, before client runtime.
"""
import json
from pathlib import Path
import shutil
import subprocess
import sys

prefix, output, support = map(Path, sys.argv[1:])
output.mkdir()
recipe = dict(schema_version=3, initial_boundary=None,
              stages=['synthesis', 'floorplan', 'placement', 'cts', 'routing', 'signoff'])
result = subprocess.run([str(prefix/'bin/hardcaml-asic-experimental-plan-inspect')],
                        input=json.dumps(recipe), text=True, capture_output=True, check=True)
discovery = json.loads(result.stdout)
operations = discovery['operation_sequence']
inventory = [o['backend'] for o in operations]
settings = {o['backend']['implementation']: o['settings'] for o in operations if o['settings']}
(output/'classic-inventory.json').write_text(json.dumps(inventory))
(output/'classic-settings.json').write_text(json.dumps(settings))
def image(value):
    if isinstance(value, dict):
        if 'tested_image_id' in value:
            return value['tested_image_id']
        return next((found for child in value.values() if (found := image(child))), None)
    if isinstance(value, list):
        return next((found for child in value if (found := image(child))), None)
(output/'image.txt').write_text(image(discovery))
for name in ('stage_preparation_engine.py', 'segment_service_engine.py',
             'segment_service_fixture.py', 'bridge_protocol_fixture.py'):
    shutil.copyfile(Path(__file__).with_name(name), output/name)
relative = Path('tech/ihp-sg13cmos5l/def/tt_block_6x4_pgvdd.def')
destination = output/'support-tools'/relative
destination.parent.mkdir(parents=True)
shutil.copyfile(support/relative, destination)
