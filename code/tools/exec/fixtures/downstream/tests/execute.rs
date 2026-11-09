//! This fixture resolves outside the workspace and invokes the public tools.
//! The process port uses an actual shell and pipe; LSP ports isolate service IO
//! while assertions cover tool validation, path sequencing and full result retention.
use pl_agent_tool::Tool;
use pl_tool_exec::{ExecContext, ExecTool, exec_definition};
use pl_tool_lsp_capabilities::{LspCapabilitiesTool, lsp_capabilities_definition};
use pl_tool_lsp_query::{LspQueryTool, QueryError, lsp_query_definition};
use pl_tool_lsp_support::{
    Capabilities, CapabilityReader, LspContext, Operation, QueryRequest, QueryResult, QueryService,
    ServerCapabilities,
};
use pl_tool_process::{
    CancellationToken, CommandCaptureOffsets, CommandCaptureReceipt, CommandInputOutcome,
    CommandInputReceipt, CommandOutputSnapshot, CommandProcessFinalResult, CommandProcessLifecycle,
    FinalCommandProcess, InputRequest, InputTarget, ProcessExecutor, ProcessInput, ProcessRequest,
    RunningCommandProcess, StdinCloseState,
};
use pl_tool_write_stdin::{StdinContext, StdinResult, WriteStdinTool, write_stdin_definition};
use std::{
    io,
    path::PathBuf,
    process::Stdio,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio::{
    io::AsyncWriteExt,
    process::ChildStdin,
    sync::{Mutex, Notify},
};

#[derive(Clone, Default)]
struct PipeOwner(Arc<PipeState>);
#[derive(Default)]
struct PipeState {
    stdin: Mutex<Option<ChildStdin>>,
    ready: Notify,
    starts: AtomicUsize,
}

fn observation() -> CommandOutputSnapshot {
    CommandOutputSnapshot {
        state: CommandProcessLifecycle::Running(RunningCommandProcess::healthy()),
        process_id: None,
        stdout: pl_tool_process::TruncatedOutput::empty(),
        stderr: pl_tool_process::TruncatedOutput::empty(),
        stdout_omission_marker: None,
        stderr_omission_marker: None,
        output_file: "stdout.raw".into(),
        capture_file: "stdout.raw".into(),
        stderr_output_file: "stderr.raw".into(),
        stderr_capture_file: "stderr.raw".into(),
        message: "observed".into(),
        output_revision: 0,
        exit_code: None,
        signal: None,
        supervision_failure: None,
        input_receipt: None,
        stdout_text_lossy: false,
        stderr_text_lossy: false,
        output_artifacts: vec![],
        output_failure: None,
        capture_plan: None,
        capture_offsets: CommandCaptureOffsets::default(),
        capture_limit_bytes: 16 * 1024 * 1024,
        capture_usage: None,
        model_output_bytes_cap: None,
    }
}

impl ProcessExecutor for PipeOwner {
    type Error = io::Error;
    async fn run(&self, request: ProcessRequest) -> io::Result<CommandOutputSnapshot> {
        assert_eq!(request.timeout.as_secs(), 17);
        assert_eq!(request.max_output_bytes, 65536);
        assert!(!request.allow_workspace_escape);
        assert!(!request.cancellation.is_cancelled());
        let mut child = tokio::process::Command::new("sh")
            .arg("-c")
            .arg(request.command)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;
        self.0.starts.fetch_add(1, Ordering::SeqCst);
        *self.0.stdin.lock().await = child.stdin.take();
        self.0.ready.notify_one();
        let output = child.wait_with_output().await?;
        let mut snapshot = observation();
        snapshot.exit_code = output.status.code();
        snapshot.state = CommandProcessLifecycle::Final(FinalCommandProcess::new(
            CommandProcessFinalResult::Succeeded {
                exit_code: output.status.code().unwrap(),
            },
        ));
        snapshot.stdout.content = String::from_utf8(output.stdout).unwrap();
        snapshot.stderr.content = String::from_utf8(output.stderr).unwrap();
        snapshot.stdout.original_length = snapshot.stdout.content.len();
        snapshot.stderr.original_length = snapshot.stderr.content.len();
        snapshot.capture_offsets = CommandCaptureOffsets {
            stdout: snapshot.stdout.original_length as u64,
            stderr: snapshot.stderr.original_length as u64,
        };
        snapshot.capture_usage = Some(CommandCaptureReceipt {
            captured_bytes: snapshot.capture_offsets.total(),
            limit_bytes: snapshot.capture_limit_bytes,
            confirmed: snapshot.capture_offsets,
            charged_bytes: snapshot.capture_offsets.total(),
            refused_bytes: 0,
        });
        Ok(snapshot)
    }
}
impl ProcessInput for PipeOwner {
    type Target = ();
    type Error = io::Error;
    fn resolve(&self, receipt: &str, terminal_eof: bool) -> io::Result<InputTarget<()>> {
        assert_eq!(receipt, "original-receipt");
        assert!(!terminal_eof);
        Ok(InputTarget::Live(()))
    }
    async fn write(&self, request: InputRequest<()>) -> io::Result<CommandOutputSnapshot> {
        assert_eq!(request.max_output_bytes, 7);
        let mut lock = self.0.stdin.lock().await;
        let stdin = lock.as_mut().expect("same owner's existing stdin");
        stdin.write_all(request.chars.as_bytes()).await?;
        if request.close_stdin {
            stdin.shutdown().await?;
            *lock = None;
        }
        let mut snapshot = observation();
        snapshot.input_receipt = Some(CommandInputReceipt {
            accepted_bytes: request.chars.len() as u64,
            remote_confirmed_bytes: None,
            delivery_pending: false,
            close_state: Some(StdinCloseState::Closed),
            outcome: CommandInputOutcome::Complete,
            detail: None,
        });
        Ok(snapshot)
    }
}

#[tokio::test]
async fn exec_and_stdin_use_one_actual_pipe_and_preserve_domain_output() {
    let owner = PipeOwner::default();
    let exec = ExecTool::<PipeOwner>::new(exec_definition());
    let exec_owner = owner.clone();
    let running = tokio::spawn(async move {
        exec.execute(
            r#"{"command":"cat; printf err >&2","timeoutSeconds":17,"maxOutputChars":100000}"#
                .into(),
            ExecContext {
                process: exec_owner,
                allow_workspace_escape: false,
                cancellation: CancellationToken::new(),
            },
        )
        .await
        .unwrap()
    });
    owner.0.ready.notified().await;
    let input = WriteStdinTool::<PipeOwner>::new(write_stdin_definition()).execute(
        r#"{"taskId":"original-receipt","chars":"汉字\n","closeStdin":true,"maxOutputChars":7}"#.into(),
        StdinContext { processes: owner.clone(), cancellation: CancellationToken::new() },
    ).await.unwrap();
    let input_record: serde_json::Value =
        serde_json::from_str(&input.encode(Some("input-receipt".into())).unwrap()).unwrap();
    assert_eq!(input_record["taskId"], "input-receipt");
    assert_eq!(input_record["targetTaskId"], "original-receipt");
    let StdinResult::Observed {
        snapshot,
        outcome,
        target_receipt,
        ..
    } = input
    else {
        panic!("live input");
    };
    assert_eq!(target_receipt, "original-receipt");
    assert_eq!(outcome, pl_tool_write_stdin::InputOutcome::Complete);
    let receipt = snapshot.input_receipt.unwrap();
    assert_eq!(receipt.accepted_bytes, 7);
    assert_eq!(receipt.remote_confirmed_bytes, None);
    let result = tokio::time::timeout(std::time::Duration::from_secs(5), running)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(result.snapshot.stdout.content, "汉字\n");
    assert_eq!(result.snapshot.stderr.content, "err");
    assert_eq!(owner.0.starts.load(Ordering::SeqCst), 1);
    assert_eq!(result.outcome(), pl_tool_exec::ExecOutcome::Succeeded);
    let text = result
        .encode::<String>(&[], Some("original-receipt".into()))
        .unwrap();
    let record: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(record["stdout"]["displayedBytes"], 7);
    assert_eq!(record["stderr"]["displayedBytes"], 3);
    assert_eq!(record["requestedBodyBytes"], 100000);
    assert_eq!(record["effectiveBodyBytes"], 65536);
}

#[tokio::test]
async fn invalid_exec_never_admits_a_process() {
    let owner = PipeOwner::default();
    let tool = ExecTool::<PipeOwner>::new(exec_definition());
    for raw in [
        r#"{"command":"cat","timeoutSeconds":0}"#,
        r#"{"command":"cat","maxOutputChars":0}"#,
        r#"{"command":"  "}"#,
    ] {
        let error = tool
            .execute(
                raw.into(),
                ExecContext {
                    process: owner.clone(),
                    allow_workspace_escape: false,
                    cancellation: CancellationToken::new(),
                },
            )
            .await
            .unwrap_err();
        let pl_tool_exec::ExecError::InvalidInput(error) = error else {
            panic!("input error");
        };
        let diagnostic: serde_json::Value =
            serde_json::from_str(&error.diagnostic_json().unwrap()).unwrap();
        assert_eq!(diagnostic["processStarted"], false);
    }
    assert_eq!(owner.0.starts.load(Ordering::SeqCst), 0);
}

#[derive(Clone, Default)]
struct Service {
    queries: Arc<AtomicUsize>,
    resolutions: Arc<AtomicUsize>,
    cancel_after_resolve: Option<CancellationToken>,
}
impl CapabilityReader for Service {
    type Error = io::Error;
    async fn capabilities(&self) -> io::Result<Capabilities> {
        Ok(Capabilities {
            servers: vec![ServerCapabilities {
                id: "rust".into(),
                display_name: "Rust".into(),
                language_ids: vec!["rust".into()],
                operations: vec!["hover".into()],
                availability: "available".into(),
                ready: true,
            }],
        })
    }
}
impl QueryService for Service {
    type Error = io::Error;
    async fn resolve_path(&self, path: PathBuf, operation: Operation) -> io::Result<PathBuf> {
        self.resolutions.fetch_add(1, Ordering::SeqCst);
        assert_eq!(path, PathBuf::from("src/lib.rs"));
        assert_eq!(operation, Operation::Hover);
        if let Some(cancel) = &self.cancel_after_resolve {
            cancel.cancel();
        }
        Ok(PathBuf::from("/authorized/src/lib.rs"))
    }
    async fn query(&self, request: QueryRequest) -> io::Result<QueryResult> {
        self.queries.fetch_add(1, Ordering::SeqCst);
        assert_eq!(request.language_id, "rust");
        assert_eq!(
            request.file_path,
            Some(PathBuf::from("/authorized/src/lib.rs"))
        );
        assert_eq!((request.line, request.character), (Some(2), Some(3)));
        Ok(QueryResult {
            success: true,
            operation: request.operation,
            server_id: Some("rust".into()),
            result: "type information 汉字 ".repeat(2000),
            result_count: Some(1),
            file_count: Some(1),
        })
    }
}
fn hover() -> String {
    r#"{"languageId":"rust","operation":"hover","filePath":"src/lib.rs","line":2,"character":3}"#
        .into()
}

#[tokio::test]
async fn lsp_tools_execute_validate_resolve_and_retain_full_results() {
    let service = Service::default();
    let capabilities = LspCapabilitiesTool::<Service>::new(lsp_capabilities_definition())
        .execute(
            "{}".into(),
            LspContext {
                service: service.clone(),
                cancellation: CancellationToken::new(),
            },
        )
        .await
        .unwrap();
    assert_eq!(capabilities.value.servers[0].language_ids, ["rust"]);
    let tool = LspQueryTool::<Service>::new(lsp_query_definition());
    let result = tool
        .execute(
            hover(),
            LspContext {
                service: service.clone(),
                cancellation: CancellationToken::new(),
            },
        )
        .await
        .unwrap();
    let (full, preview) = result.encode().unwrap();
    assert!(full.len() > 12 * 1024);
    assert!(preview.contains("LSP preview omitted"));
    assert!(full.contains("type information"));
    assert_eq!(service.resolutions.load(Ordering::SeqCst), 1);
    assert_eq!(service.queries.load(Ordering::SeqCst), 1);
    let invalid = hover().replace("\"line\":2", "\"line\":0");
    assert!(matches!(
        tool.execute(
            invalid,
            LspContext {
                service: service.clone(),
                cancellation: CancellationToken::new()
            }
        )
        .await,
        Err(QueryError::Invalid(_))
    ));
    assert_eq!(service.resolutions.load(Ordering::SeqCst), 1);
    assert_eq!(service.queries.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn lsp_cancellation_after_authorization_does_not_query_service() {
    let cancellation = CancellationToken::new();
    let service = Service {
        cancel_after_resolve: Some(cancellation.clone()),
        ..Default::default()
    };
    let result = LspQueryTool::<Service>::new(lsp_query_definition())
        .execute(
            hover(),
            LspContext {
                service: service.clone(),
                cancellation,
            },
        )
        .await;
    assert!(matches!(result, Err(QueryError::Cancelled)));
    assert_eq!(service.queries.load(Ordering::SeqCst), 0);
}
