"""Bounded archive/bootstrap/consumer integration using one private hardlink prefix."""
import argparse
import ast
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from reference_harness import RUNTIME, hardlink_prefix, thin_prefix


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--consumer-script', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='thin-integration-', dir='/tmp/opencode') as tmp:
        root = Path(tmp)
        prefix = root / 'prefix'
        hardlink_prefix(repo / '_build/install/default', prefix)
        thin_prefix(prefix)
        package = prefix / 'lib/hardcaml_asic/flow/hardcaml_asic_flow'
        assert {p.name for p in (package / 'data').iterdir()} == {
            'toolchain.sh', 'toolchain.lock', 'managed-python.json', 'version.txt'}
        cli = prefix / 'bin/hardcaml-asic-flow'
        cold = dict(os.environ, PATH='/no-python', PYTHONPATH='/denied')
        for arguments in (['--help'], ['--version'], ['--version', '--json']):
            result = subprocess.run([str(cli), *arguments], env=cold, capture_output=True, text=True, check=True)
            if '--json' in arguments:
                value = json.loads(result.stdout)
                assert value['package_version'] == '0.1.0' and value['cli_contract']['version'] == 4
        # Host payloads import without the oracle. The bridge's LibreLane imports
        # require its authorized runtime, exercised by the protocol/stage corpus.
        for name in RUNTIME:
            tree = ast.parse((package / (name + '.py')).read_text())
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.level:
                    assert node.module in RUNTIME if node.module else all(alias.name in RUNTIME for alias in node.names)
        entry = 'import importlib,sys;sys.path.insert(0,sys.argv[1]);' + ';'.join(
            f'importlib.import_module("hardcaml_asic_flow.{name}")' for name in RUNTIME
            if name not in ('librelane_bridge', 'stage_metadata_probe'))
        subprocess.run([sys.executable, '-I', '-B', '-c', entry, str(package.parent)], cwd=root, check=True)
        managed = [sys.executable, '-I', '-B', '-c',
                   'import sys;sys.path.insert(0,sys.argv.pop(1));from hardcaml_asic_flow.managed_python import main;sys.exit(main())',
                   str(package.parent)]
        subprocess.run([*managed, '--describe'], cwd=root, check=True)
        checked = subprocess.run([*managed, '--check', '--root', str(root / 'missing-python')], cwd=root)
        assert checked.returncode == 3
        env = dict(os.environ, PATH=str(prefix / 'bin') + os.pathsep + os.environ['PATH'], TOOLCHAIN=str(root / 'missing-tools'))
        checked = subprocess.run(['bash', str(args.consumer_script.resolve().parents[1] / 'bootstrap.sh'),
                                  '--check', '--no-container'], env=env, cwd=root, capture_output=True, text=True)
        assert checked.returncode == 2, (checked.returncode, checked.stdout, checked.stderr)
        assert not (root / 'missing-tools').exists()
        spec = importlib.util.spec_from_file_location('consumer_dependency', args.consumer_script.resolve())
        dep = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(dep)
        work = root / 'validation'
        work.mkdir()
        dep.validate_install(prefix, work, dep.run)
        for script, arguments in (
            ('check_archive.py', ['--cli', str(prefix / 'bin/hardcaml-asic-experimental-archive'),
                                  '--consumer', 'unused', '--installed-prefix', str(prefix)]),
            ('check_archive_encoding.py', ['--consumer', 'unused', '--installed-prefix', str(prefix)]),
        ):
            subprocess.run([sys.executable, '-B', str(repo / 'test' / script), *arguments], cwd=root, check=True)
        files = [p for p in prefix.rglob('*') if p.is_file()]
        logical = sum(p.stat().st_size for p in files)
        private = [p for p in root.rglob('*') if p.is_file() and not p.is_symlink() and p.stat().st_nlink == 1]
        print(json.dumps(dict(prefix_files=len(files), prefix_logical_bytes=logical,
                              private_allocated_bytes=sum(p.stat().st_blocks * 512 for p in private),
                              free_bytes=os.statvfs(root).f_bavail * os.statvfs(root).f_frsize)))
        print('thin runtime imports, native cold CLI, read-only bootstrap and independent consumer validation/linkage passed')


if __name__ == '__main__':
    main()
