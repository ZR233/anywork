//! Linux process evidence for the composed Lua -> Thread -> production executor cancellation path.
#![cfg(target_os = "linux")]
#[path = "support/binding_host.rs"]
mod host;
use pl_agent_tool::{Tool, ToolHandle};
use pl_core::{
    context::ResourceReference, model::DynModelSession, thread::ThreadHandle,
    tool::opaque::ToolError,
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_registration},
    command::{CommandCaptureStream, CommandOutputSnapshot},
    exec::{CommandAccess, CommandOutputArchive, ThreadExecTool},
};
use sha2::{Digest, Sha256};
use std::{path::PathBuf, sync::Arc, time::Duration};

/// Explicit provider call identities keep scripted receipt queries reproducible, while all
/// scheduling, task queries, waits, cancellation and commands remain production.
struct LifecycleModel {
    calls: std::collections::VecDeque<pl_core::model::ModelToolCall>,
    requests: Arc<std::sync::Mutex<Vec<pl_core::model::ModelRequest>>>,
}

impl pl_core::model::ModelSession for LifecycleModel {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        self.requests.lock().unwrap().push(request.clone());
        let calls = self.calls.pop_front().into_iter().collect();
        Ok(pl_core::model::PreparedModelCall::new(async move {
            Ok(pl_core::model::ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![],
                tool_calls: calls,
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), pl_core::model::ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn slow_command_status_queries_and_top_level_wait_share_the_real_task_lifecycle() {
    use pl_core::thread::task::TaskStatus;
    use pl_tool::task_control::{TaskControlKind, TaskControlTool};
    use serde_json::json;

    let root = tempfile::tempdir().unwrap();
    let definition = pl_tool::exec::exec_definition();
    let backend = pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap();
    let command = ThreadExecTool::new(
        Arc::new(backend),
        Arc::new(Archive(root.path().join("archive"))),
        CommandAccess::WorkspaceOnly,
        definition.clone(),
    )
    .registration(
        prepare_registration("exec_command", &definition, ToolCallPolicy::DirectOnly).unwrap(),
    )
    .nested(false);
    let lua = pl_tool::lua::LuaTool::new("");
    let lua = prepare_registration("exec", lua.definition(), ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(lua))
        .with_nested_calls()
        .foreground_coexisting();
    let list = pl_tool::task_control::ListTasksTool::declaration();
    let list = prepare_registration("list_tool_tasks", &list, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(
            pl_tool::binding::prepare_native_tool::<pl_tool::task_control::ListTasksTool>()
                .unwrap()
                .attach(pl_tool::task_control::ListTasksTool),
        ))
        .nested(true);
    let query = pl_tool::task_control::query_definition();
    let query = TaskControlTool::new(TaskControlKind::Query, query.clone())
        .registration(
            prepare_registration("get_tool_task", &query, ToolCallPolicy::DirectOnly).unwrap(),
        )
        .nested(true);
    let sleep = pl_tool::session::SleepTool::declaration();
    let sleep = prepare_registration("sleep", &sleep, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(
            pl_tool::binding::prepare_native_tool::<pl_tool::session::SleepTool>()
                .unwrap()
                .attach(pl_tool::session::SleepTool),
        ))
        .top_level_only();
    let mut registrations = vec![command, lua, list, query, sleep];
    for (kind, definition) in [
        (
            TaskControlKind::Wait,
            pl_tool::task_control::wait_definition(),
        ),
        (
            TaskControlKind::Cancel,
            pl_tool::task_control::cancel_definition(),
        ),
    ] {
        let prepared =
            prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)
                .unwrap();
        registrations.push(TaskControlTool::new(kind, definition).registration(prepared));
    }
    let script = [
        (
            "slow-program",
            "exec",
            json!({"code": "local r=tools.exec_command({command=[=[echo $$ > business.pid; printf 'ready\\n'; while [ ! -f release ]; do sleep 0.02; done; printf 'finished\\n']=],timeoutSeconds=15}); assert(r.exitCode==0); return {taskId=r.taskId,stdout=r.stdout.content}", "timeoutMs":20000}),
        ),
        (
            "query-process",
            "exec",
            json!({"code": "local found; for _,t in ipairs(tools.list_tool_tasks({})) do if t.toolId=='exec_command' then found=t end end; assert(found and found.status=='succeeded'); local q=tools.get_tool_task({taskId=found.taskId,resultCursor=0}); local r=json.decode(q.result.content); assert(r.exitCode==0 and r.stdout.content=='ready\\nfinished\\n'); return {taskId=q.task.taskId,status=q.task.status,exitCode=r.exitCode}"}),
        ),
        ("timer", "sleep", json!({"durationMs":60000})),
        (
            "query-pending",
            "exec",
            json!({"code":"local q=tools.get_tool_task({taskId='task:timer'}); assert(q.task.status=='running'); return q.task"}),
        ),
        (
            "wait-timeout",
            "wait",
            json!({"taskIds":["task:timer"],"timeoutMs":10}),
        ),
        (
            "cancel-timer",
            "cancel_tool_task",
            json!({"taskId":"task:timer"}),
        ),
        (
            "wait-cancelled",
            "wait",
            json!({"taskIds":["task:timer"],"timeoutMs":1000}),
        ),
        (
            "query-terminal",
            "exec",
            json!({"code":"local q=tools.get_tool_task({taskId='task:timer',resultCursor=0}); assert(q.task.status=='cancelled'); return q.task"}),
        ),
    ];
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let model = LifecycleModel {
        calls: script
            .into_iter()
            .map(|(id, tool, arguments)| pl_core::model::ModelToolCall {
                call_id: id.into(),
                tool_id: tool.into(),
                arguments: pl_core::context::OpaquePayload::new(
                    "application/json",
                    1,
                    arguments.to_string(),
                )
                .unwrap(),
                rejection: None,
                presentation_contract: None,
            })
            .collect(),
        requests: requests.clone(),
    };
    let thread =
        ThreadHandle::start("lua-process-observe".into(), DynModelSession::new(model)).unwrap();
    thread.register_tools(registrations).await.unwrap();
    let mut input = host::turn("observe");
    input.max_model_steps = pl_core::thread::ModelStepLimit::Limited(10.try_into().unwrap());
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(input).await }
    });
    let pid = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if let Ok(text) = tokio::fs::read_to_string(root.path().join("business.pid")).await
                && let Ok(pid) = text.trim().parse::<u32>()
            {
                break pid;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    // Cross the ordinary one-second background delivery window. The Lua invocation still owns
    // this command and waits, while the public Thread snapshot remains responsive and accurate.
    tokio::time::sleep(Duration::from_millis(1200)).await;
    let running = thread.snapshot();
    assert!(std::path::Path::new(&format!("/proc/{pid}")).exists());
    let process = running
        .tasks
        .values()
        .find(|t| t.tool_id == "exec_command" && t.status == TaskStatus::Running)
        .unwrap();
    assert_eq!(
        requests.lock().unwrap().len(),
        1,
        "Lua must not hand off a premature command receipt"
    );
    let wait_cancellation = tokio_util::sync::CancellationToken::new();
    let pending_wait = tokio::spawn({
        let thread = thread.clone();
        let id = process.id.clone();
        let cancellation = wait_cancellation.clone();
        async move { thread.wait_task(&id, cancellation).await }
    });
    tokio::time::sleep(Duration::from_millis(20)).await;
    assert!(!pending_wait.is_finished());
    wait_cancellation.cancel();
    assert!(matches!(
        pending_wait.await.unwrap(),
        Err(pl_core::thread::ThreadError::Cancelled)
    ));
    assert_eq!(
        thread.snapshot().tasks[&process.id].status,
        TaskStatus::Running
    );
    assert!(std::path::Path::new(&format!("/proc/{pid}")).exists());
    tokio::fs::write(root.path().join("release"), b"finish")
        .await
        .unwrap();
    let terminal = tokio::time::timeout(
        Duration::from_secs(10),
        thread.wait_task(&process.id, tokio_util::sync::CancellationToken::new()),
    )
    .await
    .expect("releasing the real process must wake the original task waiter")
    .unwrap();
    let terminal: serde_json::Value =
        serde_json::from_str(terminal.output.payload().content()).unwrap();
    assert_eq!(terminal["exitCode"], 0);
    tokio::time::timeout(Duration::from_secs(15), runner)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let effects = thread.effects().await.unwrap();
    let deliveries = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect::<Vec<_>>();
    let timed_out = deliveries
        .iter()
        .find(|d| d.call_id == "wait-timeout")
        .unwrap();
    let result: serde_json::Value =
        serde_json::from_str(timed_out.output.payload().content()).unwrap();
    assert_eq!(result["timedOut"], true);
    assert_eq!(
        result["tasks"][0]["status"], "running",
        "wait timeout must not cancel its task"
    );
    let cancelled = deliveries
        .iter()
        .find(|d| d.call_id == "wait-cancelled")
        .unwrap();
    let result: serde_json::Value =
        serde_json::from_str(cancelled.output.payload().content()).unwrap();
    assert_eq!(result["timedOut"], false);
    assert_eq!(result["tasks"][0]["status"], "cancelled");
    assert!(
        thread
            .snapshot()
            .tasks
            .values()
            .all(|t| t.status != TaskStatus::Running)
    );
    assert!(
        thread
            .snapshot()
            .tasks
            .values()
            .filter(|t| t.tool_id == "exec")
            .all(|t| t.status == TaskStatus::Succeeded)
    );
    assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct Archive(PathBuf);
impl CommandOutputArchive for Archive {
    async fn retain(
        &self,
        _: &str,
        snapshot: &CommandOutputSnapshot,
        stream: CommandCaptureStream,
    ) -> Result<ResourceReference, ToolError> {
        let path = match stream {
            CommandCaptureStream::Stdout => &snapshot.capture_file,
            CommandCaptureStream::Stderr => &snapshot.stderr_capture_file,
        };
        let mut bytes = tokio::fs::read(path).await.map_err(ToolError::new)?;
        let confirmed = snapshot
            .confirmed_bytes(stream)
            .ok_or_else(|| ToolError::new(std::io::Error::other("capture length is unknown")))?;
        bytes.truncate(usize::try_from(confirmed).map_err(ToolError::new)?);
        let digest = hex::encode(Sha256::digest(&bytes));
        tokio::fs::create_dir_all(&self.0)
            .await
            .map_err(ToolError::new)?;
        tokio::fs::write(self.0.join(&digest), &bytes)
            .await
            .map_err(ToolError::new)?;
        ResourceReference::new(
            format!("lua-process:{digest}"),
            format!("sha256:{digest}"),
            bytes.len() as u64,
            "text/plain".into(),
        )
        .map_err(ToolError::new)
    }
}

#[tokio::test]
async fn deadline_cancellation_and_close_join_real_lua_child_processes() {
    for action in ["deadline", "cancel", "close"] {
        let root = tempfile::tempdir().unwrap();
        let backend = pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap();
        let definition = pl_tool::exec::exec_definition();
        let prepared =
            prepare_registration("exec_command", &definition, ToolCallPolicy::DirectOnly).unwrap();
        let command = ThreadExecTool::new(
            Arc::new(backend),
            Arc::new(Archive(root.path().join("archive"))),
            CommandAccess::WorkspaceOnly,
            definition,
        )
        .registration(prepared)
        .nested(false);
        let tool = pl_tool::lua::LuaTool::new("");
        let lua = prepare_registration("exec", tool.definition(), ToolCallPolicy::DirectOnly)
            .unwrap()
            .attach(ToolHandle::new(tool))
            .with_nested_calls()
            .foreground();
        let timeout = if action == "deadline" { 5000 } else { 60000 };
        let model = host::Calls { calls: [("exec".into(), serde_json::json!({"code":"tools.exec_command({command='echo $$ > business.pid; exec sleep 600', timeoutSeconds=600})", "timeoutMs":timeout}).to_string())].into(), requests: Default::default() };
        let thread =
            ThreadHandle::start(format!("lua-process-{action}"), DynModelSession::new(model))
                .unwrap();
        thread.register_tools(vec![command, lua]).await.unwrap();
        let input = host::turn("process");
        let cancellation = input.cancellation.clone();
        let runner = tokio::spawn({
            let thread = thread.clone();
            async move { thread.run_turn(input).await }
        });
        let pid = tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if let Ok(text) = tokio::fs::read_to_string(root.path().join("business.pid")).await
                    && let Ok(pid) = text.trim().parse::<u32>()
                {
                    break pid;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await;
        if action == "cancel" {
            cancellation.cancel();
        }
        if action == "close" || pid.is_err() {
            thread.close().await.unwrap();
        }
        let result = tokio::time::timeout(Duration::from_secs(15), runner)
            .await
            .expect("VM and command must settle")
            .unwrap();
        if action != "close" && pid.is_ok() {
            thread.close().await.unwrap();
        }
        let pid = pid.expect("real business process must have started");
        assert!(
            !std::path::Path::new(&format!("/proc/{pid}")).exists(),
            "business process survived {action}"
        );
        eprintln!("REAPED action={action} pid={pid}");
        assert!(
            thread
                .snapshot()
                .tasks
                .values()
                .all(|task| task.status != pl_core::thread::task::TaskStatus::Running)
        );
        if action == "deadline" {
            result.unwrap();
        } else {
            assert!(result.is_err());
        }
    }
}

#[tokio::test]
async fn nonzero_process_exit_is_lua_data_while_the_original_child_stays_failed() {
    let root = tempfile::tempdir().unwrap();
    let backend = pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap();
    let definition = pl_tool::exec::exec_definition();
    let command = ThreadExecTool::new(
        Arc::new(backend),
        Arc::new(Archive(root.path().join("archive"))),
        CommandAccess::WorkspaceOnly,
        definition.clone(),
    )
    .registration(
        prepare_registration("exec_command", &definition, ToolCallPolicy::DirectOnly).unwrap(),
    )
    .nested(false);
    let tool = pl_tool::lua::LuaTool::new("");
    let lua = prepare_registration("exec", tool.definition(), ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(tool))
        .with_nested_calls()
        .foreground();
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    std::fs::write(root.path().join("unselected-output"), "UNSELECTED_STDOUT").unwrap();
    let model = host::Calls {
        calls: [("exec".into(), serde_json::json!({"code": "local r=tools.exec_command({command=[=[printf 'once\\n' >> invocation-count; cat unselected-output; printf 'expected failing test' >&2; exit 7]=]}); assert(r.exitCode==7); return {exitCode=r.exitCode,stderr=r.stderr.content}"}).to_string())].into(),
        requests: requests.clone(),
    };
    let thread = ThreadHandle::start("lua-nonzero".into(), DynModelSession::new(model)).unwrap();
    thread.register_tools(vec![command, lua]).await.unwrap();
    thread.run_turn(host::turn("nonzero")).await.unwrap();
    let effects = thread.effects().await.unwrap();
    let parent = effects
        .iter()
        .flat_map(|effect| effect.tasks.iter())
        .rev()
        .find(|t| t.tool_id == "exec")
        .unwrap();
    assert_eq!(parent.status, pl_core::thread::task::TaskStatus::Succeeded);
    let child = effects
        .iter()
        .flat_map(|effect| effect.tasks.iter())
        .rev()
        .find(|t| t.tool_id == "exec_command")
        .unwrap();
    assert_eq!(child.status, pl_core::thread::task::TaskStatus::Failed);
    assert_eq!(
        child.parent_call_id.as_deref(),
        Some(parent.call_id.as_str())
    );
    let original = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|d| d.call_id == child.call_id)
        .unwrap();
    assert!(
        original
            .output
            .payload()
            .content()
            .contains("UNSELECTED_STDOUT")
    );
    let model_context =
        serde_json::to_string(&requests.lock().unwrap().last().unwrap().context).unwrap();
    assert!(model_context.contains("expected failing test"));
    assert!(!model_context.contains("UNSELECTED_STDOUT"));
    assert_eq!(
        std::fs::read_to_string(root.path().join("invocation-count")).unwrap(),
        "once\n"
    );
    thread.close().await.unwrap();
}
