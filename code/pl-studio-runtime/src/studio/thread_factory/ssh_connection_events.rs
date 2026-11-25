//! Watches an SSH alias state transitions and appends durable boundary events into History.

use std::sync::Arc;

use pl_tool::remote::{SshConnectionState, SshManager};
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use crate::history::{HistoryEvent, HistoryEventKind, HistoryStore, HistoryTimelineRole};

/// Observes `rx` until `cancel` fires, emitting `ConnectionDisconnected` and
/// `ConnectionReconnected` boundary events after an initial `Ready` state has been seen.
pub(super) async fn run_ssh_connection_observer(
    mut rx: watch::Receiver<SshConnectionState>,
    ssh_alias: String,
    history: HistoryStore,
    cancel: CancellationToken,
) {
    let mut had_ready = matches!(&*rx.borrow(), SshConnectionState::Ready { .. });
    let mut disconnected_after_ready = false;
    let observer_id = uuid::Uuid::new_v4().simple().to_string();
    let mut ordinal: u64 = 0;

    loop {
        tokio::select! {
            () = cancel.cancelled() => break,
            changed = rx.changed() => {
                if changed.is_err() {
                    break;
                }
                if cancel.is_cancelled() {
                    break;
                }
                let state = rx.borrow_and_update().clone();
                match state {
                    SshConnectionState::Ready { .. } => {
                        if disconnected_after_ready {
                            ordinal += 1;
                            let data = serde_json::json!({
                                "state": "reconnected",
                                "scope": "ssh",
                                "target": ssh_alias,
                            });
                            append_ssh_event(
                                &history,
                                &observer_id,
                                ordinal,
                                HistoryEventKind::ConnectionReconnected,
                                data,
                            )
                            .await;
                            disconnected_after_ready = false;
                        }
                        had_ready = true;
                    }
                    SshConnectionState::Disconnected => {
                        if had_ready && !disconnected_after_ready {
                            ordinal += 1;
                            let data = serde_json::json!({
                                "state": "disconnected",
                                "scope": "ssh",
                                "target": ssh_alias,
                                "recoverable": true,
                            });
                            append_ssh_event(
                                &history,
                                &observer_id,
                                ordinal,
                                HistoryEventKind::ConnectionDisconnected,
                                data,
                            )
                            .await;
                            disconnected_after_ready = true;
                        }
                    }
                    SshConnectionState::Failed { code, message } => {
                        if had_ready && !disconnected_after_ready {
                            ordinal += 1;
                            let data = serde_json::json!({
                                "state": "disconnected",
                                "scope": "ssh",
                                "target": ssh_alias,
                                "recoverable": true,
                                "code": code,
                                "reason": message,
                            });
                            append_ssh_event(
                                &history,
                                &observer_id,
                                ordinal,
                                HistoryEventKind::ConnectionDisconnected,
                                data,
                            )
                            .await;
                            disconnected_after_ready = true;
                        }
                    }
                    SshConnectionState::Connecting | SshConnectionState::Closing => {}
                }
            }
        }
    }
}

pub(super) async fn spawn_ssh_connection_watcher(
    ssh_manager: Arc<SshManager>,
    ssh_alias: String,
    history: HistoryStore,
    cancel: CancellationToken,
) {
    if cancel.is_cancelled() {
        return;
    }
    let rx = ssh_manager.subscribe_state(&ssh_alias).await;
    tokio::spawn(run_ssh_connection_observer(rx, ssh_alias, history, cancel));
}

async fn append_ssh_event(
    history: &HistoryStore,
    observer_id: &str,
    ordinal: u64,
    kind: HistoryEventKind,
    data: serde_json::Value,
) {
    let now_secs = crate::studio::ids::unix_seconds();
    let recorded_at = crate::history::milliseconds_from_seconds(now_secs).unwrap_or(0);
    let mut event = HistoryEvent::new(
        format!("conn:ssh:{observer_id}:{ordinal}:{}", kind.as_str()),
        kind,
        HistoryTimelineRole::Boundary,
        recorded_at,
    );
    event.occurred_at = Some(recorded_at);
    if let Err(error) = crate::studio::runtime::chat_item::build_connection_event(&mut event, data)
    {
        tracing::warn!(
            target: "conversation_work",
            error = %error,
            "failed building SSH connection history event"
        );
        return;
    }
    if let Err(error) = history.accept_batch(&[event]).await {
        tracing::debug!(
            target: "conversation_work",
            error = %error,
            "skipped SSH connection history event because HistoryStore did not accept it"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::history::{HistoryDemand, HistoryEventsQuery, HistoryLimits, body};

    #[tokio::test]
    async fn ssh_connection_observer_emits_only_post_ready_disconnect_and_reconnect()
    -> anyhow::Result<()> {
        let dir = tempfile::tempdir()?;
        let store = HistoryStore::open(
            dir.path().join("history.sqlite"),
            "ssh-thread",
            HistoryLimits::default(),
        )
        .await?;
        let (tx, rx) = watch::channel(SshConnectionState::Connecting);
        let cancel = CancellationToken::new();
        let handle = tokio::spawn(run_ssh_connection_observer(
            rx,
            "dev-box".into(),
            store.clone(),
            cancel.clone(),
        ));

        // Initial connect -> Ready must not emit a boundary event.
        tx.send_replace(SshConnectionState::Ready {
            helper_version: "1.0.0".into(),
            architecture: "x86_64".into(),
        });
        tokio::task::yield_now().await;
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        let reader = store.reader();
        let initial_page = reader
            .timeline_page(None, None, HistoryDemand::default())
            .await?;
        assert!(initial_page.entries.is_empty());

        // Ready -> Failed -> Disconnected (duplicate) -> Ready emits 1 disconnect + 1 reconnect.
        tx.send_replace(SshConnectionState::Failed {
            code: "sshDisconnected".into(),
            message: "broken pipe".into(),
        });
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        tx.send_replace(SshConnectionState::Disconnected);
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        tx.send_replace(SshConnectionState::Connecting);
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        tx.send_replace(SshConnectionState::Ready {
            helper_version: "1.0.0".into(),
            architecture: "x86_64".into(),
        });
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;

        cancel.cancel();
        let _ = handle.await;

        let page = reader
            .timeline_page(None, None, HistoryDemand::default())
            .await?;
        assert_eq!(page.entries.len(), 2);
        let reconnected = &page.entries[0].event;
        let disconnected = &page.entries[1].event;
        assert!(!page.entries[0].has_folded_after);
        assert!(!page.entries[1].has_folded_after);
        assert_eq!(reconnected.kind, HistoryEventKind::ConnectionReconnected);
        assert_eq!(disconnected.kind, HistoryEventKind::ConnectionDisconnected);
        assert!(reconnected.original.is_none());
        assert!(disconnected.original.is_none());

        let conn_env = body::decode_event_envelope(disconnected)?;
        assert_eq!(conn_env.item_type, "connection");
        assert_eq!(conn_env.data["scope"], "ssh");
        assert_eq!(conn_env.data["target"], "dev-box");
        assert_eq!(conn_env.data["state"], "disconnected");
        assert_eq!(conn_env.data["code"], "sshDisconnected");
        assert_eq!(conn_env.data["reason"], "broken pipe");

        // Must never appear in Originals / TextOriginals.
        let text_originals = reader
            .events_page(
                HistoryEventsQuery::TextOriginals,
                None,
                None,
                HistoryDemand::default(),
            )
            .await?;
        assert!(text_originals.entries.is_empty());

        reader.close().await;
        store.close().await?;
        Ok(())
    }
}
