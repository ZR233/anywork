#[path = "../../tools/support/git/fixtures/downstream/tests/support/mod.rs"]
mod support;

use std::{
    error::Error,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};

use pl_agent_tool::Tool;
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_tool::{
    execution::{ExecutionBackend, ExecutionOutput, ExecutionRequest, LocalExecutionBackend},
    git::{GitHostError, GitTool, GitToolKind, GitWorkspaceConfig, NoGitCredentialProvider},
};
use serde_json::{Value, json};
use support::{Repository, git};

fn context() -> CallContext {
    CallContext {
        thread_id: "git-binding".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}

fn input(raw: &str) -> OpaquePayload {
    OpaquePayload::new("application/json", 1, raw).unwrap()
}

async fn execute(
    config: &GitWorkspaceConfig,
    kind: GitToolKind,
    raw: &str,
) -> Result<ToolOutput, ToolError> {
    let definition = kind.definition();
    let tool = GitTool::new(
        kind,
        config.clone(),
        Arc::new(LocalExecutionBackend),
        Arc::new(NoGitCredentialProvider),
        definition.clone(),
    );
    assert_eq!(tool.definition(), &definition);
    let result = tool.execute(input(raw), context()).await?;
    assert_eq!(result.payload().format(), "pl.tool.git");
    assert_eq!(result.payload().version(), 1);
    Ok(result)
}

fn payload(output: &ToolOutput) -> Value {
    serde_json::from_str(output.payload().content()).unwrap()
}

#[tokio::test]
async fn production_binding_dispatches_all_eight_independent_tools_with_existing_payloads() {
    let repo = Repository::new();
    let mut config = GitWorkspaceConfig::local(&repo.worktree).with_native_credentials();
    config.default_push_branch = Some("topic".into());
    execute(&config, GitToolKind::Commit, r#"{"message":"initial"}"#)
        .await
        .unwrap();
    let initial = git(&repo.worktree, &["rev-parse", "HEAD"]);
    assert!(
        payload(&execute(&config, GitToolKind::Status, "{}").await.unwrap())["stdout"]
            .as_str()
            .unwrap()
            .starts_with("## main")
    );
    execute(&config, GitToolKind::Push, r#"{"branch":"main"}"#)
        .await
        .unwrap();
    execute(
        &config,
        GitToolKind::Branch,
        r#"{"action":"create","name":"topic"}"#,
    )
    .await
    .unwrap();
    std::fs::write(repo.worktree.join("tracked.txt"), "adapter change\n").unwrap();
    assert!(
        payload(&execute(&config, GitToolKind::Diff, "{}").await.unwrap())["stdout"]
            .as_str()
            .unwrap()
            .contains("+adapter change")
    );
    execute(
        &config,
        GitToolKind::Commit,
        r#"{"message":"changed","all":true}"#,
    )
    .await
    .unwrap();
    execute(&config, GitToolKind::Push, "{}").await.unwrap();
    assert_eq!(
        git(&repo.remote, &["rev-parse", "refs/heads/topic"]),
        git(&repo.worktree, &["rev-parse", "HEAD"])
    );
    execute(&config, GitToolKind::Fetch, "{}").await.unwrap();
    assert_eq!(
        payload(
            &execute(&config, GitToolKind::WorkspaceInfo, "{}")
                .await
                .unwrap()
        ),
        json!({
            "clone": repo.worktree, "worktree": repo.worktree,
        })
    );
    assert_eq!(
        payload(
            &execute(&config, GitToolKind::SyncDefaultBranch, "{}")
                .await
                .unwrap()
        ),
        json!({
            "clone": repo.worktree, "worktree": repo.worktree,
            "forced": false, "preservedChanges": false,
        })
    );
    assert_eq!(git(&repo.worktree, &["rev-parse", "HEAD"]), initial);
    let failure = execute(&config, GitToolKind::Commit, r#"{"message":"empty"}"#)
        .await
        .unwrap_err();
    let source = failure
        .source
        .downcast_ref::<GitHostError>()
        .unwrap()
        .original();
    assert_eq!(source.observed().unwrap().payload()["status"], 1);
    assert!(
        source
            .observed()
            .unwrap()
            .stdout()
            .contains("nothing to commit")
    );
}

#[derive(Debug, Default)]
struct RefusingBackend(AtomicUsize);

impl ExecutionBackend for RefusingBackend {
    type Error = std::io::Error;

    async fn run(&self, _request: ExecutionRequest) -> Result<ExecutionOutput, Self::Error> {
        self.0.fetch_add(1, Ordering::SeqCst);
        Err(std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "fixture-private-backend-diagnostic",
        ))
    }
}

#[tokio::test]
async fn encoding_cancellation_and_domain_validation_are_enforced_before_host_execution() {
    let backend = Arc::new(RefusingBackend::default());
    let kind = GitToolKind::Diff;
    let tool = GitTool::new(
        kind,
        GitWorkspaceConfig::local("unused"),
        backend.clone(),
        Arc::new(NoGitCredentialProvider),
        kind.definition(),
    );
    let error = tool
        .execute(OpaquePayload::text("{}"), context())
        .await
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("unsupported Git argument encoding")
    );
    let context = context();
    context.cancellation.cancel();
    let error = tool.execute(input("{}"), context).await.unwrap_err();
    assert!(error.source.is::<pl_core::thread::ThreadError>());
    let error = tool
        .execute(input(r#"{"path":"../outside"}"#), self::context())
        .await
        .unwrap_err();
    assert!(error.to_string().contains("unsafe git path"));
    assert_eq!(backend.0.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn host_backend_errors_keep_the_concrete_source_without_retry() {
    let backend = Arc::new(RefusingBackend::default());
    let kind = GitToolKind::Status;
    let tool = GitTool::new(
        kind,
        GitWorkspaceConfig::local("unused"),
        backend.clone(),
        Arc::new(NoGitCredentialProvider),
        kind.definition(),
    );
    let error = tool.execute(input("{}"), context()).await.unwrap_err();
    assert_public_diagnostic(&error, "fixture-private-backend-diagnostic");
    let mut source: &(dyn Error + 'static) = error
        .source
        .downcast_ref::<GitHostError>()
        .unwrap()
        .original();
    let original = loop {
        if let Some(error) = source.downcast_ref::<std::io::Error>() {
            break error;
        }
        source = source
            .source()
            .expect("original backend error must remain in the trusted source chain");
    };
    assert_eq!(original.kind(), std::io::ErrorKind::PermissionDenied);
    assert_eq!(backend.0.load(Ordering::SeqCst), 1);
}

#[derive(Debug)]
struct SensitiveRemoteBackend;

impl ExecutionBackend for SensitiveRemoteBackend {
    type Error = pl_tool::remote::RemoteExecutionError;

    async fn run(&self, _request: ExecutionRequest) -> Result<ExecutionOutput, Self::Error> {
        Err(pl_tool::remote::RemoteExecutionError::Spawn {
            source: pl_tool::remote::RemoteClientError::Protocol(
                "fixture-private-remote-diagnostic".into(),
            ),
        })
    }
}

#[tokio::test]
async fn retained_remote_sources_must_not_publish_private_diagnostics_to_history() {
    let kind = GitToolKind::Status;
    let tool = GitTool::new(
        kind,
        GitWorkspaceConfig::local("unused"),
        Arc::new(SensitiveRemoteBackend),
        Arc::new(NoGitCredentialProvider),
        kind.definition(),
    );
    let error = tool.execute(input("{}"), context()).await.unwrap_err();
    assert_public_diagnostic(&error, "fixture-private-remote-diagnostic");
    assert!(error.to_string().contains("remote command spawn failed"));
    let mut source: &(dyn Error + 'static) = error
        .source
        .downcast_ref::<GitHostError>()
        .unwrap()
        .original();
    loop {
        if let Some(remote) = source.downcast_ref::<pl_tool::remote::RemoteExecutionError>() {
            let pl_tool::remote::RemoteExecutionError::Spawn { source } = remote else {
                panic!("not the original remote failure")
            };
            assert!(
                source
                    .to_string()
                    .contains("fixture-private-remote-diagnostic")
            );
            break;
        }
        source = source
            .source()
            .expect("native remote source must be retained for trusted inspection");
    }
}

fn assert_public_diagnostic(error: &ToolError, private: &str) {
    let mut source: Option<&(dyn Error + 'static)> = Some(error);
    while let Some(error) = source {
        assert!(!error.to_string().contains(private));
        assert!(!format!("{error:?}").contains(private));
        assert!(!error.is::<pl_tool_git_support::GitError>());
        assert!(!error.is::<pl_tool::remote::RemoteExecutionError>());
        source = error.source();
    }
    let history = serde_json::to_string(&error).unwrap();
    assert!(
        !history.contains(private),
        "private remote source escaped its public diagnostic boundary: {history}"
    );
}

#[derive(Debug)]
struct PrivateCredentialProvider;

impl pl_tool::git::GitCredentialProvider for PrivateCredentialProvider {
    type Error = std::io::Error;

    async fn credential(
        &self,
        _request: pl_tool::git::GitCredentialRequest,
    ) -> Result<Option<pl_tool::git::GitCredential>, Self::Error> {
        Err(std::io::Error::other("fixture-private-credential-token"))
    }
}

#[tokio::test]
async fn credential_source_is_retained_without_publishing_its_private_diagnostic() {
    let backend = Arc::new(RefusingBackend::default());
    let kind = GitToolKind::Fetch;
    let tool = GitTool::new(
        kind,
        GitWorkspaceConfig::local("unused"),
        backend.clone(),
        Arc::new(PrivateCredentialProvider),
        kind.definition(),
    );
    let error = tool.execute(input("{}"), context()).await.unwrap_err();
    assert_public_diagnostic(&error, "fixture-private-credential-token");
    let original = error
        .source
        .downcast_ref::<GitHostError>()
        .unwrap()
        .original();
    let original = original
        .source()
        .unwrap()
        .downcast_ref::<std::io::Error>()
        .unwrap();
    assert!(
        original
            .to_string()
            .contains("fixture-private-credential-token")
    );
    assert_eq!(backend.0.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn host_error_source_retains_side_effect_observations() {
    let repo = Repository::new();
    git(&repo.worktree, &["commit", "-m", "initial"]);
    std::fs::write(repo.worktree.join("local-note"), "keep\n").unwrap();
    let mut config = GitWorkspaceConfig::local(&repo.worktree).with_native_credentials();
    config.remote_url = Some(repo.worktree.join("not-a-remote").to_str().unwrap().into());
    let error = execute(
        &config,
        GitToolKind::SyncDefaultBranch,
        r#"{"preserveChanges":true}"#,
    )
    .await
    .unwrap_err();
    let original = error
        .source
        .downcast_ref::<GitHostError>()
        .unwrap()
        .original();
    let pl_tool_git_support::GitError::AfterCommands { completed, source } = original else {
        panic!("missing prior side effects")
    };
    assert_eq!(completed.len(), 2);
    assert!(completed[0].stdout().contains("Saved working directory"));
    assert!(matches!(
        source.as_ref(),
        pl_tool_git_support::GitError::Command { .. }
    ));
    assert_ne!(original.observed().unwrap().payload()["status"], 0);
    assert_eq!(git(&repo.worktree, &["stash", "list"]).lines().count(), 1);
    assert!(!repo.worktree.join("local-note").exists());
}
