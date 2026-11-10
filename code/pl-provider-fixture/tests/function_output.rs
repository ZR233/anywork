use futures::{SinkExt, StreamExt};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use serde_json::json;

#[tokio::test]
async fn responses_rejects_non_json_output_for_schema_declared_functions() {
    for additional_tools in [false, true] {
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp,
            "schema test",
            0,
            Reply::Sse(responses_text("accepted", "answer", "fixture-model")),
        )])
        .await
        .unwrap();
        let declaration = json!({"type":"function","name":"lookup","parameters":{"type":"object"},"output_schema":{"type":"object"}});
        let mut body = json!({
            "stream": true,
            "input": [
                {"type":"message", "role":"user", "content":"schema test"},
                {"type":"function_call", "name":"lookup", "call_id":"call-1", "arguments":"{}"},
                {"type":"function_call_output", "call_id":"call-1", "output":"not JSON"}
            ]
        });
        if additional_tools {
            body["input"].as_array_mut().unwrap().insert(
                0,
                json!({
                    "type":"additional_tools", "role":"developer", "tools":[declaration]
                }),
            );
        } else {
            body["tools"] = json!([declaration]);
        }
        let client = reqwest::Client::new();
        let url = format!("{}/responses", fixture.base_url());
        let rejected = client.post(&url).json(&body).send().await.unwrap();
        assert_eq!(rejected.status(), reqwest::StatusCode::BAD_REQUEST);
        let error: serde_json::Value = rejected.json().await.unwrap();
        assert_eq!(error["error"]["code"], "invalid_value");
        assert!(
            error["error"]["message"]
                .as_str()
                .unwrap()
                .contains("expected a JSON string")
        );

        let items = body["input"].as_array_mut().unwrap();
        items.last_mut().unwrap()["output"] = json!("{\"content\":\"valid\"}");
        let accepted = client.post(&url).json(&body).send().await.unwrap();
        assert_eq!(accepted.status(), reqwest::StatusCode::OK);
        let report = fixture.shutdown().await.unwrap();
        assert_eq!(report.requests.len(), 2);
        assert!(!report.requests[0].accepted);
        assert!(report.requests[1].accepted);
        assert_eq!(report.consumed_steps, 1);
    }
}

#[tokio::test]
async fn websocket_continuation_rejects_non_json_output_from_previous_response() {
    use pl_provider_fixture::RealtimeToolCall;
    use tokio_tungstenite::tungstenite::Message;

    let call = RealtimeToolCall {
        item_id: "ws-item",
        call_id: "ws-call",
        name: "lookup",
        arguments: "{}".into(),
    };
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesWebSocket,
            "ws schema",
            0,
            Reply::WebSocket(pl_provider_fixture::responses_tool_calls(
                "ws-source",
                "fixture-model",
                &[call],
            )),
        ),
        Step::tool_output(
            Protocol::ResponsesWebSocket,
            "ws-call",
            "not JSON",
            1,
            Reply::WebSocket(responses_text("accepted", "ws-done", "fixture-model")),
        ),
    ])
    .await
    .unwrap();
    let (mut socket, _) =
        tokio_tungstenite::connect_async(format!("{}/responses", fixture.ws_url()))
            .await
            .unwrap();
    let tools = json!([{"type":"function","name":"lookup","parameters":{"type":"object"},"output_schema":{"type":"object"}}]);
    socket
        .send(Message::Text(
            json!({
                "type":"response.create", "stream":true,
                "input":[{"type":"message","role":"user","content":"ws schema"}],
                "tools":tools
            })
            .to_string()
            .into(),
        ))
        .await
        .unwrap();
    loop {
        let event: serde_json::Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        if event["type"] == "response.completed" {
            break;
        }
    }
    socket
        .send(Message::Text(
            json!({
                "type":"response.create", "stream":true, "previous_response_id":"ws-source",
                "input":[{"type":"function_call_output","call_id":"ws-call","output":"not JSON"}],
                "tools":tools
            })
            .to_string()
            .into(),
        ))
        .await
        .unwrap();
    let event: serde_json::Value =
        serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(event["type"], "error");
    assert_eq!(event["status"], 400);
    assert_eq!(event["error"]["code"], "invalid_value");
    assert!(
        event["error"]["message"]
            .as_str()
            .unwrap()
            .contains("expected a JSON string")
    );
    let report = fixture.shutdown().await.unwrap();
    assert_eq!(report.requests.len(), 2);
    assert!(report.requests[0].accepted);
    assert!(!report.requests[1].accepted);
    assert_eq!(report.consumed_steps, 1);
}
