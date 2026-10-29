"""Independent B adversarial wire review of A. Pure stdin/public-codec probes.

No A source/test changes, emission, publication, simulator or native tool calls.
The independent signer intentionally recomputes identities for malformed records:
rejection must come from schema/range/type checks, not a conveniently stale hash.
"""
import argparse
import copy
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess


def canonical(j):
    return json.dumps(j, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def sign(j):
    j = copy.deepcopy(j)
    j.pop('identity', None)
    j['parameters'].sort(key=lambda p: p.get('key', ''))
    for p in j['parameters']:
        if p.get('type') == 'enum':
            p['values'].sort()
    envelope = dict(contract='hardcaml-asic.hardware-variant', schema_version=1, payload=j)
    j['identity'] = hashlib.sha256(canonical(envelope).encode()).hexdigest()
    return j


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--probe', type=Path, required=True)
    a = parser.parse_args()
    probe = str(a.probe.resolve())
    env = dict(os.environ, PATH='/no-tools', PYTHONPATH='/no-catalog')
    sample = json.loads(subprocess.check_output([probe, 'sample'], env=env))
    assert sign(sample) == sample, 'independent domain-separated canonical signer agrees'
    checks = []

    def raw(label, data, accept=False, normalized=None):
        p = subprocess.run([probe, 'decode'], input=data, capture_output=True, env=env, timeout=10)
        assert p.returncode == 0, (label, p.returncode, p.stderr)
        result = json.loads(p.stdout)
        assert result['accepted'] == accept, (label, result)
        if normalized is not None:
            assert result['normalized'] == normalized, (label, result)
        checks.append(label)
        return result

    def value(label, j, accept=False):
        j = sign(j)
        return raw(label, canonical(j).encode(), accept, j if accept else None)

    # Parameter/assignment/enum permutations and raw JSON escaping normalize to
    # precisely the constructor's original declaration and identity.
    for pi, parameters in enumerate(itertools.permutations(sample['parameters'])):
        for ai, assignments in enumerate(itertools.permutations(sample['assignments'].items())):
            for reverse_enum in [False, True]:
                j = copy.deepcopy(sample)
                j['parameters'] = list(copy.deepcopy(parameters))
                j['assignments'] = dict(assignments)
                if reverse_enum:
                    next(p for p in j['parameters'] if p['type'] == 'enum')['values'].reverse()
                j = dict(reversed(list(j.items())))
                raw(f'permutation-{pi}-{ai}-{reverse_enum}', json.dumps(j).encode(), True, sample)
    original = canonical(sample)
    raw('escaped ASCII key/value aliases', original.replace('depth', r'\u0064epth')
        .replace('binary', r'\u0062inary').encode(), True, sample)

    for n in [-1000000000, 0, 1000000000]:
        j = copy.deepcopy(sample)
        j['assignments']['depth'] = n
        value(f'inclusive-depth-{n}', j, True)
    for n in [-1000000001, 1000000001, 2**62 - 1, -(2**62), 2**63, 10**300]:
        j = copy.deepcopy(sample)
        j['assignments']['depth'] = n
        value(f'out-of-range-or-bigint-{n}', j)
    for field in ['minimum', 'maximum']:
        for n in [-1000000001, 1000000001, 2**63, 10**300, 1.0, True, None, '100']:
            j = copy.deepcopy(sample)
            next(p for p in j['parameters'] if p['type'] == 'integer')[field] = n
            value(f'bound-{field}-{n}', j)
    for scalar in [256.0, '256', True, None, [], {}]:
        j = copy.deepcopy(sample)
        j['assignments']['depth'] = scalar
        value(f'integer-type-{scalar}', j)
    for scalar in [0, 1, 'true', None, [], {}]:
        j = copy.deepcopy(sample)
        j['assignments']['enabled'] = scalar
        value(f'boolean-type-{scalar}', j)
    for scalar in [1, True, None, [], {}, 'not_in_enum']:
        j = copy.deepcopy(sample)
        j['assignments']['encoding'] = scalar
        value(f'enum-type-{scalar}', j)

    for field in ['design_id', 'schema_id']:
        for text in ['', 'UPPER', '9prefix', 'a/b', 'x;exec', 'é', 'a\x00b', 'x' * 129]:
            j = copy.deepcopy(sample)
            j[field] = text
            value(f'identifier-{field}-{text!r}', j)
    for top in ['hidden', 'compiled_source_proven', 'semantic_use_proven']:
        j = copy.deepcopy(sample)
        j[top] = True
        value(f'unknown-top-{top}', j)
    for version in [0, 2, 1.0, True, '1']:
        j = copy.deepcopy(sample)
        j['schema_version'] = version
        value(f'version-{version!r}', j)
    for mutation in ['missing-assignment', 'unknown-assignment', 'empty-schema',
                     'duplicate-parameter', 'duplicate-enum', 'inverted-range',
                     'unknown-parameter-field', 'missing-parameter-field']:
        j = copy.deepcopy(sample)
        if mutation == 'missing-assignment':
            j['assignments'].pop('depth')
        elif mutation == 'unknown-assignment':
            j['assignments']['other'] = True
        elif mutation == 'empty-schema':
            j['parameters'], j['assignments'] = [], {}
        elif mutation == 'duplicate-parameter':
            j['parameters'].append(copy.deepcopy(j['parameters'][0]))
        elif mutation == 'duplicate-enum':
            next(p for p in j['parameters'] if p['type'] == 'enum')['values'].append('binary')
        elif mutation == 'inverted-range':
            next(p for p in j['parameters'] if p['type'] == 'integer').update(minimum=1, maximum=0)
        elif mutation == 'unknown-parameter-field':
            j['parameters'][0]['default'] = 128
        else:
            j['parameters'][0].pop('maximum')
        value(mutation, j)

    for n in [64, 65]:
        j = copy.deepcopy(sample)
        j['parameters'] = [dict(key=f'p{i}', type='boolean') for i in range(n)]
        j['assignments'] = {f'p{i}': bool(i % 2) for i in range(n)}
        value(f'parameter-cardinality-{n}', j, n == 64)
        j = copy.deepcopy(sample)
        next(p for p in j['parameters'] if p['type'] == 'enum')['values'] = [f'e{i}' for i in range(n)]
        j['assignments']['encoding'] = 'e0'
        value(f'enum-cardinality-{n}', j, n == 64)
    raw('duplicate-top-escaped-key', ('{"design_id":"review","\\u0064esign_id":"review",' + original[1:]).encode())
    raw('duplicate-assignment-escaped-key', original.replace('"assignments":{',
        '"assignments":{"\\u0064epth":256,').encode())
    raw('duplicate-parameter-field', original.replace('"minimum":-1000000000',
        '"minimum":-1000000000,"\\u006dinimum":-1000000000').encode())
    raw('leading-comment', ('/* comment */' + original).encode())
    raw('embedded-comment', original.replace('"parameters":', '"parameters":/* comment */').encode())
    raw('trailing-object', (original + '{}').encode())
    raw('leading-plus', original.replace('"depth":256', '"depth":+256').encode())
    raw('leading-zero', original.replace('"depth":256', '"depth":0256').encode())
    raw('integer-underscore', original.replace('"depth":256', '"depth":2_56').encode())
    raw('float-exponent-not-integer-token', original.replace('"depth":256', '"depth":2.56e2').encode())
    raw('overflow-float', original.replace('"depth":256', '"depth":1e9999').encode())
    raw('enormous-integer-token', original.replace('"depth":256', '"depth":' + '9' * 10000).encode())
    raw('invalid-utf8', original.encode().replace(b'review.v1', b'review.\xff'))
    for text in [r'\ud800', r'\udc00', r'\ud800\u0061', r'\q', '\x01']:
        raw(f'bad-escape/control-{text!r}', original.replace('review.v1', text).encode())
    padded = original.encode() + b' ' * (128 * 1024 - len(original.encode()))
    raw('exact-wire-byte-limit', padded, True, sample)
    raw('over-wire-byte-limit', padded + b' ')
    raw('depth-limit', b'[' * 257 + b'0' + b']' * 257)
    print(json.dumps(dict(status='passed', checks=len(checks), constructor_identity=sample['identity'],
                          permutation_checks=72, malformed_signed_records='independently rehashed',
                          all_controls=checks)))


if __name__ == '__main__':
    main()
