"""Real installed LibreLane State only; no Classic, engine, probe or EDA launch."""
from decimal import Decimal
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
from importlib.metadata import version
from librelane.state import State
from librelane.common import Path as NativePath
# Register the actual ODB format, as normal backend imports do. No step runs.
from librelane.steps import openroad

with tempfile.TemporaryDirectory(prefix='native-publisher-state-', dir='/tmp/opencode') as tmp:
    root = Path(tmp)
    candidate, store = root / 'candidate', root / 'store'
    candidate.mkdir()
    store.mkdir()
    source = root / 'netlist'
    source.write_text('native fixture view')
    # Golden tested-image pin; no provider Python source imports in this test.
    image = 'sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a'
    compatibility = {'bridge_sha256': '1' * 64, 'binding': {'image_identity': {'image_id': image}}}
    state = State({'odb': NativePath(str(source)), 'def': NativePath(str(source)),
                   'lib': {'tt': [NativePath(str(source))]}},
                  metrics={'positive': Decimal('Infinity'), 'negative': Decimal('-Infinity'),
                           'nan': float('nan'), 'finite': Decimal('1.25'), 'integer': 123456789012345678901234567890,
                           'negative_zero': -0.0, 'text': 'Infinity NaN', 'nested': [float('inf'), None]})
    state.validate()
    before = state.dumps()
    (candidate / 'state.json').write_text(before)
    (candidate / 'resolved.json').write_text('{}')
    import hashlib
    (candidate / 'closure.json').write_text(json.dumps({str(source): {
        'bytes': source.stat().st_size, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}}))
    (candidate / 'segment.json').write_text(json.dumps(dict(status='completed', boundary='placement',
        bridge_sha256='1' * 64, metrics={})))
    q = dict(candidate=str(candidate), store=str(store), boundary='placement', name='native-state',
             mode='missing', compatibility=compatibility)
    p = subprocess.run([sys.argv[1]], input=json.dumps(q) + '\n', capture_output=True, text=True, check=True)
    result = json.loads(p.stdout)
    assert 'path' in result, result
    after = (Path(result['path']) / 'state.json').read_text()
    original_metrics = json.loads(before)['metrics']
    published_metrics = json.loads(after)['metrics']
    for key in original_metrics:
        a, b = original_metrics[key], published_metrics[key]
        if key == 'nan':
            assert math.isnan(a) and math.isnan(b)
        else:
            assert a == b and type(a) is type(b), (key, a, b)
    assert math.copysign(1, published_metrics['negative_zero']) == -1
    loaded = State.loads(after)
    loaded.validate()
    assert math.isinf(loaded.metrics['positive']) and loaded.metrics['positive'] > 0
    assert math.isinf(loaded.metrics['negative']) and loaded.metrics['negative'] < 0
    assert math.isnan(loaded.metrics['nan'])
    assert loaded.metrics['finite'] == Decimal('1.25')
    assert str(loaded['odb']).startswith(result['path'] + '/views/')
    assert (candidate / 'state.json').read_text() == before
    print(f'native LibreLane {version("librelane")} State.dumps -> publisher -> State.loads/validate: Infinity, -Infinity, NaN, '
          'Decimal finite, signed zero, big integer, nested metrics and rewritten real views passed')
