use anyhow::{Context, Result};
use axum::{body::to_bytes, extract::FromRequestParts, http::Request, response::IntoResponse};
use pl_protocol::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatBatch, ChatDeliveryKind,
    ChatEntry, ChatFactPosition, ChatPlacement, ChatScope, ChatSourceId, ChatSourceLifecycle,
    ChatSourceState, ChatTerminalOutcome, ChatToolIdentity, PayloadData, ReadDemand,
    ThreadWaitIntent, ThreadWaitPresentation, ThreadWaitState, studio::StudioErrorCode,
};

use super::*;

async fn conversation_query(uri: &str) -> Result<(ChatScope, ReadDemand), ApiError> {
    let (mut parts, _) = Request::builder().uri(uri).body(()).unwrap().into_parts();
    let ApiQuery(query) =
        ApiQuery::<ConversationQuery>::from_request_parts(&mut parts, &()).await?;
    query.scope_demand()
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
async fn conversation_query_requires_demand_and_rejects_old_resume_parameters() {
    assert!(matches!(
        conversation_query("/?maxItems=7&maxBytes=4096").await,
        Ok((
            ChatScope::Main,
            ReadDemand {
                max_items: 7,
                max_bytes: 4096
            }
        ))
    ));
    assert!(matches!(
        conversation_query("/?maxItems=3&maxBytes=4096&parentId=parent-a").await,
        Ok((ChatScope::Children { parent_id }, _)) if parent_id == "parent-a"
    ));
    assert!(matches!(
        conversation_query("/?maxItems=3&maxBytes=4096&membersDatabaseId=db&membersProjectionVersion=1&membersItemId=group-a").await,
        Ok((ChatScope::GroupMembers { reference }, _))
            if reference.database_id == "db"
                && reference.projection_version == 1
                && reference.item_id == "group-a"
    ));
    for uri in [
        "/",
        "/?maxItems=7",
        "/?maxBytes=4096",
        "/?maxItems=-1&maxBytes=4096",
        "/?maxItems=7&maxBytes=4096&timelineEpoch=epoch-a",
        "/?maxItems=7&maxBytes=4096&appendSeq=7",
        "/?maxItems=7&maxBytes=4096&currentMaxItems=3&currentMaxBytes=4096",
        "/?maxItems=7&maxBytes=4096&parent_id=parent-a",
        "/?maxItems=7&maxBytes=4096&unknown=1",
        "/?maxItems=7&maxItems=8&maxBytes=4096",
        "/?maxItems=7&maxBytes=4096&membersItemId=group-a",
        "/?maxItems=7&maxBytes=4096&membersDatabaseId=db&membersItemId=group-a",
        "/?maxItems=7&maxBytes=4096&parentId=parent-a&membersDatabaseId=db&membersProjectionVersion=1&membersItemId=group-a",
    ] {
        let Err(error) = conversation_query(uri).await else {
            panic!("invalid conversation query admitted: {uri}");
        };
        assert_eq!(error.0.code, StudioErrorCode::InvalidArgument, "{uri}");
    }
}

#[tokio::test]
async fn chat_event_is_exactly_the_canonical_batch_without_transport_cursor() -> Result<()> {
    let batch = ChatBatch {
        placement: ChatPlacement::Set,
        entries: vec![
            ChatEntry::Atom(Box::new(ChatAtom {
                id: "member-a".into(),
                completion_item_id: Some("message-a".into()),
                completion_seq: Some(7),
                source: ChatSourceId::ForegroundTurn {
                    turn_id: "turn-a".into(),
                },
                source_state: None,
                source_order: Some(3),
                kind: ChatAtomKind::Text,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Terminal {
                    started: Some(ChatFactPosition {
                        effect_seq: 4,
                        suborder: 0,
                    }),
                    ended: Some(ChatFactPosition {
                        effect_seq: 5,
                        suborder: 0,
                    }),
                    outcome: ChatTerminalOutcome::Completed,
                },
                turn_id: Some("turn-a".into()),
                attempt_id: Some("attempt-a".into()),
                tool: None,
                wait: None,
                text_channel: Some(pl_protocol::ThreadTextChannel::Final),
                content_present: Some(true),
                started_at: None,
                finished_at: None,
                contents: Vec::new(),
                payload: Some(PayloadData::Inline {
                    bytes: b"  body\n".to_vec(),
                }),
            })),
            ChatEntry::Atom(Box::new(ChatAtom {
                id: "active-wait".into(),
                completion_item_id: None,
                completion_seq: None,
                source: ChatSourceId::ForegroundTurn {
                    turn_id: "turn-a".into(),
                },
                source_state: None,
                source_order: Some(4),
                kind: ChatAtomKind::ToolCall,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Active {
                    started: None,
                    status: ChatActiveStatus::Running,
                },
                turn_id: Some("turn-a".into()),
                attempt_id: Some("attempt-a".into()),
                tool: Some(ChatToolIdentity {
                    call_id: "wait-call".into(),
                    name: "wait".into(),
                }),
                wait: Some(ThreadWaitPresentation::new(
                    ThreadWaitIntent::Timer {
                        duration_ms: 30_000,
                    },
                    ThreadWaitState::Waiting,
                    None,
                )),
                text_channel: None,
                content_present: None,
                started_at: None,
                finished_at: None,
                contents: Vec::new(),
                payload: None,
            })),
            ChatEntry::Source(ChatSourceState {
                source: ChatSourceId::ForegroundTurn {
                    turn_id: "turn-a".into(),
                },
                lifecycle: ChatSourceLifecycle::Active,
                started: Some(ChatFactPosition {
                    effect_seq: 1,
                    suborder: 0,
                }),
                ended: None,
            }),
        ],
        before: Some("opaque-before".into()),
        current: None,
    };
    batch.validate_for(&ChatScope::Children {
        parent_id: "parent-a".into(),
    })?;
    let event = encode_conversation_event(&ConversationEvent::Chat {
        batch: Box::new(batch.clone()),
    })?;
    let response = Sse::new(futures::stream::iter([Ok::<_, Infallible>(event)])).into_response();
    let bytes = to_bytes(response.into_body(), 8192).await?;
    let wire = std::str::from_utf8(&bytes)?;
    assert_eq!(wire.matches("event: chat\n").count(), 1);
    assert!(!wire.lines().any(|line| line.starts_with("id:")));
    let mut data = wire.lines().filter_map(|line| line.strip_prefix("data: "));
    let decoded: ChatBatch = serde_json::from_str(data.next().context("missing chat event")?)?;
    assert_eq!(decoded, batch);
    assert!(data.next().is_none());
    Ok(())
}

#[test]
fn openapi_has_only_demand_conversation_and_independent_canonical_queries() -> Result<()> {
    let document = serde_json::to_value(crate::openapi_document())?;
    let paths = document["paths"].as_object().context("missing paths")?;
    assert!(!paths.keys().any(|path| path.contains("/timeline")));
    let events = &paths["/api/v1/threads/{thread_id}/events"]["get"];
    let params = events["parameters"].as_array().context("missing params")?;
    for name in ["maxItems", "maxBytes"] {
        assert!(
            params
                .iter()
                .any(|param| param["name"] == name && param["required"] == true)
        );
    }
    assert!(
        !params
            .iter()
            .any(|param| param["name"] == "timelineEpoch" || param["name"] == "appendSeq")
    );
    assert!(events["responses"]["200"]["headers"]["X-Anywork-Conversation"].is_object());
    for name in ["membersDatabaseId", "membersProjectionVersion", "membersItemId"] {
        assert!(params.iter().any(|param| param["name"] == name && param["required"] == false));
    }
    let schemas = &document["components"]["schemas"];
    assert!(schemas["TimelineItem"]["properties"]["members"].is_object());
    assert!(schemas["TimelineItem"]["properties"].get("currentMembers").is_none());
    assert!(schemas["TimelineMembersRef"]["properties"]["databaseId"].is_object());
    assert!(schemas["TimelineMembersRef"]["properties"]["projectionVersion"].is_object());
    assert!(schemas["TimelineMembersRef"]["properties"]["itemId"].is_object());
    for suffix in [
        "chat/older",
        "contents/manifest",
        "contents/read",
        "contents/watch",
        "current/page",
    ] {
        let path = format!("/api/v1/threads/{{thread_id}}/{suffix}");
        let post = &paths[&path]["post"];
        assert!(post.is_object(), "{path}");
        assert!(post["requestBody"]["required"] == true, "{path}");
        assert!(
            post["parameters"]
                .as_array()
                .context("missing capability parameter")?
                .iter()
                .any(|parameter| parameter["name"] == "X-Anywork-Conversation"
                    && parameter["in"] == "header"
                    && parameter["required"] == true),
            "{path}"
        );
    }
    // Unrelated execution/receipt APIs remain available.
    assert!(paths.contains_key("/api/v1/threads/{thread_id}/turns"));
    assert!(paths.contains_key("/api/v1/threads/{thread_id}/prompts"));
    Ok(())
}

#[tokio::test]
async fn main_sse_preserves_display_items_and_lightweight_outcome_without_member_payloads() -> Result<()> {
    let batch: ChatBatch = serde_json::from_value(serde_json::json!({
        "placement": "set",
        "entries": [
            {"kind": "item", "value": {
                "id": "group", "kind": "workGroup",
                "source": {"kind": "foregroundTurn", "turnId": "turn"},
                "delivery": "foreground", "turnId": "turn",
                "startedAt": 100, "finishedAt": 110,
                "summary": {
                    "memberCount": 20, "activeCount": 0, "failedCount": 1, "cancelledCount": 2,
                    "categories": [{"category": "command", "count": 20}],
                    "startedAt": 100, "finishedAt": 110
                },
                "members": {"databaseId": "db", "projectionVersion": 1, "itemId": "group"},
                "position": 4, "admissionClosed": true
            }},
            {"kind": "item", "value": {
                "id": "interrupted-text", "kind": "text",
                "source": {"kind": "foregroundTurn", "turnId": "turn"},
                "atomKind": "text", "delivery": "foreground", "outcome": "cancelled",
                "textChannel": "final", "turnId": "turn",
                "startedAt": 111, "finishedAt": 112,
                "payload": {"kind": "deferred", "reference": {
                    "databaseId": "db",
                    "target": {"kind": "itemPayload", "itemId": "original-content"}
                }, "byteLength": 1000000},
                "contentItemId": "original-content", "position": 5, "admissionClosed": true
            }}
        ],
        "before": "opaque-item-page",
        "current": serde_json::to_value(pl_protocol::CurrentProjection::empty(43, pl_protocol::ThreadStatus::Idle))?
    }))?;
    batch.validate_for(&ChatScope::Main)?;
    let event = encode_conversation_event(&ConversationEvent::Chat { batch: Box::new(batch.clone()) })?;
    let response = Sse::new(futures::stream::iter([Ok::<_, Infallible>(event)])).into_response();
    let bytes = to_bytes(response.into_body(), 8192).await?;
    let wire = std::str::from_utf8(&bytes)?;
    let data = wire.lines().find_map(|line| line.strip_prefix("data: ")).context("missing Main chat")?;
    let decoded: ChatBatch = serde_json::from_str(data)?;
    assert_eq!(decoded, batch);
    assert!(!wire.contains("currentMembers"));
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
