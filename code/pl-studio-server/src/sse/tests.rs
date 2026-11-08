use anyhow::{Context, Result};
use axum::{body::to_bytes, extract::FromRequestParts, http::Request, response::IntoResponse};
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatBatch, ChatDeliveryKind, ChatFactPosition,
    ChatPlacement, ChatScope, ChatSourceId, ChatTerminalOutcome, ChatToolIdentity, CompletedEntry,
    CompletionRunPosition, MainPresentation, PayloadData, ReadDemand, studio::StudioErrorCode,
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
        StudioProductTopic::McpCatalog {
            scope: pl_protocol::McpScope::Host,
        },
        StudioProductTopic::McpCatalog {
            scope: pl_protocol::McpScope::Ssh {
                ssh_alias: identity.into(),
            },
        },
        StudioProductTopic::ThreadMcp {
            thread_id: identity.into(),
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
async fn conversation_query_requires_demand_and_accepts_only_complete_scope_references() {
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
        conversation_query("/?maxItems=3&maxBytes=4096&runDatabaseId=db&runIndexVersion=1&runStartSeq=17").await,
        Ok((ChatScope::Run { reference }, _))
            if reference.database_id == "db"
                && reference.index_version == 1
                && reference.start_seq == 17
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
        "/?maxItems=7&maxBytes=4096&runDatabaseId=db",
        "/?maxItems=7&maxBytes=4096&runDatabaseId=db&runIndexVersion=1",
        "/?maxItems=7&maxBytes=4096&parentId=parent-a&runDatabaseId=db&runIndexVersion=1&runStartSeq=7",
        "/?maxItems=7&maxBytes=4096&runDatabaseId=db&runIndexVersion=1&runStartSeq=0",
    ] {
        let Err(error) = conversation_query(uri).await else {
            panic!("invalid conversation query admitted: {uri}");
        };
        assert_eq!(error.0.code, StudioErrorCode::InvalidArgument, "{uri}");
    }
}

#[tokio::test]
async fn unsupported_run_index_is_a_typed_protocol_version_mismatch() {
    let Err(error) = conversation_query(
        "/?maxItems=3&maxBytes=4096&runDatabaseId=db&runIndexVersion=2&runStartSeq=17",
    )
    .await
    else {
        panic!("unsupported completion run index version was accepted");
    };
    assert_eq!(error.0.code, StudioErrorCode::Protocol);
    assert_eq!(
        error.0.reason(),
        Some(pl_protocol::studio::StudioErrorReason::ProtocolVersionMismatch.label())
    );
}

#[tokio::test]
async fn chat_event_is_exactly_the_canonical_batch_without_transport_cursor() -> Result<()> {
    let batch = ChatBatch {
        placement: ChatPlacement::Set,
        entries: vec![CompletedEntry {
            record_id: "message-a".into(),
            completion_seq: 7,
            run: Some(CompletionRunPosition {
                start_seq: 7,
                ordinal: 1,
            }),
            main_presentation: MainPresentation::Single,
            atom: ChatAtom {
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
            },
        }],
        before: Some("opaque-before".into()),
        from_seq: None,
        through_seq: 7,
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
    for name in ["runDatabaseId", "runIndexVersion", "runStartSeq"] {
        assert!(
            params
                .iter()
                .any(|param| param["name"] == name && param["required"] == false)
        );
    }
    let schemas = &document["components"]["schemas"];
    assert!(schemas["CompletedEntry"].is_object());
    assert!(schemas["CompletionRunRef"].is_object());
    assert!(schemas["ActivitySnapshot"].is_object());
    assert!(schemas["MainPresentation"].is_object());
    assert!(schemas["ChatBatch"]["properties"]["fromSeq"].is_object());
    assert!(schemas["ChatBatch"]["properties"]["throughSeq"].is_object());
    assert!(schemas["ChatBatch"]["properties"].get("current").is_none());
    assert!(schemas.get("TimelineItem").is_none());
    assert!(schemas.get("TimelineMembersRef").is_none());
    assert!(schemas.get("ChatEntry").is_none());
    for suffix in [
        "chat/older",
        "chat/completed",
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
async fn main_sse_encodes_typed_completed_entries_without_legacy_display_shapes() -> Result<()> {
    let batch: ChatBatch = serde_json::from_value(serde_json::json!({
        "placement": "set",
        "entries": [
            {
                "recordId": "record-a",
                "completionSeq": 8,
                "run": {"startSeq": 8, "ordinal": 1},
                "mainPresentation": "single",
                "atom": {
                    "id": "atom-a",
                    "completionItemId": "record-a",
                    "completionSeq": 8,
                    "source": {"kind": "foregroundTurn", "turnId": "turn"},
                    "kind": "text",
                    "delivery": "foreground",
                    "lifecycle": {"kind": "terminal", "outcome": "completed"},
                    "contents": [],
                    "payload": {"kind": "deferred", "reference": {
                        "databaseId": "db",
                        "target": {"kind": "itemPayload", "itemId": "record-a"}
                    }, "byteLength": 1000000}
                }
            }
        ],
        "before": "opaque-run-page",
        "fromSeq": null,
        "throughSeq": 8
    }))?;
    batch.validate_for(&ChatScope::Main)?;
    let event = encode_conversation_event(&ConversationEvent::Chat {
        batch: Box::new(batch.clone()),
    })?;
    let response = Sse::new(futures::stream::iter([Ok::<_, Infallible>(event)])).into_response();
    let bytes = to_bytes(response.into_body(), 8192).await?;
    let wire = std::str::from_utf8(&bytes)?;
    let data = wire
        .lines()
        .find_map(|line| line.strip_prefix("data: "))
        .context("missing Main chat")?;
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
