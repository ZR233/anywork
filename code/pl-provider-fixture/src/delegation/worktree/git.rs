//! Git is invoked exclusively inside the production exec tool, never here.
use super::*;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Registration {
    pub path: String,
    pub head: String,
    pub branch: String,
    pub locked: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct PathState {
    pub path: String,
    pub exists: bool,
    pub dirty_file: Option<String>,
    pub commit_file: Option<Vec<u8>>,
    pub head: Option<String>,
    pub status: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Git {
    pub kind: String,
    pub path: String,
    pub head: String,
    pub common_dir: String,
    pub branch: String,
    pub status: String,
    pub worktrees: Vec<Registration>,
    pub refs: BTreeMap<String, String>,
    pub primary_path: String,
    pub primary_head: String,
    pub files: BTreeMap<String, Option<String>>,
    pub commit_file: Option<Vec<u8>>,
    pub targets: Vec<PathState>,
}

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum Action {
    Read,
    NestedCommit,
    Untracked,
    Stage,
    CommitThenModify,
    CommitDirty,
    ChildDirty,
    ChildCommit,
    Lock,
    Unlock,
}

#[derive(Serialize)]
struct Parameters<'a> {
    action: Action,
    targets: &'a [String],
}

// All subprocess calls have per-command identity, hook and credential settings.
// No stash, fetch, automatic staging, pruning, internal-lock writes or raw remove.
const PRELUDE: &str = r#"
import os, json, subprocess
from pathlib import Path
GIT = ['git', '-c', 'core.hooksPath=/dev/null', '-c', 'credential.helper=', '-c', 'user.name=Anywork Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false']
def git(*args, cwd=None):
    result = subprocess.run(GIT + list(args), cwd=cwd, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError('git failed (' + str(result.returncode) + '): ' + ' '.join(args) + ': ' + result.stderr)
    if result.stderr:
        raise RuntimeError('unexpected git stderr: ' + result.stderr)
    return result.stdout
root = os.path.realpath('.')
assert Path('fixture-base.txt').is_file(), 'not the synthetic repository'
assert git('ls-files', '--error-unmatch', 'fixture-base.txt').strip() == 'fixture-base.txt'
assert Path('.gitignore').read_text().strip() == '.anywork/', 'unexpected synthetic ignore contract'
def registrations():
    trees = []
    for field in git('worktree', 'list', '--porcelain', '-z').split('\0'):
        if field.startswith('worktree '):
            trees.append({'path':os.path.realpath(field[9:]),'head':'','branch':'','locked':None})
        elif field.startswith('HEAD '):
            trees[-1]['head'] = field[5:]
        elif field.startswith('branch '):
            trees[-1]['branch'] = field[7:]
        elif field == 'locked' or field.startswith('locked '):
            trees[-1]['locked'] = field[7:] if field.startswith('locked ') else ''
    assert trees
    return trees
"#;

const SCRIPT: &str = r#"
action = params['action']
def create(name, text):
    with open(name, 'x') as file:
        file.write(text)
def commit(name, message):
    git('add', '--', name)
    git('commit', '-m', message, '--', name)
if action == 'nestedCommit':
    assert not git('status', '--porcelain')
    create('fixture-parent.txt', 'synthetic parent commit\n')
    commit('fixture-parent.txt', 'fixture: distinct parent HEAD')
elif action == 'untracked':
    assert not git('status', '--porcelain')
    create('fixture-dirty.txt', 'synthetic dirty baseline\n')
elif action == 'stage':
    assert Path('fixture-dirty.txt').read_text() == 'synthetic dirty baseline\n'
    git('add', '--', 'fixture-dirty.txt')
elif action == 'commitThenModify':
    assert Path('fixture-dirty.txt').read_text() == 'synthetic dirty baseline\n'
    git('commit', '-m', 'fixture: staged admission sample', '--', 'fixture-dirty.txt')
    Path('fixture-dirty.txt').write_text('synthetic dirty modified\n')
elif action == 'commitDirty':
    assert Path('fixture-dirty.txt').read_text() == 'synthetic dirty modified\n'
    commit('fixture-dirty.txt', 'fixture: restore clean parent')
elif action == 'childDirty':
    assert not git('status', '--porcelain')
    create('fixture-child-dirty.txt', 'synthetic child dirty guard\n')
elif action == 'childCommit':
    assert not git('status', '--porcelain')
    create('fixture-child-commit.txt', 'synthetic unmerged child commit\n')
    commit('fixture-child-commit.txt', 'fixture: unmerged child guard')
elif action in ['lock', 'unlock']:
    assert len(params['targets']) == 1
    target = params['targets'][0]
    assert target != root and os.path.isdir(target)
    if action == 'lock':
        git('worktree', 'lock', '--reason', 'synthetic acceptance lock', target)
    else:
        git('worktree', 'unlock', target)
else:
    assert action == 'read'
worktrees = registrations()
primary = worktrees[0]['path']
files = {}
for name in ['fixture-parent.txt', 'fixture-dirty.txt', 'fixture-child-dirty.txt', 'fixture-child-commit.txt']:
    file = Path(name)
    files[name] = file.read_text() if file.is_file() else None
targets = []
for target in params['targets']:
    file = Path(target) / 'fixture-child-dirty.txt'
    committed = Path(target) / 'fixture-child-commit.txt'
    exists = os.path.lexists(target)
    targets.append({'path':target,'exists':exists,'dirtyFile':file.read_text() if file.is_file() else None,'commitFile':list(committed.read_bytes()) if committed.is_file() else None,'head':git('rev-parse','HEAD',cwd=target).strip() if exists else None,'status':git('status','--porcelain',cwd=target) if exists else None})
committed = Path('fixture-child-commit.txt')
refs = dict(line.split(' ', 1) for line in git('for-each-ref', '--format=%(refname) %(objectname)').splitlines())
print(json.dumps({'kind':'worktreeEvidence','path':root,'head':git('rev-parse','HEAD').strip(),'commonDir':os.path.realpath(git('rev-parse','--path-format=absolute','--git-common-dir').strip()),'branch':git('symbolic-ref','--short','HEAD').strip(),'status':git('status','--porcelain'),'worktrees':worktrees,'refs':refs,'primaryPath':primary,'primaryHead':git('rev-parse','HEAD',cwd=primary).strip(),'files':files,'commitFile':list(committed.read_bytes()) if committed.is_file() else None,'targets':targets}, sort_keys=True))
"#;

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

pub(super) fn python<T: serde::de::DeserializeOwned>(
    flow: &Flow<'_>,
    label: &str,
    parameters: &impl Serialize,
    body: &str,
) -> Progress<T> {
    let encoded = serde_json::to_string(parameters).context("encode synthetic Git parameters")?;
    let literal = serde_json::to_string(&encoded).context("encode Python parameter literal")?;
    let script = format!("import json\nparams = json.loads({literal})\n{PRELUDE}\n{body}");
    exec::exec(flow, label, format!("python3 -c {}", shell_quote(&script)))
}

pub(super) fn capture(
    flow: &Flow<'_>,
    label: &str,
    action: Action,
    targets: &[String],
) -> Progress<Git> {
    let git: Git = python(flow, label, &Parameters { action, targets }, SCRIPT)?;
    require(
        git.kind == "worktreeEvidence"
            && !git.path.is_empty()
            && !git.head.is_empty()
            && !git.common_dir.is_empty()
            && !git.branch.is_empty(),
        "Git evidence has no actual identity",
    )?;
    Ok(git)
}

pub(super) fn retained(parent: &Git, child: &Git, snapshot: &Git) -> Result<()> {
    parent_unchanged(parent, snapshot)?;
    require(
        snapshot.targets.iter().any(|target| {
            target.path == child.path
                && target.exists
                && target.head.as_deref() == Some(child.head.as_str())
                && target.status.as_deref() == Some(child.status.as_str())
                && target.commit_file == child.commit_file
                && target.dirty_file.as_deref()
                    == child
                        .files
                        .get("fixture-child-dirty.txt")
                        .and_then(Option::as_deref)
        }) && snapshot.worktrees.iter().any(|tree| {
            tree.path == child.path && tree.branch == format!("refs/heads/{}", child.branch)
        }) && snapshot.refs.get(&format!("refs/heads/{}", child.branch)) == Some(&child.head),
        "close protection changed the original bound path/HEAD/status/file data/registration/ref",
    )
}

pub(super) fn removed(parent: &Git, child: &Git, snapshot: &Git) -> Result<()> {
    parent_unchanged(parent, snapshot)?;
    require(
        snapshot
            .targets
            .iter()
            .any(|target| target.path == child.path && !target.exists)
            && !snapshot
                .worktrees
                .iter()
                .any(|tree| tree.path == child.path)
            && snapshot.refs.get(&format!("refs/heads/{}", child.branch)) == Some(&child.head),
        "cleanup did not remove only the original worktree while preserving its ref",
    )
}

pub(super) fn parent_unchanged(parent: &Git, snapshot: &Git) -> Result<()> {
    require(
        parent.path == snapshot.path
            && parent.head == snapshot.head
            && parent.common_dir == snapshot.common_dir
            && parent.branch == snapshot.branch
            && parent.primary_path == snapshot.primary_path
            && parent.primary_head == snapshot.primary_head
            && parent.status == snapshot.status
            && parent.files == snapshot.files
            && parent.commit_file == snapshot.commit_file
            && parent
                .refs
                .iter()
                .all(|(name, head)| snapshot.refs.get(name) == Some(head)),
        "cleanup changed parent directory/HEAD/dirty data or an existing ref",
    )
}
