//! A symbolic unborn HEAD is a real admission input, never an optional normal HEAD.
use super::*;
use std::collections::BTreeMap;

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct HeadProbe {
    exit_code: i32,
    stdout: String,
    stderr: String,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct NoHeadGit {
    path: String,
    common_dir: String,
    git_dir: String,
    admin_backlink: Option<String>,
    symbolic_ref: Option<String>,
    head_probe: HeadProbe,
    refs: BTreeMap<String, String>,
    worktrees: Vec<git::Registration>,
    index_entries: String,
    index_tree: String,
    status: String,
    files: BTreeMap<String, Option<Vec<u8>>>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct NoHeadEvidence {
    original_symbolic_ref: Option<String>,
    unborn_symbolic_ref: String,
    before: NoHeadGit,
    before_rejection: NoHeadGit,
    after_rejection: NoHeadGit,
    restored: NoHeadGit,
    directory_before: Vec<DirectoryIdentity>,
    directory_before_rejection: Vec<DirectoryIdentity>,
    directory_after_rejection: Vec<DirectoryIdentity>,
    directory_restored: Vec<DirectoryIdentity>,
    rejection: FailedCallEvidence,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct FailedCallEvidence {
    call_id: String,
    tool: String,
    task_id: String,
    status: FailedStatus,
    pub output: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum FailedStatus {
    Failed,
}

const SCRIPT: &str = r#"
action = params['action']
original = params['originalRef']
unborn = params['unbornRef']
assert root == params['path'], 'noHEAD caller path changed; HEAD untouched'
common, admin, backlink = physical(root)
assert (common, admin, backlink) == (params['commonDir'], params['gitDir'], params['adminBacklink']), 'noHEAD physical identity changed; HEAD untouched'
if action == 'unborn':
    assert symbolic_branch(full=True) == original
    assert not git('status', '--porcelain')
    assert git('rev-parse', '--verify', 'HEAD').strip() == params['head']
    assert unborn not in dict(line.split(' ', 1) for line in git('for-each-ref', '--format=%(refname) %(objectname)').splitlines())
    git('symbolic-ref', 'HEAD', unborn)
elif action == 'restore':
    current = symbolic_branch(full=True)
    if current == unborn:
        if original is None:
            git('update-ref', '--no-deref', 'HEAD', params['head'])
        else:
            assert git('rev-parse', '--verify', original).strip() == params['head'], 'original branch changed; HEAD not restored'
            git('symbolic-ref', 'HEAD', original)
    else:
        assert current == original, 'unexpected HEAD mode; restoration refused'
        assert git('rev-parse', '--verify', 'HEAD').strip() == params['head'], 'unexpected original HEAD OID; restoration refused'
    assert symbolic_branch(full=True) == original, 'HEAD mode restoration was not confirmed'
    assert git('rev-parse', '--verify', 'HEAD').strip() == params['head'], 'HEAD OID restoration was not confirmed'
else:
    assert action == 'read'
probe = subprocess.run(GIT + ['rev-parse', '--verify', 'HEAD'], text=True, capture_output=True)
common, admin, backlink = physical(root)
files = {}
for name in ['fixture-base.txt', '.gitignore', 'fixture-parent.txt', 'fixture-dirty.txt', 'fixture-child-dirty.txt', 'fixture-child-commit.txt']:
    file = Path(name)
    files[name] = list(file.read_bytes()) if file.is_file() else None
print(json.dumps({'path':root,'commonDir':common,'gitDir':admin,'adminBacklink':backlink,'symbolicRef':symbolic_branch(full=True),'headProbe':{'exitCode':probe.returncode,'stdout':probe.stdout,'stderr':probe.stderr},'refs':dict(line.split(' ',1) for line in git('for-each-ref','--format=%(refname) %(objectname)').splitlines()),'worktrees':registrations(),'indexEntries':git('ls-files','--stage','-z'),'indexTree':git('write-tree').strip(),'status':git('status','--porcelain'),'files':files}, sort_keys=True))
"#;

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
struct Parameters<'a> {
    action: &'a str,
    original_ref: Option<&'a str>,
    unborn_ref: &'a str,
    head: &'a str,
    path: &'a str,
    common_dir: &'a str,
    git_dir: &'a str,
    admin_backlink: Option<&'a str>,
}

#[derive(Clone, Copy)]
struct Probe<'a> {
    root: &'a str,
    parent: &'a Git,
    route: &'a Route,
    before: &'a NoHeadGit,
    directory_before: &'a [DirectoryIdentity],
    parameters: Parameters<'a>,
}

struct ExerciseEvidence {
    before_rejection: NoHeadGit,
    after_rejection: NoHeadGit,
    directory_before_rejection: Vec<DirectoryIdentity>,
    directory_after_rejection: Vec<DirectoryIdentity>,
    rejection: FailedCallEvidence,
}

pub(super) fn run(
    flow: &Flow<'_>,
    root: &str,
    parent: &Git,
    route: &Route,
) -> Progress<NoHeadEvidence> {
    let read_parameters = Parameters {
        action: "read",
        original_ref: None,
        unborn_ref: "",
        head: &parent.head,
        path: &parent.path,
        common_dir: &parent.common_dir,
        git_dir: &parent.git_dir,
        admin_backlink: parent.admin_backlink.as_deref(),
    };
    let before: NoHeadGit = git::python(flow, "no-head-before", &read_parameters, SCRIPT)?;
    require(
        before.path == parent.path
            && before.common_dir == parent.common_dir
            && before.git_dir == parent.git_dir
            && before.admin_backlink == parent.admin_backlink
            && parent.detached == before.symbolic_ref.is_none()
            && before.status.is_empty()
            && before.head_probe.exit_code == 0
            && before.head_probe.stdout.trim() == parent.head
            && before.head_probe.stderr.is_empty()
            && before.symbolic_ref
                == parent
                    .branch
                    .as_ref()
                    .map(|branch| format!("refs/heads/{branch}")),
        "noHEAD preparation lost the real clean caller identity/HEAD/symbolic ref",
    )?;
    let original = before.symbolic_ref.clone();
    let unborn = format!(
        "refs/heads/fixture-no-head-{}",
        super::super::input_digest(&format!("{root}:{}", flow.prefix))
    );
    require(
        !before.refs.contains_key(&unborn),
        "noHEAD synthetic symbolic branch already exists",
    )?;
    let directory_before = admission::directory(flow, "no-head-directory-before", root)?;
    let parameters = Parameters {
        action: "unborn",
        original_ref: original.as_deref(),
        unborn_ref: &unborn,
        ..read_parameters
    };
    let probe = Probe {
        root,
        parent,
        route,
        before: &before,
        directory_before: &directory_before,
        parameters,
    };
    // Calls are normal cross-request progress. Only a real failure enters
    // recovery; replay reconstructs that same error from committed tool results.
    let outcome = match exercise(flow, &probe) {
        Ok(evidence) => Ok(evidence),
        Err(Stop::Call(call)) => return Err(Stop::Call(call)),
        Err(Stop::Failed(error)) => Err(error),
    };
    if outcome.is_err() {
        match setting_finished(flow) {
            Ok(()) => {}
            Err(Stop::Call(call)) => return Err(Stop::Call(call)),
            Err(Stop::Failed(error)) => {
                return Err(recovery_error(
                    outcome.err(),
                    error.context(
                        "setting outcome is not proven quiescent; HEAD restoration NOT attempted",
                    ),
                ));
            }
        }
    }
    let (restored, directory_restored) = match restore(flow, &probe) {
        Ok(evidence) => evidence,
        Err(Stop::Call(call)) => return Err(Stop::Call(call)),
        Err(Stop::Failed(error)) => return Err(recovery_error(outcome.err(), error)),
    };
    let exercise = match outcome {
        Ok(evidence) => evidence,
        Err(error) => return Err(Stop::Failed(error.context(
            "noHEAD original HEAD/mode/OID and complete input baseline verified after recovery; original failure retained"))),
    };
    Ok(NoHeadEvidence {
        original_symbolic_ref: original,
        unborn_symbolic_ref: unborn,
        before,
        before_rejection: exercise.before_rejection,
        after_rejection: exercise.after_rejection,
        restored,
        directory_before,
        directory_before_rejection: exercise.directory_before_rejection,
        directory_after_rejection: exercise.directory_after_rejection,
        directory_restored,
        rejection: exercise.rejection,
    })
}

fn exercise(flow: &Flow<'_>, probe: &Probe<'_>) -> Progress<ExerciseEvidence> {
    let Probe {
        root,
        parent,
        route,
        before,
        directory_before,
        parameters,
    } = *probe;
    let unborn = parameters.unborn_ref;
    let before_rejection: NoHeadGit =
        git::python(flow, "no-head-point-unborn", &parameters, SCRIPT)?;
    require(
        before_rejection.head_probe.exit_code != 0
            && before_rejection.head_probe.stdout.is_empty()
            && !before_rejection.head_probe.stderr.is_empty()
            && before_rejection.symbolic_ref.as_deref() == Some(unborn),
        "symbolic unborn HEAD was not proven by actual failed rev-parse --verify HEAD",
    )?;
    unchanged_input(before, &before_rejection)?;
    require(
        before.worktrees.len() == before_rejection.worktrees.len()
            && before_rejection.worktrees.iter().any(|tree| {
                tree.path == parent.path && tree.branch.as_deref() == Some(unborn) && !tree.detached
            })
            && before
                .worktrees
                .iter()
                .filter(|tree| tree.path != parent.path)
                .eq(before_rejection
                    .worktrees
                    .iter()
                    .filter(|tree| tree.path != parent.path)),
        "pointing noHEAD changed a worktree registration other than the caller symbolic HEAD",
    )?;
    let directory_before_rejection = admission::directory(flow, "no-head-directory-unborn", root)?;
    require(
        directory_before == directory_before_rejection.as_slice(),
        "noHEAD preparation published a child",
    )?;
    let message = format!(
        "{}\nDELEGATION_EXPECT_COMPLETION:{}",
        marker("read", parent),
        serde_json::to_string(&completion_expectation(route)?)
            .context("encode noHEAD expected completion")?
    );
    let arguments = json!({"profileId":"worktree_executor","taskSummary":"Reject actual unborn caller HEAD","message":message,"modelSelection":route});
    flow.rejected(
        "no-head-spawn",
        "spawn_agent",
        arguments.clone(),
        "工作区没有有效的 HEAD commit；请先完成初始 commit 后重试",
    )?;
    let rejection = observed_failure(flow, "no-head-spawn", "spawn_agent", arguments)?;
    let after_rejection: NoHeadGit = git::python(
        flow,
        "no-head-after-rejection",
        &Parameters {
            action: "read",
            ..parameters
        },
        SCRIPT,
    )?;
    let directory_after_rejection = admission::directory(flow, "no-head-directory-after", root)?;
    require(
        before_rejection == after_rejection
            && directory_before_rejection == directory_after_rejection,
        "noHEAD rejection changed files/index/refs/registrations or published a child",
    )?;
    Ok(ExerciseEvidence {
        before_rejection,
        after_rejection,
        directory_before_rejection,
        directory_after_rejection,
        rejection,
    })
}

fn restore(flow: &Flow<'_>, probe: &Probe<'_>) -> Progress<(NoHeadGit, Vec<DirectoryIdentity>)> {
    let restored: NoHeadGit = git::python(
        flow,
        "no-head-restore-symbolic-ref",
        &Parameters {
            action: "restore",
            ..probe.parameters
        },
        SCRIPT,
    )?;
    let directory_restored = admission::directory(flow, "no-head-directory-restored", probe.root)?;
    require(
        restored.path == probe.before.path
            && restored.common_dir == probe.before.common_dir
            && restored.git_dir == probe.before.git_dir
            && restored.admin_backlink == probe.before.admin_backlink
            && restored.symbolic_ref == probe.before.symbolic_ref
            && restored.head_probe == probe.before.head_probe,
        "noHEAD original physical identity/HEAD mode/OID restoration was not confirmed",
    )?;
    require(
        restored == *probe.before && directory_restored.as_slice() == probe.directory_before,
        &format!(
            "noHEAD original HEAD/mode/OID verified, but the input baseline differs; expected directory {:?}, observed {:?}; unknown members/data preserved",
            probe.directory_before, directory_restored
        ),
    )?;
    Ok((restored, directory_restored))
}

fn recovery_error(original: Option<anyhow::Error>, recovery: anyhow::Error) -> Stop {
    match original {
        Some(original) => Stop::Failed(anyhow::Error::new(RecoveryFailure { original, recovery })),
        None => {
            Stop::Failed(recovery.context(
                "noHEAD exercise finished but restoring/verifying the original input failed",
            ))
        }
    }
}

#[derive(Debug)]
struct RecoveryFailure {
    original: anyhow::Error,
    recovery: anyhow::Error,
}

impl std::fmt::Display for RecoveryFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "noHEAD recovery/verification failed or remains unverified: {:#}; original failure retained",
            self.recovery
        )
    }
}

impl std::error::Error for RecoveryFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(self.original.as_ref())
    }
}

#[derive(Deserialize)]
struct EndedCommand {
    state: EndedState,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum EndedState {
    Final,
}

/// A lost/invalid setting result does not prove absence of side effects. Before
/// any recovery write, require its exact task and a final process projection.
/// Running/unknown commands remain explicitly unrecovered rather than racing
/// a command that might still switch HEAD after a recovery no-op.
fn setting_finished(flow: &Flow<'_>) -> Progress<()> {
    let call_id = format!("{}-no-head-point-unborn", flow.prefix);
    let calls: Vec<_> = flow
        .request
        .input
        .iter()
        .filter(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(&call_id))
        .collect();
    require(
        calls.len() == 1,
        "noHEAD setting call identity is missing/duplicated; outcome unknown",
    )?;
    let call = calls[0];
    require(
        call.name.as_deref() == Some("exec"),
        "noHEAD setting call was not exec",
    )?;
    let arguments: Value = serde_json::from_str(
        call.arguments
            .as_deref()
            .context("noHEAD setting call lost its arguments")?,
    )
    .context("decode original noHEAD setting arguments")?;
    let (index, output) = flow
        .request
        .tool_call_output(&call_id, "exec", &arguments)?
        .context("noHEAD setting has no committed output; outcome unknown")?;
    let task_id = match &output {
        ToolCallOutput::Immediate(_) => format!("task:{call_id}"),
        ToolCallOutput::Pending { task_id, .. } => task_id.clone(),
    };
    let query: ToolTaskQuery = flow.read(
        "no-head-setting-terminal-status",
        "get_tool_task",
        json!({"taskId":task_id}),
    )?;
    require(
        query.task.task_id == task_id
            && query.task.tool_id == "exec"
            && query.task.status != ToolTaskStatus::Running,
        &format!(
            "noHEAD setting task {task_id} has no verified terminal status; restoration refused"
        ),
    )?;
    let text = match output {
        ToolCallOutput::Immediate(text) => text,
        ToolCallOutput::Pending { .. } => {
            // Observe only the original committed completion; never start a
            // second waiting path after the setting owner has already failed.
            flow.request
                .task_completion_after(index, &task_id, "exec")?
                .context("noHEAD setting has no terminal process delivery; restoration unconfirmed/not attempted")?
                .projection
        }
    };
    let ended: EndedCommand = exec::first(&text).context(
        "noHEAD setting lacks a final process snapshot; HEAD restoration remains unverified",
    )?;
    let EndedState::Final = ended.state;
    Ok(())
}

fn unchanged_input(before: &NoHeadGit, after: &NoHeadGit) -> Result<()> {
    require(
        before.path == after.path
            && before.common_dir == after.common_dir
            && before.git_dir == after.git_dir
            && before.admin_backlink == after.admin_backlink
            && before.refs == after.refs
            && before.index_entries == after.index_entries
            && before.index_tree == after.index_tree
            && before.files == after.files,
        "noHEAD preparation changed the original repository/index/files/refs",
    )
}

/// Evidence-only projection after Flow has resolved the call (rejected/read).
/// There is no second waiter, result decoder or alternate asynchronous owner.
pub(super) fn observed_failure(
    flow: &Flow<'_>,
    label: &str,
    tool: &str,
    arguments: Value,
) -> Progress<FailedCallEvidence> {
    let call_id = format!("{}-{label}", flow.prefix);
    let (call_index, output) = flow
        .request
        .tool_call_output(&call_id, tool, &arguments)?
        .context("failed tool evidence lost its actual call/output")?;
    let (task_id, output) = match output {
        ToolCallOutput::Immediate(text) => {
            // Same exact core task identity and label already used by Flow::rejected.
            let task_id = format!("task:{call_id}");
            let query: ToolTaskQuery = flow.read(
                &format!("{label}-rejection-task-status"),
                "get_tool_task",
                json!({"taskId":task_id}),
            )?;
            require(
                query.task.task_id == task_id
                    && query.task.tool_id == tool
                    && query.task.status == ToolTaskStatus::Failed
                    && !query.task.cancel_requested,
                "negative tool evidence is not the exact real Failed task",
            )?;
            (task_id, text)
        }
        ToolCallOutput::Pending { task_id, .. } => {
            let completed = flow
                .request
                .task_completion_after(call_index, &task_id, tool)?
                .context("Flow did not resolve the failed tool's actual terminal report")?;
            require(
                completed.status == TaskCompletionStatus::Failed,
                "negative tool evidence is not an actual Failed terminal report",
            )?;
            (task_id, completed.projection)
        }
    };
    Ok(FailedCallEvidence {
        call_id,
        tool: tool.into(),
        task_id,
        status: FailedStatus::Failed,
        output,
    })
}
