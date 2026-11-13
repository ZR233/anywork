use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtomKind, ChatContentRole, ChatScope, ContentRange, ReadDemand, ThreadTextChannel, Turn,
};
use pl_studio_runtime::{ConversationEvent, StudioRuntime};

/// Reads sealed text using the existing native content references, including large final answers.
pub(super) async fn final_text(runtime: &StudioRuntime, turn: &Turn) -> Result<String> {
    let demand = ReadDemand {
        max_items: 128,
        max_bytes: pl_protocol::CHAT_BATCH_MAX_BYTES,
    };
    let mut feed = runtime
        .open_conversation_feed(&turn.thread_id, ChatScope::Main, demand)
        .await?;
    let result = async {
        let mut batch = loop {
            if let ConversationEvent::Chat { batch } =
                feed.recv().await?.context("缺少已完成对话")?
            {
                break batch;
            }
        };
        let mut parts = Vec::new();
        loop {
            for entry in &batch.entries {
                let atom = &entry.atom;
                if atom.kind != ChatAtomKind::Text
                    || atom.turn_id.as_deref() != Some(turn.id.as_str())
                    || atom.text_channel != Some(ThreadTextChannel::Final)
                {
                    continue;
                }
                for content in atom
                    .contents
                    .iter()
                    .filter(|content| content.role == ChatContentRole::Body)
                {
                    let mut bytes = Vec::new();
                    loop {
                        let window = feed
                            .reader()
                            .read_content(
                                &content.reference,
                                ContentRange {
                                    offset: bytes.len() as u64,
                                    max_bytes: pl_protocol::CONTENT_WINDOW_MAX_BYTES,
                                },
                            )
                            .await?;
                        ensure!(window.sealed, "最终文本尚未封存");
                        let exhausted =
                            window.offset + window.bytes.len() as u64 >= window.available_through;
                        ensure!(
                            exhausted || !window.bytes.is_empty(),
                            "最终文本读取没有前进"
                        );
                        bytes.extend(window.bytes);
                        if exhausted {
                            break;
                        }
                    }
                    parts.push((entry.completion_seq, String::from_utf8(bytes)?));
                }
            }
            let Some(before) = &batch.before else {
                break;
            };
            *batch = feed.reader().load_older(before, demand).await?;
        }
        parts.sort_by_key(|(sequence, _)| *sequence);
        Ok(parts
            .into_iter()
            .map(|(_, text)| text)
            .collect::<Vec<_>>()
            .join("\n"))
    }
    .await;
    feed.close().await?;
    result
}
