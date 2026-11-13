//! The same product manager preserves root facts while independently draining output.
#![cfg(target_os = "linux")]
#[path = "support/helper.rs"]
mod helper;
#[path = "support/remote.rs"]
mod support;
use anyhow::Context;
use pl_tool::command::{
    CommandCaptureState, CommandProcessLifecycle, CommandProcessManager, CommandStartRequest,
    ExecutorCommandBackend,
};
use std::{sync::Arc, time::Duration};

async fn root_and_tail(expire: bool) -> anyhow::Result<()> {
    for remote in [false, true] {
        let helper = support::Helper::start(helper::remote_helper_executable()).await?;
        let backend = if remote {
            helper.commands()?
        } else {
            ExecutorCommandBackend::local(helper.root.path())?
        };
        let backend = Arc::new(backend);
        let manager = CommandProcessManager::new(backend.clone());
        let request=CommandStartRequest {
            interactive: false,
            command:"(while test ! -e release-tail; do sleep 0.02; done; printf 'tail-after-root\n') & exit 17".into(),
            cwd:None,allow_workspace_escape:false,timeout:if expire {Duration::from_millis(500)}else {Duration::from_secs(5)},yield_time:Duration::ZERO,max_output_chars:4096,
            session_id:"root-tail".into(),tool_id:"root-tail".into(),call_id:"root-tail".into(),cancellation_token:None,output_observer:None,
        };
        let owner = manager.clone();
        let task = tokio::spawn(async move { owner.run_task("task-root-tail", request).await });
        let observed = tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if let Some(snapshot) = manager.snapshot("task-root-tail", 4096).await
                    && snapshot.exit_code.is_some()
                {
                    break snapshot;
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await?;
        anyhow::ensure!(observed.exit_code == Some(17));
        anyhow::ensure!(matches!(
            observed.state,
            CommandProcessLifecycle::Draining(_)
        ));
        anyhow::ensure!(
            observed.capture.is_none(),
            "root exit does not complete capture"
        );
        if !expire {
            tokio::fs::write(helper.root.path().join("release-tail"), b"release").await?;
        }
        let result = tokio::time::timeout(Duration::from_secs(2), task).await;
        // Always release the fixture's inherited-output child before teardown.
        tokio::fs::write(helper.root.path().join("release-tail"), b"release").await?;
        let result = result???;
        anyhow::ensure!(result.exit_code == Some(17) && result.state.is_final());
        if expire {
            anyhow::ensure!(result.state.is_timed_out());
            let capture = result
                .capture
                .as_ref()
                .expect("completion after reader cancellation");
            anyhow::ensure!(capture.stdout.state == CommandCaptureState::Incomplete);
            anyhow::ensure!(capture.stdout.confirmed_bytes.is_none());
        } else {
            anyhow::ensure!(result.stdout.content == "tail-after-root\n");
            anyhow::ensure!(
                result
                    .capture
                    .as_ref()
                    .is_some_and(|capture| capture.complete())
            );
        }
        if !remote {
            backend.executor().close().await?;
        }
        helper.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn root_exit_is_visible_before_tail_and_capture_completion() -> anyhow::Result<()> {
    root_and_tail(false).await
}
#[tokio::test]
async fn deadline_can_end_drain_without_overwriting_the_observed_root_exit() -> anyhow::Result<()> {
    root_and_tail(true).await
}

#[tokio::test]
async fn remote_helper_default_stdin_is_eof_and_interactive_input_remains_explicit()
-> anyhow::Result<()> {
    let helper = support::Helper::start(helper::remote_helper_executable()).await?;
    tokio::fs::write(helper.root.path().join("needle.txt"), "stdin-mode-probe\n").await?;
    let manager = CommandProcessManager::new(Arc::new(helper.commands()?));
    let request = |command: &str, interactive| CommandStartRequest {
        command: command.into(),
        interactive,
        cwd: None,
        allow_workspace_escape: false,
        timeout: Duration::from_secs(2),
        yield_time: Duration::ZERO,
        max_output_chars: 4096,
        session_id: "stdin-mode".into(),
        tool_id: "stdin-mode".into(),
        call_id: "stdin-mode".into(),
        cancellation_token: None,
        output_observer: None,
    };
    let search = manager
        .run_task("task-remote-search", request("cat; cat needle.txt", false))
        .await?;
    anyhow::ensure!(search.exit_code == Some(0) && search.stderr.content.is_empty());
    anyhow::ensure!(search.stdout.content == "stdin-mode-probe\n");
    let input = manager
        .start(request("printf 'once\\n' >> interactive-once; cat", true))
        .await?;
    let id = input
        .process_id
        .context("interactive cat is still running")?;
    let result = manager
        .write_stdin(pl_tool::command::CommandWriteRequest {
            process_id: id.clone(),
            chars: "输入\n".into(),
            close_stdin: true,
            yield_time: Duration::from_secs(2),
            max_output_chars: 4096,
            cancellation: Default::default(),
        })
        .await?;
    anyhow::ensure!(result.exit_code == Some(0) && result.stdout.content == "输入\n");
    anyhow::ensure!(
        result
            .input_receipt
            .as_ref()
            .is_some_and(|receipt| receipt.accepted_bytes == 7)
    );
    anyhow::ensure!(
        tokio::fs::read_to_string(helper.root.path().join("interactive-once")).await? == "once\n"
    );
    helper.close().await?;
    Ok(())
}
