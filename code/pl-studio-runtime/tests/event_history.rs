#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};

use pl_core::thread::current::RuntimeEpoch;
use pl_studio_runtime::history::*;
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ChatActiveStatus, ChatTerminalOutcome, ContentRange,
    CurrentContentRef, CurrentFrame, CurrentProjection, RuntimeCostAmount,
};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement, TransactionTrait,
};
use std::{path::Path, sync::Arc};
use support::{Environment, current_demand, prompt_step, reached};

fn demand() -> HistoryDemand {
    HistoryDemand::default()
}
fn entity(id: &str, run: RuntimeEpoch, active: bool) -> HistoryEntityHead {
    HistoryEntityHead {
        entity_id: id.into(),
        run_id: Some(run.to_string()),
        attempt_id: Some(uuid::Uuid::new_v4().to_string()),
        source: HistorySource::ForegroundTurn {
            turn_id: "turn-a".into(),
        },
        kind: HistoryEntityKind::Text,
        delivery: HistoryDelivery::Foreground,
        state: if active {
            HistoryEntityState::KnownActive {
                status: ChatActiveStatus::Running,
            }
        } else {
            HistoryEntityState::KnownTerminal {
                outcome: ChatTerminalOutcome::Completed,
            }
        },
        started_at: Some(10),
        finished_at: (!active).then_some(20),
        text_channel: Some(ThreadTextChannel::Final),
        tool: None,
        wait: None,
        content_present: Some(true),
        single_visibility: None,
        observation: HistoryObservation::Original,
        presentation_contract: None,
        detail_event_id: None,
        input_manifest_event_id: None,
        body_manifest_event_id: None,
    }
}
fn single(id: &str, run: RuntimeEpoch, body: &[u8]) -> HistoryEvent {
    let mut event = HistoryEvent::new(id, HistoryEventKind::EntityEnded, 20);
    let mut head = entity(id, run, false);
    head.body_manifest_event_id = Some(id.into());
    head.detail_event_id = Some(id.into());
    event.header.run_id = head.run_id.clone();
    event.header.attempt_id = head.attempt_id.clone();
    event.header.entity_id = Some(id.into());
    event.header.turn_id = Some("turn-a".into());
    event.header.source = Some(head.source.clone());
    event.header.row_key = Some(format!("single:{id}"));
    event.header.original = Some(HistoryOriginalInfo {
        query_class: "conversation".into(),
        parent_id: None,
        original_kind: head.kind,
        tool_name: None,
    });
    event.head = Some(HistoryRowHead::Single(head));
    event.is_anchor = true;
    let payload = HistoryBody::new(
        "canonical",
        HistoryBodyRole::CanonicalPayload,
        b"opaque original bytes".to_vec(),
    );
    event.payload_body_id = Some(payload.body_id.clone());
    event.bodies.push(payload);
    event.bodies.push(HistoryBody::new(
        "body",
        HistoryBodyRole::Body,
        body.to_vec(),
    ));
    event
}
async fn raw(path: &Path) -> Result<DatabaseConnection> {
    let path = path.to_path_buf();
    let mut options = sea_orm::ConnectOptions::new("sqlite:");
    options.map_sqlx_sqlite_opts(move |options| {
        options
            .filename(&path)
            .foreign_keys(true)
            .create_if_missing(true)
    });
    Ok(Database::connect(options).await?)
}

fn final_text_reference(projection: &CurrentProjection) -> Option<CurrentContentRef> {
    projection
        .atoms
        .iter()
        .filter(|atom| {
            atom.kind == pl_studio_runtime::ChatAtomKind::Text
                && atom.text_channel == Some(pl_studio_runtime::ThreadTextChannel::Final)
        })
        .flat_map(|atom| atom.contents.iter())
        .find(|content| content.role == pl_studio_runtime::ChatContentRole::Body)
        .map(|content| content.reference.clone())
}

async fn read_current_body(
    reader: &pl_studio_runtime::CurrentReader,
    reference: &CurrentContentRef,
) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    loop {
        let window = reader
            .read_body(
                reference.clone(),
                ContentRange {
                    offset: bytes.len() as u64,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        ensure!(window.offset == bytes.len() as u64);
        let finished = window.offset + window.bytes.len() as u64 == window.available_through;
        ensure!(
            finished || !window.bytes.is_empty(),
            "Current body did not advance"
        );
        bytes.extend(window.bytes);
        if finished {
            break;
        }
    }
    Ok(bytes)
}

async fn read_history_body(
    reader: &HistoryReader,
    reference: &HistoryEventBodyRef,
) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    while bytes.len() as u64 != reference.byte_length {
        let window = reader
            .read_body(
                reference.clone(),
                bytes.len() as u64,
                (reference.byte_length - bytes.len() as u64).min(64 * 1024) as u32,
            )
            .await?;
        ensure!(!window.bytes.is_empty(), "history body did not advance");
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}

#[tokio::test]
async fn real_prompt_and_saved_stream_are_independent_from_the_later_immutable_history()
-> Result<()> {
    use pl_provider_fixture::ReplyStage;

    let stage = ReplyStage::new();
    let head = "流".repeat(33_000);
    let tail = "🎉完整终稿";
    let expected = format!("{head}{tail}").into_bytes();
    let mut frames = pl_provider_fixture::responses_text_chunks(
        &[head.as_str(), tail],
        "current-history",
        support::MODEL,
    );
    let after: Vec<_> = frames.split_off(3);
    let reply = ReplyStage::staged(vec![frames, after], &[&stage]);
    let mut env = Environment::new(vec![prompt_step("current-history", 0, reply)], vec![]).await?;
    let result = async {
        let thread = env
            .start(
                pl_studio_runtime::ThreadWorkspaceMode::Worktree,
                "current-history",
            )
            .await?;
        let id = thread.thread.id;
        let demand = current_demand();
        let history_demand = HistoryDemand::default();
        let reader = env
            .runtime
            .open_current_reader(&id, CURRENT_PROTOCOL_VERSION, demand)
            .await?;
        let mut metadata = reader.watch(None, demand).await?;
        let Some(CurrentFrame::Reset { view }) = metadata.next().await? else {
            anyhow::bail!("Current watch did not begin with Reset");
        };
        ensure!(
            view.state.schema_version == pl_studio_runtime::THREAD_SCHEMA_VERSION,
            "Current did not expose the current Thread schema"
        );
        ensure!(
            view.state
                .runtime
                .as_ref()
                .is_none_or(|runtime| runtime.deferred.is_empty()),
            "small runtime snapshot unexpectedly deferred a State field"
        );
        ensure!(
            view.state
                .activity
                .as_ref()
                .is_none_or(|activity| activity.deferred.is_empty()),
            "small activity snapshot unexpectedly deferred a State field"
        );
        reached(&stage).await?;
        let mut reference = None;
        while reference.is_none() {
            match metadata.next().await? {
                Some(CurrentFrame::Reset { view }) => {
                    reference = final_text_reference(&view.projection);
                }
                Some(CurrentFrame::Projection { projection, .. }) => {
                    reference = final_text_reference(&projection);
                }
                Some(CurrentFrame::Notification { .. }) => {}
                None => anyhow::bail!("Current watch ended before the response body appeared"),
            }
        }
        let reference = reference.unwrap();
        for stale_reference in [
            {
                let mut stale = reference.clone();
                stale.owner_id.push_str(":wrong-owner");
                stale
            },
            {
                let mut stale = reference.clone();
                stale.generation.push_str(":wrong-generation");
                stale
            },
        ] {
            let stale = reader
                .read_body(
                    stale_reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 1,
                    },
                )
                .await
                .unwrap_err();
            ensure!(
                stale
                    .downcast_ref::<pl_studio_runtime::StudioError>()
                    .and_then(|error| error.reason())
                    == Some("staleCurrentReference"),
                "wrong owner or body generation was accepted"
            );
        }
        let live_view = reader.snapshot(demand).await?;
        ensure!(
            live_view
                .state
                .runtime
                .as_ref()
                .is_some_and(|runtime| runtime.deferred.is_empty()),
            "live runtime snapshot unexpectedly deferred a State field"
        );
        ensure!(
            live_view
                .state
                .activity
                .as_ref()
                .is_none_or(|activity| activity.deferred.is_empty()),
            "live activity snapshot unexpectedly deferred a State field"
        );
        let r1 = live_view.revision.owner_id;
        let mut body = reader
            .watch_body(
                reference.clone(),
                ContentRange {
                    offset: 65_530,
                    max_bytes: 40,
                },
            )
            .await?;
        let live_window = body.next().await?.context("live body watch")?;
        ensure!(live_window.offset == 65_530);
        ensure!(live_window.bytes == expected[65_530..65_570]);
        ensure!(
            !live_window.sealed,
            "the held provider attempt was still active"
        );

        let saved_stream_bytes =
            tokio::time::timeout(support::integration_test_deadline()?, async {
                loop {
                    if let Ok(saved) = support::saved(&env.home, &id).await
                        && let Some(call) = saved.current.model_call.as_ref()
                        && let pl_core::thread::current::SavedModelPhase::Streaming { stream } =
                            &call.phase
                    {
                        let stream = pl_model::completion::ModelStreamCurrent::decode(stream)?;
                        if stream.content_parts.iter().any(|part| part.text == head) {
                            return Ok::<_, anyhow::Error>(std::fs::read(
                                saved.root.join("current.json"),
                            )?);
                        }
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
                }
            })
            .await
            .context("periodic Current did not save the held provider prefix")??;
        stage.release();
        let terminal = loop {
            let Some(frame) = metadata.next().await? else {
                anyhow::bail!("Current watch ended before the provider Turn completed");
            };
            if let CurrentFrame::Notification { notification, .. } = frame
                && let pl_studio_runtime::ThreadNotification::TurnCompleted { turn } =
                    notification.notification
            {
                break turn;
            }
        };
        ensure!(terminal.input_id.as_deref() == Some("input-current-history"));
        loop {
            match body.next().await {
                Ok(Some(window)) => {
                    ensure!(window.bytes == expected[65_530..65_570]);
                    if window.sealed {
                        break;
                    }
                }
                Err(error)
                    if error
                        .downcast_ref::<pl_studio_runtime::StudioError>()
                        .is_some_and(|error| error.reason() == Some("staleCurrentReference")) =>
                {
                    break;
                }
                Err(error) => return Err(error),
                Ok(None) => {
                    anyhow::bail!("body watch ended without sealing or retiring the live reference")
                }
            }
        }
        body.close().await?;
        metadata.close().await?;
        reader.close().await?;

        env.runtime.synchronize_thread_observation(&id).await?;
        let saved = support::saved(&env.home, &id).await?;
        ensure!(saved.current.schema_version == pl_core::thread::current::CURRENT_SCHEMA_VERSION);
        ensure!(saved.current.saved_runtime_epoch.to_string() == r1);

        let history = env
            .runtime
            .open_history_reader(&id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let originals = history
            .events_page(
                HistoryEventsQuery::TextOriginals,
                None,
                None,
                history_demand,
            )
            .await?;
        let mut canonical = None;
        let mut durable = None;
        for event in originals.entries {
            let Some(payload_ref) = event.payload_ref.clone() else {
                continue;
            };
            let payload = read_history_body(&history, &payload_ref).await?;
            let envelope: serde_json::Value = serde_json::from_slice(&payload)?;
            ensure!(envelope["contract"] == "anywork.chat/1");
            let bodies = history
                .list_bodies(event.header.event_id.clone(), None, history_demand)
                .await?;
            let body = bodies
                .entries
                .into_iter()
                .find(|entry| entry.role == HistoryBodyRole::Body)
                .context("text original has no body")?;
            let bytes = read_history_body(&history, &body.reference).await?;
            if bytes == expected {
                ensure!(canonical.is_none(), "final body was stored more than once");
                canonical = Some((event.header.event_id.clone(), envelope));
                durable = Some(body.reference);
            }
        }
        let (event_id, envelope) = canonical.context("final text original")?;
        let durable = durable.context("final text body reference")?;
        ensure!(envelope["turnId"].is_string());
        history.close().await;
        let provider_requests = env.root_provider.recorded().len();
        ensure!(provider_requests == 1, "fixture prompt made extra requests");

        env.restart().await?;
        std::fs::write(saved.root.join("current.json"), b"broken current JSON")?;
        let broken_current_history = env
            .runtime
            .open_history_reader(&id, HISTORY_PROTOCOL_VERSION)
            .await?;
        let detail = broken_current_history
            .read_event(event_id.clone(), history_demand)
            .await?;
        ensure!(read_history_body(&broken_current_history, &durable).await? == expected);
        ensure!(detail.header.event_id == event_id);
        broken_current_history.close().await;
        ensure!(env.root_provider.recorded().len() == provider_requests);

        std::fs::write(saved.root.join("current.json"), &saved_stream_bytes)?;
        env.restart().await?;
        std::fs::write(saved.path, b"broken history; Current must not open it")?;
        let current = env
            .runtime
            .open_current_reader(&id, CURRENT_PROTOCOL_VERSION, demand)
            .await?;
        let view = current.snapshot(demand).await?;
        ensure!(
            view.revision.owner_id == r1 && !view.projection.execution_present,
            "passive cold reading must retain saved provenance without activating a new Core owner"
        );
        let restored = final_text_reference(&view.projection).context("saved streaming body")?;
        ensure!(
            read_current_body(&current, &restored).await? == head.as_bytes(),
            "cold Current borrowed the later final body from History"
        );
        let stale = current
            .read_body(
                reference,
                ContentRange {
                    offset: 0,
                    max_bytes: 1,
                },
            )
            .await
            .unwrap_err();
        ensure!(
            stale
                .downcast_ref::<pl_studio_runtime::StudioError>()
                .and_then(|error| error.reason())
                == Some("staleCurrentReference")
        );
        current.close().await?;
        ensure!(env.root_provider.recorded().len() == provider_requests);
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}

#[tokio::test]
async fn accepted_and_committed_pages_share_fixed_cuts_and_immutable_body_ranges() -> Result<()> {
    let temp = tempfile::tempdir()?;
    std::fs::write(temp.path().join("current.json"), b"not current JSON")?;
    let store = HistoryStore::open(
        temp.path().join("history.sqlite"),
        "history",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let bytes: Vec<_> = (0..150_002).map(|index| (index % 251) as u8).collect();
    let first = single("first", run, &bytes);
    store.accept_batch(std::slice::from_ref(&first)).await?;
    let cut = reader.capture().await?;
    let before = reader
        .timeline_page(Some(cut.clone()), None, demand())
        .await?;
    assert_eq!(before.entries.len(), 1);
    let body_page = reader.list_bodies("first".into(), None, demand()).await?;
    let body = body_page
        .entries
        .iter()
        .find(|body| body.body_key == "body")
        .unwrap()
        .reference
        .clone();
    assert_eq!(
        reader.read_body(body.clone(), 65_530, 40).await?.bytes,
        bytes[65_530..65_570]
    );
    assert!(matches!(
        reader.read_body(body.clone(), 0, 65_537).await,
        Err(HistoryError::InvalidDemand(_))
    ));
    reader.verify_body(body.clone()).await?;
    let mut invalid = body.clone();
    invalid.owner_event_id = "someone-else".into();
    assert!(matches!(
        reader.read_body(invalid, 0, 1).await,
        Err(HistoryError::InvalidCursor)
    ));
    let mut changed = first.clone();
    changed.header.seq = 0;
    changed.header.event_id = "first-status".into();
    changed.header.original = None;
    changed.is_anchor = false;
    changed.bodies.clear();
    changed.payload_body_id = None;
    if let Some(HistoryRowHead::Single(head)) = &mut changed.head {
        head.finished_at = Some(50);
    }
    store
        .accept_batch(&[changed, single("second", run, b"next")])
        .await?;
    assert_eq!(
        reader
            .timeline_page(Some(cut.clone()), None, demand())
            .await?,
        before
    );
    store.flush().await?;
    assert_eq!(store.status().pending_events, 0);
    assert_eq!(
        reader.timeline_page(Some(cut), None, demand()).await?,
        before
    );
    assert_eq!(
        reader.read_body(body, 149_990, 64).await?.bytes,
        bytes[149_990..]
    );
    let original = reader
        .events_page(
            HistoryEventsQuery::Originals {
                scope: ChatScope::conversation(None),
            },
            None,
            None,
            demand(),
        )
        .await?;
    assert_eq!(original.entries.len(), 2);
    let detail = reader.read_event("first".into(), demand()).await?;
    assert_eq!(
        reader
            .read_body(detail.payload_ref.unwrap(), 0, 64)
            .await?
            .bytes,
        b"opaque original bytes"
    );
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn event_retries_are_exact_and_sql_enforces_immutable_facts() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "immutability", HistoryLimits::default()).await?;
    let event = single("idempotent", RuntimeEpoch::new(), b"retained");
    let first = store.accept_batch(std::slice::from_ref(&event)).await?;
    assert_eq!(
        store.accept_batch(std::slice::from_ref(&event)).await?,
        first
    );
    let mut conflict = event.clone();
    conflict.bodies[1].bytes = Arc::from(&b"different"[..]);
    assert!(matches!(
        store.accept_batch(&[conflict.clone()]).await,
        Err(HistoryError::Conflict(_))
    ));
    store.flush().await?;
    assert_eq!(store.accept_batch(&[event]).await?, first);
    assert!(matches!(
        store.accept_batch(&[conflict]).await,
        Err(HistoryError::Conflict(_))
    ));
    let db = raw(&path).await?;
    for sql in [
        "UPDATE history_events SET recorded_at=0",
        "DELETE FROM history_events",
        "UPDATE history_bodies SET byte_length=0",
        "DELETE FROM history_bodies",
        "UPDATE history_body_chunks SET data=X'00'",
        "DELETE FROM history_body_chunks",
    ] {
        assert!(db.execute_unprepared(sql).await.is_err(), "{sql}");
    }
    db.close().await?;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn failed_transaction_keeps_accepted_facts_and_corrupt_chunks_are_not_eof() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("history.sqlite");
    let store = HistoryStore::open(&path, "failure", HistoryLimits::default()).await?;
    let reader = store.reader();
    let db = raw(&path).await?;
    db.execute_unprepared("CREATE TRIGGER reject_test_write BEFORE INSERT ON history_events BEGIN SELECT RAISE(ABORT,'injected database failure'); END;").await?;
    let event = single("retained", RuntimeEpoch::new(), b"original");
    store.accept_batch(&[event]).await?;
    let cut = reader.capture().await?;
    assert!(store.flush().await.is_err());
    assert_eq!(store.status().pending_events, 1);
    assert!(store.status().write_error.is_some());
    assert_eq!(
        reader
            .timeline_page(Some(cut.clone()), None, demand())
            .await?
            .entries
            .len(),
        1
    );
    db.execute_unprepared("DROP TRIGGER reject_test_write")
        .await?;
    store.flush().await?;
    assert_eq!(store.status().pending_events, 0);
    assert!(store.status().write_error.is_none());
    assert_eq!(
        reader
            .timeline_page(Some(cut), None, demand())
            .await?
            .entries
            .len(),
        1
    );
    let body = reader
        .list_bodies("retained".into(), None, demand())
        .await?
        .entries
        .into_iter()
        .find(|entry| entry.body_key == "body")
        .unwrap()
        .reference;
    db.execute_unprepared("DROP TRIGGER history_body_chunks_no_update")
        .await?;
    db.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "UPDATE history_body_chunks SET data=? WHERE body_id=?",
        vec![b"modified".to_vec().into(), body.body_id.clone().into()],
    ))
    .await?;
    assert!(matches!(
        reader.read_body(body.clone(), 0, 64).await,
        Err(HistoryError::Integrity(_))
    ));
    assert!(matches!(
        reader.verify_body(body).await,
        Err(HistoryError::Integrity(_))
    ));
    db.close().await?;
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn large_wait_targets_are_preserved_in_a_deferred_body_and_group_close_is_final() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "wait",
        HistoryLimits::default(),
    )
    .await?;
    let run = RuntimeEpoch::new();
    let reader = store.reader();
    let mut classifier = HistoryClassifier::new(run);
    let targets = (0..2000)
        .map(|index| {
            pl_studio_runtime::ThreadWaitTarget::new(
                format!("task-{index}"),
                Some("terminal".into()),
                None,
                None,
            )
        })
        .collect();
    let presentation = pl_studio_runtime::ThreadWaitPresentation::new(
        pl_studio_runtime::ThreadWaitIntent::Events {
            targets,
            timeout_ms: 3000,
        },
        pl_studio_runtime::ThreadWaitState::Waiting,
        None,
    );
    let expected = serde_json::to_vec(&presentation)?;
    let mut head = entity("wait", run, true);
    head.kind = HistoryEntityKind::ToolCall;
    head.tool = Some(HistoryToolIdentity {
        call_id: "wait-call".into(),
        name: "wait_events".into(),
    });
    head.wait = Some(HistoryWaitHead::Inline { presentation });
    let change = HistoryEntityChange {
        event: HistoryEvent::new("wait-start", HistoryEventKind::EntityStarted, 1),
        entity: head.clone(),
        placement: HistoryPlacement::Work,
        boundary_observations: Vec::new(),
        public_summary: None,
    };
    classifier.record(&store, &change).await?;
    let group = classifier.open_group().unwrap().to_owned();
    let page = reader
        .group_page(group.clone(), None, None, demand())
        .await?;
    let HistoryRowHead::Member(member) = &page.members[0].head else {
        panic!("wait member")
    };
    let Some(HistoryWaitHead::Deferred {
        intent: HistoryWaitIntentHead::Events {
            target_count: 2000, ..
        },
        presentation,
        ..
    }) = &member.wait
    else {
        panic!("deferred wait")
    };
    let mut actual = Vec::new();
    while actual.len() < expected.len() {
        actual.extend(
            reader
                .read_body(presentation.clone(), actual.len() as u64, 65_536)
                .await?
                .bytes,
        );
    }
    assert_eq!(actual, expected);
    let observed = head;
    let visible = HistoryEntityChange {
        event: HistoryEvent::new("separator", HistoryEventKind::ContentBecameVisible, 2),
        entity: entity("separator", run, true),
        placement: HistoryPlacement::Single,
        boundary_observations: vec![HistoryBoundaryObservation {
            event: HistoryEvent::new("wait-boundary", HistoryEventKind::BoundaryObserved, 2),
            entity: observed,
        }],
        public_summary: None,
    };
    classifier.record(&store, &visible).await?;
    let mut late = HistoryEvent::new("illegal-late", HistoryEventKind::EntityStateChanged, 3);
    let mut member = member.clone();
    member.detail_event_id = None;
    late.header.run_id = member.run_id.clone();
    late.header.attempt_id = member.attempt_id.clone();
    late.header.entity_id = Some(member.entity_id.clone());
    late.header.source = Some(member.source.clone());
    late.header.call_id = member.tool.as_ref().map(|tool| tool.call_id.clone());
    late.header.group_id = Some(group.clone());
    late.header.row_key = Some(format!("member:{group}:wait"));
    late.head = Some(HistoryRowHead::Member(member));
    assert!(matches!(
        store.accept_batch(&[late]).await,
        Err(HistoryError::InvalidEvent(_))
    ));
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn budgets_and_authenticated_cursors_preserve_the_unreturned_candidate() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "pages",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    store
        .accept_batch(
            &(0..5)
                .map(|index| single(&format!("row-{index}"), run, b"body"))
                .collect::<Vec<_>>(),
        )
        .await?;
    let cut = reader.capture().await?;
    let complete = reader
        .timeline_page(Some(cut.clone()), None, demand())
        .await?;
    let exact = reader
        .timeline_page(
            Some(cut.clone()),
            None,
            HistoryDemand {
                max_rows: 64,
                max_bytes: serde_json::to_vec(&complete)?.len() as u32,
            },
        )
        .await?;
    assert_eq!(
        exact, complete,
        "a proven final page must not reserve a phantom cursor"
    );
    let one = reader
        .timeline_page(
            Some(cut.clone()),
            None,
            HistoryDemand {
                max_rows: 1,
                max_bytes: 65_536,
            },
        )
        .await?;
    let budget = serde_json::to_vec(&one)?.len() as u32 + 8;
    let mut next = None;
    let mut ids = Vec::new();
    loop {
        let page = reader
            .timeline_page(
                Some(cut.clone()),
                next.take(),
                HistoryDemand {
                    max_rows: 5,
                    max_bytes: budget,
                },
            )
            .await?;
        assert!(serde_json::to_vec(&page)?.len() <= budget as usize);
        ids.extend(page.entries.into_iter().map(|entry| entry.row_key));
        next = page.next;
        if next.is_none() {
            break;
        }
    }
    assert_eq!(
        ids,
        (0..5)
            .rev()
            .map(|index| format!("single:row-{index}"))
            .collect::<Vec<_>>()
    );
    assert!(matches!(
        reader
            .timeline_page(
                Some(cut.clone()),
                None,
                HistoryDemand {
                    max_rows: 1,
                    max_bytes: 1
                }
            )
            .await,
        Err(HistoryError::InvalidDemand(_))
    ));
    let token = one.next.unwrap();
    assert!(matches!(
        reader
            .group_page("different".into(), None, Some(token.clone()), demand())
            .await,
        Err(HistoryError::InvalidCursor)
    ));
    let mut altered = token.into_bytes();
    altered[10] ^= 1;
    assert!(matches!(
        reader
            .timeline_page(None, Some(String::from_utf8(altered).unwrap()), demand())
            .await,
        Err(HistoryError::InvalidCursor)
    ));
    let other_reader = store.reader();
    assert!(matches!(
        other_reader.timeline_page(Some(cut), None, demand()).await,
        Err(HistoryError::InvalidCursor)
    ));
    other_reader.close().await;
    let long_call_id = "c".repeat(14_000);
    let mut long_events = Vec::new();
    for id in ["long-first", "long-second"] {
        let mut event = HistoryEvent::new(id, HistoryEventKind::EntityStarted, 1);
        event.header.call_id = Some(long_call_id.clone());
        long_events.push(event);
    }
    store.accept_batch(&long_events).await?;
    let query = HistoryEventsQuery::Call {
        call_id: long_call_id,
    };
    let request = HistoryDemand {
        max_rows: 1,
        max_bytes: 1_048_576,
    };
    let first = reader
        .events_page(query.clone(), None, None, request)
        .await?;
    let next = first
        .next
        .expect("full long-identity page must have a cursor");
    assert!(next.len() > 16 * 1024);
    let second = reader.events_page(query, None, Some(next), request).await?;
    assert_eq!(second.entries[0].header.event_id, "long-first");
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn classifier_keeps_boundary_observation_when_tool_ends_in_a_later_work_group() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "groups",
        HistoryLimits::default(),
    )
    .await?;
    let run = RuntimeEpoch::new();
    let reader = store.reader();
    let mut classifier = HistoryClassifier::new(run);
    let mut tool = entity("tool", run, true);
    tool.kind = HistoryEntityKind::ToolCall;
    tool.text_channel = None;
    tool.tool = Some(HistoryToolIdentity {
        call_id: "attempt-scoped-call".into(),
        name: "terminal".into(),
    });
    let start = HistoryEvent::new("tool-start", HistoryEventKind::EntityStarted, 10);
    let atom = pl_studio_runtime::ChatAtom {
        id: tool.entity_id.clone(),
        completion_item_id: None,
        completion_seq: None,
        source: tool.source.clone(),
        source_state: None,
        source_order: None,
        kind: tool.kind,
        delivery: tool.delivery,
        lifecycle: pl_studio_runtime::ChatAtomLifecycle::Active {
            status: ChatActiveStatus::Running,
            started: None,
        },
        turn_id: Some("turn-a".into()),
        attempt_id: tool.attempt_id.clone(),
        tool: tool.tool.clone(),
        wait: None,
        text_channel: None,
        started_at: tool.started_at,
        finished_at: None,
        content_present: tool.content_present,
        contents: Vec::new(),
        payload: None,
    };
    let mut change = HistoryEntityChange::from_atom(start, &atom, run)?;
    assert_eq!(change.entity.started_at, Some(10_000));
    tool = change.entity.clone();
    let mut invalid_atom = atom.clone();
    invalid_atom.finished_at = Some(i64::MAX);
    assert!(matches!(
        HistoryEntityHead::from_atom(&invalid_atom, Some(run.to_string())),
        Err(HistoryError::InvalidEvent(_))
    ));
    change.public_summary = Some("正在执行".into());
    classifier.record(&store, &change).await?;
    assert_eq!(
        reader
            .events_page(
                HistoryEventsQuery::Turn {
                    turn_id: "turn-a".into()
                },
                None,
                None,
                demand()
            )
            .await?
            .entries[0]
            .header
            .event_id,
        "tool-start"
    );
    let old_group = classifier.open_group().unwrap().to_owned();
    let mut empty = entity("text", run, true);
    empty.content_present = Some(false);
    let before_empty = reader.capture().await?;
    let mut unexpected = HistoryEvent::new(
        "unexpected-boundary",
        HistoryEventKind::BoundaryObserved,
        11,
    );
    unexpected.bodies.push(HistoryBody::new(
        "observed",
        HistoryBodyRole::ToolOutput,
        b"must not silently disappear".to_vec(),
    ));
    let mut empty_change = HistoryEntityChange {
        event: HistoryEvent::new("text-start", HistoryEventKind::EntityStarted, 11),
        entity: empty.clone(),
        placement: HistoryPlacement::Single,
        boundary_observations: vec![HistoryBoundaryObservation {
            event: unexpected,
            entity: tool.clone(),
        }],
        public_summary: None,
    };
    assert!(matches!(
        classifier.record(&store, &empty_change).await,
        Err(HistoryError::InvalidEvent(_))
    ));
    assert_eq!(reader.capture().await?, before_empty);
    assert_eq!(classifier.open_group(), Some(old_group.as_str()));
    empty_change.boundary_observations.clear();
    classifier.record(&store, &empty_change).await?;
    assert_eq!(classifier.open_group(), Some(old_group.as_str()));
    let mut boundary = HistoryEvent::new("boundary", HistoryEventKind::BoundaryObserved, 12);
    boundary.bodies.push(HistoryBody::new(
        "partial",
        HistoryBodyRole::ToolOutput,
        b"old observed bytes".to_vec(),
    ));
    let mut observed_tool = tool.clone();
    observed_tool.body_manifest_event_id = Some("boundary".into());
    empty.content_present = Some(true);
    let mut visible = HistoryEvent::new("visible", HistoryEventKind::ContentBecameVisible, 12);
    visible.header.occurred_at = Some(12);
    classifier
        .record(
            &store,
            &HistoryEntityChange {
                event: visible,
                entity: empty.clone(),
                placement: HistoryPlacement::Single,
                boundary_observations: vec![HistoryBoundaryObservation {
                    event: boundary,
                    entity: observed_tool,
                }],
                public_summary: Some("边界观察".into()),
            },
        )
        .await?;
    assert!(classifier.open_group().is_none());
    let old_cut = reader.capture().await?;
    tool.state = HistoryEntityState::KnownTerminal {
        outcome: ChatTerminalOutcome::Completed,
    };
    tool.finished_at = Some(15);
    tool.body_manifest_event_id = Some("tool-end".into());
    let mut end = HistoryEvent::new("tool-end", HistoryEventKind::EntityEnded, 15);
    end.bodies.push(HistoryBody::new(
        "final",
        HistoryBodyRole::ToolOutput,
        b"completely different final".to_vec(),
    ));
    classifier
        .record(
            &store,
            &HistoryEntityChange {
                event: end,
                entity: tool,
                placement: HistoryPlacement::Work,
                boundary_observations: Vec::new(),
                public_summary: None,
            },
        )
        .await?;
    let new_group = classifier.open_group().unwrap().to_owned();
    assert_ne!(old_group, new_group);
    // Completing the already-visible text does not close a newer Work group.
    empty.state = HistoryEntityState::KnownTerminal {
        outcome: ChatTerminalOutcome::Completed,
    };
    empty.finished_at = Some(16);
    classifier
        .record(
            &store,
            &HistoryEntityChange {
                event: HistoryEvent::new("text-end", HistoryEventKind::EntityEnded, 16),
                entity: empty,
                placement: HistoryPlacement::Single,
                boundary_observations: Vec::new(),
                public_summary: None,
            },
        )
        .await?;
    assert_eq!(classifier.open_group(), Some(new_group.as_str()));
    store.flush().await?;
    let old = reader
        .group_page(old_group.clone(), None, None, demand())
        .await?;
    let Some(HistoryRowHead::Member(old_head)) = old.members.first().map(|entry| &entry.head)
    else {
        panic!("old member")
    };
    assert!(matches!(
        old_head.state,
        HistoryEntityState::KnownActive { .. }
    ));
    assert!(matches!(
        old_head.observation,
        HistoryObservation::Boundary {
            captured_at: Some(12)
        }
    ));
    let body = reader
        .list_bodies(
            old_head.body_manifest_event_id.clone().unwrap(),
            None,
            demand(),
        )
        .await?
        .entries[0]
        .reference
        .clone();
    assert_eq!(
        reader.read_body(body, 0, 64).await?.bytes,
        b"old observed bytes"
    );
    assert_eq!(
        reader
            .group_page(new_group, None, None, demand())
            .await?
            .members
            .len(),
        1
    );
    assert_eq!(
        reader
            .timeline_page(Some(old_cut), None, demand())
            .await?
            .entries
            .len(),
        2
    );
    reader.close().await;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn source_composite_identity_and_close_do_not_share_query_consumption() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("h.sqlite");
    let store = HistoryStore::open(&path, "queries", HistoryLimits::default()).await?;
    let reader = store.reader();
    let after = reader.capture().await?;
    let waiting = reader.clone();
    let task = tokio::spawn(async move { waiting.wait_changed(after).await });
    let run = RuntimeEpoch::new();
    let mut events = Vec::new();
    for source in ["a", "b"] {
        let mut event = single(source, run, b"data");
        let source = HistorySource::InboxMessage {
            source_id: source.into(),
            message_id: "same-message".into(),
        };
        event.header.source = Some(source.clone());
        if let Some(HistoryRowHead::Single(head)) = &mut event.head {
            head.source = source;
        }
        events.push(event);
    }
    store.accept_batch(&events).await?;
    let cut = task.await.unwrap()?;
    let page = reader
        .events_page(
            HistoryEventsQuery::Source {
                source: HistorySource::InboxMessage {
                    source_id: "a".into(),
                    message_id: "same-message".into(),
                },
            },
            Some(cut.clone()),
            None,
            demand(),
        )
        .await?;
    assert_eq!(page.entries.len(), 1);
    assert_eq!(page.entries[0].header.event_id, "a");
    let old_cut = cut.clone();
    let waiter = reader.clone();
    let pending = tokio::spawn(async move { waiter.wait_changed(cut).await });
    reader.close().await;
    assert!(matches!(pending.await.unwrap(), Err(HistoryError::Closed)));
    assert_eq!(
        store
            .reader()
            .timeline_page(None, None, demand())
            .await?
            .entries
            .len(),
        2
    );
    store.close().await?;
    // A newly opened owner and reader reject old signed cuts.
    let reopened = HistoryStore::open(&path, "queries", HistoryLimits::default()).await?;
    let new_reader = reopened.reader();
    assert_eq!(
        new_reader
            .timeline_page(None, None, demand())
            .await?
            .entries
            .len(),
        2
    );
    assert!(matches!(
        new_reader
            .timeline_page(Some(old_cut), None, demand())
            .await,
        Err(HistoryError::InvalidCursor)
    ));
    new_reader.close().await;
    reopened.close().await?;
    Ok(())
}

fn usage(id: &str, run: RuntimeEpoch, priced: bool) -> HistoryUsageFact {
    let accounting = pl_studio_runtime::InferenceAccounting {
        usage: pl_studio_runtime::UsageReport {
            input_tokens: Some(100),
            output_tokens: Some(20),
            cache_read_tokens: Some(40),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(3),
            total_tokens: Some(120),
        },
        pricing: if priced {
            pl_studio_runtime::PricingOutcome::Estimated {
                cost: RuntimeCostAmount {
                    currency: "CNY".into(),
                    amount: 0.25,
                },
                cache_savings: Some(RuntimeCostAmount {
                    currency: "CNY".into(),
                    amount: 0.1,
                }),
            }
        } else {
            pl_studio_runtime::PricingOutcome::default()
        },
        ..Default::default()
    };
    HistoryUsageFact { event_id: id.into(), runtime_epoch: run, turn_id: Some("turn-a".into()), outcome: pl_core::usage::UsageOutcome::Succeeded,
        record: serde_json::from_value(serde_json::json!({"inferenceId":id,"purpose":null,"accounting":accounting,"recordedAt":20})).unwrap() }
}
#[tokio::test]
async fn usage_is_folded_once_and_unknown_cost_or_cache_baselines_stay_unknown() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = HistoryStore::open(
        temp.path().join("h.sqlite"),
        "usage",
        HistoryLimits::default(),
    )
    .await?;
    let reader = store.reader();
    let run = RuntimeEpoch::new();
    let first = usage("usage-a", run, false);
    let first_seq = store.record_usage(&first).await?;
    assert_eq!(store.record_usage(&first).await?, first_seq);
    let old = reader.capture().await?;
    store.record_usage(&usage("usage-b", run, true)).await?;
    let totals = reader.accounting(None).await?.unwrap();
    assert_eq!(totals.inference_count, 2);
    assert_eq!(totals.total_tokens, 240);
    assert_eq!(totals.updated_at, 20_000);
    assert!(totals.has_unpriced_usage);
    assert_eq!(
        reader.accounting(Some(old)).await?.unwrap().inference_count,
        1
    );
    let costs = reader.costs_page(None, None, demand()).await?;
    assert_eq!(costs.entries.len(), 1);
    let HistoryRowHead::Cost(cost) = &costs.entries[0].head else {
        panic!("cost")
    };
    assert_eq!(cost.cost_total, 0.25);
    assert_eq!(cost.updated_at, 20_000);
    let original_usage = reader.read_event("usage-a".into(), demand()).await?;
    assert_eq!(original_usage.header.recorded_at, 20_000);
    let raw_usage = reader
        .read_body(original_usage.payload_ref.unwrap(), 0, 65_536)
        .await?;
    assert_eq!(
        serde_json::from_slice::<pl_studio_runtime::InferenceBillingRecord>(&raw_usage.bytes)?
            .recorded_at,
        20
    );
    let before_overflow = reader.capture().await?;
    let mut invalid_usage = usage("overflow", run, false);
    invalid_usage.record.recorded_at = i64::MAX;
    assert!(matches!(
        store.record_usage(&invalid_usage).await,
        Err(HistoryError::InvalidEvent(_))
    ));
    assert_eq!(reader.capture().await?, before_overflow);
    let events = reader
        .events_page(HistoryEventsQuery::AllEvents, None, None, demand())
        .await?;
    assert_eq!(
        events
            .entries
            .iter()
            .filter(|event| event.payload_ref.is_some())
            .count(),
        2
    );
    store.flush().await?;
    assert_eq!(
        store.record_usage(&usage("usage-b", run, true)).await?,
        events
            .entries
            .iter()
            .find(|event| event.header.event_id == "usage-b")
            .unwrap()
            .header
            .seq
    );
    assert_eq!(reader.accounting(None).await?.unwrap().inference_count, 2);
    reader.close().await;
    store.close().await?;
    assert!(matches!(
        store.record_usage(&first).await,
        Err(HistoryError::Closed)
    ));
    Ok(())
}

#[tokio::test]
async fn streaming_conversion_copies_v24_original_bytes_without_activating_or_mutating_source()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let source_path = temp.path().join("v24.sqlite");
    let target = temp.path().join("v25.sqlite");
    let source_db = raw(&source_path).await?;
    source_db.execute_unprepared("CREATE TABLE history_meta(id INTEGER PRIMARY KEY,schema_version INTEGER,thread_id TEXT); INSERT INTO history_meta VALUES(1,24,'import'); CREATE TABLE conversation_items(seq INTEGER PRIMARY KEY,item_id TEXT UNIQUE,query_class TEXT,parent_id TEXT,payload BLOB,metadata BLOB);").await?;
    let payload = b"preserved binary original".repeat(7000);
    source_db
        .execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "INSERT INTO conversation_items VALUES(7,'original','conversation',NULL,?,?)",
            vec![
                payload.clone().into(),
                b"typed legacy metadata".to_vec().into(),
            ],
        ))
        .await?;
    source_db.close().await?;
    let source_before = std::fs::read(&source_path)?;
    let prepared = HistoryStore::open(&target, "import", HistoryLimits::default()).await?;
    let database = prepared.database_id().to_owned();
    prepared.close().await?;
    let db = raw(&target).await?;
    let tx = db.begin().await?;
    let mut importer = HistoryImport::new(&tx, database).await?;
    let source = V24HistorySource::open(&source_path, "import").await?;
    let originals = source.originals_page(0, 128).await?;
    assert_eq!(originals.len(), 1);
    assert_eq!(originals[0].payload_bytes, payload.len() as u64);
    let body = source
        .body(V24Body::Payload {
            item_id: "original".into(),
        })
        .await?;
    let reference = importer
        .copy_body(
            HistoryImportBody {
                body_id: uuid::Uuid::new_v4().to_string(),
                owner_event_id: "original".into(),
                ordinal: 0,
                body_key: "canonical".into(),
                role: HistoryBodyRole::CanonicalPayload,
                media_type: None,
            },
            &body,
        )
        .await?;
    let mut event = HistoryEvent::new("original", HistoryEventKind::LegacyObserved, 0);
    event.payload_body_id = Some(reference.body_id.clone());
    importer.insert_event(event).await?;
    importer.finish().await?;
    tx.commit().await?;
    db.close().await?;
    drop(body);
    source.close().await?;
    assert_eq!(std::fs::read(&source_path)?, source_before);
    let reopened = HistoryStore::open(&target, "import", HistoryLimits::default()).await?;
    let reader = reopened.reader();
    reader.verify_body(reference.clone()).await?;
    let mut actual = Vec::new();
    while actual.len() < payload.len() {
        actual.extend(
            reader
                .read_body(reference.clone(), actual.len() as u64, 65_536)
                .await?
                .bytes,
        );
    }
    assert_eq!(actual, payload);
    reader.close().await;
    reopened.close().await?;
    Ok(())
}
