#[path = "support/binding_host.rs"]
mod host;
#[path = "../../tools/support/git/fixtures/downstream/tests/support/mod.rs"]
mod support;

use std::{
    error::Error,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

use pl_agent_tool::Tool;
use pl_core::{
    context::OpaquePayload,
    model::DynModelSession,
    thread::{ThreadEffectBatch, ThreadHandle, ToolOutcome},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolAuthorization, ToolError},
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

#[derive(Debug, Clone, Copy)]
enum SyncFailure {
    Fetch,
    Provider,
}

const PRIVATE_SYNC_TOKEN: &str = "fixture-private-sync-credential-token";

impl pl_tool::git::GitCredentialProvider for SyncFailure {
    type Error = std::io::Error;

    async fn credential(
        &self,
        _request: pl_tool::git::GitCredentialRequest,
    ) -> Result<Option<pl_tool::git::GitCredential>, Self::Error> {
        match self {
            Self::Fetch => Ok(Some(pl_tool::git::GitCredential::new(
                PRIVATE_SYNC_TOKEN.into(),
            ))),
            Self::Provider => Err(std::io::Error::other(PRIVATE_SYNC_TOKEN)),
        }
    }
}

#[derive(Debug, Default)]
struct RecordingLocalBackend(Mutex<Vec<ExecutionOutput>>);

impl ExecutionBackend for RecordingLocalBackend {
    type Error = String;

    async fn run(&self, request: ExecutionRequest) -> Result<ExecutionOutput, Self::Error> {
        let output = LocalExecutionBackend.run(request).await?;
        self.0.lock().unwrap().push(output.clone());
        Ok(output)
    }
}

async fn sync_failure_history(failure: SyncFailure) {
    let repo = Repository::new();
    git(&repo.worktree, &["commit", "-m", "initial"]);
    std::fs::write(repo.worktree.join("local-note"), "keep\n").unwrap();
    let mut config = GitWorkspaceConfig::local(&repo.worktree);
    // A nonexistent local remote causes real Git to echo the token-bearing
    // path, proving the retained failed-command observation stays redacted.
    let remote_url = repo.worktree.join(PRIVATE_SYNC_TOKEN);
    config.remote_url = Some(remote_url.to_str().unwrap().into());
    let backend = Arc::new(RecordingLocalBackend::default());
    let kind = GitToolKind::SyncDefaultBranch;
    let definition = kind.definition();
    let prepared = pl_tool::binding::prepare_registration(
        kind.name(),
        &definition,
        pl_tool::binding::ToolCallPolicy::DirectOnly,
    )
    .unwrap();
    let tool = GitTool::new(kind, config, backend.clone(), Arc::new(failure), definition);
    let thread = ThreadHandle::start(
        "git-sync-history".into(),
        DynModelSession::new(host::Calls {
            calls: [(kind.name().into(), r#"{"preserveChanges":true}"#.into())].into(),
            requests: Arc::new(Mutex::new(Vec::new())),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![
            tool.registration(prepared, ToolAuthorization::unique()),
        ])
        .await
        .unwrap();
    thread.run_turn(host::turn("sync")).await.unwrap();
    let effects = thread.effects().await.unwrap();
    let deliveries = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect::<Vec<_>>();
    assert_eq!(deliveries.len(), 1);
    let ToolOutcome::Failed(error) = &deliveries[0].outcome else {
        panic!("sync must fail after the completed side effects")
    };
    assert_public_diagnostic(error, PRIVATE_SYNC_TOKEN);
    assert!(error.source.is::<GitHostError>());
    let envelopes = effects
        .iter()
        .map(|effect| effect.encode().unwrap())
        .collect::<Vec<_>>();
    let journal = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(journal.path(), serde_json::to_vec(&envelopes).unwrap()).unwrap();
    drop(envelopes);
    drop(deliveries);
    drop(effects);
    thread.close().await.unwrap();
    drop(thread);

    // No live original() or Thread objects remain: read the canonical journal
    // codec from disk, including the real ToolDelivery output and error serde.
    let bytes = std::fs::read(journal.path()).unwrap();
    assert!(!String::from_utf8_lossy(&bytes).contains(PRIVATE_SYNC_TOKEN));
    let envelopes: Vec<OpaquePayload> = serde_json::from_slice(&bytes).unwrap();
    let effects = envelopes
        .iter()
        .map(|envelope| ThreadEffectBatch::decode(envelope).unwrap())
        .collect::<Vec<_>>();
    let deliveries = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect::<Vec<_>>();
    assert_eq!(deliveries.len(), 1);
    let delivery = deliveries[0];
    let ToolOutcome::Failed(error) = &delivery.outcome else {
        panic!("cold history must retain the failed disposition")
    };
    assert_public_diagnostic(error, PRIVATE_SYNC_TOKEN);
    assert!(!error.source.is::<GitHostError>());
    assert_eq!(delivery.output.payload().format(), "pl.tool.git");
    assert_eq!(delivery.output.payload().version(), 1);
    let payload = payload(&delivery.output);
    let observations = payload["observations"].as_array().expect(
        "all completed and failed Git command observations must survive real Thread history",
    );
    let commands = backend.0.lock().unwrap();
    let expected_count = match failure {
        SyncFailure::Fetch => 4,
        SyncFailure::Provider => 3,
    };
    assert_eq!(
        commands.len(),
        expected_count,
        "Git commands must not repeat"
    );
    assert_eq!(observations.len(), commands.len());
    assert!(commands[0].stdout.contains("local-note"));
    assert!(commands[1].stdout.contains("Saved working directory"));
    for (observed, actual) in observations.iter().zip(commands.iter()) {
        assert_eq!(
            observed,
            &json!({
                "status": actual.status,
                "stdout": actual.stdout.replace(PRIVATE_SYNC_TOKEN, "[redacted]"),
                "stderr": actual.stderr.replace(PRIVATE_SYNC_TOKEN, "[redacted]"),
            })
        );
    }
    for field in ["status", "stdout", "stderr"] {
        assert_eq!(payload[field], observations.last().unwrap()[field]);
    }
    match failure {
        SyncFailure::Fetch => {
            let failed = observations.last().unwrap();
            assert_ne!(failed["status"], 0);
            assert!(failed["stderr"].as_str().unwrap().contains("[redacted]"));
        }
        SyncFailure::Provider => {
            assert!(observations.iter().all(|observed| observed["status"] == 0));
        }
    }
    assert_eq!(
        git(&repo.worktree, &["remote", "get-url", "origin"]).trim(),
        remote_url.to_str().unwrap()
    );
    assert_eq!(git(&repo.worktree, &["stash", "list"]).lines().count(), 1);
    assert!(!repo.worktree.join("local-note").exists());
}

#[tokio::test]
async fn sync_fetch_failure_observations_survive_thread_history() {
    sync_failure_history(SyncFailure::Fetch).await;
}

#[tokio::test]
async fn sync_provider_failure_observations_survive_thread_history() {
    sync_failure_history(SyncFailure::Provider).await;
}
