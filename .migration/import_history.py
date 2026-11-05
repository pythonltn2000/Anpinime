"""One-time exact history import. No build dispatch or original branch updates."""
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path.cwd()
MANIFEST_PATH = ROOT / '.migration/manifest.json'
RESULT_PATH = ROOT / '.migration/result.json'
TOKEN = os.environ.get('GH_TOKEN', '')
REPO = os.environ.get('ANPINIME_REPOSITORY', 'pythonltn2000/Anpinime')
BOOTSTRAP = os.environ.get('ANPINIME_BOOTSTRAP_SHA', '')
START = time.monotonic()
LAST_WRITE = 0.0
RESULT = {'status': 'started', 'destination': REPO, 'originalRefsModified': False,
          'applicationWorkflowDispatched': False}


def redact(value):
    value = str(value)
    for secret in (TOKEN, base64.b64encode(('x-access-token:' + TOKEN).encode()).decode() if TOKEN else ''):
        if secret:
            value = value.replace(secret, '[redacted]')
    return value


def budget():
    if time.monotonic() - START > 13 * 60:
        raise RuntimeError('History import reached its 13-minute application budget; no build was dispatched')


def record():
    RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULT_PATH.write_text(json.dumps(RESULT, indent=2) + '\n')


def api(path, method='GET', body=None, allow_missing=False):
    global LAST_WRITE
    budget()
    # Stay below GitHub's secondary content-creation rate; retries remain bounded.
    if method != 'GET':
        time.sleep(max(0, .9 - (time.monotonic() - LAST_WRITE)))
        LAST_WRITE = time.monotonic()
    for attempt in range(3):
        budget()
        request = urllib.request.Request('https://api.github.com/repos/' + REPO + '/' + path,
            data=json.dumps(body).encode() if body is not None else None, method=method,
            headers={'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json',
                     'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json',
                     'User-Agent': 'AnPinime-one-time-history-import'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                detail = json.loads(raw).get('message', '')
            except ValueError:
                detail = 'Non-JSON API error'
            if error.code == 404 and allow_missing:
                return None
            retry = error.code in (429, 500, 502, 503, 504) or (error.code == 403 and 'rate limit' in detail.lower())
            if retry and attempt < 2:
                time.sleep(min(15, max(2 ** attempt, int(error.headers.get('Retry-After', '0')))))
                continue
            raise RuntimeError(redact(f'{method} {path}: HTTP {error.code}: {detail}')) from None


def git(repo, *args, binary=False, env=None):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=not binary, env=env,
                                   stderr=subprocess.PIPE)


def object_sha(kind, raw):
    return hashlib.sha1(f'{kind} {len(raw)}\0'.encode() + raw).hexdigest()


def identity(value):
    match = re.fullmatch(r'(.*?) <(.*?)> (-?\d+) ([+-]\d{4})', value)
    if not match:
        raise RuntimeError('Unsupported original Git identity')
    name, email, timestamp, zone = match.groups()
    minutes = (int(zone[1:3]) * 60 + int(zone[3:])) * (1 if zone[0] == '+' else -1)
    date = dt.datetime.fromtimestamp(int(timestamp), dt.timezone(dt.timedelta(minutes=minutes)))
    return {'name': name, 'email': email, 'date': date.isoformat()}


def commit_body(repo, sha):
    raw = git(repo, 'cat-file', 'commit', sha, binary=True)
    if object_sha('commit', raw) != sha:
        raise RuntimeError('Local commit object failed integrity check: ' + sha)
    header, message = raw.split(b'\n\n', 1)
    fields = {}
    for line in header.decode().splitlines():
        key, value = line.split(' ', 1)
        if key not in ('tree', 'parent', 'author', 'committer'):
            raise RuntimeError('REST fallback cannot preserve this Git header: ' + key)
        fields.setdefault(key, []).append(value)
    body = {'tree': fields['tree'][0], 'parents': fields.get('parent', []),
            'message': message.decode(), 'author': identity(fields['author'][0]),
            'committer': identity(fields['committer'][0])}
    lines = ['tree ' + body['tree']] + ['parent ' + p for p in body['parents']]
    for kind in ('author', 'committer'):
        actor = body[kind]
        date = dt.datetime.fromisoformat(actor['date'])
        lines.append(f"{kind} {actor['name']} <{actor['email']}> {int(date.timestamp())} {date.strftime('%z')}")
    if object_sha('commit', ('\n'.join(lines) + '\n\n' + body['message']).encode()) != sha:
        raise RuntimeError('Original commit metadata failed roundtrip: ' + sha)
    return body


def tree_files(repo, tree):
    entries = []
    for row in git(repo, 'ls-tree', '-rz', tree, binary=True).split(b'\0'):
        if row:
            header, path = row.split(b'\t', 1)
            mode, kind, sha = header.decode().split()
            entries.append({'path': path.decode(), 'mode': mode, 'type': kind, 'sha': sha})
    return entries


def verify_remote_heads(heads):
    for sha in heads:
        remote = api('git/commits/' + sha, allow_missing=True)
        if remote is None:
            return False
        if remote['sha'] != sha:
            raise RuntimeError('Remote object identity mismatch')
    return True


def bridge_push(repo, bootstrap, heads):
    # Bootstrap is fetched locally from actions/checkout, including its tree.
    git(repo, 'fetch', '--no-tags', str(ROOT), bootstrap)
    tree = git(repo, 'rev-parse', bootstrap + '^{tree}').strip()
    parents = list(dict.fromkeys([bootstrap] + heads))
    env = os.environ.copy()
    env.update({'GIT_AUTHOR_NAME': 'AnPinime migration', 'GIT_AUTHOR_EMAIL': 'migration@localhost',
                'GIT_COMMITTER_NAME': 'AnPinime migration', 'GIT_COMMITTER_EMAIL': 'migration@localhost'})
    args = ['commit-tree', tree]
    for parent in parents:
        args += ['-p', parent]
    args += ['-m', 'Retain exact source history objects without changing the bootstrap tree']
    bridge = git(repo, *args, env=env).strip()
    assert git(repo, 'rev-parse', bridge + '^{tree}').strip() == tree
    env.update({'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'http.https://github.com/.extraheader',
                'GIT_CONFIG_VALUE_0': 'AUTHORIZATION: basic ' + base64.b64encode(('x-access-token:' + TOKEN).encode()).decode(),
                'GIT_TERMINAL_PROMPT': '0'})
    command = ['git', '-C', str(repo), 'push', 'https://github.com/' + REPO + '.git',
               bridge + ':refs/heads/migration/history-objects']
    pushed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, timeout=180)
    if pushed.returncode == 0:
        RESULT.update({'method': 'git-push-bridge', 'bridgeCommit': bridge, 'bridgeTree': tree,
                       'bootstrapTreeUnchanged': True})
        return True
    detail = redact(pushed.stdout + '\n' + pushed.stderr)
    if 'workflow' in detail.lower() and any(word in detail.lower() for word in ('permission', 'refusing', 'scope')):
        RESULT['bridgePushRejectedForWorkflowPermission'] = True
        print('Native object upload requires workflow permission; using exact Git Data import.', flush=True)
        return False
    raise RuntimeError('Native history upload failed: ' + detail[-2000:])


def rest_import(repo, heads, commits):
    # Read/validate every commit before issuing fallback mutations.
    bodies = {sha: commit_body(repo, sha) for sha in commits}
    objects = git(repo, 'rev-list', '--objects', '--no-object-names', *heads).splitlines()
    listed = subprocess.check_output(['git', '-C', str(repo), 'cat-file', '--batch-check=%(objectname) %(objecttype)'],
                                    input='\n'.join(objects) + '\n', text=True)
    blobs = [line.split()[0] for line in listed.splitlines() if line.split()[1] == 'blob']
    text_blobs = {}
    binary_blobs = {}
    for sha in blobs:
        raw = git(repo, 'cat-file', 'blob', sha, binary=True)
        assert object_sha('blob', raw) == sha
        try:
            text_blobs[sha] = raw.decode('utf-8')
        except UnicodeDecodeError:
            binary_blobs[sha] = raw
    # A tree entry can create a UTF-8 blob from content in the same request.
    # This avoids hundreds of extra writes while the returned root SHA still
    # proves every original byte/mode/path. Only binary data needs blob POSTs.
    for index, (sha, raw) in enumerate(binary_blobs.items(), 1):
        created = api('git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(raw).decode()})
        if created['sha'] != sha:
            raise RuntimeError('GitHub changed original blob: ' + sha)
        if index % 10 == 0 or index == len(binary_blobs):
            print(f'Imported binary blob {index}/{len(binary_blobs)}', flush=True)
    trees = list(dict.fromkeys(bodies[sha]['tree'] for sha in commits))
    for index, tree in enumerate(trees, 1):
        entries = tree_files(repo, tree)
        for entry in entries:
            if entry['type'] == 'blob' and entry['sha'] in text_blobs:
                entry['content'] = text_blobs[entry.pop('sha')]
        created = api('git/trees', 'POST', {'tree': entries})
        if created['sha'] != tree:
            raise RuntimeError('GitHub changed original tree: ' + tree)
        if index % 25 == 0 or index == len(trees):
            print(f'Imported tree {index}/{len(trees)}', flush=True)
    for index, sha in enumerate(commits, 1):
        created = api('git/commits', 'POST', bodies[sha])
        if created['sha'] != sha:
            raise RuntimeError('GitHub changed original commit: ' + sha + ' -> ' + created['sha'])
        if index % 25 == 0 or index == len(commits):
            print(f'Imported commit {index}/{len(commits)}', flush=True)
    RESULT.update({'method': 'git-data-rest', 'importedBinaryBlobs': len(binary_blobs),
                   'inlineTextBlobs': len(text_blobs), 'importedTrees': len(trees)})


def main():
    manifest = json.loads(MANIFEST_PATH.read_text())
    heads = list(dict.fromkeys(row['sha'] for row in manifest['branches']))
    RESULT.update({'source': manifest['source'], 'expectedBranches': manifest['branches']})
    validate = os.environ.get('ANPINIME_VALIDATE_ONLY')
    if validate:
        repo = Path(validate)
        commits = git(repo, 'rev-list', '--reverse', '--topo-order', *heads).splitlines()
        for sha in commits:
            commit_body(repo, sha)
        print('PASS: exact Git metadata roundtrip for', len(commits), 'commits')
        RESULT.update({'status': 'local-validation-passed', 'originalCommitsVerified': len(commits)})
        return
    if REPO.lower() != 'pythonltn2000/anpinime' or not TOKEN or not re.fullmatch(r'[0-9a-f]{40}', BOOTSTRAP):
        raise RuntimeError('Migration requires the intended repository, bootstrap SHA and its job token')
    if git(ROOT, 'rev-parse', 'HEAD').strip() != BOOTSTRAP:
        raise RuntimeError('Checkout differs from the expected bootstrap commit')
    with tempfile.TemporaryDirectory(prefix='anpinime-history-') as temp:
        bundle = Path(temp) / 'project.bundle'
        with bundle.open('wb') as output:
            for index in range(manifest['parts']):
                output.write((ROOT / f'.migration/project.bundle.{index:03d}').read_bytes())
        if bundle.stat().st_size != manifest['bundleBytes'] or hashlib.sha256(bundle.read_bytes()).hexdigest() != manifest['bundleSHA256']:
            raise RuntimeError('Git bundle integrity check failed')
        RESULT['bundleIntegrity'] = 'PASS'
        repo = Path(temp) / 'repository.git'
        subprocess.run(['git', 'clone', '--mirror', str(bundle), str(repo)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        git(repo, 'fsck', '--full')
        commits = git(repo, 'rev-list', '--reverse', '--topo-order', *heads).splitlines()
        if verify_remote_heads(heads):
            RESULT['method'] = 'original-heads-already-present'
        elif not bridge_push(repo, BOOTSTRAP, heads):
            rest_import(repo, heads, commits)
        if not verify_remote_heads(heads):
            raise RuntimeError('Original history heads are not accessible after import')
        RESULT.update({'status': 'original-commits-ready', 'originalCommitsVerified': len(commits),
                       'elapsedSeconds': round(time.monotonic() - START, 2)})
        print(f'PASS: {len(commits)} exact commits ready; original branch restoration is left to the connector.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        RESULT.update({'status': 'failed', 'error': redact(error)})
        raise RuntimeError(redact(error)) from None
    finally:
        record()
