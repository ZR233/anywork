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
    message_wakes: usize,
}

impl pl_core::model::ModelSession for LifecycleModel {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        self.requests.lock().unwrap().push(request.clone());
        let last_result = request.context.records.iter().rev().find(|record| {
            matches!(
                record.source,
                pl_core::context::ContextSource::ToolResult { .. }
            )
        });
        let mut followup = None;
        if let Some(record) = last_result
            && let pl_core::context::ContextSource::ToolResult { call_id, tool_id } = &record.source
            && tool_id == "wait"
            && (call_id.starts_with("wait-slow-program") || call_id.starts_with("wait-interactive"))
        {
            let text = record
                .content
                .iter()
                .find_map(|part| match part {
                    pl_core::context::ContextContent::Text { text } => Some(text.as_ref()),
                    _ => None,
                })
                .expect("wait must deliver its real result");
            let result: serde_json::Value = serde_json::from_str(text).unwrap();
            assert_eq!(
                result["timedOut"], false,
                "program wait must finish within its original deadline"
            );
            if result["tasks"]
                .as_array()
                .unwrap()
                .iter()
                .any(|task| task["status"] == "running")
            {
                self.message_wakes += 1;
                assert!(
                    self.message_wakes <= 4,
                    "unexpected repeated non-task wakes"
                );
                let original = request
                    .context
                    .records
                    .iter()
                    .flat_map(|record| record.tool_calls.iter())
                    .find(|call| &call.call_id == call_id)
                    .unwrap();
                let mut next = original.clone();
                next.call_id = format!("{call_id}-resume");
                followup = Some(next);
            }
        }
        let mut next = followup.or_else(|| self.calls.pop_front());
        if let Some(call) = next.as_mut()
            && call.call_id.starts_with("recover-output")
        {
            let text = request.context.records.iter().find_map(|record| {
                if !matches!(&record.source, pl_core::context::ContextSource::ToolResult { call_id, .. } if call_id == "truncated-program") {
                    return None;
                }
                record.content.iter().find_map(|part| match part {
                    pl_core::context::ContextContent::Text { text } => Some(text.as_ref()),
                    _ => None,
                })
            }).expect("foreground program must deliver its result");
            if call.call_id.ends_with("-diagnostic") {
                assert!(
                    text.starts_with("[Lua execution failed"),
                    "failure must remain visible"
                );
            } else {
                assert!(
                    text.contains("BEGIN"),
                    "truncation must retain the output head"
                );
            }
            if !text.contains("Lua execution failed") {
                assert!(
                    text.contains("FINAL SUMMARY END"),
                    "truncation must retain the terminal summary"
                );
            }
            let encoded_id = text
                .split_once("taskId=")
                .expect("truncated result must identify its retained original")
                .1;
            let id: String = serde_json::Deserializer::from_str(encoded_id)
                .into_iter()
                .next()
                .unwrap()
                .unwrap();
            let mut args: serde_json::Value =
                serde_json::from_str(call.arguments.content()).unwrap();
            args["code"] = args["code"]
                .as_str()
                .unwrap()
                .replace("RECOVER_TASK_ID", &serde_json::to_string(&id).unwrap())
                .into();
            call.arguments =
                pl_core::context::OpaquePayload::new("application/json", 1, args.to_string())
                    .unwrap();
        }
        if let Some(call) = next.as_mut()
            && matches!(call.call_id.as_str(), "query-process" | "interactive-query")
        {
            let expected = if call.call_id == "query-process" {
                "ready\nfinished\n"
            } else {
                "ready\nreceived:hello\n"
            };
            let observed = request
                .context
                .records
                .iter()
                .rev()
                .flat_map(|record| record.content.iter())
                .find_map(|part| {
                    let pl_core::context::ContextContent::Text { text } = part else {
                        return None;
                    };
                    let start = text.find('{')?;
                    let value: serde_json::Value =
                        serde_json::Deserializer::from_str(&text[start..])
                            .into_iter()
                            .next()?
                            .ok()?;
                    (value["stdout"]["content"] == expected)
                        .then(|| value["taskId"].as_str().map(str::to_owned))
                        .flatten()
                })
                .expect("the model must receive the real selected command taskId");
            let mut arguments: serde_json::Value =
                serde_json::from_str(call.arguments.content()).unwrap();
            arguments["code"] =
                serde_json::Value::String(arguments["code"].as_str().unwrap().replace(
                    "OBSERVED_COMMAND_TASK",
                    &serde_json::to_string(&observed).unwrap(),
                ));
            call.arguments =
                pl_core::context::OpaquePayload::new("application/json", 1, arguments.to_string())
                    .unwrap();
        }
        let calls = next.into_iter().collect();
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
async fn truncated_program_exposes_head_tail_and_queryable_original_without_reexecution() {
    use pl_tool::task_control::{TaskControlKind, TaskControlTool};
    for (fails, diagnostic_only) in [(false, false), (true, false), (true, true)] {
        let root = tempfile::tempdir().unwrap();
        let definition = pl_tool::exec::exec_definition();
        let command = ThreadExecTool::new(
            Arc::new(pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap()),
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
        let query = pl_tool::task_control::query_definition();
        let query = TaskControlTool::new(TaskControlKind::Query, query.clone())
            .registration(
                prepare_registration("get_tool_task", &query, ToolCallPolicy::DirectOnly).unwrap(),
            )
            .nested(true);
        let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
        let finish = if diagnostic_only {
            "error('EXPECTED_FAILURE'..string.rep('中',8192))"
        } else if fails {
            "print(text); error('EXPECTED_FAILURE')"
        } else {
            "return text"
        };
        let code = format!(
            "local r=tools.exec_command({{command=[=[printf 'once\\n' >> invocation-count]=]}}); assert(r.exitCode==0); local text='BEGIN'..string.rep('中',8192)..'FINAL SUMMARY END'; {finish}"
        );
        let status = if fails { "failed" } else { "succeeded" };
        let recovery = format!(
            r#"
local chunks={{}}; local cursor=0
repeat
  local q=tools.get_tool_task({{taskId=RECOVER_TASK_ID,resultCursor=cursor}})
  assert(q.task.status=='{status}')
  chunks[#chunks+1]=q.result.content; cursor=q.result.nextCursor
until cursor==nil or cursor==json.null
assert(#chunks>1)
local saved=json.decode(table.concat(chunks))
local expected='BEGIN'..string.rep('中',8192)..'FINAL SUMMARY END'
assert(saved.output=={expected_output})
{error_check}
return {{pages=#chunks,bytes=#saved.output}}
"#,
            expected_output = if diagnostic_only {
                "''"
            } else if fails {
                r"expected..'\n'"
            } else {
                "expected"
            },
            error_check = if fails {
                "assert(saved.error:find('EXPECTED_FAILURE',1,true))"
            } else {
                "assert(saved.error==json.null)"
            }
        );
        let recovery_id = if diagnostic_only {
            "recover-output-diagnostic"
        } else {
            "recover-output"
        };
        let model = LifecycleModel {
            calls: [
                (
                    "truncated-program",
                    serde_json::json!({"code":code,"maxOutputBytes":256}),
                ),
                (recovery_id, serde_json::json!({"code":recovery})),
            ]
            .into_iter()
            .map(|(id, args)| pl_core::model::ModelToolCall {
                call_id: id.into(),
                tool_id: "exec".into(),
                arguments: pl_core::context::OpaquePayload::new(
                    "application/json",
                    1,
                    args.to_string(),
                )
                .unwrap(),
                rejection: None,
                presentation_contract: None,
            })
            .collect(),
            requests: requests.clone(),
            message_wakes: 0,
        };
        let thread = ThreadHandle::start(
            format!("truncation-{fails}-{diagnostic_only}"),
            DynModelSession::new(model),
        )
        .unwrap();
        thread
            .register_tools(vec![command, lua, query])
            .await
            .unwrap();
        thread.run_turn(host::turn("recovery")).await.unwrap();
        let effects = thread.effects().await.unwrap();
        let delivery = effects
            .iter()
            .flat_map(|e| e.deliveries.iter())
            .find(|d| d.call_id == recovery_id)
            .unwrap();
        assert!(matches!(
            delivery.outcome,
            pl_core::thread::ToolOutcome::Succeeded
        ));
        assert_eq!(
            std::fs::read_to_string(root.path().join("invocation-count")).unwrap(),
            "once\n"
        );
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn slow_command_status_queries_and_top_level_wait_share_the_real_task_lifecycle() {
    use pl_core::thread::task::TaskStatus;
    use pl_tool::task_control::{TaskControlKind, TaskControlTool};
    use serde_json::json;

    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("search-probe.txt"),
        "default-stdin-probe\n",
    )
    .unwrap();
    let definition = pl_tool::exec::exec_definition();
    let backend = pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap();
    let command = ThreadExecTool::new(
        Arc::new(backend),
        Arc::new(Archive(root.path().join("archive"))),
        CommandAccess::WorkspaceOnly,
        definition.clone(),
    )
    .registrations(
        prepare_registration("exec_command", &definition, ToolCallPolicy::DirectOnly).unwrap(),
        prepare_registration(
            "write_stdin",
            &pl_tool::exec::write_stdin_definition(),
            ToolCallPolicy::DirectOnly,
        )
        .unwrap(),
        pl_tool::exec::write_stdin_definition(),
    );
    let lua = pl_tool::lua::LuaTool::new("");
    let lua = prepare_registration("exec", lua.definition(), ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(lua))
        .with_nested_calls();
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
    let mut registrations = command
        .into_iter()
        .map(|tool| tool.nested(false))
        .collect::<Vec<_>>();
    registrations.extend([lua, list, query, sleep]);
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
            json!({"code": "local r=tools.exec_command({command=[=[echo $$ > business.pid; printf 'ready\\n'; while [ ! -f release ]; do sleep 0.02; done; printf 'finished\\n']=],timeoutSeconds=15}); assert(r.exitCode==0); return r", "timeoutMs":20000}),
        ),
        (
            "wait-slow-program",
            "wait",
            json!({"taskIds":["task:slow-program"],"timeoutMs":20000}),
        ),
        (
            "query-process",
            "exec",
            json!({"code": "local q=tools.get_tool_task({taskId=OBSERVED_COMMAND_TASK,resultCursor=0}); local r=json.decode(q.result.content); assert(q.task.status=='succeeded' and r.exitCode==0 and r.stdout.content=='ready\\nfinished\\n'); return {taskId=q.task.taskId,status=q.task.status,exitCode=r.exitCode}"}),
        ),
        (
            "truncated-output",
            "exec",
            json!({"code": "local r=tools.exec_command({command=[=[printf '0123456789abcdefghij']=],maxOutputChars=8}); assert(r.exitCode==0 and r.stdout.wasTruncated and r.stdout.omittedBytes>0); local full=tools.exec_command({command='cat '..string.format('%q',r.stdoutFile)}); assert(full.stdout.content=='0123456789abcdefghij'); return {bytes=#full.stdout.content}"}),
        ),
        (
            "default-stdin",
            "exec",
            json!({"code": "local r=tools.exec_command({command=[=[rg -n -F -- default-stdin-probe]=],timeoutSeconds=2}); assert(r.exitCode==0 and r.stderr.content=='' and r.stdout.content:find('search-probe.txt',1,true)); local eof=tools.exec_command({command='cat',timeoutSeconds=2}); assert(eof.exitCode==0 and eof.stdout.content==''); return 'default stdin is EOF; search uses workspace files'"}),
        ),
        (
            "interactive-start",
            "exec",
            json!({"code": "return tools.exec_command({command=[=[printf 'ready\\n'; IFS= read -r value; printf 'received:%s\\n' \"$value\"]=], timeoutSeconds=15,interactive=true})"}),
        ),
        (
            "interactive-input",
            "exec",
            json!({"code": "local target; for _,t in ipairs(tools.list_tool_tasks({})) do if t.toolId=='exec_command' and t.status=='running' then assert(not target); target=t end end; assert(target); local r=tools.write_stdin({taskId=target.taskId,chars='hello\\n',closeStdin=true}); assert(r.inputReceipt.acceptedBytes==6); return r"}),
        ),
        (
            "wait-interactive",
            "wait",
            json!({"taskIds":["task:interactive-start"],"timeoutMs":15000}),
        ),
        (
            "interactive-query",
            "exec",
            json!({"code": "local q=tools.get_tool_task({taskId=OBSERVED_COMMAND_TASK,resultCursor=0}); local r=json.decode(q.result.content); assert(q.task.status=='succeeded' and r.stdout.content=='ready\\nreceived:hello\\n'); return 'interactive command completed'"}),
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
        message_wakes: 0,
    };
    let thread =
        ThreadHandle::start("lua-process-observe".into(), DynModelSession::new(model)).unwrap();
    thread.register_tools(registrations).await.unwrap();
    let mut input = host::turn("observe");
    input.max_model_steps = pl_core::thread::ModelStepLimit::Limited(20.try_into().unwrap());
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
    assert!(
        requests.lock().unwrap().len() >= 2,
        "the running Lua program must yield so the model can wait"
    );
    assert!(
        requests.lock().unwrap().iter().all(|request| request
            .context
            .records
            .iter()
            .flat_map(|record| record.tool_calls.iter())
            .all(|call| call.call_id != "query-process")),
        "a message wake must not let the simulated model assume command completion"
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
    let parent = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.call_id == "slow-program")
        .unwrap();
    let receipt: serde_json::Value =
        serde_json::from_str(parent.output.payload().content()).unwrap();
    let selected: serde_json::Value =
        serde_json::from_str(receipt["output"].as_str().unwrap()).unwrap();
    assert_eq!(selected["exitCode"], terminal["exitCode"]);
    assert_eq!(selected["stdout"]["content"], terminal["stdout"]["content"]);
    assert_eq!(selected["taskId"], terminal["taskId"]);
    assert_eq!(terminal["captureStatus"], "complete");
    assert!(terminal["stdoutResource"].is_object());
    assert!(
        selected.to_string().len() * 2 < terminal.to_string().len(),
        "returning the command view should not repeat the full archive envelope"
    );
    let stdin = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.tool_id == "write_stdin")
        .unwrap();
    let original_stdin: serde_json::Value =
        serde_json::from_str(stdin.output.payload().content()).unwrap();
    let parent_stdin = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.call_id == "interactive-input")
        .unwrap();
    let parent_stdin: serde_json::Value =
        serde_json::from_str(parent_stdin.output.payload().content()).unwrap();
    let selected_stdin: serde_json::Value =
        serde_json::from_str(parent_stdin["output"].as_str().unwrap())
            .unwrap_or_else(|error| panic!("stdin program result {parent_stdin}: {error}"));
    assert_eq!(
        selected_stdin["inputReceipt"],
        original_stdin["inputReceipt"]
    );
    assert_eq!(
        selected_stdin["targetTaskId"],
        original_stdin["targetTaskId"]
    );
    assert!(selected_stdin.to_string().len() * 2 < original_stdin.to_string().len());
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
    let final_tasks = effects
        .iter()
        .flat_map(|effect| effect.tasks.iter())
        .map(|task| (task.call_id.as_str(), task))
        .collect::<std::collections::BTreeMap<_, _>>();
    for id in [
        "slow-program",
        "query-process",
        "truncated-output",
        "default-stdin",
        "interactive-start",
        "interactive-input",
        "interactive-query",
        "query-pending",
        "query-terminal",
    ] {
        assert_eq!(
            final_tasks[id].status,
            TaskStatus::Succeeded,
            "program {id} must complete: {:?}",
            effects
                .iter()
                .flat_map(|effect| effect.deliveries.iter())
                .find(|delivery| delivery.call_id == id)
                .map(|delivery| delivery.output.payload().content())
        );
    }
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
    for signal in [None, Some(15)] {
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
        let diagnostic = "诊断\n".repeat(4096) + "expected failing test\nFINAL_DIAGNOSTIC";
        std::fs::write(root.path().join("failing-diagnostic"), &diagnostic).unwrap();
        let ending = if signal.is_some() {
            "kill -TERM $$"
        } else {
            "exit 7"
        };
        let command_text = format!(
            "printf 'once\\n' >> invocation-count; cat unselected-output; cat failing-diagnostic >&2; {ending}"
        );
        let checks = if signal.is_some() {
            "assert(not ok and r.output.exitCode==json.null and r.output.signal==15); assert(r.message:find('signal 15',1,true),'signal missing from diagnostic'); r=r.output"
        } else {
            "assert(ok and r.exitCode==7 and r.signal==nil)"
        };
        let code = format!(
            "local ok,r=pcall(function() return tools.exec_command({{command={}}}) end); {}; assert(r.stderr.content==string.rep('诊断'..string.char(10),4096)..'expected failing test'..string.char(10)..'FINAL_DIAGNOSTIC'); return {{exitCode=r.exitCode,signal=r.signal,stderr=r.stderr.content}}",
            serde_json::to_string(&command_text).unwrap(),
            checks,
        );
        let model = host::Calls {
            calls: [("exec".into(), serde_json::json!({"code": code}).to_string())].into(),
            requests: requests.clone(),
        };
        let thread =
            ThreadHandle::start("lua-nonzero".into(), DynModelSession::new(model)).unwrap();
        thread.register_tools(vec![command, lua]).await.unwrap();
        thread.run_turn(host::turn("nonzero")).await.unwrap();
        let effects = thread.effects().await.unwrap();
        let parent = effects
            .iter()
            .flat_map(|effect| effect.tasks.iter())
            .rev()
            .find(|t| t.tool_id == "exec")
            .unwrap();
        let diagnostic_payload = effects
            .iter()
            .flat_map(|e| e.deliveries.iter())
            .find(|d| d.call_id == parent.call_id)
            .unwrap()
            .output
            .payload()
            .content()
            .to_owned();
        assert_eq!(
            parent.status,
            pl_core::thread::task::TaskStatus::Succeeded,
            "signal case {signal:?}: {diagnostic_payload}"
        );
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
        let raw: serde_json::Value =
            serde_json::from_str(original.output.payload().content()).unwrap();
        assert_eq!(raw["signal"], serde_json::json!(signal));
        assert_eq!(raw["stderr"]["content"], diagnostic);
        assert_eq!(raw["stderr"]["wasTruncated"], false);
        let parent_delivery = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .find(|d| d.call_id == parent.call_id)
            .unwrap();
        let selected: serde_json::Value =
            serde_json::from_str(parent_delivery.output.payload().content()).unwrap();
        let selected: serde_json::Value =
            serde_json::from_str(selected["output"].as_str().unwrap()).unwrap();
        assert_eq!(
            selected["stderr"], diagnostic,
            "Lua receives the complete diagnostic before model projection"
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
}

#[tokio::test]
async fn unhandled_command_archive_failure_retains_stderr_and_its_original_identity() {
    let root = tempfile::tempdir().unwrap();
    let diagnostic = "BEGIN_DIAGNOSTIC\n".to_owned() + &"诊断\n".repeat(4096) + "END_DIAGNOSTIC";
    std::fs::write(root.path().join("diagnostic"), &diagnostic).unwrap();
    let archive = root.path().join("archive");
    std::fs::write(&archive, "occupied").unwrap();
    let definition = pl_tool::exec::exec_definition();
    let command = ThreadExecTool::new(
        Arc::new(pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap()),
        Arc::new(Archive(archive)),
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
    let model = host::Calls {
        calls: [("exec".into(), serde_json::json!({"code":"return tools.exec_command({command=[=[printf 'once\\n' >> invocation-count; printf 'UNSELECTED_STDOUT'; cat diagnostic >&2]=]})"}).to_string())].into(),
        requests: requests.clone(),
    };
    let thread =
        ThreadHandle::start("lua-archive-failure".into(), DynModelSession::new(model)).unwrap();
    thread.register_tools(vec![command, lua]).await.unwrap();
    thread
        .run_turn(host::turn("archive-failure"))
        .await
        .unwrap();
    let effects = thread.effects().await.unwrap();
    let parent = effects
        .iter()
        .flat_map(|e| e.deliveries.iter())
        .find(|d| d.tool_id == "exec")
        .unwrap();
    let child = effects
        .iter()
        .flat_map(|e| e.tasks.iter())
        .find(|t| t.tool_id == "exec_command")
        .unwrap();
    let payload: serde_json::Value =
        serde_json::from_str(parent.output.payload().content()).unwrap();
    let error = payload["error"].as_str().unwrap();
    assert!(
        error.contains(&diagnostic),
        "unhandled execution failure lost captured stderr: {error}"
    );
    assert!(
        error.contains(&child.id),
        "failure must identify its queryable original"
    );
    assert!(!error.contains("UNSELECTED_STDOUT"));
    let context = serde_json::to_string(&requests.lock().unwrap().last().unwrap().context).unwrap();
    assert!(context.contains("BEGIN_DIAGNOSTIC") && context.contains("END_DIAGNOSTIC"));
    assert!(context.contains("Output truncated") && context.contains("get_tool_task"));
    assert_eq!(
        std::fs::read_to_string(root.path().join("invocation-count")).unwrap(),
        "once\n"
    );
    thread.close().await.unwrap();
}
