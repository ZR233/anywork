#[path = "support/binding_host.rs"]
mod host;
use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{DynModelSession, ModelSession},
    thread::{
        ThreadHandle, ToolDeliveryTarget,
        cold::{ColdStore, ColdStoreHandle},
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
        let data = json!({"selected":7,"hidden":"PRIVATE_INTERMEDIATE"}).to_string();
        let output = ToolOutput::new(
            OpaquePayload::new("application/json", 1, data.clone()).unwrap(),
            vec![
                ContextContent::Text { text: data.into() },
                pl_model::runtime::attachment_content(
                    pl_core::context::ResourceReference::new(
                        "LUA_IMAGE".into(),
                        format!("sha256:{}", "0".repeat(64)),
                        0,
                        "image/png".into(),
                    )
                    .unwrap(),
                    pl_model::completion::AttachmentModality::Image,
                )
                .unwrap(),
            ],
        );
        if self.fail {
            Err(ToolError::new(std::io::Error::other("child failed")).with_output(output))
        } else {
            Ok(output)
        }
    }
}

#[tokio::test]
async fn real_thread_retains_nested_originals_without_putting_them_into_model_history() {
    for (fail, denied) in [(false, false), (true, false), (false, true)] {
        let expected_calls = if denied { 0 } else { 3 };
        let directory = tempfile::tempdir().unwrap();
        let options = pl_core::persistence::SqliteSessionOptions {
            path: directory.path().join("history.sqlite"),
        };
        let store = pl_core::persistence::SqliteSessionStore::open(options.clone())
            .await
            .unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let requests = Arc::new(Mutex::new(Vec::new()));
        let code = if fail || denied {
            "local function child() local ok,err=pcall(function() return tools.child({n=7}) end); assert(not ok); return tostring(err) end; parallel({child,child,child}); return 'handled'"
        } else {
            "local r=parallel({function() return tools.child({n=7}) end,function() return tools.child({n=7}) end,function() return tools.child({n=7}) end}); return r[1].selected"
        };
        let model = host::Calls {
            calls: std::collections::VecDeque::from([(
                "exec".into(),
                json!({"code":code}).to_string(),
            )]),
            requests: requests.clone(),
        };
        let thread =
            ThreadHandle::start("lua-test".into(), DynModelSession::new(Projected(model))).unwrap();
        thread
            .attach_storage(ColdStoreHandle::new(store.clone()))
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
        let effects = thread.effects().await.unwrap();
        let deliveries = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .collect::<Vec<_>>();
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
        assert!(child.output.payload().content().contains(if denied {
            "host policy denied"
        } else {
            "PRIVATE_INTERMEDIATE"
        }));
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
        assert_eq!(serialized.contains("LUA_IMAGE"), !denied);
        assert_eq!(
            deliveries
                .iter()
                .filter(|delivery| delivery.tool_id == "child")
                .count(),
            3
        );
        assert_eq!(calls.load(Ordering::SeqCst), expected_calls);
        thread.flush().await.unwrap();
        let checkpoint = thread.checkpoint(0).unwrap();
        thread.close().await.unwrap();
        store.shutdown().await.unwrap();
        let reopened = pl_core::persistence::SqliteSessionStore::open(options)
            .await
            .unwrap();
        let saved = ColdStore::read_tool_task(&reopened, "lua-test", &format!("task:{call_id}"))
            .await
            .unwrap()
            .unwrap();
        assert!(saved.task.parent_call_id.is_some());
        assert_eq!(
            saved.task.invocation.unwrap().arguments.content(),
            "{\"n\":7}"
        );
        assert!(
            saved
                .delivery
                .unwrap()
                .output
                .payload()
                .content()
                .contains(if denied {
                    "host policy denied"
                } else {
                    "PRIVATE_INTERMEDIATE"
                })
        );
        assert_eq!(
            calls.load(Ordering::SeqCst),
            expected_calls,
            "cold reads must not replay tools"
        );
        let resumed =
            ThreadHandle::resume_without_model("lua-test".into(), Some(checkpoint)).unwrap();
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
        reopened.shutdown().await.unwrap();
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
        Ok(ToolOutput::new(
            OpaquePayload::text("revealed"),
            vec![ContextContent::Text {
                text: "revealed".into(),
            }],
        )
        .with_revealed_tools(vec!["child".into()]))
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
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        Ok(ToolOutput::new(
            OpaquePayload::text("gate completed"),
            vec![],
        ))
    }
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
