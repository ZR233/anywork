mod support;

use std::{
    error::Error,
    path::PathBuf,
    process::Command,
    sync::{Arc, Mutex},
};

use pl_agent_tool::{
    Tool, ToolDefinition, ToolHandle,
    typed::{ArgumentError, decode_json, input_schema_for},
};
use pl_tool_git_support::*;
use serde_json::{Value, json};
use support::{Repository, git};

type IndependentTool = ToolHandle<String, (), GitOutput, GitError>;

#[derive(Debug)]
struct Process;

impl GitExecutor for Process {
    type Error = std::io::Error;

    async fn run(&self, command: GitCommand) -> Result<GitCommandOutput, Self::Error> {
        let output = Command::new(&command.program)
            .args(&command.args)
            .current_dir(&command.cwd)
            .envs(&command.env)
            .output()?;
        Ok(GitCommandOutput {
            status: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

fn runner(config: &GitWorkspaceConfig) -> GitRunner<Process> {
    GitRunner::new(config.clone(), Arc::new(Process))
}

fn network(config: &GitWorkspaceConfig) -> GitNetwork<Process, NoGitCredentialProvider> {
    GitNetwork::new(runner(config), Arc::new(NoGitCredentialProvider))
}

fn definitions() -> Vec<ToolDefinition> {
    vec![
        pl_tool_git_status::definition(),
        pl_tool_git_diff::definition(),
        pl_tool_git_branch::definition(),
        pl_tool_git_fetch::definition(),
        pl_tool_git_commit::definition(),
        pl_tool_git_push::definition(),
        pl_tool_git_workspace_info::definition(),
        pl_tool_git_sync_default_branch::definition(),
    ]
}

#[test]
fn declarations_and_strict_wire_contract_match_the_pre_migration_tools() {
    let baseline: Value = serde_json::from_str(include_str!("definitions.json")).unwrap();
    assert_eq!(serde_json::to_value(definitions()).unwrap(), baseline);

    let fetch: pl_tool_git_fetch::GitFetchInput = decode_json("{}").unwrap();
    assert_eq!(fetch.remote(), None);
    assert_eq!(fetch.refspec, None);
    assert!(fetch.prune);
    let push: pl_tool_git_push::GitPushInput = decode_json("{}").unwrap();
    assert_eq!(push.remote(), None);
    assert_eq!(push.branch, None);
    assert!(!push.set_upstream);
    let fetch: pl_tool_git_fetch::GitFetchInput =
        decode_json(r#"{"remote":"upstream","refspec":"main","prune":false}"#).unwrap();
    assert_eq!(fetch.remote().as_deref(), Some("upstream"));
    assert_eq!(fetch.refspec.as_deref(), Some("main"));
    assert!(!fetch.prune);
    let push: pl_tool_git_push::GitPushInput =
        decode_json(r#"{"remote":"fork","branch":"topic","setUpstream":true}"#).unwrap();
    assert_eq!(push.remote().as_deref(), Some("fork"));
    assert_eq!(push.branch.as_deref(), Some("topic"));
    assert!(push.set_upstream);

    for schema in [
        input_schema_for::<pl_tool_git_fetch::GitFetchInput>(),
        input_schema_for::<pl_tool_git_push::GitPushInput>(),
    ] {
        assert_eq!(schema["additionalProperties"], false);
        assert_eq!(
            schema["properties"]["remote"]["type"],
            json!(["string", "null"])
        );
    }
    for raw in [r#"{"unexpected":1}"#, r#"{"remote":{}}"#] {
        for error in [
            decode_json::<pl_tool_git_fetch::GitFetchInput>(raw).unwrap_err(),
            decode_json::<pl_tool_git_push::GitPushInput>(raw).unwrap_err(),
        ] {
            let ArgumentError::Decode { source, .. } = error else {
                panic!("not a decode failure")
            };
            assert!(source.column() > 0);
        }
    }
    assert!(matches!(
        decode_json::<pl_tool_git_fetch::GitFetchInput>("{} {}"),
        Err(ArgumentError::Trailing { .. })
    ));
    assert!(matches!(
        decode_json::<pl_tool_git_push::GitPushInput>("{} {}"),
        Err(ArgumentError::Trailing { .. })
    ));
}

#[tokio::test]
async fn eight_independent_tools_execute_a_real_repository_lifecycle() {
    let repo = Repository::new();
    let mut config = GitWorkspaceConfig::local(&repo.worktree).with_native_credentials();
    config.default_push_branch = Some("topic".into());
    config.remote_url = Some(repo.remote.to_str().unwrap().into());
    config
        .workspace_info
        .insert("label".into(), json!("independent"));

    let commit =
        pl_tool_git_commit::GitCommit::new(runner(&config), pl_tool_git_commit::definition());
    let first = commit
        .execute(r#"{"message":"initial"}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(first.payload()["status"], 0);
    let initial = git(&repo.worktree, &["rev-parse", "HEAD"]);

    let status =
        pl_tool_git_status::GitStatus::new(runner(&config), pl_tool_git_status::definition());
    assert!(
        status
            .execute("{}".into(), ())
            .await
            .unwrap()
            .stdout()
            .starts_with("## main")
    );
    let push = pl_tool_git_push::GitPush::new(network(&config), pl_tool_git_push::definition());
    push.execute(r#"{"branch":"main","setUpstream":true}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(
        git(&repo.remote, &["rev-parse", "refs/heads/main"]),
        initial
    );

    let branch =
        pl_tool_git_branch::GitBranch::new(runner(&config), pl_tool_git_branch::definition());
    assert!(
        branch
            .execute("{}".into(), ())
            .await
            .unwrap()
            .stdout()
            .contains("main")
    );
    branch
        .execute(
            r#"{"action":"create","name":"topic","startPoint":"main"}"#.into(),
            (),
        )
        .await
        .unwrap();
    assert_eq!(
        git(&repo.worktree, &["branch", "--show-current"]).trim(),
        "topic"
    );

    std::fs::write(repo.worktree.join("tracked.txt"), "staged change\n").unwrap();
    let diff = pl_tool_git_diff::GitDiff::new(runner(&config), pl_tool_git_diff::definition());
    assert!(
        diff.execute(r#"{"path":"tracked.txt"}"#.into(), ())
            .await
            .unwrap()
            .stdout()
            .contains("+staged change")
    );
    git(&repo.worktree, &["add", "tracked.txt"]);
    assert!(
        diff.execute(r#"{"staged":true,"path":"tracked.txt"}"#.into(), ())
            .await
            .unwrap()
            .stdout()
            .contains("+staged change")
    );
    commit
        .execute(r#"{"message":"staged"}"#.into(), ())
        .await
        .unwrap();
    std::fs::write(repo.worktree.join("tracked.txt"), "tracked change\n").unwrap();
    commit
        .execute(r#"{"message":"tracked","all":true}"#.into(), ())
        .await
        .unwrap();
    push.execute(r#"{"setUpstream":true}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(
        git(&repo.remote, &["rev-parse", "refs/heads/topic"]),
        git(&repo.worktree, &["rev-parse", "HEAD"])
    );

    let fetch = pl_tool_git_fetch::GitFetch::new(network(&config), pl_tool_git_fetch::definition());
    assert_eq!(
        fetch.execute("{}".into(), ()).await.unwrap().payload()["status"],
        0
    );
    let info = pl_tool_git_workspace_info::GitWorkspaceInfo::new(
        config.clone(),
        pl_tool_git_workspace_info::definition(),
    );
    assert_eq!(
        info.execute("{}".into(), ()).await.unwrap().payload(),
        &json!({
            "clone": repo.worktree,
            "worktree": repo.worktree,
            "label": "independent",
        })
    );

    std::fs::write(repo.worktree.join("local-note"), "keep\n").unwrap();
    let sync = pl_tool_git_sync_default_branch::GitSyncDefaultBranch::new(
        network(&config),
        pl_tool_git_sync_default_branch::definition(),
    );
    let dirty = sync.execute("{}".into(), ()).await.unwrap_err();
    assert!(dirty.to_string().contains("uncommitted changes"));
    assert!(dirty.observed().is_none());
    let result = sync
        .execute(r#"{"preserveChanges":true}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(
        result.payload(),
        &json!({
            "clone": repo.worktree,
            "worktree": repo.worktree,
            "preservedChanges": true,
            "forced": false,
        })
    );
    assert_eq!(git(&repo.worktree, &["rev-parse", "HEAD"]), initial);
    assert_eq!(
        std::fs::read_to_string(repo.worktree.join("local-note")).unwrap(),
        "keep\n"
    );
    assert_eq!(
        std::fs::read_to_string(repo.worktree.join("tracked.txt")).unwrap(),
        "initial\n"
    );
    std::fs::write(repo.worktree.join(".git/info/exclude"), "ignored.tmp\n").unwrap();
    std::fs::write(repo.worktree.join("ignored.tmp"), "discard\n").unwrap();
    sync.execute(r#"{"force":true}"#.into(), ()).await.unwrap();
    assert!(!repo.worktree.join("local-note").exists());
    assert!(!repo.worktree.join("ignored.tmp").exists());
    branch
        .execute(r#"{"action":"switch","name":"main"}"#.into(), ())
        .await
        .unwrap();
    assert_eq!(
        git(&repo.worktree, &["branch", "--show-current"]).trim(),
        "main"
    );
}

#[derive(Debug, Default)]
struct Recorder(Mutex<Vec<GitCommand>>);

impl GitExecutor for Recorder {
    type Error = std::io::Error;

    async fn run(&self, command: GitCommand) -> Result<GitCommandOutput, Self::Error> {
        self.0.lock().unwrap().push(command);
        Ok(GitCommandOutput {
            status: 0,
            stdout: String::new(),
            stderr: String::new(),
        })
    }
}

#[tokio::test]
async fn semantic_and_wire_rejections_do_not_reach_the_command_capability() {
    let executor = Arc::new(Recorder::default());
    let config = GitWorkspaceConfig::local("unused").with_native_credentials();
    let make_runner = || GitRunner::new(config.clone(), executor.clone());
    let make_network = || GitNetwork::new(make_runner(), Arc::new(NoGitCredentialProvider));
    let cases: Vec<(IndependentTool, &str)> = vec![
        (
            ToolHandle::new(pl_tool_git_diff::GitDiff::new(
                make_runner(),
                pl_tool_git_diff::definition(),
            )),
            r#"{"path":"../outside"}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_diff::GitDiff::new(
                make_runner(),
                pl_tool_git_diff::definition(),
            )),
            r#"{"path":"C:\\outside"}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_branch::GitBranch::new(
                make_runner(),
                pl_tool_git_branch::definition(),
            )),
            r#"{"action":"create","name":"unsafe..branch"}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_branch::GitBranch::new(
                make_runner(),
                pl_tool_git_branch::definition(),
            )),
            r#"{"action":"switch"}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_fetch::GitFetch::new(
                make_network(),
                pl_tool_git_fetch::definition(),
            )),
            r#"{"remote":"upstream"}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_fetch::GitFetch::new(
                make_network(),
                pl_tool_git_fetch::definition(),
            )),
            r#"{"refspec":"refs/heads/other"}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_commit::GitCommit::new(
                make_runner(),
                pl_tool_git_commit::definition(),
            )),
            r#"{"message":" "}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_push::GitPush::new(
                make_network(),
                pl_tool_git_push::definition(),
            )),
            "{}",
        ),
        (
            ToolHandle::new(pl_tool_git_sync_default_branch::GitSyncDefaultBranch::new(
                make_network(),
                pl_tool_git_sync_default_branch::definition(),
            )),
            r#"{"force":true,"preserveChanges":true}"#,
        ),
        (
            ToolHandle::new(pl_tool_git_status::GitStatus::new(
                make_runner(),
                pl_tool_git_status::definition(),
            )),
            r#"{"unknown":1}"#,
        ),
    ];
    for (tool, raw) in cases {
        assert!(tool.execute(raw.into(), ()).await.is_err(), "{raw}");
    }
    assert!(executor.0.lock().unwrap().is_empty());
    let policy = GitPolicy::default();
    for refspec in [
        "main",
        "refs/heads/main",
        "refs/pull/42/head",
        "pull/42/head:pr/42",
        "refs/pull/42/head:refs/remotes/origin/pr/42",
    ] {
        policy.validate_fetch_refspec(Some(refspec)).unwrap();
    }
    for refspec in [
        "pull/no/head",
        "pull/42/head:pr/43",
        "+refs/heads/main:main",
    ] {
        assert!(policy.validate_fetch_refspec(Some(refspec)).is_err());
    }
}

#[derive(Debug)]
struct TokenProvider(Mutex<Vec<GitCredentialRequest>>);

impl GitCredentialProvider for TokenProvider {
    type Error = std::io::Error;

    async fn credential(
        &self,
        request: GitCredentialRequest,
    ) -> Result<Option<GitCredential>, Self::Error> {
        self.0.lock().unwrap().push(request);
        Ok(Some(GitCredential::new("fixture-private-token".into())))
    }
}

#[derive(Debug)]
struct CredentialProbe {
    status: i32,
    paths: Mutex<Vec<PathBuf>>,
}

impl GitExecutor for CredentialProbe {
    type Error = std::io::Error;

    async fn run(&self, command: GitCommand) -> Result<GitCommandOutput, Self::Error> {
        let token = command.env.get(GIT_TOKEN_ENV).unwrap();
        assert_eq!(command.env["GIT_TERMINAL_PROMPT"], "0");
        assert!(!format!("{command:?}").contains(token));
        assert!(!command.args.iter().any(|arg| arg.contains(token)));
        let path = PathBuf::from(&command.env["GIT_ASKPASS"]);
        let script = std::fs::read_to_string(&path)?;
        assert_eq!(script, git_askpass_script());
        assert!(!script.contains(token));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&path)?.permissions().mode() & 0o777,
                0o700
            );
            for (prompt, expected) in [("Username", "x-access-token"), ("Password", token.as_str())]
            {
                let answer = Command::new(&path)
                    .arg(prompt)
                    .envs(&command.env)
                    .output()?;
                assert!(
                    answer.status.success(),
                    "{}",
                    String::from_utf8_lossy(&answer.stderr)
                );
                assert_eq!(String::from_utf8_lossy(&answer.stdout).trim(), expected);
            }
        }
        self.paths.lock().unwrap().push(path);
        Ok(GitCommandOutput {
            status: self.status,
            stdout: format!("stdout {token}"),
            stderr: format!("stderr {token}"),
        })
    }
}

#[tokio::test]
async fn provider_credentials_redact_success_and_failure_and_always_remove_askpass() {
    for status in [0, 17] {
        let provider = Arc::new(TokenProvider(Mutex::new(Vec::new())));
        let executor = Arc::new(CredentialProbe {
            status,
            paths: Mutex::new(Vec::new()),
        });
        let network = GitNetwork::new(
            GitRunner::new(GitWorkspaceConfig::local("unused"), executor.clone()),
            provider.clone(),
        );
        let tool = pl_tool_git_push::GitPush::new(network, pl_tool_git_push::definition());
        let result = tool.execute(r#"{"branch":"topic"}"#.into(), ()).await;
        let output = match &result {
            Ok(output) => output,
            Err(error) => {
                assert!(!format!("{error:?}").contains("fixture-private-token"));
                error.observed().unwrap()
            }
        };
        assert_eq!(output.payload()["status"], status);
        assert_eq!(output.payload()["stdout"], "stdout [redacted]");
        assert_eq!(output.payload()["stderr"], "stderr [redacted]");
        assert_eq!(result.is_ok(), status == 0);
        assert_eq!(
            *provider.0.lock().unwrap(),
            vec![GitCredentialRequest {
                operation: GitCredentialOperation::Push,
                remote: "origin".into()
            }]
        );
        for path in executor.paths.lock().unwrap().iter() {
            assert!(!path.exists());
        }
    }
}

#[derive(Debug)]
struct BrokenProvider;

#[derive(Debug)]
struct CredentialUnavailable;

impl std::fmt::Display for CredentialUnavailable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("credential service unavailable")
    }
}

impl Error for CredentialUnavailable {}

impl GitCredentialProvider for BrokenProvider {
    type Error = CredentialUnavailable;

    async fn credential(
        &self,
        _request: GitCredentialRequest,
    ) -> Result<Option<GitCredential>, Self::Error> {
        Err(CredentialUnavailable)
    }
}

#[tokio::test]
async fn native_credentials_bypass_provider_and_missing_or_failed_provider_never_runs_git() {
    let executor = Arc::new(Recorder::default());
    let config = GitWorkspaceConfig::local("unused");
    let failed = pl_tool_git_fetch::GitFetch::new(
        GitNetwork::new(
            GitRunner::new(config.clone(), executor.clone()),
            Arc::new(BrokenProvider),
        ),
        pl_tool_git_fetch::definition(),
    )
    .execute("{}".into(), ())
    .await
    .unwrap_err();
    assert!(failed.source().unwrap().is::<CredentialUnavailable>());
    let missing = pl_tool_git_fetch::GitFetch::new(
        GitNetwork::new(
            GitRunner::new(config.clone(), executor.clone()),
            Arc::new(NoGitCredentialProvider),
        ),
        pl_tool_git_fetch::definition(),
    )
    .execute("{}".into(), ())
    .await
    .unwrap_err();
    assert!(missing.to_string().contains("token is not configured"));
    assert!(executor.0.lock().unwrap().is_empty());
    pl_tool_git_fetch::GitFetch::new(
        GitNetwork::new(
            GitRunner::new(config.with_native_credentials(), executor.clone()),
            Arc::new(BrokenProvider),
        ),
        pl_tool_git_fetch::definition(),
    )
    .execute("{}".into(), ())
    .await
    .unwrap();
    let commands = executor.0.lock().unwrap();
    assert_eq!(commands.len(), 1);
    assert!(commands[0].env.is_empty());
}

#[derive(Debug)]
struct PendingExecutor {
    path: Mutex<Option<PathBuf>>,
    entered: tokio::sync::Notify,
}

impl GitExecutor for PendingExecutor {
    type Error = std::io::Error;

    async fn run(&self, command: GitCommand) -> Result<GitCommandOutput, Self::Error> {
        *self.path.lock().unwrap() = Some(PathBuf::from(&command.env["GIT_ASKPASS"]));
        self.entered.notify_one();
        std::future::pending().await
    }
}

#[tokio::test]
async fn dropping_a_suspended_network_call_releases_its_askpass_file() {
    let executor = Arc::new(PendingExecutor {
        path: Mutex::new(None),
        entered: tokio::sync::Notify::new(),
    });
    let tool = pl_tool_git_fetch::GitFetch::new(
        GitNetwork::new(
            GitRunner::new(GitWorkspaceConfig::local("unused"), executor.clone()),
            Arc::new(TokenProvider(Mutex::new(Vec::new()))),
        ),
        pl_tool_git_fetch::definition(),
    );
    let task = tokio::spawn(async move { tool.execute("{}".into(), ()).await });
    executor.entered.notified().await;
    let path = executor.path.lock().unwrap().clone().unwrap();
    assert!(path.exists());
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    assert!(!path.exists());
}

#[derive(Debug, Default)]
struct BrokenExecutor(Mutex<Option<PathBuf>>);

impl GitExecutor for BrokenExecutor {
    type Error = std::io::Error;

    async fn run(&self, command: GitCommand) -> Result<GitCommandOutput, Self::Error> {
        let path = PathBuf::from(&command.env["GIT_ASKPASS"]);
        assert!(path.exists());
        *self.0.lock().unwrap() = Some(path);
        Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "executor denied command",
        ))
    }
}

#[tokio::test]
async fn executor_failure_preserves_its_source_and_removes_askpass() {
    let executor = Arc::new(BrokenExecutor::default());
    let tool = pl_tool_git_fetch::GitFetch::new(
        GitNetwork::new(
            GitRunner::new(GitWorkspaceConfig::local("unused"), executor.clone()),
            Arc::new(TokenProvider(Mutex::new(Vec::new()))),
        ),
        pl_tool_git_fetch::definition(),
    );
    let error = tool.execute("{}".into(), ()).await.unwrap_err();
    let source = error
        .source()
        .unwrap()
        .downcast_ref::<std::io::Error>()
        .unwrap();
    assert_eq!(source.kind(), std::io::ErrorKind::PermissionDenied);
    assert!(!executor.0.lock().unwrap().as_ref().unwrap().exists());
}

#[tokio::test]
async fn sync_failure_keeps_prior_side_effect_observations_without_automatic_retry() {
    let repo = Repository::new();
    git(&repo.worktree, &["commit", "-m", "initial"]);
    std::fs::write(repo.worktree.join("local-note"), "keep\n").unwrap();
    let mut config = GitWorkspaceConfig::local(&repo.worktree).with_native_credentials();
    config.remote_url = Some(repo.worktree.join("not-a-remote").to_str().unwrap().into());
    let tool = pl_tool_git_sync_default_branch::GitSyncDefaultBranch::new(
        network(&config),
        pl_tool_git_sync_default_branch::definition(),
    );
    let error = tool
        .execute(r#"{"preserveChanges":true}"#.into(), ())
        .await
        .unwrap_err();
    let GitError::AfterCommands { completed, source } = &error else {
        panic!("missing prior command observations: {error:?}");
    };
    assert_eq!(completed.len(), 2);
    assert!(completed[0].stdout().contains("Saved working directory"));
    assert!(matches!(source.as_ref(), GitError::Command { .. }));
    assert_ne!(error.observed().unwrap().payload()["status"], 0);
    assert_eq!(git(&repo.worktree, &["stash", "list"]).lines().count(), 1);
    assert!(!repo.worktree.join("local-note").exists());
    assert!(
        git(
            &repo.worktree,
            &["stash", "show", "--include-untracked", "--name-only"]
        )
        .contains("local-note")
    );
}
