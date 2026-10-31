use anyhow::{Context, Result};
use axum::{body::to_bytes, extract::FromRequestParts, http::Request, response::IntoResponse};
use pl_protocol::{
    ThreadContentField, ThreadTextChannel, TimelineDescriptor, TimelineFieldPreview, TimelineItem,
    TimelineItemHeader, TimelineItemSource, TimelineTextDescriptor, studio::StudioErrorCode,
};

use super::*;

async fn resume(uri: &str) -> Result<Option<TimelineCompletionCursor>, ApiError> {
    let (mut parts, _) = Request::builder().uri(uri).body(()).unwrap().into_parts();
    let ApiQuery(query) =
        ApiQuery::<ConversationQuery>::from_request_parts(&mut parts, &()).await?;
    query.resume_after()
}

async fn product_topic(uri: &str) -> Result<pl_studio_runtime::StudioProductTopic, ApiError> {
    let (mut parts, _) = Request::builder().uri(uri).body(()).unwrap().into_parts();
    let ApiQuery(query) =
        ApiQuery::<ProductTopicQuery>::from_request_parts(&mut parts, &()).await?;
    parse_product_topic(&query)
}

#[tokio::test]
async fn product_resync_preserves_topic_and_encoded_scope() {
    use pl_studio_runtime::StudioProductTopic;

    let identity = " 宿主 /?&=+#% ";
    for topic in [
        StudioProductTopic::ProjectDirectory,
        StudioProductTopic::Skills {
            workspace_id: identity.into(),
        },
        StudioProductTopic::SessionCosts {
            root_thread_id: identity.into(),
        },
        StudioProductTopic::ChildInteractions {
            host_thread_id: identity.into(),
        },
    ] {
        let resync = topic_resync_path(&topic);
        let uri: axum::http::Uri = resync.parse().unwrap();
        assert_eq!(uri.path(), "/api/v1/state/product");
        let parsed = product_topic(&resync)
            .await
            .unwrap_or_else(|error| panic!("invalid resync URI {resync}: {}", error.0));
        assert_eq!(parsed, topic);
    }
}

#[tokio::test]
async fn child_interactions_query_requires_exactly_its_host_scope() {
    use pl_studio_runtime::StudioProductTopic;

    let valid = "/?topic=childInteractions&hostThreadId=host-a";
    assert!(matches!(
        product_topic(valid).await,
        Ok(StudioProductTopic::ChildInteractions { host_thread_id }) if host_thread_id == "host-a"
    ));
    for uri in [
        "/?topic=childInteractions",
        "/?topic=childInteractions&hostThreadId=",
        "/?topic=childInteractions&hostThreadId=%20%09",
        "/?topic=childInteractions&workspaceId=host-a",
        "/?topic=childInteractions&rootThreadId=host-a",
        "/?topic=childInteractions&hostThreadId=host-a&workspaceId=workspace-a",
        "/?topic=childInteractions&hostThreadId=host-a&rootThreadId=root-a",
        "/?topic=childInteractions&hostThreadId=host-a&hostThreadId=host-b",
        "/?topic=childInteractions&host_thread_id=host-a",
        "/?topic=projectDirectory&hostThreadId=host-a",
        "/?topic=skills&workspaceId=workspace-a&hostThreadId=host-a",
        "/?topic=sessionCosts&rootThreadId=root-a&hostThreadId=host-a",
    ] {
        let Err(error) = product_topic(uri).await else {
            panic!("invalid topic scope was admitted: {uri}");
        };
        assert_eq!(error.0.code, StudioErrorCode::InvalidArgument, "{uri}");
    }
}

#[tokio::test]
async fn conversation_resume_requires_an_explicit_valid_completion_prefix() {
    assert!(matches!(resume("/").await, Ok(None)));
    let Ok(Some(cursor)) = resume("/?timelineEpoch=epoch-a&appendSeq=7").await else {
        panic!("a complete accepted prefix must be admitted");
    };
    assert_eq!(cursor.timeline_epoch, "epoch-a");
    assert_eq!(cursor.append_seq, 7);
    assert!(matches!(
        resume("/?timelineEpoch=epoch-a&appendSeq=0").await,
        Ok(Some(TimelineCompletionCursor { append_seq: 0, .. }))
    ));
    for uri in [
        "/?timelineEpoch=epoch-a",
        "/?appendSeq=7",
        "/?timelineEpoch=&appendSeq=7",
        "/?timelineEpoch=epoch-a&appendSeq=-1",
        "/?timelineEpoch=epoch-a&appendSeq=9223372036854775808",
        "/?timeline_epoch=epoch-a&appendSeq=7",
        "/?timelineEpoch=epoch-a&appendSeq=7&unknown=1",
    ] {
        let Err(error) = resume(uri).await else {
            panic!("invalid completion prefix was admitted: {uri}");
        };
        assert_eq!(error.0.code, StudioErrorCode::InvalidArgument, "{uri}");
    }
}

#[tokio::test]
async fn sse_keeps_nonempty_completion_and_activity_commit_in_one_delivery() -> Result<()> {
    let text = "  completed body\n";
    let item = TimelineItem {
        header: TimelineItemHeader {
            id: "completed-text".into(),
            thread_id: "thread".into(),
            turn_id: Some("turn".into()),
            append_seq: 8,
            source_effect_seq: Some(11),
            sealed_at: Some(17),
        },
        descriptor: TimelineDescriptor::Text(TimelineTextDescriptor {
            channel: ThreadTextChannel::Final,
            attachments: vec![],
            outcome: serde_json::from_value(serde_json::json!({
                "kind": "completed", "data": {"completedAt": 17}
            }))?,
        }),
        source: TimelineItemSource::Content,
        fields: vec![TimelineFieldPreview {
            field: ThreadContentField::Text,
            text: text.into(),
            total_bytes: text.len() as u64,
        }],
    };
    let event = ConversationEvent::ActivityContent {
        frame: ActivityContentFrame::Commit {
            generation: "activity".into(),
            revision: 3,
        },
        completed: Some(Box::new(TimelineTailUpdate::Batch {
            subscription_id: "subscription".into(),
            timeline_epoch: "epoch-a".into(),
            from_seq: 7,
            through_seq: 8,
            items: vec![item],
        })),
    };
    let (sender, receiver) = mpsc::channel(1);
    assert!(send_conversation_event(&sender, &CancellationToken::new(), &event).await);
    drop(sender);
    let response = Sse::new(ReceiverStream::new(receiver)).into_response();
    let bytes = to_bytes(response.into_body(), 8192).await?;
    let wire = std::str::from_utf8(&bytes)?;
    assert_eq!(wire.matches("event: activityContent\n").count(), 1);
    let mut data = wire.lines().filter_map(|line| line.strip_prefix("data: "));
    let payload: serde_json::Value =
        serde_json::from_str(data.next().context("missing SSE delivery")?)?;
    assert!(
        data.next().is_none(),
        "the commit was split into multiple events"
    );
    assert_eq!(payload["frame"]["kind"], "commit");
    assert_eq!(payload["frame"]["revision"], 3);
    let completed: TimelineTailUpdate = serde_json::from_value(payload["completed"].clone())?;
    assert_eq!(completion_event_id(&completed), "timeline:epoch-a:8");
    let TimelineTailUpdate::Batch {
        from_seq,
        through_seq,
        items,
        ..
    } = completed
    else {
        panic!("the nonempty completion batch was not preserved");
    };
    assert_eq!((from_seq, through_seq), (7, 8));
    assert_eq!(items[0].header.append_seq, 8);
    assert_eq!(items[0].fields[0].text, text);
    Ok(())
}

#[tokio::test]
async fn full_sse_send_ends_on_shutdown_or_receiver_close() {
    use std::task::Poll;

    for disconnect in [false, true] {
        let shutdown = CancellationToken::new();
        let (sender, receiver) = mpsc::channel(1);
        assert!(send_json(&sender, &shutdown, "baseline", None, &"held").await);
        let send = send_json(&sender, &shutdown, "batch", None, &"blocked");
        tokio::pin!(send);
        assert!(matches!(futures::poll!(send.as_mut()), Poll::Pending));
        if disconnect {
            drop(receiver);
        } else {
            shutdown.cancel();
        }
        assert!(matches!(futures::poll!(send.as_mut()), Poll::Ready(false)));
    }
}
