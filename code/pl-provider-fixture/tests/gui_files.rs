use pl_provider_fixture::{FixtureServer, GUI_FILES_PROMPT, GUI_PROMPT, gui_script};
use reqwest::StatusCode;
use serde_json::json;

#[tokio::test]
async fn gui_files_continuation_accepts_the_completed_tool_result() {
    let fixture = FixtureServer::start(gui_script()).await.unwrap();
    let client = reqwest::Client::new();
    for prompt in [GUI_PROMPT, GUI_FILES_PROMPT] {
        let response = client
            .post(format!("{}/responses", fixture.base_url()))
            .json(&json!({
                "stream": true,
                "input": [{"role": "user", "content": prompt}]
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        response.text().await.unwrap();
    }
    let response = client
        .post(format!("{}/responses", fixture.base_url()))
        .json(&json!({
            "stream": true,
            "input": [
                {"role": "user", "content": GUI_FILES_PROMPT},
                {
                    "type": "function_call_output",
                    "call_id": "file-display-call",
                    "output": "File display archived: 3 ready, 0 failed."
                }
            ]
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert!(
        response
            .text()
            .await
            .unwrap()
            .contains("file-display-answer")
    );
    assert_eq!(fixture.finish().await.unwrap().len(), 3);
}
