//! Wire and gate evidence only. These tests do not implement a presentation
//! reducer or claim that Flutter/Core consumed any lifecycle fact.

use super::*;
use futures::{Stream, StreamExt};

#[tokio::test]
async fn image_prompt_requires_three_real_pngs_in_one_input() {
    let mut step = Control::default()
        .script()
        .into_iter()
        .find(|step| matches!(step.request, RequestMatch::PromptImages { .. }))
        .unwrap();
    let RequestMatch::PromptImages { step: ordinal, .. } = &mut step.request else {
        unreachable!()
    };
    *ordinal = 0;
    let fixture = FixtureServer::start(vec![step]).await.unwrap();
    let client = reqwest::Client::new();
    let url = format!("{}/responses", fixture.base_url());
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../anywork");
    let mut content = vec![json!({"type":"input_text","text":IMAGE_PROMPT})];
    for path in [
        "assets/branding/anywork-startup-cat.png",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png",
    ] {
        let bytes = std::fs::read(root.join(path)).unwrap();
        content.push(json!({
            "type":"input_image",
            "image_url":format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes))
        }));
    }
    let valid = json!({
        "model":"fixture-model","stream":true,
        "input":[{"role":"user","content":content}],
    });
    let mut missing = valid.clone();
    missing["input"][0]["content"].as_array_mut().unwrap().pop();
    let mut duplicate = valid.clone();
    duplicate["input"][0]["content"][2] = content[1].clone();
    let mut extra = valid.clone();
    extra["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .push(content[3].clone());
    let mut invalid_data = valid.clone();
    invalid_data["input"][0]["content"][1]["image_url"] = "data:image/png;base64,broken!".into();
    let mut remote_url = valid.clone();
    remote_url["input"][0]["content"][1]["image_url"] = "https://example.invalid/image.png".into();
    let mut wrong_text = valid.clone();
    wrong_text["input"][0]["content"][0]["text"] = "different input".into();
    let mut wrong_order = valid.clone();
    wrong_order["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .swap(1, 2);
    let split = json!({
        "model":"fixture-model","stream":true,
        "input":[
            {"role":"user","content":[{"type":"input_text","text":"earlier input"},content[1]]},
            {"role":"user","content":[content[0],content[2],content[3]]},
        ],
    });
    let historical = json!({
        "model":"fixture-model","stream":true,
        "input":[valid["input"][0], {"role":"user","content":[content[0]]}],
    });
    let rejected = [
        missing,
        duplicate,
        extra,
        invalid_data,
        remote_url,
        wrong_text,
        wrong_order,
        split,
        historical,
    ];
    let rejection_count = rejected.len();
    for request in rejected {
        let response = client.post(&url).json(&request).send().await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        let error: Value = response.json().await.unwrap();
        assert_eq!(error["error"]["code"], "fixture_mismatch");
    }
    let response = client.post(&url).json(&valid).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let wire = response.bytes().await.unwrap();
    // The same fixture step still issues three independent real view_image
    // calls plus the directory-failure call; no additional provider step.
    let observed = events(&wire);
    let calls = observed
        .iter()
        .filter_map(|event| {
            (event["type"] == "response.output_item.done"
                && event["item"]["type"] == "function_call")
                .then_some(&event["item"])
        })
        .collect::<Vec<_>>();
    assert_eq!(calls.len(), 4);
    assert_eq!(calls[0]["call_id"], "concept-image-a");
    assert_eq!(calls[1]["call_id"], "concept-image-b");
    assert_eq!(calls[2]["call_id"], "concept-image-c");
    assert_eq!(calls[3]["call_id"], "concept-image-failed");
    assert_eq!(calls[3]["arguments"], r#"{"path":"."}"#);
    let report = fixture.shutdown().await.unwrap();
    assert_eq!(report.consumed_steps, 1);
    assert_eq!(report.requests.len(), rejection_count + 1);
    assert!(
        report.requests[..rejection_count]
            .iter()
            .all(|request| !request.accepted)
    );
    assert!(report.requests.last().unwrap().accepted);
}

fn control(names: &[&'static str]) -> Control {
    Control {
        names: names.to_vec(),
        stages: names.iter().map(|_| ReplyStage::new()).collect(),
    }
}

fn events(wire: &[u8]) -> Vec<Value> {
    String::from_utf8_lossy(wire)
        .split_inclusive("\n\n")
        .filter(|frame| frame.ends_with("\n\n"))
        .filter_map(|frame| frame.trim().strip_prefix("data: ").map(str::to_owned))
        .filter(|frame| frame != "[DONE]")
        .map(|frame| serde_json::from_str(&frame).unwrap())
        .collect()
}

async fn read_through(
    stream: &mut (impl Stream<Item = reqwest::Result<Bytes>> + Unpin),
    wire: &mut Vec<u8>,
    count: usize,
) -> Vec<Value> {
    while events(wire).len() < count {
        let chunk = tokio::time::timeout(Duration::from_secs(5), stream.next())
            .await
            .expect("provider gate failed to deliver its prefix")
            .expect("provider ended before the expected gate")
            .unwrap();
        wire.extend_from_slice(&chunk);
    }
    let observed = events(wire);
    assert_eq!(observed.len(), count, "a later segment escaped its gate");
    observed
}

async fn observe(control: Control, step: Step, prompt: &str, counts: &[usize]) -> Vec<Value> {
    let names = control.names.clone();
    assert_eq!(names.len(), counts.len());
    let fixture = FixtureServer::start_with_options(
        vec![step],
        FixtureOptions {
            timeline_concept: Some(control),
            ..FixtureOptions::default()
        },
    )
    .await
    .unwrap();
    let client = reqwest::Client::new();
    let base = fixture.base_url();
    let gate = |name: &str| format!("{}/__timeline_concept/{name}", base.trim_end_matches("/v1"));
    // An observer cannot manufacture a reached stage by releasing it early.
    assert_eq!(
        client.post(gate(names[0])).send().await.unwrap().status(),
        StatusCode::CONFLICT
    );
    let response = client
        .post(format!("{base}/responses"))
        .json(&json!({
            "model":"fixture-model", "stream":true,
            "input":[{"role":"user","content":[{"type":"input_text","text":prompt}]}],
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let mut stream = response.bytes_stream();
    let mut wire = Vec::new();
    for (index, name) in names.iter().enumerate() {
        assert_eq!(
            client.get(gate(name)).send().await.unwrap().status(),
            StatusCode::NO_CONTENT
        );
        read_through(&mut stream, &mut wire, counts[index]).await;
        if let Some(next) = names.get(index + 1) {
            assert_eq!(
                client.post(gate(next)).send().await.unwrap().status(),
                StatusCode::CONFLICT
            );
        }
        assert_eq!(
            client.post(gate(name)).send().await.unwrap().status(),
            StatusCode::NO_CONTENT
        );
        assert_eq!(
            client.post(gate(name)).send().await.unwrap().status(),
            StatusCode::CONFLICT
        );
    }
    while let Some(chunk) = tokio::time::timeout(Duration::from_secs(5), stream.next())
        .await
        .expect("released provider response did not finish")
    {
        wire.extend_from_slice(&chunk.unwrap());
    }
    let requests = fixture.finish().await.unwrap();
    assert_eq!(requests.len(), 1);
    assert!(requests[0].accepted);
    assert!(String::from_utf8_lossy(&wire).ends_with("data: [DONE]\n\n"));
    events(&wire)
}

#[tokio::test]
async fn a07_keeps_reasoning_active_until_after_readable_text_and_text_terminal() {
    let control = control(OVERLAP_STAGES);
    let step = control.overlap_step(0);
    let observed = observe(control, step, OVERLAP_PROMPT, &[3, 5, 6, 7, 8]).await;
    assert_eq!(observed.len(), 9);
    assert_eq!(observed[1]["item"]["type"], "reasoning");
    assert_eq!(observed[3]["type"], "response.output_item.added");
    assert_eq!(observed[3]["item"]["id"], "concept-a07-text");
    assert_eq!(observed[4]["item_id"], "concept-a07-text");
    assert_eq!(observed[5]["item_id"], "concept-a07-text");
    assert_eq!(
        format!(
            "{}{}",
            observed[4]["delta"].as_str().unwrap(),
            observed[5]["delta"].as_str().unwrap()
        ),
        OVERLAP_TEXT
    );
    assert_eq!(observed[6], text_done("concept-a07-text", 1, OVERLAP_TEXT));
    assert_eq!(observed[7]["type"], "response.output_item.done");
    assert_eq!(observed[7]["item"]["id"], "concept-a07-reason");
    assert_eq!(observed[8]["type"], "response.completed");
}

#[tokio::test]
async fn a14_empty_text_lifecycle_separates_two_real_reasoning_identities() {
    let control = control(EMPTY_TEXT_STAGES);
    let step = control.empty_text_step(0);
    let observed = observe(control, step, EMPTY_TEXT_PROMPT, &[4, 6, 8, 11, 13, 14]).await;
    assert_eq!(observed.len(), 15);
    assert_eq!(observed[3]["item"]["id"], "concept-a14-work-a");
    assert_eq!(observed[4]["type"], "response.output_item.added");
    assert_eq!(observed[4]["item"]["id"], "concept-a14-empty");
    assert_eq!(observed[5]["type"], "response.content_part.added");
    assert_eq!(observed[5]["part"]["text"], "");
    assert_eq!(observed[6]["type"], "response.content_part.done");
    assert_eq!(observed[6]["item_id"], observed[5]["item_id"]);
    assert_eq!(observed[7], text_done("concept-a14-empty", 1, ""));
    assert_eq!(observed[8]["item"]["id"], "concept-a14-work-b");
    assert_ne!(observed[3]["item"]["id"], observed[8]["item"]["id"]);
    assert!(!observed.iter().any(|event| {
        event["type"] == "response.output_text.delta" && event["item_id"] == "concept-a14-empty"
    }));
    assert_eq!(
        observed[13],
        text_done("concept-a14-text", 3, EMPTY_TEXT_ANSWER)
    );
    assert_eq!(observed[14]["type"], "response.completed");
}
