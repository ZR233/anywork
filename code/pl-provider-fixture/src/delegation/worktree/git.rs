//! Git is invoked exclusively inside the production exec tool, never here.
use super::*;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Registration {
    pub path: String,
    pub head: String,
    pub branch: Option<String>,
    pub detached: bool,
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
    pub branch: Option<String>,
    pub detached: Option<bool>,
    pub common_dir: Option<String>,
    pub git_dir: Option<String>,
    pub admin_backlink: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Git {
    pub kind: String,
    pub path: String,
    pub head: String,
    pub common_dir: String,
    pub git_dir: String,
    pub admin_backlink: Option<String>,
    pub branch: Option<String>,
    pub detached: bool,
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
def symbolic_branch(cwd=None, full=False):
    args = ['symbolic-ref', '--quiet'] + ([] if full else ['--short']) + ['HEAD']
    result = subprocess.run(GIT + args, cwd=cwd, text=True, capture_output=True)
    if result.returncode == 0 and result.stdout.strip() and not result.stderr:
        return result.stdout.strip()
    if result.returncode == 1 and not result.stdout and not result.stderr:
        return None
    raise RuntimeError('git symbolic-ref failed (' + str(result.returncode) + '): ' + result.stderr + result.stdout)
def physical(path):
    common = os.path.realpath(git('rev-parse','--path-format=absolute','--git-common-dir',cwd=path).strip())
    admin = os.path.realpath(git('rev-parse','--absolute-git-dir',cwd=path).strip())
    backlink_file = Path(admin) / 'gitdir'
    backlink = None
    if admin != common:
        value = backlink_file.read_text().strip()
        assert value, 'empty worktree admin backlink'
        backlink = os.path.realpath(os.path.join(admin, value))
    return common, admin, backlink
def registrations(cwd=None):
    trees = []
    for field in git('worktree', 'list', '--porcelain', '-z', cwd=cwd).split('\0'):
        if field.startswith('worktree '):
            trees.append({'path':os.path.realpath(field[9:]),'head':'','branch':None,'detached':False,'locked':None})
        elif field.startswith('HEAD '):
            trees[-1]['head'] = field[5:]
        elif field.startswith('branch '):
            trees[-1]['branch'] = field[7:]
        elif field == 'detached':
            trees[-1]['detached'] = True
        elif field == 'locked' or field.startswith('locked '):
            trees[-1]['locked'] = field[7:] if field.startswith('locked ') else ''
    assert trees
    return trees
def snapshot(path, targets):
    path = os.path.realpath(path)
    common, admin, backlink = physical(path)
    branch = symbolic_branch(cwd=path)
    trees = registrations(cwd=path)
    files = {}
    for name in ['fixture-parent.txt', 'fixture-dirty.txt', 'fixture-child-dirty.txt', 'fixture-child-commit.txt']:
        file = Path(path) / name
        files[name] = file.read_text() if file.is_file() else None
    observed = []
    for target in targets:
        file = Path(target) / 'fixture-child-dirty.txt'
        committed = Path(target) / 'fixture-child-commit.txt'
        exists = os.path.lexists(target)
        target_common, target_admin, target_backlink = physical(target) if exists else (None, None, None)
        target_branch = symbolic_branch(cwd=target) if exists else None
        observed.append({'path':target,'exists':exists,'dirtyFile':file.read_text() if file.is_file() else None,'commitFile':list(committed.read_bytes()) if committed.is_file() else None,'head':git('rev-parse','HEAD',cwd=target).strip() if exists else None,'status':git('status','--porcelain',cwd=target) if exists else None,'branch':target_branch,'detached':target_branch is None if exists else None,'commonDir':target_common,'gitDir':target_admin,'adminBacklink':target_backlink})
    committed = Path(path) / 'fixture-child-commit.txt'
    return {'kind':'worktreeEvidence','path':path,'head':git('rev-parse','HEAD',cwd=path).strip(),'commonDir':common,'gitDir':admin,'adminBacklink':backlink,'branch':branch,'detached':branch is None,'status':git('status','--porcelain',cwd=path),'worktrees':trees,'refs':dict(line.split(' ', 1) for line in git('for-each-ref','--format=%(refname) %(objectname)',cwd=path).splitlines()),'primaryPath':trees[0]['path'],'primaryHead':git('rev-parse','HEAD',cwd=trees[0]['path']).strip(),'files':files,'commitFile':list(committed.read_bytes()) if committed.is_file() else None,'targets':observed}
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
print(json.dumps(snapshot(root, params['targets']), sort_keys=True))
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
            && !git.git_dir.is_empty()
            && git.detached == git.branch.is_none()
            && git.branch.as_ref().is_none_or(|branch| !branch.is_empty()),
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
                && target.branch == child.branch
                && target.detached == Some(child.detached)
                && target.common_dir.as_deref() == Some(child.common_dir.as_str())
                && target.git_dir.as_deref() == Some(child.git_dir.as_str())
                && target.admin_backlink == child.admin_backlink
                && target.commit_file == child.commit_file
                && target.dirty_file.as_deref()
                    == child
                        .files
                        .get("fixture-child-dirty.txt")
                        .and_then(Option::as_deref)
        }) && refs_preserved(&child.refs, &snapshot.refs),
        "close protection changed the original bound path/HEAD/status/file data/registration/ref",
    )?;
    registered(child, snapshot)
}

pub(super) fn removed(parent: &Git, child: &Git, snapshot: &Git) -> Result<()> {
    parent_unchanged(parent, snapshot)?;
    require(
        refs_preserved(&child.refs, &snapshot.refs),
        "cleanup changed an originally present ref",
    )?;
    removed_site(&child.path, snapshot)
}

/// Physical postcondition only. Cross-journey callers must independently
/// validate refs against the latest authorized, actually observed baseline.
pub(super) fn removed_site(path: &str, snapshot: &Git) -> Result<()> {
    require(
        snapshot
            .targets
            .iter()
            .any(|target| target.path == path && !target.exists)
            && !snapshot.worktrees.iter().any(|tree| tree.path == path),
        "closed worktree path or its exact registration is still present",
    )
}

pub(super) fn parent_unchanged(parent: &Git, snapshot: &Git) -> Result<()> {
    require(
        parent.path == snapshot.path
            && parent.head == snapshot.head
            && parent.common_dir == snapshot.common_dir
            && parent.git_dir == snapshot.git_dir
            && parent.admin_backlink == snapshot.admin_backlink
            && parent.branch == snapshot.branch
            && parent.detached == snapshot.detached
            && parent.primary_path == snapshot.primary_path
            && parent.primary_head == snapshot.primary_head
            && parent.status == snapshot.status
            && parent.files == snapshot.files
            && parent.commit_file == snapshot.commit_file
            && refs_preserved(&parent.refs, &snapshot.refs),
        "cleanup changed parent directory/HEAD/dirty data or an existing ref",
    )
}

pub(super) fn refs_preserved(
    before: &BTreeMap<String, String>,
    after: &BTreeMap<String, String>,
) -> bool {
    before
        .iter()
        .all(|(name, head)| after.get(name) == Some(head))
}

pub(super) fn same_identity(before: &Git, after: &Git) -> bool {
    before.path == after.path
        && before.common_dir == after.common_dir
        && before.git_dir == after.git_dir
        && before.admin_backlink == after.admin_backlink
}

pub(super) fn registered(child: &Git, snapshot: &Git) -> Result<()> {
    let rows: Vec<_> = snapshot
        .worktrees
        .iter()
        .filter(|tree| tree.path == child.path)
        .collect();
    let branch = child
        .branch
        .as_ref()
        .map(|branch| format!("refs/heads/{branch}"));
    require(
        snapshot.common_dir == child.common_dir
            && child.git_dir != child.common_dir
            && child.admin_backlink.as_deref() == Some(format!("{}/.git", child.path).as_str())
            && child.detached == child.branch.is_none()
            && rows.len() == 1
            && rows[0].head == child.head
            && rows[0].branch == branch
            && rows[0].detached == child.detached,
        "owned worktree lost exact path/registration/HEAD/common-dir/admin backlink or observed checkout mode",
    )
}

pub(super) fn close_preserved(before: &Git, after: &Git, removed_path: Option<&str>) -> Result<()> {
    let expected: Vec<_> = before
        .worktrees
        .iter()
        .filter(|tree| removed_path != Some(tree.path.as_str()))
        .collect();
    require(
        before.refs == after.refs && expected == after.worktrees.iter().collect::<Vec<_>>(),
        "close changed refs or any registration beyond the exact removed binding",
    )
}

pub(super) fn new_detached_child(parent: &Git, child: &Git) -> Result<()> {
    require(
        child.path != parent.path
            && child.common_dir == parent.common_dir
            && child.git_dir != parent.git_dir
            && child.branch.is_none()
            && child.detached
            && child.refs == parent.refs,
        "new owned worktree was not detached at an independent registered site with unchanged refs",
    )?;
    registered(child, child)
}
