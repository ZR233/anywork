use super::super::content::FinalError;
use super::super::watch::ReplyWatch;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

#[derive(Debug)]
enum SelectedOutput {
    Caption(crate::channel_output::ChannelTarget, String, String),
    File(
        crate::channel_output::ChannelTarget,
        String,
        crate::channel_output::FileDelivery,
        Vec<u8>,
    ),
}

struct SelectedOutputPort(std::sync::Arc<tokio::sync::Mutex<Vec<SelectedOutput>>>);

impl crate::channel_output::ChannelOutputPort for SelectedOutputPort {
    async fn send_caption(
        &self,
        target: &crate::channel_output::ChannelTarget,
        operation: &str,
        caption: &str,
        _: &CancellationToken,
    ) -> crate::channel_output::ChannelDeliveryResult {
        self.0.lock().await.push(SelectedOutput::Caption(
            target.clone(),
            operation.into(),
            caption.into(),
        ));
        crate::channel_output::ChannelDeliveryResult::Confirmed {
            message_ids: vec![crate::channel_output::PlatformMessageId(
                "second-caption".into(),
            )],
        }
    }

    async fn send_file(
        &self,
        target: &crate::channel_output::ChannelTarget,
        operation: &str,
        file: &crate::channel_output::FileDelivery,
        bytes: Vec<u8>,
        _: &CancellationToken,
    ) -> crate::channel_output::ChannelDeliveryResult {
        self.0.lock().await.push(SelectedOutput::File(
            target.clone(),
            operation.into(),
            file.clone(),
            bytes,
        ));
        crate::channel_output::ChannelDeliveryResult::Confirmed {
            message_ids: vec![crate::channel_output::PlatformMessageId(
                "second-file".into(),
            )],
        }
    }
}

#[tokio::test]
async fn automatic_file_dispatch_uses_selected_binding_without_any_feishu_configuration()
-> anyhow::Result<()> {
    use super::super::session::ReplySession;
    use crate::channel_output::{ChannelOutputBinding, ChannelTarget};
    use crate::runtime_test_support as support;
    let env = support::Environment::new(
        vec![
            support::prompt_step(
                "binding-explicit",
                0,
                support::program_reply(
                    "show_files",
                    "selected-display-call",
                    serde_json::json!({
                        "caption":"selected caption",
                        "files":[{"kind":"workspace","path":"selected.md"}],
                    }),
                ),
            ),
            support::prompt_step(
                "binding-explicit",
                1,
                support::text_reply("done", "binding-final"),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let bytes = b"# original selected bytes\n";
        tokio::fs::write(env.repo.join("selected.md"), bytes).await?;
        tokio::fs::write(env.repo.join("unselected.md"), b"do not deliver").await?;
        assert!(env.runtime.read_bots().await?.bots.is_empty());
        let thread = env
            .start(crate::ThreadWorkspaceMode::Local, "binding-explicit")
            .await?
            .thread;
        let turn = support::completed_prompt(&env.runtime, &thread.id, "binding-explicit").await?;
        // File routing consumes a saved reply, after the original History handoff is durable.
        env.runtime
            .synchronize_thread_observation(&thread.id)
            .await?;
        let mut watch = ReplyWatch::open(&env.runtime, &thread.id).await?;
        let observed = async {
            watch
                .select_target(&env.runtime, "input-binding-explicit", Some(&turn.id))
                .await?;
            tokio::time::timeout(Duration::from_secs(10), async {
                while watch.terminal(&turn.id).is_none() {
                    watch.receive().await?;
                }
                Ok::<_, FinalError>(())
            })
            .await??;
            let projection = watch.projection().expect("target projection");
            assert_eq!(projection.file_displays().count(), 1);
            let calls = std::sync::Arc::new(tokio::sync::Mutex::new(Vec::new()));
            let target = ChannelTarget {
                adapter: "second-test-channel".into(),
                account_id: "no-feishu-account".into(),
                conversation_id: "selected-second-conversation".into(),
            };
            let mut run = ReplySession {
                output: ChannelOutputBinding::new(
                    target.clone(),
                    SelectedOutputPort(calls.clone()),
                ),
                bot_id: "no-bot-config".into(),
                chat_id: "not-the-selected-target".into(),
                message_id: "source-message".into(),
                text: String::new(),
                attachments: Vec::new(),
                worker_id: "source-owner".into(),
                thread_id: thread.id.clone(),
                original_input: "input-binding-explicit".into(),
                watch_input: "input-binding-explicit".into(),
                hinted: Default::default(),
                delivered_displays: Default::default(),
                file_delivery_diagnostic: None,
                card: None,
                next_observation: tokio::time::Instant::now(),
            };
            super::deliver_file_displays(
                &env.runtime,
                &mut run,
                &turn.id,
                &projection,
                &CancellationToken::new(),
            )
            .await
            .map_err(|error| anyhow::anyhow!("{error:?}"))?;
            // The actual automatic entry, not a direct driver call, owns replay suppression.
            super::deliver_file_displays(
                &env.runtime,
                &mut run,
                &turn.id,
                &projection,
                &CancellationToken::new(),
            )
            .await
            .map_err(|error| anyhow::anyhow!("{error:?}"))?;
            let calls = calls.lock().await;
            assert_eq!(calls.len(), 2, "{calls:?}");
            let [
                SelectedOutput::Caption(caption_target, caption_operation, caption),
                SelectedOutput::File(file_target, file_operation, file, actual_bytes),
            ] = calls.as_slice()
            else {
                anyhow::bail!("caption and file did not go through selected binding in order");
            };
            assert_eq!(caption_target, &target);
            assert_eq!(file_target, &target);
            assert_eq!(caption, "selected caption");
            assert_ne!(caption_operation, file_operation);
            assert_eq!(file.filename, "selected.md");
            assert_eq!(actual_bytes, bytes);
            file.resource.verify(actual_bytes)?;
            assert!(run.file_delivery_diagnostic.is_none());
            Ok::<_, anyhow::Error>(())
        }
        .await;
        let closed = watch.close().await;
        observed?;
        closed?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
