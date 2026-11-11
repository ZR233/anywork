use std::time::Duration;

use anyhow::{Context, Result, ensure};
use axum::extract::FromRequestParts;
use axum::http::{HeaderValue, Request};
use axum::response::IntoResponse;
use futures::StreamExt;
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
};
use pl_protocol::{ChatBatch, ChatPlacement, ChatScope};
use pl_provider_fixture::FixtureServer;
use pl_studio_runtime::{
    StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore, StudioConfig},
};

use super::*;
use crate::routes::ApiQuery;
use crate::sse::{ConversationQuery, thread_events};

const DEADLINE: Duration = Duration::from_secs(10);
const MODEL: &str = "server-fixture";
const ACCOUNT: &str = "server-fixture";

mod journey;
mod timeline;

/// Both fixtures use the same explicit, credential-free loopback model route.
fn configure(home: &std::path::Path, base_url: String) -> Result<()> {
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    let mut model = ModelInfo::compatible(MODEL);
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.capabilities.instruction_snapshot_overrides = true;
    model.base_instructions = "Respond using the finite fixture script.".into();
    config.models.accounts.insert(
        AccountId::new(ACCOUNT)?,
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible(ACCOUNT, base_url),
            vec![model],
        ),
    );
    let route = ModelRouteConfig {
        account_id: AccountId::new(ACCOUNT)?,
        model_id: MODEL.into(),
        effort: None,
    };
    for selected in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *selected = route.clone();
    }
    ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
    Ok(())
}

async fn open(state: &AppState, thread_id: &str) -> Result<axum::response::Response> {
    let (mut parts, _) = Request::builder()
        .uri("/?maxItems=1&maxBytes=16384")
        .header("last-event-id", "timeline:obsolete:999")
        .body(())?
        .into_parts();
    let query = ApiQuery::<ConversationQuery>::from_request_parts(&mut parts, &())
        .await
        .map_err(|error| anyhow::anyhow!("{}", error.0))?;
    thread_events(State(state.clone()), Path(thread_id.into()), query)
        .await
        .map(IntoResponse::into_response)
        .map_err(|error| anyhow::anyhow!("{}", error.0))
}

fn assert_stale(result: Result<ReadLease, ApiError>) {
    let Err(error) = result else {
        panic!("stale transport capability was admitted");
    };
    assert_eq!(error.0.code, StudioErrorCode::Conflict);
    assert_eq!(error.0.reason(), Some("staleReadScope"));
}

/// Real runtime, database and reader; no duplicated fake Session or stream
/// harness. TMPDIR can be set by the runner to keep the isolated home local.
#[tokio::test]
async fn original_sse_lease_queries_and_both_close_paths() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let project_path = temp.path().join("project");
    std::fs::create_dir(&project_path)?;
    let home = temp.path().join("home");
    // create_thread constructs an owner before any passive SSE is opened. Its
    // binding must therefore be valid, but this script accepts no model call.
    let provider = FixtureServer::start(vec![]).await?;
    let prepared: Result<StudioRuntime> = async {
        configure(&home, provider.base_url())?;
        let mut options = StudioRuntimeOptions::http_server(Some(home));
        options.host = StudioHostKind::Test;
        Box::pin(StudioRuntime::initialize(options))
            .await
            .map_err(Into::into)
    }
    .await;
    let runtime = match prepared {
        Ok(runtime) => runtime,
        Err(error) => {
            let provider = provider.finish().await;
            return Err(error.context(format!("provider cleanup: {provider:?}")));
        }
    };
    let mut states = Vec::new();
    let result = async {
        let project = runtime.open_project(&project_path).await?;
        let thread = runtime
            .create_thread(&project.id, "HTTP read scope")
            .await?;
        for disconnect in [false, true] {
            let state = AppState::new(runtime.clone(), CancellationToken::new());
            states.push(state.clone());
            let response = open(&state, &thread.id).await?;
            tokio::task::yield_now().await;
            assert_eq!(response.status(), axum::http::StatusCode::OK);
            let id = response.headers()[CONVERSATION_HEADER].to_str()?.to_owned();
            let mut headers = HeaderMap::new();
            headers.insert(CONVERSATION_HEADER, HeaderValue::from_str(&id)?);
            let lease = state
                .conversations
                .borrow(&thread.id, &headers, &state.shutdown)
                .map_err(|error| anyhow::anyhow!("{}", error.0))?;
            assert_eq!(id, lease.owner.reader.subscription_id());
            assert_eq!(thread.id, lease.owner.reader.thread_id());

            assert_stale(
                state
                    .conversations
                    .borrow("another-thread", &headers, &state.shutdown),
            );
            assert_stale(state.conversations.borrow(
                &thread.id,
                &HeaderMap::new(),
                &state.shutdown,
            ));
            let mut duplicate = headers.clone();
            duplicate.append(CONVERSATION_HEADER, HeaderValue::from_str(&id)?);
            assert_stale(
                state
                    .conversations
                    .borrow(&thread.id, &duplicate, &state.shutdown),
            );

            // Leave the response completely unpolled. The first queued frame
            // blocks all further feed receives, but an admitted query still
            // reaches the real reader and reports its own invalid cursor.
            let read = crate::conversation::older(
                State(state.clone()),
                Path(thread.id.clone()),
                headers.clone(),
                ApiJson(OlderRequest {
                    before: "not-an-original-cursor".into(),
                    demand: ReadDemand {
                        max_items: 4,
                        max_bytes: 16384,
                    },
                }),
            );
            let error = tokio::time::timeout(DEADLINE, read)
                .await?
                .err()
                .context("invalid cursor unexpectedly admitted")?;
            assert_eq!(error.0.code, StudioErrorCode::InvalidArgument);
            assert_ne!(error.0.reason(), Some("staleReadScope"));

            let mut body = response.into_body().into_data_stream();
            let mut wire = String::new();
            let batch = tokio::time::timeout(DEADLINE, async {
                loop {
                    let bytes = body.next().await.context("SSE ended before Set")??;
                    wire.push_str(std::str::from_utf8(&bytes)?);
                    for event in wire.split("\n\n") {
                        if event.lines().any(|line| line == "event: chat") {
                            let data = event
                                .lines()
                                .find_map(|line| line.strip_prefix("data: "))
                                .context("chat event lacks payload")?;
                            return Ok::<ChatBatch, anyhow::Error>(serde_json::from_str(data)?);
                        }
                    }
                }
            })
            .await??;
            assert_eq!(batch.placement, ChatPlacement::Set);
            batch.validate_for(&ChatScope::Main)?;

            if disconnect {
                drop(body);
                tokio::time::timeout(DEADLINE, lease.owner.cancel.cancelled()).await?;
            } else {
                state.shutdown.cancel();
            }
            // Existing short reads are explicitly accounted for until their
            // lease is dropped; shutdown must wait, without permitting new ones.
            let shutdown = state.conversations.shutdown();
            tokio::pin!(shutdown);
            assert!(matches!(
                futures::poll!(shutdown.as_mut()),
                std::task::Poll::Pending
            ));
            assert_stale(
                state
                    .conversations
                    .borrow(&thread.id, &headers, &state.shutdown),
            );
            let reader = lease.owner.reader.clone();
            drop(lease);
            tokio::time::timeout(DEADLINE, shutdown).await?;
            ensure!(state.conversations.0.lock().unwrap().readers.is_empty());
            let after = reader
                .load_older(
                    "not-an-original-cursor",
                    ReadDemand {
                        max_items: 4,
                        max_bytes: 16384,
                    },
                )
                .await;
            ensure!(
                after.is_err(),
                "closed read owner retained usable resources"
            );
            assert_eq!(state.streams.available_permits(), crate::MAX_STREAMS);
        }
        Ok::<_, anyhow::Error>(())
    }
    .await;
    let mut cleanup = Ok(());
    for state in states {
        state.shutdown.cancel();
        if let Err(error) = tokio::time::timeout(DEADLINE, state.conversations.shutdown()).await {
            cleanup = Err(anyhow::Error::from(error));
        }
    }
    let shutdown = runtime.shutdown_runtime().await;
    let provider = provider.finish().await;
    result.with_context(|| {
        format!("HTTP owners cleanup: {cleanup:?}; runtime: {shutdown:?}; provider: {provider:?}")
    })?;
    cleanup?;
    shutdown?;
    provider?;
    Ok(())
}
