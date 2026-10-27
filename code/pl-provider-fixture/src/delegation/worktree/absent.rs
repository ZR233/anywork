//! Missing bindings are observed through Git and filesystem commands, not lease edits.
use super::*;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Inventory {
    path: String,
    exists: bool,
    head: Option<String>,
    common_dir: Option<String>,
    branch: Option<String>,
    detached: Option<bool>,
    git_dir: Option<String>,
    admin_backlink: Option<String>,
    status: Option<String>,
    files: BTreeMap<String, Option<Vec<u8>>>,
    tree_digest: Option<String>,
    entries: usize,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Site {
    parent_path: String,
    parent_head: String,
    common_dir: String,
    original: Inventory,
    neighbor: Option<Inventory>,
    worktrees: Vec<git::Registration>,
    refs: BTreeMap<String, String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct AbsentCase {
    pub child_id: String,
    registration_present: bool,
    original_path: String,
    neighbor_path: Option<String>,
    before: Site,
    absent: Site,
    closed: Site,
    restored: Option<Site>,
    after_retry: Option<Site>,
    retry_owner_error: Option<String>,
    retry_failure: Option<no_head::FailedCallEvidence>,
}

#[derive(Serialize)]
struct Parameters<'a> {
    action: &'a str,
    original: &'a str,
    neighbor: Option<&'a str>,
    expected: Option<&'a Inventory>,
}

const SCRIPT: &str = r#"
import hashlib, stat
def _raise_walk_error(error):
    raise error
def inspect(path):
    exists = os.path.lexists(path)
    if not exists:
        return {'path':path,'exists':False,'head':None,'commonDir':None,'branch':None,'detached':None,'gitDir':None,'adminBacklink':None,'status':None,'files':{},'treeDigest':None,'entries':0}
    assert os.path.isdir(path) and not os.path.islink(path)
    files = {}
    for name in ['fixture-base.txt', '.gitignore', 'fixture-parent.txt', 'fixture-dirty.txt', 'fixture-child-dirty.txt', 'fixture-child-commit.txt']:
        file = Path(path) / name
        files[name] = list(file.read_bytes()) if file.is_file() else None
    entries = []
    for directory, dirs, names in os.walk(path, followlinks=False, onerror=_raise_walk_error):
        dirs.sort()
        names.sort()
        for name in sorted(dirs + names):
            file = Path(directory) / name
            mode = file.lstat().st_mode
            identity = [str(file.relative_to(path)), stat.S_IFMT(mode), stat.S_IMODE(mode)]
            if stat.S_ISLNK(mode):
                identity.append(os.readlink(file))
            elif stat.S_ISREG(mode):
                digest = hashlib.sha256()
                with file.open('rb') as source:
                    for chunk in iter(lambda: source.read(65536), b''):
                        digest.update(chunk)
                identity.append(digest.hexdigest())
            else:
                assert stat.S_ISDIR(mode), 'unexpected synthetic worktree entry kind'
            entries.append(identity)
    digest = hashlib.sha256(json.dumps(sorted(entries), separators=(',',':')).encode()).hexdigest()
    common, admin, backlink = physical(path)
    branch = symbolic_branch(cwd=path)
    return {'path':path,'exists':True,'head':git('rev-parse','--verify','HEAD',cwd=path).strip(),'commonDir':common,'branch':branch,'detached':branch is None,'gitDir':admin,'adminBacklink':backlink,'status':git('status','--porcelain',cwd=path),'files':files,'treeDigest':digest,'entries':len(entries)}
original = params['original']
neighbor = params['neighbor']
assert original != root and os.path.isabs(original)
if neighbor is not None:
    assert os.path.dirname(neighbor) == os.path.dirname(original) and neighbor != original
if params['action'] == 'remove':
    assert inspect(original) == params['expected']
    git('worktree','remove','--',original)
elif params['action'] == 'move':
    assert neighbor is not None and not os.path.lexists(neighbor)
    assert inspect(original) == params['expected']
    Path(original).rename(neighbor)
elif params['action'] == 'restore':
    assert neighbor is not None and not os.path.lexists(original)
    assert inspect(neighbor) == params['expected']
    Path(neighbor).rename(original)
else:
    assert params['action'] == 'read'
print(json.dumps({'parentPath':root,'parentHead':git('rev-parse','--verify','HEAD').strip(),'commonDir':os.path.realpath(git('rev-parse','--path-format=absolute','--git-common-dir').strip()),'original':inspect(original),'neighbor':inspect(neighbor) if neighbor is not None else None,'worktrees':registrations(),'refs':dict(line.split(' ',1) for line in git('for-each-ref','--format=%(refname) %(objectname)').splitlines())}, sort_keys=True))
"#;

pub(super) fn run(
    flow: &Flow<'_>,
    root: &str,
    parent: &Git,
    route: &Route,
    evidence: &mut Evidence,
) -> Progress<()> {
    for registered in [false, true] {
        let label = if registered {
            "absent-registered"
        } else {
            "absent-unregistered"
        };
        let spawn = flow.spawn(
            label,
            "worktree_executor",
            Some(route),
            &marker("read", parent),
            None,
        )?;
        let child = observe_child(flow, label, root, spawn)?;
        git::new_detached_child(parent, &child.git)?;
        require(
            child.git.path != parent.path
                && child.git.head == parent.head
                && child.git.common_dir == parent.common_dir
                && child.git.status.is_empty(),
            "NotPresent child did not execute at its real isolated clean assignment",
        )?;
        let suffix: String = super::super::input_digest(&child.spawn.agent_id)
            .chars()
            .take(16)
            .collect();
        let neighbor = registered.then(|| format!("{}.fixture-absent-{suffix}", child.git.path));
        let before = inspect(
            flow,
            &format!("{label}-before"),
            &child.git.path,
            neighbor.as_deref(),
        )?;
        check_parent(parent, &child.git, &before)?;
        check_present_child(&child.git, &before.original)?;
        require(
            before.neighbor.as_ref().is_none_or(|site| !site.exists),
            "NotPresent neighbor already exists",
        )?;
        check_registration(&child.git, &before, true)?;
        let absent: Site = git::python(
            flow,
            &format!("{label}-prepare"),
            &Parameters {
                action: if registered { "move" } else { "remove" },
                original: &child.git.path,
                neighbor: neighbor.as_deref(),
                expected: Some(&before.original),
            },
            SCRIPT,
        )?;
        check_absent(parent, &child.git, &absent, registered)?;
        require(
            before.refs == absent.refs
                && unchanged_registrations(&before, &absent, &child.git.path),
            "NotPresent preparation changed refs or unrelated registrations",
        )?;
        if registered {
            require(
                before.worktrees == absent.worktrees
                    && same_contents(
                        &before.original,
                        absent.neighbor.as_ref().context("moved neighbor missing")?,
                    ),
                "moving the child altered registration or actual neighbor contents",
            )?;
        }
        let close_label = format!("{label}-close");
        let result = flow.close(&close_label, &child.spawn.as_spawn())?;
        require_not_present(&result, &child.git, &child.spawn.agent_id, registered)?;
        let tool_output = successful_text(flow, &close_label, &child.spawn.agent_id)?;
        let closed = inspect(
            flow,
            &format!("{label}-closed"),
            &child.git.path,
            neighbor.as_deref(),
        )?;
        require(
            closed == absent,
            "NotPresent close changed missing path/registration/refs or neighbor bytes",
        )?;
        let git = git::capture(
            flow,
            &format!("{label}-closed-git"),
            Action::Read,
            std::slice::from_ref(&child.git.path),
        )?;
        git::parent_unchanged(parent, &git)?;
        evidence.closes.push(Close {
            label: close_label,
            force: false,
            result,
            tool_output,
            owner_error: None,
            before: None,
            git,
        });
        let (restored, after_retry, retry_owner_error, retry_failure) = if registered {
            let restored: Site = git::python(
                flow,
                &format!("{label}-restore"),
                &Parameters {
                    action: "restore",
                    original: &child.git.path,
                    neighbor: neighbor.as_deref(),
                    expected: Some(
                        closed
                            .neighbor
                            .as_ref()
                            .context("closed neighbor missing")?,
                    ),
                },
                SCRIPT,
            )?;
            require(
                restored == before,
                "restoring the moved child changed its actual files/HEAD/registration/ref",
            )?;
            let retry_label = format!("{label}-terminal-retry");
            let arguments = json!({"target":child.spawn.agent_id});
            // Flow alone resolves background completion. Its expected failure is
            // accepted only after independently verifying the exact Failed task,
            // complete typed outcome and the specific terminal replacement cause.
            let owner_error =
                match flow.read::<Closed>(&retry_label, "close_agent", arguments.clone()) {
                    Err(Stop::Call(call)) => return Err(Stop::Call(call)),
                    Err(Stop::Failed(error)) => Some(format!("{error:#}")),
                    Ok(result) => {
                        require(
                            result.error.is_some(),
                            "terminal NotPresent retry returned a successful outcome",
                        )?;
                        None
                    }
                };
            let failure = no_head::observed_failure(flow, &retry_label, "close_agent", arguments)?;
            let result: Closed = exec::first(&failure.output)?;
            let error = result
                .error
                .as_ref()
                .context("terminal NotPresent retry has no actual error")?;
            require(
                error.code == "agentCloseIncomplete"
                    && error.message
                        == format!(
                            "{}: absent child path/registration changed; replacement preserved",
                            child.spawn.agent_id,
                        ),
                "terminal NotPresent retry failed for a different reason",
            )?;
            // A failed terminal revalidation retains NotPresent, never grants
            // a new cleanup or replaces the already durable terminal outcome.
            require_member(&result, &child.git, &child.spawn.agent_id, true)?;
            let after = inspect(
                flow,
                &format!("{label}-after-retry"),
                &child.git.path,
                neighbor.as_deref(),
            )?;
            require(
                after == restored,
                "terminal NotPresent retry changed the replacement/neighbor/refs/registration",
            )?;
            let git = git::capture(
                flow,
                &format!("{label}-retry-git"),
                Action::Read,
                std::slice::from_ref(&child.git.path),
            )?;
            git::retained(parent, &child.git, &git)?;
            evidence.closes.push(Close {
                label: retry_label,
                force: false,
                result,
                tool_output: failure.output.clone(),
                owner_error: owner_error.clone(),
                before: None,
                git,
            });
            (Some(restored), Some(after), owner_error, Some(failure))
        } else {
            (None, None, None, None)
        };
        evidence.not_present.push(AbsentCase {
            child_id: child.spawn.agent_id.clone(),
            registration_present: registered,
            original_path: child.git.path.clone(),
            neighbor_path: neighbor,
            before,
            absent,
            closed,
            restored,
            after_retry,
            retry_owner_error,
            retry_failure,
        });
        evidence.children.push(child);
    }
    Ok(())
}

fn inspect(flow: &Flow<'_>, label: &str, original: &str, neighbor: Option<&str>) -> Progress<Site> {
    git::python(
        flow,
        label,
        &Parameters {
            action: "read",
            original,
            neighbor,
            expected: None,
        },
        SCRIPT,
    )
}

fn check_parent(parent: &Git, child: &Git, site: &Site) -> Result<()> {
    require(
        site.parent_path == parent.path
            && site.parent_head == parent.head
            && site.common_dir == parent.common_dir
            && git::refs_preserved(&parent.refs, &site.refs)
            && git::refs_preserved(&child.refs, &site.refs),
        "NotPresent probe changed parent identity or lost an originally present ref",
    )
}

fn check_present_child(child: &Git, inventory: &Inventory) -> Result<()> {
    require(
        inventory.path == child.path
            && inventory.exists
            && inventory.head.as_deref() == Some(child.head.as_str())
            && inventory.common_dir.as_deref() == Some(child.common_dir.as_str())
            && inventory.branch == child.branch
            && inventory.detached == Some(child.detached)
            && inventory.git_dir.as_deref() == Some(child.git_dir.as_str())
            && inventory.admin_backlink == child.admin_backlink
            && inventory.status.as_deref() == Some(child.status.as_str())
            && inventory
                .tree_digest
                .as_ref()
                .is_some_and(|digest| !digest.is_empty())
            && inventory.entries > 0
            && child.files.iter().all(|(name, content)| {
                inventory.files.get(name).is_some_and(|bytes| {
                    bytes.as_deref() == content.as_ref().map(|text| text.as_bytes())
                })
            }),
        "NotPresent original directory does not match its actual completed child report",
    )
}

fn same_contents(a: &Inventory, b: &Inventory) -> bool {
    a.exists
        && b.exists
        && a.head == b.head
        && a.common_dir == b.common_dir
        && a.branch == b.branch
        && a.detached == b.detached
        && a.git_dir == b.git_dir
        && a.admin_backlink == b.admin_backlink
        && a.status == b.status
        && a.files == b.files
        && a.tree_digest == b.tree_digest
        && a.entries == b.entries
}

fn check_registration(child: &Git, site: &Site, registered: bool) -> Result<()> {
    let rows: Vec<_> = site
        .worktrees
        .iter()
        .filter(|tree| tree.path == child.path)
        .collect();
    require(
        if registered {
            rows.len() == 1
                && rows[0].branch
                    == child
                        .branch
                        .as_ref()
                        .map(|branch| format!("refs/heads/{branch}"))
                && rows[0].detached == child.detached
                && rows[0].head == child.head
        } else {
            rows.is_empty()
        },
        "NotPresent exact registration presence/branch/HEAD differs from observed expectation",
    )
}

fn unchanged_registrations(before: &Site, after: &Site, path: &str) -> bool {
    before
        .worktrees
        .iter()
        .filter(|tree| tree.path != path)
        .eq(after.worktrees.iter().filter(|tree| tree.path != path))
}

fn check_absent(parent: &Git, child: &Git, site: &Site, registered: bool) -> Result<()> {
    check_parent(parent, child, site)?;
    require(
        site.original.path == child.path && !site.original.exists,
        "NotPresent original path still exists",
    )?;
    check_registration(child, site, registered)
}

fn require_member(result: &Closed, child: &Git, id: &str, registered: bool) -> Result<()> {
    require(
        result.target == id
            && result.agents.len() == 1
            && result.agents[0].agent_id == id
            && result.agents[0].execution_closed
            && matches!(&result.agents[0].worktree_cleanup, WorktreeCleanup::NotPresent { path, registration_present }
            if path == &child.path && *registration_present == registered),
        "NotPresent close lost exact target/executionClosed/path/registrationPresent facts",
    )
}

fn require_not_present(result: &Closed, child: &Git, id: &str, registered: bool) -> Result<()> {
    require(
        result.error.is_none() && result.succeeded_for(id),
        "NotPresent close returned an error or incomplete outcome",
    )?;
    require_member(result, child, id, registered)
}

fn successful_text(flow: &Flow<'_>, label: &str, id: &str) -> Result<String> {
    let call_id = format!("{}-{label}", flow.prefix);
    let (index, output) = flow
        .request
        .tool_call_output(&call_id, "close_agent", &json!({"target":id}))?
        .context("NotPresent close lost actual call output")?;
    match output {
        ToolCallOutput::Immediate(text) => Ok(text),
        ToolCallOutput::Pending { task_id, .. } => {
            let completion = flow
                .request
                .task_completion_after(index, &task_id, "close_agent")?
                .context("NotPresent close has no actual terminal report")?;
            require(
                completion.status == TaskCompletionStatus::Succeeded,
                "NotPresent close did not really succeed",
            )?;
            Ok(completion.projection)
        }
    }
}

pub(super) fn verify_reopened(
    flow: &Flow<'_>,
    label: &str,
    parent: &Git,
    child: &Child,
    case: &AbsentCase,
    close: &Closed,
) -> Progress<()> {
    require(
        case.child_id == child.spawn.agent_id && case.original_path == child.git.path,
        "reopened NotPresent evidence belongs to a different actual child",
    )?;
    require_not_present(
        close,
        &child.git,
        &child.spawn.agent_id,
        case.registration_present,
    )?;
    let actual = inspect(
        flow,
        &format!("{label}-not-present-site"),
        &case.original_path,
        case.neighbor_path.as_deref(),
    )?;
    check_parent(parent, &child.git, &actual)?;
    check_registration(&child.git, &actual, case.registration_present)?;
    let final_site = case.after_retry.as_ref().unwrap_or(&case.closed);
    require(
        actual.original == final_site.original && actual.neighbor == final_site.neighbor,
        "reopened NotPresent original or neighboring directory changed",
    )?;
    Ok(())
}
