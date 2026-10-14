"""Sequential standalone corpus, reusing one disposable thin hardlinked prefix."""
import hashlib
import argparse
import contextlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from reference_harness import hardlink_prefix, thin_prefix


def inventory(prefix):
    return {str(p.relative_to(prefix)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (prefix / 'bin').glob('*') if p.is_file()} | {
        str(p.relative_to(prefix)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (prefix / 'lib/hardcaml_asic/flow').rglob('*') if p.is_file()}


def main():
    repo = Path(__file__).resolve().parents[1]
    names = ('preflight', 'postcheck', 'coarse_run', 'collect', 'report', 'finalization',
             'execution_identity', 'execution_plans', 'checkpoints', 'checkpoint_publisher',
             'runner', 'result_store', 'runtime_contract', 'execution_transport',
             'observation', 'observation_writer', 'stage_preparation', 'segment_service',
             'stage_domain', 'process_supervisor', 'backend_protocol')
    parser = argparse.ArgumentParser()
    parser.add_argument('--start', choices=names, default=names[0])
    parser.add_argument('--resume-prefix', type=Path, help='explicit own disposable prefix after an outer timeout')
    args = parser.parse_args()
    if args.resume_prefix:
        prefix = args.resume_prefix.resolve(strict=True)
        if prefix.parent.parent != Path('/tmp/opencode') or not prefix.parent.name.startswith('installed-corpus-'):
            parser.error('resume prefix must be an own /tmp/opencode/installed-corpus-*/prefix')
    context = (contextlib.nullcontext(str(prefix.parent)) if args.resume_prefix else
               tempfile.TemporaryDirectory(prefix='installed-corpus-', dir='/tmp/opencode'))
    with context as tmp:
        prefix = Path(tmp) / 'prefix'
        if not args.resume_prefix:
            hardlink_prefix(repo / '_build/install/default', prefix)
            thin_prefix(prefix)
        before = inventory(prefix)
        env = dict(os.environ, FLOW_TEST_INSTALLED_PREFIX=str(prefix), PYTHONDONTWRITEBYTECODE='1')
        selected = names[names.index(args.start):]
        for name in selected:
            arguments = ['--installed-hardlink' if name == 'coarse_run' else '--installed']
            subprocess.run([sys.executable, '-B', str(repo / 'test' / ('check_' + name + '.py')),
                            *arguments], env=env, cwd=repo, check=True)
            after = inventory(prefix)
            assert after == before, ('installed fixture failed to restore prefix: ' + name,
                                     {key for key in before.keys() | after.keys() if before.get(key) != after.get(key)})
            if name == 'observation':
                subprocess.run([sys.executable, '-B', str(repo / 'test/check_observation.py'),
                                '--installed', '--historical'], env=env, cwd=repo, check=True)
        assert inventory(prefix) == before
        for script, arguments in (
            ('check_archive.py', ['--cli', str(prefix / 'bin/hardcaml-asic-experimental-archive'),
                                  '--consumer', 'unused', '--installed-prefix', str(prefix)]),
            ('check_archive_encoding.py', ['--consumer', 'unused', '--installed-prefix', str(prefix)]),
        ):
            subprocess.run([sys.executable, '-B', str(repo / 'test' / script), *arguments], cwd=repo, check=True)
            assert inventory(prefix) == before
        print(str(len(selected) + ('observation' in selected)) +
              ' standalone installed modes plus archive/encoding passed sequentially using one unchanged thin prefix')


if __name__ == '__main__':
    main()
