//! Linux process evidence for the composed Lua -> Thread -> production executor cancellation path.
use crate::binding_host as host;
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
                    (value["stdout"] == expected)
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
local chunks={{}}; local cursor=0; local seen=0; local total=nil
repeat
  local q=tools.get_tool_task({{taskId=RECOVER_TASK_ID,resultCursor=cursor}})
  assert(q.task.taskId==RECOVER_TASK_ID and q.task.toolId=='exec' and q.task.status=='{status}')
  total=total or q.result.totalBytes
  assert(q.result.totalBytes==total and #q.result.content>0)
  chunks[#chunks+1]=q.result.content; cursor=q.result.nextCursor
  seen=seen+#q.result.content
  assert(cursor==json.null and seen==total or cursor==seen and seen<total)
until cursor==nil or cursor==json.null
assert(#chunks>1)
local original=table.concat(chunks)
local multibyte=assert(original:find('中',1,true))
local ok,err=pcall(function() tools.get_tool_task({{taskId=RECOVER_TASK_ID,resultCursor=multibyte}}) end)
assert(not ok and err.message:find('UTF-8 character',1,true))
local saved=json.decode(original).data.value
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
    let gate = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    std::fs::write(root.path().join("business.py"), format!(
        "import os, socket\ns=socket.create_connection(('127.0.0.1', {}))\nprint('ready', flush=True)\ns.sendall((str(os.getpid())+'\\n').encode())\nassert s.recv(1) == b'x'\nprint('finished', flush=True)\n", gate.local_addr().unwrap().port()
    )).unwrap();
    std::fs::write(
        root.path().join("search-probe.txt"),
        "default-stdin-probe\n",
    )
    .unwrap();
    let definition = pl_tool::exec::exec_definition();
    let backend = pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap();
    let processes = Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
        backend,
    )));
    let command = ThreadExecTool::from_process_manager(
        processes.clone(),
        Arc::new(Archive(root.path().join("archive"))),
        CommandAccess::WorkspaceOnly,
        definition.clone(),
    )
    .registration(
        prepare_registration("exec_command", &definition, ToolCallPolicy::DirectOnly).unwrap(),
    );
    // A refreshed catalog retires borrowed tool instances without retiring the Thread's controller.
    let retired = ThreadExecTool::from_process_manager(
        processes.clone(),
        Arc::new(Archive(root.path().join("archive"))),
        CommandAccess::WorkspaceOnly,
        definition.clone(),
    );
    pl_agent_tool::Tool::close(&retired).await.unwrap();
    assert_eq!(
        processes.lifecycle(),
        pl_tool::command::ProcessManagerLifecycle::Open
    );
    let stdin_definition = pl_tool::exec::write_stdin_definition();
    let stdin = prepare_registration("write_stdin", &stdin_definition, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(pl_tool::binding::NativeWorkspaceTool::new(
            pl_tool::exec::ThreadWriteStdinTool::new(processes, stdin_definition),
        )))
        .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
            "builtin.write_stdin@1",
        ));
    let command = vec![command, stdin];
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
            json!({"code": "local r=tools.exec_command({command=[=[python3 -u business.py]=],timeoutSeconds=15}); assert(r.exitCode==0); return r", "timeoutMs":20000}),
        ),
        (
            "wait-slow-program",
            "wait",
            json!({"taskIds":["task:slow-program"],"timeoutMs":20000}),
        ),
        (
            "query-process",
            "exec",
            json!({"code": "local q=tools.get_tool_task({taskId=OBSERVED_COMMAND_TASK,resultCursor=0}); local r=json.decode(q.result.content).data.value; assert(q.task.status=='succeeded' and r.exitCode==0 and r.stdout=='ready\\nfinished\\n'); return {taskId=q.task.taskId,status=q.task.status,exitCode=r.exitCode}"}),
        ),
        (
            "truncated-output",
            "exec",
            json!({"code": "local r=tools.exec_command({command=[=[printf '0123456789abcdefghij']=],maxOutputChars=8}); assert(r.exitCode==0 and r.stdoutWasTruncated and r.stdoutOmittedBytes>0); local full=tools.exec_command({command='cat '..string.format('%q',r.stdoutFile)}); assert(full.stdout=='0123456789abcdefghij'); return {bytes=#full.stdout}"}),
        ),
        (
            "default-stdin",
            "exec",
            json!({"code": "local r=tools.exec_command({command=[=[cat; cat search-probe.txt]=],timeoutSeconds=2}); assert(r.exitCode==0 and r.stderr=='' and r.stdout=='default-stdin-probe\\n'); return 'default stdin is EOF; workspace files remain readable'"}),
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
            json!({"code": "local q=tools.get_tool_task({taskId=OBSERVED_COMMAND_TASK,resultCursor=0}); local r=json.decode(q.result.content).data.value; assert(q.task.status=='succeeded' and r.stdout=='ready\\nreceived:hello\\n'); return 'interactive command completed'"}),
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
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt};
    let (socket, _) = tokio::time::timeout(Duration::from_secs(10), gate.accept())
        .await
        .unwrap()
        .unwrap();
    let mut socket = tokio::io::BufReader::new(socket);
    let mut identity = String::new();
    tokio::time::timeout(Duration::from_secs(10), socket.read_line(&mut identity))
        .await
        .unwrap()
        .unwrap();
    let pid: u32 = identity.trim().parse().unwrap();
    // Only the Thread's delivery clock advances. The original process stays behind its gate.
    tokio::time::pause();
    tokio::time::advance(Duration::from_millis(1200)).await;
    tokio::time::resume();
    let mut snapshots = thread.subscribe();
    let running = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let snapshot = snapshots
                .next()
                .await
                .expect("the running owner remains observable");
            if requests.lock().unwrap().len() >= 2
                && snapshot
                    .tasks
                    .values()
                    .any(|t| t.tool_id == "exec_command" && t.status == TaskStatus::Running)
            {
                break snapshot;
            }
        }
    })
    .await
    .expect("background delivery wakes the model without ending the process");
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
    let pending_wait = {
        let thread = thread.clone();
        let id = process.id.clone();
        let cancellation = wait_cancellation.clone();
        async move { thread.wait_task(&id, cancellation).await }
    };
    tokio::pin!(pending_wait);
    assert!(futures::poll!(&mut pending_wait).is_pending());
    wait_cancellation.cancel();
    assert!(matches!(
        pending_wait.await,
        Err(pl_core::thread::ThreadError::Cancelled)
    ));
    assert_eq!(
        thread.snapshot().tasks[&process.id].status,
        TaskStatus::Running
    );
    assert!(std::path::Path::new(&format!("/proc/{pid}")).exists());
    socket.get_mut().write_all(b"x").await.unwrap();
    let terminal = tokio::time::timeout(
        Duration::from_secs(10),
        thread.wait_task(&process.id, tokio_util::sync::CancellationToken::new()),
    )
    .await
    .expect("releasing the real process must wake the original task waiter")
    .unwrap();
    assert_eq!(
        pl_tool::exec::saved_command_exit_code(terminal.output.details()),
        Some(0)
    );
    assert_eq!(
        pl_tool::exec::saved_command_resources(terminal.output.details())
            .unwrap()
            .len(),
        2
    );
    assert!(
        terminal
            .output
            .content()
            .iter()
            .all(|part| matches!(part, pl_core::context::ContextContent::Text { .. }))
    );
    let capture = &terminal.output.details().unwrap()["command"];
    let terminal = terminal.output.data().unwrap();
    assert_eq!(terminal["exitCode"], 0);
    assert_eq!(terminal.as_object().unwrap().len(), 4);
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
    let receipt: serde_json::Value = parent.output.data().unwrap().clone();
    let selected: serde_json::Value =
        serde_json::from_str(receipt["output"].as_str().unwrap()).unwrap();
    assert_eq!(selected["exitCode"], terminal["exitCode"]);
    assert_eq!(selected["stdout"], terminal["stdout"]);
    assert_eq!(selected["taskId"], terminal["taskId"]);
    assert_eq!(capture["captureStatus"], "complete");
    assert!(capture["stdoutResource"].is_object());
    assert!(
        selected.get("stdoutResource").is_none(),
        "a program result carries the command value without full archive metadata"
    );
    let stdin = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.tool_id == "write_stdin")
        .unwrap();
    let original_stdin: serde_json::Value = stdin.output.data().unwrap().clone();
    let parent_stdin = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.call_id == "interactive-input")
        .unwrap();
    let parent_stdin: serde_json::Value = parent_stdin.output.data().unwrap().clone();
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
    assert_eq!(selected_stdin, original_stdin);
    let deliveries = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect::<Vec<_>>();
    let timed_out = deliveries
        .iter()
        .find(|d| d.call_id == "wait-timeout")
        .unwrap();
    let result: serde_json::Value = timed_out.output.data().unwrap().clone();
    assert_eq!(result["timedOut"], true);
    assert_eq!(
        result["tasks"][0]["status"], "running",
        "wait timeout must not cancel its task"
    );
    let cancelled = deliveries
        .iter()
        .find(|d| d.call_id == "wait-cancelled")
        .unwrap();
    let result: serde_json::Value = cancelled.output.data().unwrap().clone();
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
                .and_then(|delivery| delivery.output.data())
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
        let timeout = if action == "deadline" { 300 } else { 60000 };
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
async fn cancelling_one_real_lua_child_returns_observed_stderr_without_cancelling_the_program() {
    use pl_core::thread::{
        ToolDeliveryTarget, ToolOutcome,
        task::{TaskCancellationReceipt, TaskStatus},
    };

    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("stdout-fixture"), b"unselected stdout\n").unwrap();
    let definition = pl_tool::exec::exec_definition();
    let prepared =
        prepare_registration("exec_command", &definition, ToolCallPolicy::DirectOnly).unwrap();
    let command = ThreadExecTool::new(
        Arc::new(pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap()),
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
    let code = r#"
        local ok, err = pcall(tools.exec_command, args)
        assert(not ok, 'a cancelled child returned success')
        assert(err.message:find('cancelled', 1, true), err.message)
        assert(err.output and err.output.stderr == 'observed before cancellation\n', 'missing observed stderr')
        return {taskId=err.output.taskId, stderr=err.output.stderr, continued=true}
    "#;
    let arguments = serde_json::json!({
        "code": code,
        "args": {
            "command": "cat stdout-fixture; echo $$ > business.pid; printf 'observed before cancellation\\n' >&2; exec sleep 600",
            "timeoutSeconds": 20,
        },
    });
    let requests = Arc::new(std::sync::Mutex::new(Vec::new()));
    let model = host::Calls {
        calls: [("exec".into(), arguments.to_string())].into(),
        requests: requests.clone(),
    };
    let thread =
        ThreadHandle::start("lua-child-only-cancel".into(), DynModelSession::new(model)).unwrap();
    thread.register_tools(vec![command, lua]).await.unwrap();
    let mut snapshots = thread.subscribe();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(host::turn("cancel-child")).await }
    });
    let observed = tokio::time::timeout(Duration::from_secs(10), async {
        while let Some(snapshot) = snapshots.next().await {
            for (id, progress) in &snapshot.tool_progress {
                if let Some(task) = snapshot.tasks.get(id)
                    && task.tool_id == "exec_command"
                    && task.status == TaskStatus::Running
                    && progress.parts().iter().any(|part| {
                        let text = part.content().text();
                        text.contains("observed before cancellation\n")
                            && text.contains("unselected stdout\n")
                    })
                {
                    return Some(task.clone());
                }
            }
        }
        None
    })
    .await;
    if !matches!(&observed, Ok(Some(_))) {
        thread.close().await.unwrap();
    }
    let child = observed
        .unwrap()
        .expect("the running child published its stderr");
    let pid = std::fs::read_to_string(root.path().join("business.pid")).unwrap();
    let cancelled = thread.cancel_task(child.id.clone()).await.unwrap();
    assert_eq!(cancelled, TaskCancellationReceipt::Requested);
    let finished = tokio::time::timeout(Duration::from_secs(10), runner).await;
    thread.close().await.unwrap();
    finished
        .expect("the parent Lua program must continue")
        .unwrap()
        .unwrap();
    assert!(!std::path::Path::new(&format!("/proc/{}", pid.trim())).exists());

    let effects = thread.effects().await.unwrap();
    let mut deliveries = effects.iter().flat_map(|effect| effect.deliveries.iter());
    let child_delivery = deliveries
        .clone()
        .find(|delivery| delivery.call_id == child.call_id)
        .unwrap();
    let parent_delivery = deliveries
        .find(|delivery| delivery.tool_id == "exec")
        .unwrap();
    assert!(matches!(child_delivery.outcome, ToolOutcome::Cancelled));
    assert!(
        matches!(&child_delivery.target, ToolDeliveryTarget::Nested { parent_call_id }
        if parent_call_id == &parent_delivery.call_id)
    );
    assert!(child_delivery.delivered_context.is_empty());
    assert_eq!(
        child_delivery.output.control(),
        pl_core::tool::ToolControl::Continue
    );
    assert!(child_delivery.output.extension_mutations().is_empty());
    assert!(child_delivery.output.revealed_tools().is_empty());
    assert!(child_delivery.output.interaction().is_none());
    let task = effects
        .iter()
        .rev()
        .flat_map(|effect| effect.tasks.iter())
        .find(|task| task.id == child.id)
        .unwrap();
    assert_eq!(task.status, TaskStatus::Cancelled);
    assert!(task.cancel_requested);
    let child_data = child_delivery.output.data().unwrap();
    assert_eq!(child_data["taskId"], child.id);
    assert_eq!(child_data["stdout"], "unselected stdout\n");
    assert_eq!(child_data["stderr"], "observed before cancellation\n");

    assert!(matches!(parent_delivery.outcome, ToolOutcome::Succeeded));
    let parent_data = parent_delivery.output.data().unwrap();
    assert!(parent_data["error"].is_null());
    let program_output: serde_json::Value =
        serde_json::from_str(parent_data["output"].as_str().unwrap()).unwrap();
    assert_eq!(
        program_output,
        serde_json::json!({
            "taskId": child.id, "stderr": "observed before cancellation\n", "continued": true,
        })
    );
    let requests = requests.lock().unwrap();
    let result = requests
        .last()
        .unwrap()
        .context
        .records
        .iter()
        .find(|record| {
            matches!(&record.source, pl_core::context::ContextSource::ToolResult { call_id, .. }
            if call_id == &parent_delivery.call_id)
        })
        .expect("the model got the Lua program's selected output");
    let context = serde_json::to_string(&result.content).unwrap();
    assert!(context.contains("observed before cancellation"));
    assert!(!context.contains("unselected stdout"));
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
            "local ok,r=pcall(function() return tools.exec_command({{command={}}}) end); {}; assert(r.stderr==string.rep('诊断'..string.char(10),4096)..'expected failing test'..string.char(10)..'FINAL_DIAGNOSTIC'); return {{exitCode=r.exitCode,signal=r.signal,stderr=r.stderr}}",
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
            .data()
            .unwrap();
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
            original.output.data().unwrap()["stdout"]
                .as_str()
                .unwrap()
                .contains("UNSELECTED_STDOUT")
        );
        let raw: serde_json::Value = original.output.data().unwrap().clone();
        assert_eq!(raw["signal"], serde_json::json!(signal));
        assert_eq!(raw["stderr"], diagnostic);
        assert!(raw.get("stderrWasTruncated").is_none());
        if signal.is_none() {
            assert_eq!(raw.as_object().unwrap().len(), 4);
            assert_eq!(raw["exitCode"], 7);
            assert!(original.output.details().unwrap()["command"]["capture"].is_object());
        }
        let parent_delivery = effects
            .iter()
            .flat_map(|effect| effect.deliveries.iter())
            .find(|d| d.call_id == parent.call_id)
            .unwrap();
        let selected: serde_json::Value = parent_delivery.output.data().unwrap().clone();
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
        calls: [("exec".into(), serde_json::json!({"code":"return tools.exec_command({command=[=[printf 'once\\n' >> invocation-count; printf 'UNSELECTED_STDOUT'; cat diagnostic >&2; exit 7]=]})"}).to_string())].into(),
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
    let child_output = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .find(|delivery| delivery.call_id == child.call_id)
        .unwrap();
    let pl_core::thread::ToolOutcome::Failed(failure) = &child_output.outcome else {
        panic!("archive failure must fail the command invocation");
    };
    assert_eq!(failure.kind(), pl_core::tool::ToolFailureKind::Invocation);
    assert!(failure.source.downcast_ref::<std::io::Error>().is_some());
    let child_data = child_output.output.data().unwrap();
    assert_eq!(child_data["exitCode"], 7);
    assert_eq!(child_data["archiveStatus"], "failed");
    assert_eq!(child_data["diagnostic"]["code"], "exec.archive_failed");
    let payload: serde_json::Value = parent.output.data().unwrap().clone();
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

#[tokio::test]
async fn actual_launch_and_stdin_rejections_match_their_closed_declarations() {
    use pl_core::tool::ToolFailureKind;
    use serde_json::{Value, json};

    let root = tempfile::tempdir().unwrap();
    let exec_definition = pl_tool::exec::exec_definition();
    let stdin_definition = pl_tool::exec::write_stdin_definition();
    let backend = pl_tool::command::ExecutorCommandBackend::local(root.path()).unwrap();
    let processes = Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
        backend,
    )));
    let command = ThreadExecTool::from_process_manager(
        processes.clone(),
        Arc::new(Archive(root.path().join("archive"))),
        CommandAccess::WorkspaceOnly,
        exec_definition.clone(),
    );
    let stdin = pl_tool::exec::ThreadWriteStdinTool::new(processes, stdin_definition.clone());
    let stdin = prepare_registration("write_stdin", &stdin_definition, ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(pl_tool::binding::NativeWorkspaceTool::new(
            stdin,
        )))
        .nested(false);
    let command = command
        .registration(
            prepare_registration("exec_command", &exec_definition, ToolCallPolicy::DirectOnly)
                .unwrap(),
        )
        .nested(false);
    let lua = pl_tool::lua::LuaTool::new("");
    let lua = prepare_registration("exec", lua.definition(), ToolCallPolicy::DirectOnly)
        .unwrap()
        .attach(ToolHandle::new(lua))
        .with_nested_calls()
        .foreground();
    let code = r#"
        local started, launch=pcall(tools.exec_command, {command='exit 0',cwd='missing-directory'})
        assert(not started and launch.output.processStarted==false and launch.output.exitCode==nil)
        local done=tools.exec_command({command='exit 0'})
        local sent, write=pcall(tools.write_stdin, {taskId=done.taskId,chars='never sent'})
        assert(not sent and write.output.targetTaskId==done.taskId)
        assert(write.output.inputReceipt.outcome=='notSent' and write.output.inputReceipt.acceptedBytes==0)
        return 'checked'
    "#;
    let thread = ThreadHandle::start(
        "command-schema-branches".into(),
        DynModelSession::new(host::Calls {
            calls: [("exec".into(), json!({"code":code}).to_string())].into(),
            requests: Default::default(),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![command, stdin, lua])
        .await
        .unwrap();
    thread
        .run_turn(host::turn("verify observed result branches"))
        .await
        .unwrap();
    let effects = thread.effects().await.unwrap();
    thread.close().await.unwrap();
    let deliveries: Vec<_> = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect();
    let parent = deliveries
        .iter()
        .find(|delivery| delivery.tool_id == "exec")
        .unwrap();
    assert_eq!(
        parent.output.data().unwrap(),
        &json!({"output":"checked", "error":null})
    );

    let rejected = |tool_id| {
        let delivery = deliveries
            .iter()
            .find(|delivery| {
                delivery.tool_id == tool_id
                    && matches!(delivery.outcome, pl_core::thread::ToolOutcome::Failed(_))
            })
            .unwrap();
        let pl_core::thread::ToolOutcome::Failed(error) = &delivery.outcome else {
            unreachable!()
        };
        assert_eq!(error.kind(), ToolFailureKind::Invocation);
        delivery.output.data().unwrap()
    };
    let launch = rejected("exec_command");
    assert_eq!(launch["processStarted"], false);
    assert!(launch["taskId"].is_string());
    for stream_field in ["exitCode", "stdout", "stderr"] {
        assert!(launch.get(stream_field).is_none());
    }
    let write = rejected("write_stdin");
    assert_ne!(write["taskId"], write["targetTaskId"]);
    assert_eq!(write["status"], "succeeded");
    assert_eq!(write["diagnostic"]["code"], "exec.stdin_closed");
    assert_eq!(
        write["inputReceipt"],
        json!({"acceptedBytes":0, "outcome":"notSent"})
    );

    let assert_closed_branch_fields = |schema: &Value, data: &Value, key: &str| {
        let branch = schema["oneOf"]
            .as_array()
            .unwrap()
            .iter()
            .find(|branch| {
                branch["required"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|field| field == key)
            })
            .unwrap();
        assert_eq!(branch["additionalProperties"], false);
        for field in branch["required"].as_array().unwrap() {
            assert!(
                data.get(field.as_str().unwrap()).is_some(),
                "missing {field}"
            );
        }
        for field in data.as_object().unwrap().keys() {
            assert!(
                branch["properties"].get(field).is_some(),
                "undeclared {field}"
            );
        }
        let diagnostic = &branch["properties"]["diagnostic"];
        assert_eq!(diagnostic["additionalProperties"], false);
        for field in data["diagnostic"].as_object().unwrap().keys() {
            assert!(
                diagnostic["properties"].get(field).is_some(),
                "undeclared diagnostic {field}"
            );
        }
    };
    let exec_schema = exec_definition.output_schema().unwrap();
    assert_closed_branch_fields(exec_schema, launch, "processStarted");
    assert_closed_branch_fields(
        stdin_definition.output_schema().unwrap(),
        write,
        "targetTaskId",
    );
    assert_eq!(
        exec_schema["oneOf"][0]["required"],
        json!(["taskId", "exitCode", "stdout", "stderr"])
    );
}
