//! Loopback transport through the real production host bindings and provider clients.
use axum::{
    Json, Router,
    extract::State,
    http::{HeaderMap, StatusCode, Uri},
    response::IntoResponse,
};
use pl_agent_tool::Tool;
use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
use pl_model::protocol::{
    ProtocolEndpoint,
    deepseek::tools::{ToolsClient, ToolsError, ToolsOptions},
};
use pl_tool::{binding::prepare_native_tool, search::*};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};
#[path = "support/binding_host.rs"]
mod host;

fn context() -> CallContext {
    CallContext {
        thread_id: "search-host".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}
#[derive(Clone, Default)]
struct StateData(Arc<Mutex<Vec<(String, Value)>>>);
struct Server {
    url: String,
    state: StateData,
    task: tokio::task::JoinHandle<()>,
}
impl Server {
    async fn start() -> Self {
        async fn respond(
            State(state): State<StateData>,
            uri: Uri,
            headers: HeaderMap,
            Json(body): Json<Value>,
        ) -> impl IntoResponse {
            assert_eq!(headers["authorization"], "Bearer fixture-key");
            state
                .0
                .lock()
                .unwrap()
                .push((uri.path().into(), body.clone()));
            match uri.path() {
                "/alpha/search" => (
                    StatusCode::OK,
                    Json(json!({"output":"search body","encrypted_output":"opaque","results":[]})),
                ),
                "/v1/tools/search" if body["query"] == "failure" => (
                    StatusCode::BAD_GATEWAY,
                    Json(json!({"error":{"message":"fixture failure"},"observation":"retained"})),
                ),
                "/v1/tools/search" => (
                    StatusCode::OK,
                    Json(
                        json!({"results":[{"url":"https://example.org/","title":"Source","snippet":"excerpt","date":"2026-01-01"}]}),
                    ),
                ),
                "/v1/tools/fetch" => (
                    StatusCode::OK,
                    Json(json!({"content":"fetched body","title":"Page"})),
                ),
                _ => panic!("unexpected endpoint {uri}"),
            }
        }
        let state = StateData::default();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let router = Router::new().fallback(respond).with_state(state.clone());
        let task = tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        Self { url, state, task }
    }
    async fn close(self) {
        self.task.abort();
        assert!(self.task.await.unwrap_err().is_cancelled());
    }
}
fn args(value: Value) -> OpaquePayload {
    OpaquePayload::new("application/json", 1, value.to_string()).unwrap()
}
#[tokio::test]
async fn standalone_search_host_preserves_frozen_options_commands_and_payload() {
    let server = Server::start().await;
    let client = WebSearchClient::new(&SearchEndpoint {
        base_url: server.url.clone(),
        bearer_token: Some("fixture-key".into()),
        http_headers: None,
    })
    .unwrap();
    let options = ThreadSearchOptions {
        model: "search-model".into(),
        settings: pl_tool::search::SearchSettings::from_config(&Default::default()),
        max_output_tokens: Some(512),
    };
    let tool = prepare_native_tool()
        .unwrap()
        .attach(ThreadWebSearchTool::new(client, options));
    let output = tool.execute(args(json!({"search_query":[{"q":"question"}],"find":[{"ref_id":"page","pattern":"text"}]})), context()).await.unwrap();
    assert_eq!(output.payload().format(), "pl.tool.web-search");
    assert_eq!(output.payload().version(), 1);
    assert_eq!(
        serde_json::from_str::<Value>(output.payload().content()).unwrap()["encrypted_output"],
        "opaque"
    );
    let requests = server.state.0.lock().unwrap().clone();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].1["id"], "turn:call");
    assert_eq!(requests[0].1["model"], "search-model");
    assert_eq!(requests[0].1["max_output_tokens"], 512);
    assert_eq!(requests[0].1["commands"]["find"][0]["pattern"], "text");
    assert_eq!(requests[0].1["settings"]["external_web_access"], false);
    server.close().await;
}
#[tokio::test]
async fn deepseek_hosts_keep_real_client_wire_sources_and_observed_failures() {
    let server = Server::start().await;
    let mut endpoint = ProtocolEndpoint::deepseek(Some(server.url.clone()));
    endpoint.bearer_token = Some("fixture-key".into());
    let client = ToolsClient::new(&endpoint, ToolsOptions::default()).unwrap();
    let search = prepare_native_tool()
        .unwrap()
        .attach(ThreadDeepSeekWebSearchTool::new(client.clone()));
    let output = search
        .execute(args(json!({"queries":["question","question"]})), context())
        .await
        .unwrap();
    assert_eq!(output.payload().format(), "pl.tool.deepseek-web-search");
    let value: Value = serde_json::from_str(output.payload().content()).unwrap();
    assert_eq!(value["queries"], json!(["question"]));
    assert_eq!(
        value["responses"][0]["sources"][0]["publishedAt"],
        "2026-01-01"
    );
    let prepared = pl_tool::binding::prepare_registration(
        "deepseek_web_search",
        search.definition(),
        pl_tool::binding::ToolCallPolicy::DirectOnly,
    )
    .unwrap();
    let thread = pl_core::thread::ThreadHandle::start(
        "search-host".into(),
        pl_core::model::DynModelSession::new(host::Calls {
            calls: [(
                "deepseek_web_search".into(),
                json!({"queries":["failure"]}).to_string(),
            )]
            .into(),
            requests: Arc::new(Mutex::new(Vec::new())),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![
            prepared.attach(pl_agent_tool::ToolHandle::new(search)),
        ])
        .await
        .unwrap();
    thread.run_turn(host::turn("failed-search")).await.unwrap();
    let effects = thread.effects().await.unwrap();
    let deliveries: Vec<_> = effects
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .collect();
    assert_eq!(deliveries.len(), 1);
    let pl_core::thread::ToolOutcome::Failed(error) = &deliveries[0].outcome else {
        panic!("provider failure became success")
    };
    assert!(matches!(
        error.source.downcast_ref::<ToolsError>(),
        Some(ToolsError::HttpStatus { status: 502, .. })
    ));
    assert!(
        deliveries[0]
            .output
            .payload()
            .content()
            .contains("retained")
    );
    thread.close().await.unwrap();
    let fetch = prepare_native_tool()
        .unwrap()
        .attach(ThreadDeepSeekWebFetchTool::new(client));
    let output = fetch
        .execute(args(json!({"url":"https://example.org/"})), context())
        .await
        .unwrap();
    assert_eq!(output.payload().format(), "pl.tool.deepseek-web-fetch");
    assert_eq!(
        serde_json::from_str::<Value>(output.payload().content()).unwrap()["content"],
        "fetched body"
    );
    let requests = server.state.0.lock().unwrap().clone();
    assert_eq!(requests.len(), 3);
    assert_eq!(
        requests[0].1,
        json!({"query":"question","count":10,"need_content":false})
    );
    assert_eq!(requests[2].1, json!({"url":"https://example.org/"}));
    server.close().await;
}
