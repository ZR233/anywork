//! Linux process evidence for the composed Lua -> Thread -> production worker cancellation path.
#![cfg(target_os = "linux")]
#[path = "support/helper.rs"]
mod helper;
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
        bytes.truncate(snapshot.capture_offsets.get(stream) as usize);
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
    // Build/locate the matched production helper before starting any execution deadline.
    let worker = helper::remote_helper_executable();
    for action in ["deadline", "cancel", "close"] {
        let root = tempfile::tempdir().unwrap();
        let backend =
            pl_tool::command::LocalCommandBackend::new(root.path()).with_worker_executable(worker);
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
    let backend = pl_tool::command::LocalCommandBackend::new(root.path())
        .with_worker_executable(helper::remote_helper_executable());
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
