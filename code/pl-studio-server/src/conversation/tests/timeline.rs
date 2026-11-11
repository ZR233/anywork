use super::*;

fn api<T>(result: Result<T, ApiError>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{}", error.0))
}

#[tokio::test]
async fn timeline_open_events_and_close_share_original_capability() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let project_path = temp.path().join("project");
    std::fs::create_dir(&project_path)?;
    let home = temp.path().join("home");
    let provider = FixtureServer::start(vec![]).await?;
    configure(&home, provider.base_url())?;
    let mut options = StudioRuntimeOptions::http_server(Some(home));
    options.host = StudioHostKind::Test;
    let runtime = Box::pin(StudioRuntime::initialize(options)).await?;
    let state = AppState::new(runtime.clone(), CancellationToken::new());
    let result: Result<()> = async {
        let project = runtime.open_project(&project_path).await?;
        let thread = runtime
            .create_thread(&project.id, "HTTP timeline scope")
            .await?;
        for attach in [false, true] {
            let request = serde_json::from_value(serde_json::json!({
                "demand": { "maxItems": 1, "maxBytes": 16384 }
            }))?;
            let response = api(crate::timeline::open(
                State(state.clone()),
                Path(thread.id.clone()),
                ApiJson(request),
            )
            .await)?
            .into_response();
            let id = response.headers()[CONVERSATION_HEADER].to_str()?.to_owned();
            let mut headers = HeaderMap::new();
            headers.insert(CONVERSATION_HEADER, HeaderValue::from_str(&id)?);
            let lease = api(state
                .conversations
                .borrow(&thread.id, &headers, &state.shutdown))?;
            let owner = Arc::clone(&lease.owner);
            drop(lease);
            assert_stale(
                state
                    .conversations
                    .borrow("foreign-thread", &headers, &state.shutdown),
            );
            let missing = crate::timeline::events(
                State(state.clone()),
                Path(thread.id.clone()),
                HeaderMap::new(),
            )
            .await;
            ensure!(
                missing.is_err(),
                "events must require the original capability"
            );
            let stream = if attach {
                let stream = api(crate::timeline::events(
                    State(state.clone()),
                    Path(thread.id.clone()),
                    headers.clone(),
                )
                .await)?
                .into_response();
                ensure!(
                    crate::timeline::events(
                        State(state.clone()),
                        Path(thread.id.clone()),
                        headers.clone(),
                    )
                    .await
                    .is_err(),
                    "one open must not attach two event consumers"
                );
                Some(stream)
            } else {
                None
            };
            // No body polling/credit: a query must reach the original independent reader.
            let query = crate::timeline::older(
                State(state.clone()),
                Path(thread.id.clone()),
                headers.clone(),
                ApiJson(OlderRequest {
                    before: "not-a-timeline-cursor".into(),
                    demand: ReadDemand {
                        max_items: 1,
                        max_bytes: 16384,
                    },
                }),
            );
            let error = tokio::time::timeout(DEADLINE, query)
                .await?
                .err()
                .context("invalid cursor admitted")?;
            ensure!(error.0.code == StudioErrorCode::InvalidArgument);
            ensure!(error.0.reason() != Some("staleReadScope"));
            let mut stream = stream.map(|response| response.into_body().into_data_stream());
            if let Some(body) = stream.as_mut() {
                // The query above ran while content was unconsumed. The first
                // ordinary frame must still be the original Timeline Set, not
                // a duplicated State baseline from the former mixed feed.
                let batch = tokio::time::timeout(DEADLINE, async {
                    let mut wire = String::new();
                    loop {
                        let bytes = body.next().await.context("Timeline ended before Set")??;
                        wire.push_str(std::str::from_utf8(&bytes)?);
                        let Some((event, _)) = wire.split_once("\n\n") else {
                            continue;
                        };
                        ensure!(
                            event.lines().any(|line| line == "event: timeline"),
                            "non-Timeline first frame: {event}"
                        );
                        let data = event
                            .lines()
                            .find_map(|line| line.strip_prefix("data: "))
                            .context("Timeline frame has no data")?;
                        return serde_json::from_str::<pl_protocol::TimelineBatch>(data)
                            .map_err(anyhow::Error::from);
                    }
                })
                .await??;
                batch
                    .validate()
                    .map_err(|error| anyhow::anyhow!("{error}"))?;
                ensure!(batch.placement == ChatPlacement::Set);
                ensure!(batch.live.is_some(), "Set must carry its original live cut");
            }
            api(tokio::time::timeout(
                DEADLINE,
                crate::timeline::close(
                    State(state.clone()),
                    Path(thread.id.clone()),
                    headers.clone(),
                ),
            )
            .await?)?;
            assert_stale(
                state
                    .conversations
                    .borrow(&thread.id, &headers, &state.shutdown),
            );
            ensure!(owner.native.lock().await.is_none());
            drop(stream);
        }
        ensure!(state.streams.available_permits() == crate::MAX_STREAMS);
        Ok(())
    }
    .await;
    state.shutdown.cancel();
    state.conversations.shutdown().await;
    let shutdown = runtime.shutdown_runtime().await;
    let fixture = provider.finish().await;
    result.context(format!(
        "cleanup: runtime={shutdown:?}; provider={fixture:?}"
    ))
}
