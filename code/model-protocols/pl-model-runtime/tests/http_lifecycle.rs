use pl_model_runtime::runtime::{ModelInvocationContext, ModelRuntime, ModelSession};
use pl_model_wire::completion::stream::event::{ModelBlockKind, ModelStreamEvent};
use pl_model_wire::{
    completion::{CompletionRequest, Message, MessageContent, MessageRole},
    model::{ModelDefinition, ModelTransportProfile},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

fn request() -> CompletionRequest {
    CompletionRequest::builder()
        .messages(vec![Message {
            role: MessageRole::User,
            content: MessageContent::text("continue"),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }])
        .build()
}

fn runtime(base: String, native: bool) -> ModelRuntime {
    let mut endpoint = pl_model_openai::endpoint::compatible_endpoint("fixture", base);
    endpoint.service_capabilities.remote_compaction = native;
    runtime_with_endpoint(endpoint)
}

fn runtime_with_endpoint(endpoint: pl_model_wire::protocol::ProtocolEndpoint) -> ModelRuntime {
    let mut model = ModelDefinition::compatible("http-model");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.extra.capabilities.web_search = true;
    ModelRuntime::bind(
        "fixture",
        endpoint,
        model,
        &pl_model_openai_wire::OPENAI_WIRE_CODEC,
        pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
        None,
    )
    .unwrap()
}

type Chunk = (Vec<u8>, tokio::sync::oneshot::Sender<()>);

async fn server() -> (
    String,
    tokio::sync::mpsc::Sender<Chunk>,
    tokio::task::JoinHandle<()>,
) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1", listener.local_addr().unwrap());
    let (send, mut chunks) = tokio::sync::mpsc::channel::<Chunk>(1);
    let task = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        // Small virtual-time fragments must reach the peer immediately rather
        // than waiting for TCP's wall-clock delayed-ACK/Nagle interval.
        socket.set_nodelay(true).unwrap();
        let mut request = Vec::new();
        loop {
            let mut buffer = [0; 4096];
            let count = socket.read(&mut buffer).await.unwrap();
            assert_ne!(count, 0);
            request.extend_from_slice(&buffer[..count]);
            if let Some(end) = request.windows(4).position(|w| w == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&request[..end]).to_ascii_lowercase();
                let length = headers
                    .lines()
                    .find_map(|line| line.strip_prefix("content-length: "))
                    .unwrap()
                    .parse::<usize>()
                    .unwrap();
                if request.len() >= end + 4 + length {
                    break;
                }
            }
        }
        socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n").await.unwrap();
        while let Some((bytes, ack)) = chunks.recv().await {
            socket
                .write_all(format!("{:x}\r\n", bytes.len()).as_bytes())
                .await
                .unwrap();
            socket.write_all(&bytes).await.unwrap();
            socket.write_all(b"\r\n").await.unwrap();
            socket.flush().await.unwrap();
            ack.send(()).unwrap();
        }
        socket.write_all(b"0\r\n\r\n").await.unwrap();
    });
    (base, send, task)
}

async fn send(sender: &tokio::sync::mpsc::Sender<Chunk>, bytes: Vec<u8>) {
    let (ack, received) = tokio::sync::oneshot::channel();
    sender.send((bytes, ack)).await.unwrap();
    received.await.unwrap();
}

#[tokio::test]
async fn fragmented_completion_and_native_compaction_survive_active_reads_beyond_300_seconds() {
    for native in [false, true] {
        let (base, sender, server) = server().await;
        let runtime = runtime(base, native);
        let (context, received) = observed(ModelSession::default());
        let invocation = tokio::spawn(async move {
            if native {
                let response = runtime
                    .compaction()
                    .unwrap()
                    .checkpoint(request(), context)
                    .await
                    .unwrap();
                assert!(matches!(
                    response.item,
                    pl_model_wire::completion::ModelContextItem::Compaction { .. }
                ));
            } else {
                assert_eq!(
                    runtime
                        .complete(request(), context)
                        .await
                        .unwrap()
                        .content
                        .as_deref(),
                    Some("warmfragmented")
                );
            }
        });
        let warm = responses_text("warm", "active", "http-model");
        send(
            &sender,
            warm[..3]
                .iter()
                .map(|event| format!("data: {event}\n\n"))
                .collect::<String>()
                .into_bytes(),
        )
        .await;
        tokio::time::timeout(Duration::from_secs(5), received.notified())
            .await
            .unwrap();
        for delta in ["frag", "men", "te", "d"] {
            tokio::time::pause();
            tokio::time::advance(Duration::from_secs(100)).await;
            tokio::time::resume();
            assert!(
                !invocation.is_finished(),
                "an active response exceeded its idle budget"
            );

            let event =
                json!({"type":"response.output_text.delta","item_id":"message-1","delta":delta});
            let data = format!("data: {event}\n\n").into_bytes();
            let (prefix, suffix) = data.split_at(data.len() / 2);
            send(&sender, prefix.to_vec()).await;
            send(&sender, suffix.to_vec()).await;
            tokio::time::timeout(Duration::from_secs(5), received.notified())
                .await
                .unwrap();
        }
        if native {
            let checkpoint = json!({"type":"response.output_item.done","item":{"type":"compaction","encrypted_content":"checkpoint"}});
            send(&sender, format!("data: {checkpoint}\n\n").into_bytes()).await;
        }
        let completed = if native {
            json!({"type":"response.completed","response":{"id":"active","usage":{"input_tokens":2,"output_tokens":1}}})
        } else {
            responses_text("warmfragmented", "active", "http-model")
                .pop()
                .unwrap()
        };
        send(&sender, format!("data: {completed}\n\n").into_bytes()).await;
        drop(sender);
        tokio::time::timeout(Duration::from_secs(5), invocation)
            .await
            .unwrap()
            .unwrap();
        server.await.unwrap();
    }
}

#[tokio::test]
async fn session_close_cancels_an_active_http_body_and_seals_admission() {
    let mut events = responses_text("observed", "closing", "http-model");
    events.pop();
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "continue",
        0,
        Reply::HangingSse(events),
    )])
    .await
    .unwrap();
    let runtime = runtime(fixture.base_url(), false);
    let session = ModelSession::default();
    let (context, received) = observed(session.clone());
    let caller_cancellation = tokio_util::sync::CancellationToken::new();
    let context = context.with_cancellation(Some(caller_cancellation.clone()));
    let invocation = tokio::spawn({
        let runtime = runtime.clone();
        async move { runtime.complete(request(), context).await }
    });
    tokio::time::timeout(Duration::from_secs(5), received.notified())
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(2), session.close())
        .await
        .unwrap()
        .unwrap();
    let failure = invocation.await.unwrap().unwrap_err();
    assert!(failure.is_cancelled());
    assert!(
        !caller_cancellation.is_cancelled(),
        "session close must not cancel the caller's token"
    );
    assert!(
        runtime
            .complete(request(), ModelInvocationContext::in_memory(session))
            .await
            .is_err()
    );
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

#[tokio::test]
async fn http_read_idle_is_bounded_and_preserves_an_unsafe_attempt_without_replay() {
    let mut events = responses_text("remote work", "idle", "http-model");
    events.pop();
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "continue",
        0,
        Reply::HangingSse(events),
    )])
    .await
    .unwrap();
    let runtime = runtime(fixture.base_url(), false);
    let mut input = request();
    input
        .tools
        .push(pl_model_wire::completion::ToolSpec::WebSearch {
            options: pl_model_wire::completion::HostedWebSearchOptions::OpenAi {
                external_web_access: false,
                indexed_web_access: None,
                filters: None,
                user_location: None,
                search_context_size: None,
                search_content_types: None,
            },
        });
    let (context, received) = observed(ModelSession::default());
    let invocation = tokio::spawn(async move { runtime.complete(input, context).await });
    tokio::time::timeout(Duration::from_secs(5), received.notified())
        .await
        .unwrap();
    tokio::time::pause();
    tokio::time::advance(Duration::from_secs(179)).await;
    assert!(!invocation.is_finished());
    tokio::time::advance(Duration::from_secs(2)).await;
    tokio::time::resume();
    let failure = tokio::time::timeout(Duration::from_secs(5), invocation)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();
    assert!(
        failure
            .source
            .provider_failure_ref()
            .is_some_and(
                |failure| failure.kind == pl_protocol::ProviderFailureKind::Transport
                    && failure.retry.is_retryable()
            )
    );
    assert!(!failure.is_cancelled());
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

#[tokio::test]
async fn settlement_save_failure_refuses_replay_and_current_capture_remains_reachable() {
    use pl_core::model::{CancellationToken, Model};
    use pl_core::thread::{
        HistoryExport, StepInput, ThreadEffectBatch, ThreadError, ThreadHandle, UsageSummary,
        cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
        current::SavedModelPhase,
        history_sink::{HistorySink, HistorySinkHandle},
    };
    use std::sync::atomic::{AtomicU64, Ordering};
    use tokio::sync::Notify;

    #[derive(Debug, Default)]
    struct Gate {
        sequence: AtomicU64,
        entered: Notify,
        release: Notify,
    }
    #[derive(Debug)]
    struct Store(Arc<Gate>);
    impl HistorySink for Store {
        fn fold_usage(&self, _: &mut UsageSummary, _: &ThreadEffectBatch) {}
        fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn reserve_operation_output(&self, _: &str, _: &str, max: u64) -> Result<u64, ColdStoreError> {
            Ok(max)
        }
        fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn release_operation_output(&self, _: &str, _: &str) {}
        fn pressure(&self, _: &str) -> StoragePressure {
            StoragePressure::default()
        }
        fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
            StorageIdleStatus {
                pressure: self.pressure(thread_id),
                reclaimable_thread_bytes: None,
            }
        }
        fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
            None
        }
        fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
            if !write.effect.model_sub_attempt_settlements.is_empty() {
                self.0
                    .sequence
                    .store(write.effect.sequence, Ordering::Release);
            }
            Ok(())
        }
        async fn confirm_model_settlement(
            &self,
            _: &str,
            sequence: u64,
        ) -> Result<(), ColdStoreError> {
            if sequence != self.0.sequence.load(Ordering::Acquire) {
                return Ok(());
            }
            self.0.entered.notify_one();
            self.0.release.notified().await;
            Err(ColdStoreError {
                source: Box::new(std::io::Error::other("controlled settlement write failure")),
            })
        }
    }

    let mut events = responses_text("visible before retry", "failed", "http-model");
    events.pop();
    events.push(json!({"type":"response.failed", "response":{
        "id": "failed", "status": "failed",
        "usage": {"input_tokens": 40, "output_tokens": 12, "total_tokens": 52},
        "error":{"code":"upstream_error", "message":"upstream unavailable"}
    }}));
    let server = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "continue",
        0,
        Reply::Sse(events),
    )])
    .await
    .unwrap();
    // Independent-call delivery must not bypass the Thread's attached settlement owner.
    let model =
        pl_model_runtime::runtime::ThreadModel::new(runtime(server.base_url(), false), None)
            .with_in_memory_settlement();
    let thread = ThreadHandle::start(
        "settlement-thread".into(),
        model.open_session().await.unwrap(),
    )
    .unwrap();
    let gate = Arc::new(Gate::default());
    thread
        .attach_history(HistorySinkHandle::new(Store(gate.clone())))
        .await
        .unwrap();
    let running = tokio::spawn({
        let thread = thread.clone();
        async move {
            thread
                .step(StepInput {
                    turn_id: "settlement-turn".into(),
                    attempt_id: "settlement-attempt".into(),
                    cancellation: CancellationToken::new(),
                    content: vec![pl_core::context::ContextContent::Text {
                        text: "continue".into(),
                    }],
                })
                .await
        }
    });
    tokio::time::timeout(Duration::from_secs(5), gate.entered.notified())
        .await
        .unwrap();
    let capture = tokio::time::timeout(
        Duration::from_secs(5),
        thread.capture_current(CancellationToken::new()),
    )
    .await
    .unwrap()
    .unwrap();
    let SavedModelPhase::Streaming { stream } = capture.model_call.unwrap().phase else {
        panic!("settlement wait must leave the original Current producer reachable");
    };
    let stream = pl_model_wire::completion::ModelStreamCurrent::decode(&stream).unwrap();
    assert_eq!(stream.generation, 0);
    assert!(stream.usage_is_terminal);
    let payload = stream
        .settlement
        .expect("settlement is visible while saving");
    let captured = pl_model_runtime::runtime::model_sub_attempt_receipt(
        &pl_core::model::ModelSubAttemptSettlement {
            turn_id: Some("settlement-turn".into()),
            attempt_id: "settlement-attempt".into(),
            generation: 0,
            payload,
        },
    )
    .unwrap();
    assert_eq!(captured.billing.accounting.usage.total_tokens, Some(52));
    assert!(captured.billing.attempt.unwrap().usage_is_terminal);
    assert!(!running.is_finished());
    gate.release.notify_one();
    let result = tokio::time::timeout(Duration::from_secs(5), running)
        .await
        .unwrap()
        .unwrap()
        .unwrap_err();
    let ThreadError::Model(error) = result else {
        panic!("unexpected result {result:?}");
    };
    assert!(
        error
            .source
            .as_deref()
            .unwrap()
            .downcast_ref::<pl_model_wire::completion::CompletionFailure>()
            .unwrap()
            .usage_is_terminal
    );
    let receipt = pl_model_runtime::runtime::model_failure_receipt(&error)
        .unwrap()
        .unwrap();
    assert_eq!(
        receipt.provider_failure.unwrap().code.as_deref(),
        Some("upstream_error")
    );
    assert_eq!(
        receipt.recovery_stop,
        Some(pl_model_runtime::runtime::ModelRecoveryStopReason::SaveFailed)
    );
    assert_eq!(receipt.settlements.len(), 1);
    assert_eq!(receipt.accounting.usage.total_tokens, Some(52));
    assert_eq!(server.finish().await.unwrap().len(), 1);
    assert!(matches!(
        thread.close().await,
        Err(ThreadError::Storage(_))
    ));
}

#[tokio::test]
async fn auxiliary_attempts_wait_for_their_exact_effect_and_keep_both_usage_samples() {
    use pl_core::model::Model;
    use pl_core::thread::{
        HistoryExport, ThreadEffectBatch, ThreadHandle, UsageSummary,
        cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
        extensions::ExtensionMutation,
        history_sink::{HistorySink, HistorySinkHandle},
    };
    use pl_model_runtime::runtime::ModelSubAttemptReceipt;
    use std::sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    };
    use tokio::sync::Notify;

    #[derive(Debug, Default)]
    struct Gate {
        first: AtomicU64,
        receipts: Mutex<Vec<ModelSubAttemptReceipt>>,
        entered: Notify,
        release: Notify,
    }
    #[derive(Debug)]
    struct Sink {
        gate: Arc<Gate>,
        reject: bool,
    }
    impl HistorySink for Sink {
        fn fold_usage(&self, _: &mut UsageSummary, _: &ThreadEffectBatch) {}
        fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn reserve_operation_output(&self, _: &str, _: &str, max: u64) -> Result<u64, ColdStoreError> {
            Ok(max)
        }
        fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn release_operation_output(&self, _: &str, _: &str) {}
        fn pressure(&self, _: &str) -> StoragePressure {
            StoragePressure::default()
        }
        fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
            StorageIdleStatus {
                pressure: self.pressure(thread_id),
                reclaimable_thread_bytes: None,
            }
        }
        fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
            None
        }
        fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
            for settlement in write.effect.model_sub_attempt_settlements.iter() {
                let mut receipts = self.gate.receipts.lock().unwrap();
                if receipts.is_empty() {
                    self.gate
                        .first
                        .store(write.effect.sequence, Ordering::Release);
                }
                receipts.push(
                    pl_model_runtime::runtime::model_sub_attempt_receipt(settlement).unwrap(),
                );
            }
            Ok(())
        }
        async fn confirm_model_settlement(
            &self,
            _: &str,
            sequence: u64,
        ) -> Result<(), ColdStoreError> {
            if sequence > 0 && sequence == self.gate.first.load(Ordering::Acquire) {
                self.gate.entered.notify_one();
                self.gate.release.notified().await;
                if self.reject {
                    return Err(ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "controlled auxiliary save failure",
                        )),
                    });
                }
            }
            Ok(())
        }
    }

    for reject in [false, true] {
        let mut steps = vec![Step::prompt(
            Protocol::ResponsesHttp,
            "continue",
            0,
            Reply::Sse(vec![json!({
                "type":"response.failed", "response":{"id":"failed", "status":"failed",
                    "usage":{"input_tokens":11,"output_tokens":3,"total_tokens":14},
                    "error":{"code":"upstream_error","message":"transient","retry_after_ms":1}},
            })]),
        )];
        if !reject {
            let mut events = responses_text("recovered", "success", "http-model");
            events.last_mut().unwrap()["response"]["usage"] =
                json!({"input_tokens":5,"output_tokens":3,"total_tokens":8});
            steps.push(Step::prompt(
                Protocol::ResponsesHttp,
                "continue",
                1,
                Reply::Sse(events),
            ));
        }
        let fixture = FixtureServer::start(steps).await.unwrap();
        let runtime = runtime(fixture.base_url(), false);
        let owner_model = pl_model_runtime::runtime::ThreadModel::new(runtime.clone(), None);
        let owner = ThreadHandle::start(
            "auxiliary".into(),
            owner_model.open_session().await.unwrap(),
        )
        .unwrap();
        let gate = Arc::new(Gate::default());
        owner
            .attach_history(HistorySinkHandle::new(Sink {
                gate: gate.clone(),
                reject,
            }))
            .await
            .unwrap();
        let session = ModelSession::default();
        let port = owner.begin_auxiliary_model_call(None).await.unwrap();
        let context =
            ModelInvocationContext::new(session.clone()).with_settlement_port("title", port);
        let running = tokio::spawn(async move { runtime.complete(request(), context).await });
        tokio::time::timeout(Duration::from_secs(5), gate.entered.notified())
            .await
            .unwrap();
        owner
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: "unrelated".into(),
                expected_revision: None,
                payload: pl_core::context::OpaquePayload::text("later effect"),
            }])
            .await
            .unwrap();
        assert!(!running.is_finished());
        assert_eq!(fixture.recorded().len(), 1);
        gate.release.notify_one();
        let result = tokio::time::timeout(Duration::from_secs(5), running)
            .await
            .unwrap()
            .unwrap();
        if reject {
            let error = result.unwrap_err();
            assert!(error.recovery_error.is_some());
            assert_eq!(
                error.source.provider_failure_ref().unwrap().code.as_deref(),
                Some("upstream_error")
            );
            assert_eq!(error.settlements.len(), 1);
        } else {
            let response = result.unwrap();
            assert_eq!(response.content.as_deref(), Some("recovered"));
            assert_eq!(response.settlements.len(), 2);
        }
        {
            let receipts = gate.receipts.lock().unwrap();
            assert_eq!(
                receipts
                    .iter()
                    .map(|receipt| receipt.billing.accounting.usage.total_tokens.unwrap())
                    .collect::<Vec<_>>(),
                if reject { vec![14] } else { vec![14, 8] }
            );
            assert!(
                receipts
                    .iter()
                    .all(|receipt| receipt.billing.purpose.as_deref() == Some("title"))
            );
        }
        session.close().await.unwrap();
        if reject {
            assert!(matches!(
                owner.close().await,
                Err(pl_core::thread::ThreadError::Storage(_))
            ));
        } else {
            owner.close().await.unwrap();
        }
        assert_eq!(
            fixture.finish().await.unwrap().len(),
            if reject { 1 } else { 2 }
        );
    }
}

#[tokio::test]
async fn persistent_invocation_without_a_settlement_owner_rejects_before_network() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "continue",
        0,
        Reply::Sse(vec![json!({
            "type":"response.failed", "response":{"id":"failed", "status":"failed",
                "usage":{"input_tokens":11,"output_tokens":3,"total_tokens":14},
                "error":{"code":"upstream_error","message":"transient","retry_after_ms":1}},
        })]),
    )])
    .await
    .unwrap();
    let session = ModelSession::default();
    let error = runtime(fixture.base_url(), false)
        .complete(request(), ModelInvocationContext::new(session.clone()))
        .await
        .unwrap_err();
    assert_eq!(
        fixture.recorded().len(),
        0,
        "missing save authority must fail before a request"
    );
    assert!(error.source.to_string().contains("durable writer"));
    assert_eq!(error.accounting.usage.total_tokens, None);
    assert!(error.settlements.is_empty());
    session.close().await.unwrap();
}

#[tokio::test]
async fn invalid_authentication_headers_do_not_settle_an_unsent_inference() {
    let fixture = FixtureServer::start(Vec::new()).await.unwrap();
    let mut endpoint =
        pl_model_openai::endpoint::compatible_endpoint("fixture", fixture.base_url());
    endpoint.bearer_token = Some("invalid\nheader".into());
    let failure = runtime_with_endpoint(endpoint)
        .complete(
            request(),
            ModelInvocationContext::in_memory(ModelSession::default()),
        )
        .await
        .unwrap_err();
    assert_eq!(fixture.recorded().len(), 0);
    assert!(matches!(
        *failure.source,
        pl_protocol::PureError::ConfigError(_)
    ));
    assert!(
        failure.settlements.is_empty(),
        "an invalid local header never reached transport"
    );
}

#[tokio::test]
async fn cancellation_during_authentication_does_not_settle_an_unsent_inference() {
    use pl_protocol::credential::{BearerCredential, EndpointAuthorization, TokenFuture};
    struct BlockingCredential(Arc<tokio::sync::Notify>);
    impl BearerCredential for BlockingCredential {
        fn registration_id(&self) -> &str {
            "fixture-credential"
        }
        fn workspace_id(&self) -> Option<&str> {
            None
        }
        fn token<'a>(&'a self, _: &'a str) -> TokenFuture<'a> {
            Box::pin(async move {
                self.0.notify_one();
                std::future::pending().await
            })
        }
    }
    let fixture = FixtureServer::start(Vec::new()).await.unwrap();
    let entered = Arc::new(tokio::sync::Notify::new());
    let mut endpoint =
        pl_model_openai::endpoint::compatible_endpoint("fixture", fixture.base_url());
    endpoint.authorization = Some(EndpointAuthorization::new(BlockingCredential(
        entered.clone(),
    )));
    let cancellation = tokio_util::sync::CancellationToken::new();
    let context = ModelInvocationContext::in_memory(ModelSession::default())
        .with_cancellation(Some(cancellation.clone()));
    let runtime = runtime_with_endpoint(endpoint);
    let running = tokio::spawn(async move { runtime.complete(request(), context).await });
    tokio::time::timeout(Duration::from_secs(5), entered.notified())
        .await
        .unwrap();
    cancellation.cancel();
    let failure = running.await.unwrap().unwrap_err();
    assert_eq!(fixture.recorded().len(), 0);
    assert!(failure.is_cancelled());
    assert!(
        failure.settlements.is_empty(),
        "credential acquisition never reached transport"
    );
}

#[tokio::test]
async fn completed_response_without_usage_keeps_the_sample_unknown() {
    use pl_core::model::ModelSubAttemptSettlement;
    use pl_model_wire::completion::CompletionTraceContext;

    let mut events = responses_text("complete", "no-usage", "http-model");
    events.last_mut().unwrap()["response"]
        .as_object_mut()
        .unwrap()
        .remove("usage");
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "continue",
        0,
        Reply::Sse(events),
    )])
    .await
    .unwrap();
    let mut response = runtime(fixture.base_url(), false)
        .complete(
            request(),
            ModelInvocationContext::in_memory(ModelSession::default()).with_trace_metadata(
                CompletionTraceContext {
                    session_id: "thread".into(),
                    turn_id: "turn".into(),
                    inference_id: "attempt".into(),
                },
            ),
        )
        .await
        .unwrap();
    assert_eq!(response.content.as_deref(), Some("complete"));
    assert!(!response.usage_is_terminal);
    assert_eq!(response.accounting.usage, Default::default());
    assert_eq!(response.settlements.len(), 1);
    let receipt =
        pl_model_runtime::runtime::model_sub_attempt_receipt(&ModelSubAttemptSettlement {
            turn_id: None,
            attempt_id: "attempt".into(),
            generation: 0,
            payload: response.settlements.pop().unwrap(),
        })
        .unwrap();
    assert!(!receipt.billing.attempt.unwrap().usage_is_terminal);
    assert_eq!(receipt.billing.accounting.usage, Default::default());
    fixture.finish().await.unwrap();
}

#[tokio::test]
async fn context_compaction_resumes_the_original_retry_budget() {
    use pl_core::context::{ContextContent, ContextRecord, ContextSource};
    use pl_core::model::{CancellationToken, Model};
    use pl_core::thread::{
        ContextReplacementReason, ModelStepLimit, ReplaceContext, ThreadError, ThreadHandle,
        TurnInput,
        context_preparation::{
            ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
        },
    };

    #[derive(Debug)]
    struct RemoveOldInput;
    impl ContextPreparationHook for RemoveOldInput {
        async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
            if !request.force_compaction {
                return ContextPreparation::Unchanged;
            }
            let records = request
                .committed_context
                .records
                .iter()
                .filter(|record| record.turn_id.is_some())
                .cloned()
                .collect();
            ContextPreparation::Prepared {
                inputs: Default::default(),
                instruction_binding: None,
                rejected_mutations: Vec::new(),
                replacement: Some(ReplaceContext {
                    expected_revision: request.committed_context.revision,
                    reason: ContextReplacementReason::Compaction,
                    records,
                }),
                facts: request.current_facts.to_vec(),
                mutations: Vec::new(),
                excluded_tool_ids: Vec::new(),
            }
        }
    }

    let fixture = FixtureServer::start((0..6).map(|index| {
        let code = if index == 4 { "context_length_exceeded" } else { "rate_limit_exceeded" };
        Step::prompt(Protocol::ResponsesHttp, "continue", index, Reply::Sse(vec![json!({
            "type": "error", "error": {"code": code, "message": code, "retry_after_ms": 0},
        })]))
    }).collect()).await.unwrap();
    let route = runtime(fixture.base_url(), false);
    let assembled = ModelRuntime::bind(
        route.account_id(),
        route.endpoint().clone(),
        route.model().clone(),
        &pl_model_openai_wire::OPENAI_WIRE_CODEC,
        pl_model_openai::adapter::ADAPTER.error_policy,
        None,
    )
    .unwrap();
    let model = pl_model_runtime::runtime::ThreadModel::new(assembled, None);
    let thread =
        ThreadHandle::start("context-budget".into(), model.open_session().await.unwrap()).unwrap();
    thread
        .replace_context(ReplaceContext {
            expected_revision: 0,
            reason: ContextReplacementReason::Rebuild,
            records: vec![ContextRecord {
                id: "old-input".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![ContextContent::Text {
                    text: "old context ".repeat(200).into(),
                }],
                tool_calls: Vec::new(),
            }],
        })
        .await
        .unwrap();
    thread
        .set_context_preparation(Some(ContextPreparer::new(RemoveOldInput)))
        .await
        .unwrap();
    let result = tokio::time::timeout(
        Duration::from_secs(10),
        thread.run_turn(TurnInput {
            turn_id: "context-turn".into(),
            attempt_prefix: "context-attempt".into(),
            content: vec![ContextContent::Text {
                text: "continue".into(),
            }],
            max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
            cancellation: CancellationToken::new(),
        }),
    )
    .await
    .unwrap()
    .unwrap_err();
    let ThreadError::Model(error) = result else {
        panic!("unexpected result: {result:?}");
    };
    let receipt = pl_model_runtime::runtime::model_failure_receipt(&error)
        .unwrap()
        .unwrap();
    assert_eq!(
        receipt.recovery_stop,
        Some(pl_model_runtime::runtime::ModelRecoveryStopReason::BudgetExhausted)
    );
    assert_eq!(receipt.retry_count, Some(5));
    assert_eq!(fixture.finish().await.unwrap().len(), 6);
    thread.close().await.unwrap();
}

#[tokio::test]
async fn oversized_sse_event_fails_before_unbounded_json_accumulation_or_retry() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}/v1", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut request = Vec::new();
        loop {
            let mut buffer = [0; 4096];
            let count = socket.read(&mut buffer).await.unwrap();
            if count == 0 {
                break;
            }
            request.extend_from_slice(&buffer[..count]);
            if request.windows(4).any(|w| w == b"\r\n\r\n") {
                break;
            }
        }
        socket
            .write_all(
                b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n",
            )
            .await
            .unwrap();
        let prefix = b"data: {\"type\":\"response.output_text.delta\",\"item_id\":\"message-1\",\"delta\":\"";
        let _ = socket.write_all(prefix).await;
        let chunk = [b'X'; 65_536];
        for _ in 0..1024 {
            if socket.write_all(&chunk).await.is_err() {
                return;
            }
        }
        let _ = socket.write_all(b"\"}\n\n").await;
    });
    let failure = runtime(base, false)
        .complete(
            request(),
            ModelInvocationContext::in_memory(ModelSession::default()),
        )
        .await
        .unwrap_err();
    let failure = failure
        .source
        .provider_failure_ref()
        .expect("oversized provider frame");
    assert_eq!(failure.kind, pl_protocol::ProviderFailureKind::Protocol);
    assert_eq!(failure.retry, pl_protocol::RetryDisposition::Permanent);
    server.abort();
    let _ = server.await;
}

fn observed(session: ModelSession) -> (ModelInvocationContext, Arc<tokio::sync::Notify>) {
    let observed = Arc::new(tokio::sync::Notify::new());
    let ready = Arc::clone(&observed);
    let context = ModelInvocationContext::in_memory(session).with_stream_observer(move |_, event| {
        if matches!(event, ModelStreamEvent::BlockDelta { kind: ModelBlockKind::Text { .. }, delta, .. } if !delta.is_empty()) {
            ready.notify_one();
        }
    });
    (context, observed)
}
