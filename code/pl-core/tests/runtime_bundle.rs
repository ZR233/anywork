#[allow(dead_code)]
mod support;
#[path = "support/tool.rs"]
mod tool_support;

use pl_core::{
    context::{ContextSource, OpaquePayload},
    model::{
        DynModelSession, Model, ModelError, ModelFactory, ModelFailureKind, ModelRequest,
        ModelSession, ModelToolCall, PreparedModelCall,
    },
    thread::{
        RuntimeBinding, RuntimeBindingReader, RuntimeBundle, RuntimeBundleReceipt, RuntimeFact,
        RuntimeModel, RuntimeTools, ThreadError, ThreadHandle,
        context_preparation::{
            ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
        },
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RuntimeTool, ToolAuthorization, ToolError},
    },
};
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, mpsc};

#[derive(Debug)]
struct Binding(&'static str);

fn bundle(
    thread: &ThreadHandle,
    label: &'static str,
    registrations: Vec<Registration>,
) -> RuntimeBundle {
    RuntimeBundle {
        base: thread.runtime_bundle_base(&thread.snapshot()),
        desired: label.into(),
        model: None,
        require_idle: false,
        wait_for_model_before_input: false,
        model_context_revision: None,
        tools: Some(RuntimeTools {
            registrations,
            binding: RuntimeBinding::new(Binding(label)),
            facts: vec![RuntimeFact {
                source_id: "fixture".into(),
                content: vec![support::text(label)],
            }],
        }),
        application: None,
        is_current: Arc::new(|| true),
    }
}

fn binding(reader: &RuntimeBindingReader) -> Option<&'static str> {
    reader.with_binding::<Binding, _>(|binding| binding.map(|binding| binding.0))
}

async fn installed(receipt: RuntimeBundleReceipt) {
    tokio::time::timeout(std::time::Duration::from_secs(5), receipt.installed())
        .await
        .expect("candidate installation timed out")
        .unwrap();
}

#[derive(Clone)]
struct ProbeModel {
    label: &'static str,
    reader: RuntimeBindingReader,
    requests: Arc<Mutex<Vec<&'static str>>>,
    closed: mpsc::UnboundedSender<&'static str>,
    open: Option<(Arc<Notify>, Arc<Notify>)>,
    fails: bool,
}

impl ProbeModel {
    fn update(&self) -> RuntimeModel {
        RuntimeModel::new(
            self.label.into(),
            ModelFactory::new(self.clone()),
            Some(ContextPreparer::new(ProbeFacts(self.label))),
        )
    }
}

#[derive(Debug)]
struct ProbeFacts(&'static str);

impl ContextPreparationHook for ProbeFacts {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        assert_eq!(
            request.current_facts.as_ref(),
            &[RuntimeFact {
                source_id: "fixture".into(),
                content: vec![support::text(self.0)],
            }]
        );
        ContextPreparation::Unchanged
    }
}

impl Model for ProbeModel {
    async fn open_session(&self) -> Result<DynModelSession, ModelError> {
        if let Some((entered, release)) = &self.open {
            entered.notify_one();
            release.notified().await;
        }
        if self.fails {
            return Err(ModelError {
                kind: ModelFailureKind::Unavailable,
                details: None,
                usage: Default::default(),
                source: None,
            });
        }
        Ok(DynModelSession::new(self.clone()))
    }
}

impl ModelSession for ProbeModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        assert_eq!(binding(&self.reader), Some(self.label));
        assert_eq!(request.tools.len(), 1);
        assert_eq!(request.tools[0].tool_id, self.label);
        self.requests.lock().unwrap().push(self.label);
        Ok(PreparedModelCall::new(async move {
            Ok(support::response(&request, Vec::new()))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        self.closed.send(self.label).unwrap();
        Ok(())
    }
}

fn probe_bundle(thread: &ThreadHandle, model: &ProbeModel) -> RuntimeBundle {
    let tool = tool_support::tool(model.label, &Arc::new(Mutex::new(Vec::new())));
    let mut candidate = bundle(thread, model.label, vec![tool]);
    candidate.model = Some(model.update());
    candidate
}

#[tokio::test]
async fn requests_see_whole_installed_bundles_and_stale_opening_is_retired() {
    let thread = ThreadHandle::start_current("atomic".into(), None).unwrap();
    let reader = thread.runtime_binding();
    let (closed, mut closes) = mpsc::unbounded_channel();
    let original = ProbeModel {
        label: "original",
        reader,
        requests: Default::default(),
        closed,
        open: None,
        fails: false,
    };
    installed(
        thread
            .install_runtime_bundle(probe_bundle(&thread, &original))
            .await
            .unwrap(),
    )
    .await;
    let entered = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let slow = ProbeModel {
        label: "slow",
        open: Some((entered.clone(), release.clone())),
        ..original.clone()
    };
    let stale = thread
        .install_runtime_bundle(probe_bundle(&thread, &slow))
        .await
        .unwrap();
    entered.notified().await;
    thread.run_turn(support::turn("old")).await.unwrap();

    let newest = ProbeModel {
        label: "newest",
        ..original.clone()
    };
    let candidate = probe_bundle(&thread, &newest);
    thread
        .mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
            id: "title.billing".into(),
            expected_revision: None,
            payload: OpaquePayload::text("saved"),
        }])
        .await
        .unwrap();
    installed(thread.install_runtime_bundle(candidate).await.unwrap()).await;
    assert!(matches!(
        &*stale.installed().await.unwrap_err(),
        ThreadError::StaleRuntimeBundle
    ));
    // This request starts immediately after installation, before any host observer runs.
    thread.run_turn(support::turn("new")).await.unwrap();
    release.notify_one();
    for expected in ["original", "slow"] {
        assert_eq!(
            tokio::time::timeout(std::time::Duration::from_secs(5), closes.recv())
                .await
                .unwrap(),
            Some(expected)
        );
    }

    let failure = ProbeModel {
        label: "failed",
        fails: true,
        ..original.clone()
    };
    let failed = thread
        .install_runtime_bundle(probe_bundle(&thread, &failure))
        .await
        .unwrap();
    assert!(matches!(
        &*failed.installed().await.unwrap_err(),
        ThreadError::Model(_)
    ));
    thread
        .run_turn(support::turn("after-failure"))
        .await
        .unwrap();
    assert_eq!(thread.snapshot().runtime_bundle.revision, 2);
    assert_eq!(
        *original.requests.lock().unwrap(),
        ["original", "newest", "newest"]
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn close_joins_a_late_opened_candidate_without_publishing_it() {
    let thread = ThreadHandle::start_current("join-opening".into(), None).unwrap();
    let reader = thread.runtime_binding();
    let (closed, mut closes) = mpsc::unbounded_channel();
    let entered = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let model = ProbeModel {
        label: "late",
        reader: reader.clone(),
        requests: Default::default(),
        closed,
        open: Some((entered.clone(), release.clone())),
        fails: false,
    };
    let receipt = thread
        .install_runtime_bundle(probe_bundle(&thread, &model))
        .await
        .unwrap();
    entered.notified().await;
    let closing = thread.clone();
    let closer = tokio::spawn(async move { closing.close().await });
    assert!(matches!(
        &*receipt.installed().await.unwrap_err(),
        ThreadError::Closed
    ));
    assert!(!closer.is_finished());
    assert_eq!(binding(&reader), None);
    release.notify_one();
    tokio::time::timeout(std::time::Duration::from_secs(5), closer)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(closes.try_recv().unwrap(), "late");
    assert_eq!(binding(&reader), None);
}

struct TaskModel;

impl ModelSession for TaskModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let tool = match request.turn_id.as_str() {
            "start" => Some("command"),
            "send" => Some("write_stdin"),
            _ => None,
        };
        let calls = tool
            .into_iter()
            .filter(|_| {
                !request.context.records.iter().any(|record| {
                    record.turn_id.as_deref() == Some(request.turn_id.as_str())
                        && matches!(record.source, ContextSource::ToolResult { .. })
                })
            })
            .map(|tool| ModelToolCall {
                call_id: format!("{}:{tool}", request.turn_id),
                tool_id: tool.into(),
                arguments: OpaquePayload::text("fixture input"),
                rejection: None,
                presentation_contract: None,
            })
            .collect();
        Ok(PreparedModelCall::new(async move {
            Ok(support::response(&request, calls))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[derive(Debug)]
enum CommandTool {
    Wait {
        input: Arc<Notify>,
        cancelled: Option<Arc<Notify>>,
    },
    Write(Arc<Notify>),
}

impl pl_agent_tool::Tool for CommandTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("CommandTool", "Command input fixture").unwrap()
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        match self {
            Self::Wait { input, cancelled } => {
                if let Some(cancelled) = cancelled {
                    context.cancellation.cancelled().await;
                    cancelled.notify_one();
                }
                input.notified().await;
            }
            Self::Write(target) => target.notify_one(),
        }
        Ok(ToolOutput::new(
            input,
            vec![support::text("original output")],
        ))
    }
}

fn command(id: &str, tool: CommandTool) -> Registration {
    Registration::prepare(id.into(), OpaquePayload::text(id))
        .unwrap()
        .attach(RuntimeTool::new(tool))
}

#[tokio::test(start_paused = true)]
async fn ordinary_incompatible_refresh_waits_for_the_original_command_input() {
    let thread = ThreadHandle::start("stdin".into(), DynModelSession::new(TaskModel)).unwrap();
    let input = Arc::new(Notify::new());
    let reader = thread.runtime_binding();
    let first = bundle(
        &thread,
        "first",
        vec![
            command(
                "command",
                CommandTool::Wait {
                    input: input.clone(),
                    cancelled: None,
                },
            ),
            command("write_stdin", CommandTool::Write(input)),
        ],
    );
    installed(thread.install_runtime_bundle(first).await.unwrap()).await;
    thread.run_turn(support::turn("start")).await.unwrap();
    assert!(
        thread
            .snapshot()
            .tasks
            .values()
            .any(|task| task.tool_id == "command")
    );
    let next = bundle(
        &thread,
        "next",
        vec![command(
            "write_stdin",
            CommandTool::Write(Arc::new(Notify::new())),
        )],
    );
    let receipt = thread.install_runtime_bundle(next).await.unwrap();
    let mut pending = Box::pin(receipt.installed());
    assert!(futures::poll!(&mut pending).is_pending());
    assert_eq!(binding(&reader), Some("first"));

    thread.run_turn(support::turn("send")).await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(5), pending)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(binding(&reader), Some("next"));
    thread.close().await.unwrap();
}

#[tokio::test(start_paused = true)]
async fn revoked_authority_cancels_the_old_task_and_waits_for_its_exit() {
    let thread =
        ThreadHandle::start_current("revocation".into(), Some(DynModelSession::new(TaskModel)))
            .unwrap();
    let input = Arc::new(Notify::new());
    let cancelled = Arc::new(Notify::new());
    let reader = thread.runtime_binding();
    let authority = ToolAuthorization::unique();
    let first = bundle(
        &thread,
        "first",
        vec![
            command(
                "command",
                CommandTool::Wait {
                    input: input.clone(),
                    cancelled: Some(cancelled.clone()),
                },
            )
            .guard_authorization(&authority),
        ],
    );
    installed(thread.install_runtime_bundle(first).await.unwrap()).await;
    thread.run_turn(support::turn("start")).await.unwrap();

    authority.revoke();
    reader.authorization_changed();
    let receipt = thread
        .install_runtime_bundle(bundle(&thread, "new-policy", Vec::new()))
        .await
        .unwrap();
    cancelled.notified().await;
    let mut pending = Box::pin(receipt.installed());
    assert!(futures::poll!(&mut pending).is_pending());
    assert_eq!(binding(&reader), Some("first"));
    input.notify_one();
    tokio::time::timeout(std::time::Duration::from_secs(5), pending)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(binding(&reader), Some("new-policy"));
    let snapshot = thread.snapshot();
    assert!(
        snapshot
            .tasks
            .values()
            .chain(snapshot.terminal_tasks.iter())
            .any(|task| {
                task.tool_id == "command"
                    && task.status == pl_core::thread::task::TaskStatus::Cancelled
            })
    );
    assert!(snapshot.deliveries.iter().any(|delivery| {
        delivery.tool_id == "command"
            && delivery
                .output
                .context()
                .contains(&support::text("original output"))
    }));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn reconfiguration_binds_instructions_to_the_version_assigned_after_concurrent_billing() {
    use pl_core::{
        context::ContextRecord,
        thread::{
            ContextReplacementReason, ReplaceContext, RuntimeApplication,
            extensions::{
                ApplicationUpdate, ExtensionInputs, ExtensionMutation, InstructionRevisionBinding,
            },
        },
    };
    let thread = ThreadHandle::start_current("mode-change".into(), None).unwrap();
    let snapshot = thread.snapshot();
    let mut candidate = bundle(&thread, "tools", Vec::new());
    candidate.base.extension_inputs =
        ExtensionInputs::capture(&snapshot.extensions, &["instructions"]);
    candidate.application = Some(RuntimeApplication {
        instruction_binding: Some(InstructionRevisionBinding {
            record_id: "projected".into(),
            extension_id: "instructions".into(),
        }),
        update: ApplicationUpdate {
            facts: Vec::new(),
            mutations: vec![ExtensionMutation::Put {
                id: "instructions".into(),
                expected_revision: None,
                payload: OpaquePayload::text("instructions"),
            }],
        },
        context: Some(ReplaceContext {
            expected_revision: snapshot.context.revision,
            reason: ContextReplacementReason::Rebuild,
            records: vec![ContextRecord {
                id: "projected".into(),
                turn_id: None,
                tool_calls: Vec::new(),
                source: ContextSource::InstructionSnapshot {
                    revision: 0,
                    content_hash: pl_core::context::content_hash(b"instructions"),
                    replaces: None,
                },
                content: vec![support::text("instructions")],
            }],
        }),
    });
    thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: "billing".into(),
            expected_revision: None,
            payload: OpaquePayload::text("saved"),
        }])
        .await
        .unwrap();
    installed(thread.install_runtime_bundle(candidate).await.unwrap()).await;
    let state = thread.snapshot();
    let assigned = state.extensions["instructions"].revision;
    assert!(assigned > state.extensions["billing"].revision);
    assert!(
        matches!(state.context.records[0].source, ContextSource::InstructionSnapshot { revision, .. } if revision == assigned)
    );
    thread.close().await.unwrap();
}
