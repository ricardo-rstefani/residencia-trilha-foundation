"""Deploy only new SAM Lambdas, using existing RDS/network/application resources."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
STACK = 'residencia-sam-lab'
PACKAGES = [('catalog', 'catalog.zip'), ('orders', 'orders.zip'), ('processor', 'processor.zip')]


def aws(*args):
    return json.loads(subprocess.check_output(
        ['aws', *args, '--output', 'json'], text=True))


def dump(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def deploy():
    manifest = json.loads((ROOT / 'release/manifest.json').read_text())
    if manifest['sha'] != os.environ['GITHUB_SHA']:
        raise ValueError('Manifest commit does not match GITHUB_SHA')
    for _, name in PACKAGES:
        digest = base64.b64encode(hashlib.sha256((ROOT / 'release' / name).read_bytes()).digest()).decode()
        if digest != manifest['files'][name]:
            raise ValueError(f'Artifact hash mismatch: {name}')
    cmd = [shutil.which('sam') or 'sam', 'deploy', '--template-file', str(ROOT / 'infrastructure/sam/template.yaml'),
           '--stack-name', STACK, '--s3-bucket', os.environ['SAM_ARTIFACT_BUCKET'],
           '--s3-prefix', STACK,
           '--no-confirm-changeset', '--no-fail-on-empty-changeset',
           '--parameter-overrides', f"ReleaseId={manifest['sha']}"]
    subprocess.run(cmd, check=True, cwd=ROOT)


def verify():
    manifest = json.loads((ROOT / 'release/manifest.json').read_text())
    stack = aws('cloudformation', 'describe-stacks', '--stack-name', STACK)['Stacks'][0]
    if stack['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE'):
        raise ValueError(f"Stack status: {stack['StackStatus']}")
    resources = aws('cloudformation', 'list-stack-resources', '--stack-name', STACK)
    if any(r['ResourceType'] not in ('AWS::Lambda::Function', 'AWS::Lambda::Version', 'AWS::Lambda::Alias')
           for r in resources['StackResourceSummaries']):
        raise ValueError('Unexpected non-Lambda resource in stack')
    functions = []
    for suffix, name in PACKAGES:
        function = f'{STACK}-{suffix}'
        alias = aws('lambda', 'get-alias', '--function-name', function, '--name', 'live')
        cfg = aws('lambda', 'get-function-configuration', '--function-name', function,
                  '--qualifier', alias['FunctionVersion'])
        if cfg['CodeSha256'] != manifest['files'][name]:
            raise ValueError(f'Published hash mismatch: {function}')
        if cfg['Environment']['Variables']['RELEASE_SHA'] != manifest['sha']:
            raise ValueError(f'Published commit mismatch: {function}')
        if cfg['State'] != 'Active':
            raise ValueError(f'Function is not active: {function}')
        functions.append({key: cfg[key] for key in
                          ('FunctionName', 'FunctionArn', 'Version', 'CodeSha256', 'Runtime', 'State', 'Role', 'VpcConfig')}
                         | {'Alias': alias, 'Commit': manifest['sha']})
    dump(ROOT / 'release/evidence/published.json', {
        'StackId': stack['StackId'], 'StackStatus': stack['StackStatus'],
        'RunUrl': os.getenv('GITHUB_SERVER_URL', 'https://github.com') + '/' + os.getenv('GITHUB_REPOSITORY', '')
                  + '/actions/runs/' + os.getenv('GITHUB_RUN_ID', ''),
        'Functions': functions,
    })
    dump(ROOT / 'release/evidence/resources.json', resources)
    print(json.dumps(functions, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=('deploy', 'verify'))
    args = parser.parse_args()
    {'deploy': deploy, 'verify': verify}[args.command]()
