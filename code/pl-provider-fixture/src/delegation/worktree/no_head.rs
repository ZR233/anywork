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
    symbolic_ref: String,
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
    original_symbolic_ref: String,
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
if action == 'unborn':
    assert git('symbolic-ref', 'HEAD').strip() == original
    assert not git('status', '--porcelain')
    assert git('rev-parse', '--verify', 'HEAD').strip() == params['head']
    assert unborn not in dict(line.split(' ', 1) for line in git('for-each-ref', '--format=%(refname) %(objectname)').splitlines())
    git('symbolic-ref', 'HEAD', unborn)
elif action == 'restore':
    assert git('symbolic-ref', 'HEAD').strip() == unborn
    assert git('rev-parse', '--verify', original).strip() == params['head']
    git('symbolic-ref', 'HEAD', original)
else:
    assert action == 'read'
probe = subprocess.run(GIT + ['rev-parse', '--verify', 'HEAD'], text=True, capture_output=True)
files = {}
for name in ['fixture-base.txt', '.gitignore', 'fixture-parent.txt', 'fixture-dirty.txt', 'fixture-child-dirty.txt', 'fixture-child-commit.txt']:
    file = Path(name)
    files[name] = list(file.read_bytes()) if file.is_file() else None
print(json.dumps({'path':root,'commonDir':os.path.realpath(git('rev-parse','--path-format=absolute','--git-common-dir').strip()),'symbolicRef':git('symbolic-ref','HEAD').strip(),'headProbe':{'exitCode':probe.returncode,'stdout':probe.stdout,'stderr':probe.stderr},'refs':dict(line.split(' ',1) for line in git('for-each-ref','--format=%(refname) %(objectname)').splitlines()),'worktrees':registrations(),'indexEntries':git('ls-files','--stage','-z'),'indexTree':git('write-tree').strip(),'status':git('status','--porcelain'),'files':files}, sort_keys=True))
"#;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Parameters<'a> {
    action: &'a str,
    original_ref: &'a str,
    unborn_ref: &'a str,
    head: &'a str,
}

pub(super) fn run(
    flow: &Flow<'_>,
    root: &str,
    parent: &Git,
    route: &Route,
) -> Progress<NoHeadEvidence> {
    let before: NoHeadGit = git::python(
        flow,
        "no-head-before",
        &Parameters {
            action: "read",
            original_ref: "",
            unborn_ref: "",
            head: &parent.head,
        },
        SCRIPT,
    )?;
    require(
        before.path == parent.path
            && before.common_dir == parent.common_dir
            && before.status.is_empty()
            && before.head_probe.exit_code == 0
            && before.head_probe.stdout.trim() == parent.head
            && before.head_probe.stderr.is_empty()
            && before.symbolic_ref == format!("refs/heads/{}", parent.branch),
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
        original_ref: &original,
        unborn_ref: &unborn,
        head: &parent.head,
    };
    let before_rejection: NoHeadGit =
        git::python(flow, "no-head-point-unborn", &parameters, SCRIPT)?;
    require(
        before_rejection.head_probe.exit_code != 0
            && before_rejection.head_probe.stdout.is_empty()
            && !before_rejection.head_probe.stderr.is_empty()
            && before_rejection.symbolic_ref == unborn,
        "symbolic unborn HEAD was not proven by actual failed rev-parse --verify HEAD",
    )?;
    unchanged_input(&before, &before_rejection)?;
    require(
        before.worktrees.len() == before_rejection.worktrees.len()
            && before_rejection
                .worktrees
                .iter()
                .any(|tree| tree.path == parent.path && tree.branch == unborn)
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
        directory_before == directory_before_rejection,
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
        "工作区需要有效的初始 commit 才能派生工作树:",
    )?;
    let rejection = observed_failure(flow, "no-head-spawn", "spawn_agent", arguments)?;
    let after_rejection: NoHeadGit = git::python(
        flow,
        "no-head-after-rejection",
        &Parameters {
            action: "read",
            original_ref: &original,
            unborn_ref: &unborn,
            head: &parent.head,
        },
        SCRIPT,
    )?;
    let directory_after_rejection = admission::directory(flow, "no-head-directory-after", root)?;
    require(
        before_rejection == after_rejection
            && directory_before_rejection == directory_after_rejection,
        "noHEAD rejection changed files/index/refs/registrations or published a child",
    )?;
    let restored: NoHeadGit = git::python(
        flow,
        "no-head-restore-symbolic-ref",
        &Parameters {
            action: "restore",
            original_ref: &original,
            unborn_ref: &unborn,
            head: &parent.head,
        },
        SCRIPT,
    )?;
    let directory_restored = admission::directory(flow, "no-head-directory-restored", root)?;
    require(
        restored == before && directory_restored == directory_before,
        "noHEAD restoration did not recover the original clean HEAD/ref/files/index/directory",
    )?;
    Ok(NoHeadEvidence {
        original_symbolic_ref: original,
        unborn_symbolic_ref: unborn,
        before,
        before_rejection,
        after_rejection,
        restored,
        directory_before,
        directory_before_rejection,
        directory_after_rejection,
        directory_restored,
        rejection,
    })
}

fn unchanged_input(before: &NoHeadGit, after: &NoHeadGit) -> Result<()> {
    require(
        before.path == after.path
            && before.common_dir == after.common_dir
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
