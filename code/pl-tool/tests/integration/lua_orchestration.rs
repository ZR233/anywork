use crate::binding_host as host;
use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{DynModelSession, ModelSession},
    thread::{
        HistoryExport, ThreadEffectBatch, ThreadHandle, ToolDeliveryTarget, UsageSummary,
        cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
        history_sink::{HistorySink, HistorySinkHandle},
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_tool::binding::{ToolCallPolicy, prepare_registration};
use serde_json::json;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

struct Child {
    definition: ToolDefinition,
    calls: Arc<AtomicUsize>,
    fail: bool,
}

fn image_reference(id: &str) -> pl_core::context::ResourceReference {
    pl_core::context::ResourceReference::new(
        id.into(),
        format!("sha256:{}", "0".repeat(64)),
        0,
        "image/png".into(),
    )
    .unwrap()
}

fn declared_image(id: &str) -> ContextContent {
    pl_model::runtime::attachment_content(
        image_reference(id),
        pl_model::completion::AttachmentModality::Image,
    )
    .unwrap()
}

#[derive(Debug)]
struct Policy {
    denied: bool,
}
impl pl_core::tool::execution_policy::ExecutionPolicy for Policy {
    async fn authorize(
        &self,
        _input: &OpaquePayload,
        _context: &CallContext,
    ) -> Result<pl_core::tool::execution_policy::ExecutionGrant, ToolError> {
        if self.denied {
            Err(ToolError::new(std::io::Error::other("host policy denied")))
        } else {
            Ok(Default::default())
        }
    }
}

struct Projected(host::Calls);
impl ModelSession for Projected {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        assert!(
            request
                .solo_tool_ids
                .iter()
                .all(|id| request.tools.iter().any(|tool| &tool.tool_id == id)),
            "nested scheduling must not refer to an undeclared model tool"
        );
        self.0
            .prepare(request)
            .await
            .map(|call| call.with_tool_projection(OpaquePayload::text("frozen image capabilities")))
    }
    async fn close(&mut self) -> Result<(), pl_core::model::ModelError> {
        self.0.close().await
    }
}
impl Tool for Child {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        assert_eq!(input.content(), "{\"n\":7}");
        if context.thread_id == "lua-test" {
            assert_eq!(
                context.model_projection.as_ref().unwrap().content(),
                "frozen image capabilities"
            );
            assert!(
                !serde_json::to_string(&context.context)
                    .unwrap()
                    .contains("PRIVATE_INTERMEDIATE")
            );
        }
        self.calls.fetch_add(1, Ordering::SeqCst);
        let data = json!({"selected":7,"hidden":"PRIVATE_INTERMEDIATE","reference":"PLAIN_IMAGE"});
        let output = ToolOutput::from_data(
            data.clone(),
            vec![
                ContextContent::Text {
                    text: data.to_string().into(),
                },
                declared_image("LUA_IMAGE"),
                ContextContent::Resource {
                    reference: image_reference("PLAIN_IMAGE"),
                },
            ],
        );
        if self.fail {
            Err(ToolError::new(std::io::Error::other("child failed")).with_output(output))
        } else {
            Ok(output)
        }
    }
}

#[derive(Debug, Clone, Default)]
struct RecordingSink(Arc<Mutex<Vec<Arc<HistoryExport>>>>);

impl HistorySink for RecordingSink {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &ThreadEffectBatch) {
        let _ = (summary, effect);
    }

    fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
        Ok(())
    }

    fn reserve_operation_output(&self, _: &str, _: &str, max: u64) -> Result<u64, ColdStoreError> {
        Ok(max)
    }

    fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }

    fn release_operation_output(&self, _: &str, _: &str) {}

    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure::default()
    }

    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: None,
        }
    }

    fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        None
    }

    fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        self.0.lock().unwrap().push(write);
        Ok(())
    }
}

#[tokio::test]
async fn real_thread_retains_nested_originals_without_putting_them_into_model_history() {
    for (fail, denied, select_reference) in [
        (false, false, false),
        (false, false, true),
        (true, false, false),
        (false, true, false),
    ] {
        let expected_calls = if denied { 0 } else { 3 };
        let sink = RecordingSink::default();
        let calls = Arc::new(AtomicUsize::new(0));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let code = if fail || denied {
            "local function child() local ok,err=pcall(function() return tools.child(args) end); assert(not ok); if err.output then assert(err.output.reference=='PLAIN_IMAGE') end end; parallel({child,child,child}); return 'handled'".to_owned()
        } else {
            let selection = if select_reference {
                "reference"
            } else {
                "selected"
            };
            format!(
                "local r=parallel({{function() return tools.child(args) end,function() return tools.child(args) end,function() return tools.child(args) end}}); return r[1].{selection}"
            )
        };
        let model = host::Calls {
            calls: std::collections::VecDeque::from([(
                "exec".into(),
                json!({"code":code,"args":{"n":7}}).to_string(),
            )]),
            requests: requests.clone(),
        };
        let thread =
            ThreadHandle::start("lua-test".into(), DynModelSession::new(Projected(model))).unwrap();
        thread
            .attach_history(HistorySinkHandle::new(sink.clone()))
            .await
            .unwrap();
        let definition = ToolDefinition::json(
            "child",
            "Test child",
            json!({"type":"object","properties":{"n":{"type":"integer"}},"required":["n"]}),
        )
        .unwrap();
        let child = prepare_registration("child", &definition, ToolCallPolicy::DirectOnly)
            .unwrap()
            .attach(ToolHandle::new(Child {
                definition,
                calls: calls.clone(),
                fail,
            }))
            .with_execution_policy(pl_core::tool::execution_policy::ExecutionPolicyHandle::new(
                Policy { denied },
            ))
            .nested(true);
        let tool = pl_tool::lua::LuaTool::new("tools.child({n=integer}) returns {selected,hidden}");
        let exec = prepare_registration("exec", tool.definition(), ToolCallPolicy::DirectOnly)
            .unwrap()
            .attach(ToolHandle::new(tool))
            .with_nested_calls()
            .foreground();
        thread.register_tools(vec![child, exec]).await.unwrap();
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            thread.run_turn(host::turn("turn")),
        )
        .await
        .expect("nested dispatch must not deadlock")
        .unwrap();
        thread.flush().await.unwrap();
        let current = thread
            .capture_current(tokio_util::sync::CancellationToken::new())
            .await
            .unwrap();
        thread.close().await.unwrap();
        let exports = sink.0.lock().unwrap().clone();
        let deliveries: Vec<_> = exports
            .iter()
            .flat_map(|export| export.effect.deliveries.iter().cloned())
            .collect();
        let child = deliveries
            .iter()
            .find(|delivery| delivery.tool_id == "child")
            .expect("nested call retained");
        let parent = deliveries
            .iter()
            .find(|delivery| delivery.tool_id == "exec")
            .unwrap();
        assert!(
            matches!(&child.target,ToolDeliveryTarget::Nested{parent_call_id} if parent_call_id==&parent.call_id)
        );
        assert!(child.delivered_context.is_empty());
        if denied {
            assert!(child.output.data().is_none());
            assert!(
                matches!(&child.outcome, pl_core::thread::ToolOutcome::Failed(error)
                if error.to_string().contains("host policy denied"))
            );
        } else {
            assert_eq!(
                child.output.data().unwrap()["hidden"],
                "PRIVATE_INTERMEDIATE"
            );
            assert!(
                child
                    .output
                    .content()
                    .iter()
                    .any(|part| matches!(part, ContextContent::Media { .. }))
            );
        }
        let call_id = child.call_id.clone();
        let serialized = serde_json::to_string(
            &requests
                .lock()
                .unwrap()
                .iter()
                .map(|request| &request.context)
                .collect::<Vec<_>>(),
        )
        .unwrap();
        assert!(!serialized.contains("PRIVATE_INTERMEDIATE"));
        assert_eq!(serialized.contains("LUA_IMAGE"), !fail && !denied);
        assert_eq!(parent.output.content().iter().any(|part| matches!(part, ContextContent::Resource { reference } if reference.id() == "PLAIN_IMAGE")), select_reference);
        assert_eq!(
            deliveries
                .iter()
                .filter(|delivery| delivery.tool_id == "child")
                .count(),
            3
        );
        assert_eq!(calls.load(Ordering::SeqCst), expected_calls);
        let saved_task = exports
            .iter()
            .flat_map(|export| export.effect.tasks.iter())
            .find(|task| task.call_id == call_id)
            .cloned()
            .expect("nested task exported");
        assert!(saved_task.parent_call_id.is_some());
        assert_eq!(
            saved_task.invocation.unwrap().arguments.content(),
            "{\"n\":7}"
        );
        assert_eq!(
            calls.load(Ordering::SeqCst),
            expected_calls,
            "cold reads must not replay tools"
        );
        let resumed = ThreadHandle::restore_current(current, None).unwrap();
        resumed
            .register_tools(vec![lua_registration()])
            .await
            .unwrap();
        resumed.flush().await.unwrap();
        resumed.close().await.unwrap();
        assert_eq!(
            calls.load(Ordering::SeqCst),
            expected_calls,
            "restoring the owner must not replay child commands"
        );
    }
}

fn lua_registration() -> pl_core::tool::opaque::Registration {
    let tool = pl_tool::lua::LuaTool::new("");
    prepare_registration("exec", tool.definition(), ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(tool))
        .with_nested_catalog(pl_tool::lua::project_catalog)
        .foreground()
}

#[tokio::test]
async fn real_thread_admits_more_than_256_children_under_ordinary_owner_governance() {
    let calls = Arc::new(AtomicUsize::new(0));
    let model = host::Calls {
        calls: std::collections::VecDeque::from([(
            "exec".into(),
            json!({"code":"for i=1,257 do tools.child({n=7}) end; return 'done'"}).to_string(),
        )]),
        requests: Default::default(),
    };
    let thread = ThreadHandle::start(
        "lua-many-children".into(),
        DynModelSession::new(Projected(model)),
    )
    .unwrap();
    let definition = ToolDefinition::json("child", "read", json!({"type":"object"})).unwrap();
    let child = prepare_registration("child", &definition, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(Child {
            definition,
            calls: calls.clone(),
            fail: false,
        }))
        .with_extension_updates()
        .nested(false);
    assert!(child.permits_nesting());
    thread
        .register_tools(vec![lua_registration(), child])
        .await
        .unwrap();
    thread.run_turn(host::turn("many-children")).await.unwrap();
    assert_eq!(calls.load(Ordering::SeqCst), 257);
    thread.close().await.unwrap();
}

struct Reveal {
    definition: ToolDefinition,
}
impl Tool for Reveal {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }
    async fn execute(&self, _: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        Ok(ToolOutput::text("revealed".into()).with_revealed_tools(vec!["child".into()]))
    }
}

#[tokio::test]
async fn frozen_sdk_tracks_discovery_without_exposing_nested_schemas_twice() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let calls = Arc::new(AtomicUsize::new(0));
    let model = host::Calls {
        calls: std::collections::VecDeque::from([
            ("reveal".into(), "{}".into()),
            (
                "exec".into(),
                json!({"code":"return tools.child({n=7}).selected"}).to_string(),
            ),
        ]),
        requests: requests.clone(),
    };
    let thread = ThreadHandle::start("lua-discovery".into(), DynModelSession::new(model)).unwrap();
    let definition = ToolDefinition::json(
        "child",
        "UNIQUE_CHILD_DESCRIPTION",
        json!({"type":"object"}),
    )
    .unwrap()
    .with_output_schema(json!({"type":"object","properties":{"selected":{"type":"integer"}}}))
    .unwrap();
    let child = prepare_registration("child", &definition, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(Child {
            definition,
            calls: calls.clone(),
            fail: false,
        }))
        .nested(true)
        .deferred();
    let definition =
        ToolDefinition::json("reveal", "Reveal child", json!({"type":"object"})).unwrap();
    let reveal = prepare_registration("reveal", &definition, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(Reveal { definition }))
        .with_tool_discovery();
    thread
        .register_tools(vec![lua_registration(), child, reveal])
        .await
        .unwrap();
    thread.run_turn(host::turn("discover")).await.unwrap();
    {
        let requests = requests.lock().unwrap();
        assert!(!requests[0].tools.iter().any(|tool| {
            tool.declaration
                .content()
                .contains("UNIQUE_CHILD_DESCRIPTION")
        }));
        assert!(requests[1].tools.iter().any(|tool| {
            tool.tool_id == "exec"
                && tool
                    .declaration
                    .content()
                    .contains("UNIQUE_CHILD_DESCRIPTION")
        }));
        assert!(
            requests
                .iter()
                .all(|request| request.tools.iter().all(|tool| tool.tool_id != "child"))
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(requests[1].tools.iter().any(|tool| {
            tool.tool_id == "exec"
                && tool
                    .declaration
                    .content()
                    .contains(r#"\"properties\":{\"selected\":"#)
        }));
    }
    thread.close().await.unwrap();
}

struct Gate {
    definition: ToolDefinition,
    entered: Arc<tokio::sync::Notify>,
    release: Arc<tokio::sync::Notify>,
    exited: Arc<std::sync::atomic::AtomicBool>,
}
impl Tool for Gate {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }
    async fn execute(
        &self,
        _: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.entered.notify_one();
        let cancelled = tokio::select! { _=context.cancellation.cancelled()=>true, _=self.release.notified()=>false };
        self.exited.store(true, Ordering::SeqCst);
        if cancelled {
            return Err(
                ToolError::new(pl_core::thread::ThreadError::Cancelled).with_output(
                    ToolOutput::from_data(
                        json!({"observed": true}),
                        vec![declared_image("CANCELLED_IMAGE")],
                    ),
                ),
            );
        }
        Ok(ToolOutput::from_data(json!("gate completed"), vec![]))
    }
}

#[tokio::test]
async fn lua_catches_nested_cancellation_without_delivering_the_child_media() {
    use pl_core::thread::{ToolOutcome, task::TaskStatus};
    use std::time::Duration;

    let entered = Arc::new(tokio::sync::Notify::new());
    let definition =
        ToolDefinition::json("gate", "Cancellable child", json!({"type":"object"})).unwrap();
    let gate = prepare_registration("gate", &definition, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(Gate {
            definition,
            entered: entered.clone(),
            release: Default::default(),
            exited: Default::default(),
        }))
        .nested(false);
    let code = "local ok, err=pcall(tools.gate, {}); assert(not ok and err.message:find('cancelled',1,true)); assert(err.output.observed); return 'parent continued'";
    let thread = ThreadHandle::start(
        "lua-cancelled-media".into(),
        DynModelSession::new(host::Calls {
            calls: [("exec".into(), json!({"code":code}).to_string())].into(),
            requests: Default::default(),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![lua_registration(), gate])
        .await
        .unwrap();
    let mut snapshots = thread.subscribe();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(host::turn("cancel gate")).await }
    });
    let observed = tokio::time::timeout(Duration::from_secs(5), async {
        entered.notified().await;
        while let Some(snapshot) = snapshots.next().await {
            if let Some(task) = snapshot
                .tasks
                .values()
                .find(|task| task.tool_id == "gate" && task.status == TaskStatus::Running)
            {
                return Some(task.id.clone());
            }
        }
        None
    })
    .await;
    if !matches!(&observed, Ok(Some(_))) {
        thread.close().await.unwrap();
    }
    let task_id = observed.unwrap().unwrap();
    assert_eq!(
        thread.cancel_task(task_id).await.unwrap(),
        pl_core::tool::task::TaskCancellationReceipt::Requested
    );
    let finished = tokio::time::timeout(Duration::from_secs(5), runner).await;
    thread.close().await.unwrap();
    finished.unwrap().unwrap().unwrap();

    let effects = thread.effects().await.unwrap();
    let mut deliveries = effects.iter().flat_map(|effect| effect.deliveries.iter());
    let child = deliveries
        .clone()
        .find(|delivery| delivery.tool_id == "gate")
        .unwrap();
    let parent = deliveries
        .find(|delivery| delivery.tool_id == "exec")
        .unwrap();
    assert!(matches!(child.outcome, ToolOutcome::Cancelled));
    assert!(
        child
            .output
            .content()
            .contains(&declared_image("CANCELLED_IMAGE"))
    );
    assert!(child.delivered_context.is_empty());
    assert!(matches!(parent.outcome, ToolOutcome::Succeeded));
    assert_eq!(parent.output.data().unwrap()["output"], "parent continued");
    assert!(
        parent
            .output
            .content()
            .iter()
            .all(|part| matches!(part, ContextContent::Text { .. }))
    );
}

#[tokio::test]
async fn revocation_during_a_program_prevents_the_next_frozen_child_and_close_joins_running_children()
 {
    for mode in 0..3 {
        let entered = Arc::new(tokio::sync::Notify::new());
        let release = Arc::new(tokio::sync::Notify::new());
        let exited = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let calls = Arc::new(AtomicUsize::new(0));
        let code = "tools.gate({}); local ok,err=pcall(function() tools.child({n=7}) end); assert(not ok); return 'denied'";
        let model = host::Calls {
            calls: std::collections::VecDeque::from([(
                "exec".into(),
                json!({"code":code}).to_string(),
            )]),
            requests: Default::default(),
        };
        let thread = ThreadHandle::start("lua-stop".into(), DynModelSession::new(model)).unwrap();
        let definition = ToolDefinition::json(
            "gate",
            "Controlled in-flight operation",
            json!({"type":"object"}),
        )
        .unwrap();
        let gate = prepare_registration("gate", &definition, ToolCallPolicy::DirectOnly)
            .unwrap()
            .attach(ToolHandle::new(Gate {
                definition,
                entered: entered.clone(),
                release: release.clone(),
                exited: exited.clone(),
            }))
            .nested(false);
        let definition =
            ToolDefinition::json("child", "Revocable child", json!({"type":"object"})).unwrap();
        let authority = pl_core::tool::opaque::ToolAuthorization::unique();
        let child = prepare_registration("child", &definition, ToolCallPolicy::DirectOnly)
            .unwrap()
            .attach(ToolHandle::new(Child {
                definition,
                calls: calls.clone(),
                fail: false,
            }))
            .with_authorization(authority.clone())
            .nested(true);
        thread
            .register_tools(vec![lua_registration(), gate, child])
            .await
            .unwrap();
        let runner = tokio::spawn({
            let thread = thread.clone();
            async move { thread.run_turn(host::turn("stop")).await }
        });
        tokio::time::timeout(std::time::Duration::from_secs(5), entered.notified())
            .await
            .unwrap();
        if mode == 2 {
            tokio::time::timeout(std::time::Duration::from_secs(5), thread.close())
                .await
                .expect("close must join the VM and child")
                .unwrap();
            assert!(runner.await.unwrap().is_err());
        } else {
            if mode == 0 {
                authority.revoke();
            } else {
                thread
                    .register_tools(vec![lua_registration()])
                    .await
                    .unwrap();
            }
            release.notify_one();
            tokio::time::timeout(std::time::Duration::from_secs(5), runner)
                .await
                .expect("revocation must settle")
                .unwrap()
                .unwrap();
            thread.close().await.unwrap();
        }
        assert!(exited.load(Ordering::SeqCst));
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }
}
