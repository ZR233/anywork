//! Wire and gate evidence only. These tests do not implement a presentation
//! reducer or claim that Flutter/Core consumed any lifecycle fact.

use super::*;
use futures::{Stream, StreamExt};

#[tokio::test]
async fn realtime_scope_strict_wire_preserves_full_and_focus_steps() {
    for scope in [RealtimeScope::Full, RealtimeScope::StopBackground] {
        for title_before in [false, true] {
            let mut expected = Vec::new();
            if scope == RealtimeScope::Full {
                expected.extend([
                    GUI_REALTIME_DELAYED_PROMPT.to_owned(),
                    GUI_REALTIME_REASONING_PROMPT.to_owned(),
                    GUI_REALTIME_LONG_COMMAND_PROMPT.to_owned(),
                    GUI_REALTIME_LONG_COMMAND_PROMPT.to_owned(),
                    realtime_delivery_marker("realtime-long-call"),
                ]);
            }
            expected.extend([
                GUI_REALTIME_PARALLEL_PROMPT.to_owned(),
                GUI_REALTIME_PARALLEL_PROMPT.to_owned(),
                realtime_delivery_marker("realtime-parallel-call-a"),
                realtime_delivery_marker("realtime-parallel-call-b"),
            ]);
            if scope == RealtimeScope::Full {
                expected.extend([
                    GUI_REALTIME_HOST_CWD_PROMPT.to_owned(),
                    GUI_REALTIME_HOST_CWD_PROMPT.to_owned(),
                    realtime_delivery_marker("realtime-host-cwd-call"),
                    GUI_REALTIME_ERROR_PROMPT.to_owned(),
                ]);
            }
            expected.extend([
                GUI_REALTIME_CANCEL_PROMPT.to_owned(),
                GUI_REALTIME_RESUME_PROMPT.to_owned(),
            ]);
            let steps = gui_realtime_script("fixture-host-cwd", None, scope);
            assert_eq!(
                steps.iter().filter(|step| !step.optional).count(),
                expected.len()
            );
            assert_eq!(
                expected.len(),
                match scope {
                    RealtimeScope::Full => 15,
                    RealtimeScope::StopBackground => REALTIME_STOP_BACKGROUND_REQUIRED_STEPS,
                }
            );
            for (index, step) in steps.iter().enumerate() {
                let (RequestMatch::Prompt { step: actual, .. }
                | RequestMatch::Delivery { step: actual, .. }) = &step.request
                else {
                    panic!("unexpected realtime request");
                };
                assert_eq!(
                    *actual, index,
                    "optional titles retain physical step indices"
                );
            }
            let first = expected.first().unwrap();
            let title = session_title_prompt(first);
            let fixture = FixtureServer::start(steps).await.unwrap();
            let client = reqwest::Client::new();
            let url = format!("{}/responses", fixture.base_url());
            let send =
                |text: String| {
                    client.post(&url).json(&json!({
                    "model": "fixture-model", "stream": true,
                    "input": [{"role":"user","content":[{"type":"input_text","text":text}]}],
                })).send()
                };
            let mut rejected = 0;
            if scope == RealtimeScope::StopBackground {
                let response = send(GUI_REALTIME_DELAYED_PROMPT.to_owned()).await.unwrap();
                assert_eq!(response.status(), StatusCode::BAD_REQUEST);
                rejected += 1;
            }
            if title_before {
                assert_eq!(send(title.clone()).await.unwrap().status(), StatusCode::OK);
            }
            for (index, text) in expected.iter().enumerate() {
                if text == &realtime_delivery_marker("realtime-parallel-call-a") {
                    let response = send(text.replace("Succeeded", "Failed")).await.unwrap();
                    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
                    rejected += 1;
                }
                let response = send(text.clone()).await.unwrap();
                assert_eq!(
                    response.status(),
                    if text == GUI_REALTIME_ERROR_PROMPT {
                        StatusCode::BAD_REQUEST
                    } else {
                        StatusCode::OK
                    },
                    "{scope:?} request {index}"
                );
                // This test exercises strict request admission, not the manual
                // text pacing. Drain the final continuation; drop other bodies,
                // including the real hanging cancel stream, as a consumer can.
                if text == GUI_REALTIME_RESUME_PROMPT {
                    assert!(
                        response
                            .text()
                            .await
                            .unwrap()
                            .contains("realtime continued after cancel")
                    );
                } else {
                    drop(response);
                }
                if index == 0 && !title_before {
                    assert_eq!(send(title.clone()).await.unwrap().status(), StatusCode::OK);
                }
            }
            let report = fixture.shutdown().await.unwrap();
            assert_eq!(report.consumed_steps, report.expected_steps);
            assert!(
                report.verify().is_err(),
                "intentional strict rejects must fail acceptance"
            );
            let requests = report.requests;
            assert_eq!(
                requests.iter().filter(|request| request.accepted).count(),
                expected.len() + 1
            );
            assert_eq!(
                requests.iter().filter(|request| !request.accepted).count(),
                rejected
            );
        }
    }
}

fn input_content(text: Option<&str>) -> Vec<Value> {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../anywork");
    let mut content = text
        .into_iter()
        .map(|text| json!({"type":"input_text","text":text}))
        .collect::<Vec<_>>();
    for (index, path) in [
        "assets/branding/anywork-startup-cat.png",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png",
    ]
    .into_iter()
    .enumerate()
    {
        content.push(json!({
            "type":"input_text",
            "text":format!("Attachment: {}", INPUT_IMAGES[index].0),
        }));
        content.push(json!({
            "type":"input_image",
            "image_url":format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(std::fs::read(root.join(path)).unwrap())),
        }));
    }
    content
}

#[test]
fn media_handoff_pure_attachment_matcher_rejects_prefix_history_order_and_hash_drift() {
    let steps = Control::default().media_handoff_script();
    let RequestMatch::PromptImages { text, images, .. } = &steps[0].request else {
        panic!("first media step must match the pure attachment input");
    };
    assert!(text.is_none());
    let content = input_content(None);
    assert_eq!(content.len(), 6);
    let valid =
        json!({"model":"fixture-model","stream":true,"input":[{"role":"user","content":content}]});
    assert!(prompt_images_match(&valid, None, images));
    assert!(!prompt_images_match(&valid, Some(IMAGE_PROMPT), images));
    let mut malformed = Vec::new();
    for prefix in ["", IMAGE_PROMPT] {
        let mut body = valid.clone();
        body["input"][0]["content"]
            .as_array_mut()
            .unwrap()
            .insert(0, json!({"type":"input_text","text":prefix}));
        malformed.push(body);
    }
    let mut missing = valid.clone();
    missing["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .truncate(4);
    malformed.push(missing);
    let mut extra = valid.clone();
    extra["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .extend_from_slice(&content[..2]);
    malformed.push(extra);
    let mut order = valid.clone();
    order["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .swap(1, 3);
    malformed.push(order);
    let mut duplicate = valid.clone();
    duplicate["input"][0]["content"][3] = content[1].clone();
    malformed.push(duplicate);
    let mut filename = valid.clone();
    filename["input"][0]["content"][0]["text"] = "Attachment: concept-input-a.png.bak".into();
    malformed.push(filename);
    let mut corrupt = valid.clone();
    corrupt["input"][0]["content"][1]["image_url"] = "data:image/png;base64,broken!".into();
    malformed.push(corrupt);
    malformed
        .push(json!({"stream":true,"input":[valid["input"][0], {"role":"user","content":[]}]}));
    malformed.push(json!({"stream":true,"input":[
        {"role":"user","content":content[..2]},
        {"role":"user","content":content[2..]},
    ]}));
    for body in malformed {
        assert!(!prompt_images_match(&body, None, images), "{body}");
    }
    let text_body = json!({"stream":true,"input":[{"role":"user","content":input_content(Some(IMAGE_PROMPT))}]});
    assert!(prompt_images_match(&text_body, Some(IMAGE_PROMPT), images));
    let stale_text = json!({"stream":true,"input":[text_body["input"][0],{"role":"user","content":input_content(Some("new prompt"))}]});
    assert!(!prompt_images_match(
        &stale_text,
        Some(IMAGE_PROMPT),
        images
    ));
}

#[test]
fn image_prompt_matcher_requires_boolean_stream_true_for_both_prefixes() {
    let steps = Control::default().media_handoff_script();
    let RequestMatch::PromptImages { images, .. } = &steps[0].request else {
        panic!("first media step must match the attachment input");
    };
    for prefix in [None, Some(IMAGE_PROMPT)] {
        let valid = json!({
            "model":"fixture-model","stream":true,
            "input":[{"role":"user","content":input_content(prefix)}],
        });
        assert!(prompt_images_match(&valid, prefix, images));
        let mut missing = valid.clone();
        missing.as_object_mut().unwrap().remove("stream");
        assert!(
            !prompt_images_match(&missing, prefix, images),
            "missing stream must fail for {prefix:?}"
        );
        for stream in [json!(false), Value::Null, json!("true"), json!(1)] {
            let mut invalid = valid.clone();
            invalid["stream"] = stream;
            assert!(
                !prompt_images_match(&invalid, prefix, images),
                "stream {:?} must fail for {prefix:?}",
                invalid["stream"]
            );
        }
    }
}

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
    for (index, path) in [
        "assets/branding/anywork-startup-cat.png",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png",
    ]
    .into_iter()
    .enumerate()
    {
        let bytes = std::fs::read(root.join(path)).unwrap();
        content.push(json!({
            "type":"input_text",
            "text":format!("Attachment: concept-input-{}.png", ['a', 'b', 'c'][index])
        }));
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
    duplicate["input"][0]["content"][4] = content[2].clone();
    let mut extra = valid.clone();
    extra["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .push(content[6].clone());
    let mut invalid_data = valid.clone();
    invalid_data["input"][0]["content"][2]["image_url"] = "data:image/png;base64,broken!".into();
    let mut remote_url = valid.clone();
    remote_url["input"][0]["content"][2]["image_url"] = "https://example.invalid/image.png".into();
    let mut wrong_text = valid.clone();
    wrong_text["input"][0]["content"][0]["text"] = "different input".into();
    let mut wrong_order = valid.clone();
    wrong_order["input"][0]["content"]
        .as_array_mut()
        .unwrap()
        .swap(2, 4);
    let mut wrong_caption = valid.clone();
    wrong_caption["input"][0]["content"][1]["text"] = "Attachment: wrong.png".into();
    let captionless = json!({
        "model":"fixture-model","stream":true,
        "input":[{"role":"user","content":[content[0],content[2],content[4],content[6]]}],
    });
    let split = json!({
        "model":"fixture-model","stream":true,
        "input":[
            {"role":"user","content":[{"type":"input_text","text":"earlier input"},content[1],content[2]]},
            {"role":"user","content":[content[0],content[3],content[4],content[5],content[6]]},
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
        wrong_caption,
        captionless,
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

#[tokio::test]
async fn tool_images_require_originals_and_call_bound_deliveries() {
    let fixture = FixtureServer::start(vec![tool_images_step()])
        .await
        .unwrap();
    let valid = tool_images_request();
    let items = valid["input"].as_array().unwrap();
    let mut missing_result = valid.clone();
    missing_result["input"].as_array_mut().unwrap().remove(0);
    let mut missing_media = valid.clone();
    missing_media["input"][4]["content"]
        .as_array_mut()
        .unwrap()
        .pop();
    let mut wrong_call = valid.clone();
    wrong_call["input"][0]["call_id"] = "unrelated-call".into();
    let mut wrong_label = valid.clone();
    wrong_label["input"][4]["content"][0]["text"] = "Image from view_image call unrelated".into();
    let mut wrong_bytes = valid.clone();
    wrong_bytes["input"][4]["content"][1]["image_url"] = "data:image/png;base64,broken!".into();
    let mut extra_media = valid.clone();
    extra_media["input"][4]["content"]
        .as_array_mut()
        .unwrap()
        .push(items[4]["content"][1].clone());
    let mut no_failure = valid.clone();
    no_failure["input"][3]["output"] = "".into();
    let mut duplicate_result = valid.clone();
    duplicate_result["input"]
        .as_array_mut()
        .unwrap()
        .insert(1, items[0].clone());
    let mut wrong_order = valid.clone();
    wrong_order["input"][4]["content"]
        .as_array_mut()
        .unwrap()
        .swap(0, 2);
    let mut historical = valid.clone();
    historical["input"].as_array_mut().unwrap().push(json!({
        "role":"user","content":[{"type":"input_text","text":"later unrelated input"}]
    }));
    let rejected = [
        missing_result,
        missing_media,
        wrong_call,
        wrong_label,
        wrong_bytes,
        extra_media,
        no_failure,
        duplicate_result,
        wrong_order,
        historical,
    ];
    let rejection_count = rejected.len();
    let client = reqwest::Client::new();
    let url = format!("{}/responses", fixture.base_url());
    for request in rejected {
        let response = client.post(&url).json(&request).send().await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
    let response = client.post(&url).json(&valid).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert!(
        String::from_utf8(response.bytes().await.unwrap().to_vec())
            .unwrap()
            .contains(IMAGE_DONE)
    );
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

fn tool_images_step() -> Step {
    let mut step = Control::default()
        .script()
        .into_iter()
        .find(|step| matches!(step.request, RequestMatch::ToolImages { .. }))
        .unwrap();
    let RequestMatch::ToolImages { step: ordinal, .. } = &mut step.request else {
        unreachable!()
    };
    *ordinal = 0;
    step.reply = Reply::Sse(responses_text(IMAGE_DONE, "images-done", "fixture-model"));
    step
}

fn tool_images_request() -> Value {
    let bytes = std::fs::read(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../anywork/integration_test/fixtures/tool-image.png"),
    )
    .unwrap();
    let digest = hex::encode(Sha256::digest(&bytes));
    let mut items = Vec::new();
    let mut media = Vec::new();
    for call in ["concept-image-a", "concept-image-b", "concept-image-c"] {
        items.push(json!({"type":"function_call_output","call_id":call,"output":""}));
        media.push(json!({
            "type":"input_text",
            "text":format!("Image from view_image call {call}: pl.studio.resource:{digest}")
        }));
        media.push(json!({
            "type":"input_image",
            "image_url":format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(&bytes))
        }));
    }
    items.push(json!({
        "type":"function_call_output","call_id":"concept-image-failed",
        "output":"tool execution failed: view_image: image source is not a regular file"
    }));
    items.push(json!({"role":"user","content":media}));
    json!({"model":"fixture-model","stream":true,"input":items})
}

#[tokio::test]
async fn tool_images_wait_for_their_own_background_png_without_advancing() {
    let fixture = FixtureServer::start(vec![tool_images_step()])
        .await
        .unwrap();
    let mut pending = tool_images_request();
    let image = pending["input"][4]["content"][1].clone();
    pending["input"][0]["output"] = tool_running_receipt("concept-image-a").into();
    pending["input"][4]["content"]
        .as_array_mut()
        .unwrap()
        .drain(..2);
    let client = reqwest::Client::new();
    let url = format!("{}/responses", fixture.base_url());
    let response = client.post(&url).json(&pending).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let wire = response.bytes().await.unwrap();
    let observed = events(&wire);
    let wait = observed
        .iter()
        .find(|event| {
            event["type"] == "response.output_item.done" && event["item"]["type"] == "function_call"
        })
        .unwrap();
    assert_eq!(wait["item"]["name"], "wait");
    let arguments: Value =
        serde_json::from_str(wait["item"]["arguments"].as_str().unwrap()).unwrap();
    assert_eq!(arguments["taskIds"], json!(["task:concept-image-a"]));
    assert!(!String::from_utf8_lossy(&wire).contains(IMAGE_DONE));

    let delivery = json!({"role":"user","content":[
        {"type":"input_text","text":"Task task:concept-image-a for tool view_image finished: Succeeded."},
        image
    ]});
    let mut complete = pending.clone();
    complete["input"]
        .as_array_mut()
        .unwrap()
        .push(delivery.clone());
    let mut wrong_task = complete.clone();
    wrong_task["input"][5]["content"][0]["text"] =
        "Task task:unrelated for tool view_image finished: Succeeded.".into();
    let mut missing_png = complete.clone();
    missing_png["input"][5]["content"]
        .as_array_mut()
        .unwrap()
        .pop();
    let mut wrong_png = complete.clone();
    wrong_png["input"][5]["content"][1]["image_url"] = "data:image/png;base64,broken!".into();
    let mut failed = complete.clone();
    failed["input"][5]["content"][0]["text"] =
        "Task task:concept-image-a for tool view_image finished: Failed.".into();
    let mut wrong_notice_type = complete.clone();
    wrong_notice_type["input"][5]["content"][0]["type"] = "input_image".into();
    let mut split_payload = complete.clone();
    split_payload["input"][5]["content"]
        .as_array_mut()
        .unwrap()
        .pop();
    split_payload["input"].as_array_mut().unwrap().push(json!({
        "role":"user","content":[
            {"type":"input_text","text":"Task task:unrelated for tool view_image finished: Succeeded."},
            image
        ]
    }));
    let mut duplicate = complete.clone();
    duplicate["input"].as_array_mut().unwrap().push(delivery);
    let mut historical = complete.clone();
    historical["input"].as_array_mut().unwrap().push(json!({
        "role":"user","content":[{"type":"input_text","text":"later unrelated input"}]
    }));
    let mut forged_media_tail = complete.clone();
    forged_media_tail["input"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "role":"user","content":[
                {"type":"input_text","text":"Image from view_image call concept-image-b: unrelated"}
            ]
        }));
    let mut forged_task_tail = complete.clone();
    forged_task_tail["input"].as_array_mut().unwrap().push(json!({
        "role":"user","content":[
            {"type":"input_text","text":"Task task:concept-image-b for tool view_image finished: Succeeded."}
        ]
    }));
    let mut exhausted = pending.clone();
    for index in 0..32 {
        exhausted["input"].as_array_mut().unwrap().push(json!({
            "type":"function_call","call_id":format!("scroll-wait-0-{index}"),
            "name":"wait","arguments":wait["item"]["arguments"]
        }));
    }
    let rejected = [
        wrong_task,
        missing_png,
        wrong_png,
        failed,
        wrong_notice_type,
        split_payload,
        duplicate,
        historical,
        forged_media_tail,
        forged_task_tail,
        exhausted,
    ];
    let rejection_count = rejected.len();
    for request in rejected {
        let response = client.post(&url).json(&request).send().await.unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
    let response = client.post(&url).json(&complete).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert!(
        String::from_utf8(response.bytes().await.unwrap().to_vec())
            .unwrap()
            .contains(IMAGE_DONE)
    );
    let report = fixture.shutdown().await.unwrap();
    assert_eq!(report.consumed_steps, 1);
    assert_eq!(report.requests.len(), rejection_count + 2);
    assert!(report.requests[0].accepted);
    assert!(
        report.requests[1..=rejection_count]
            .iter()
            .all(|request| !request.accepted)
    );
    assert!(report.requests.last().unwrap().accepted);
}

#[tokio::test]
async fn tool_image_background_completions_keep_call_identity_not_completion_order() {
    let fixture = FixtureServer::start(vec![tool_images_step()])
        .await
        .unwrap();
    let mut body = tool_images_request();
    let media = body["input"].as_array_mut().unwrap().pop().unwrap();
    for index in 0..3 {
        let call = body["input"][index]["call_id"].as_str().unwrap();
        body["input"][index]["output"] = tool_running_receipt(call).into();
    }
    body["input"].as_array_mut().unwrap().insert(
        0,
        json!({
            "role":"user","content":[{"type":"input_text","text":IMAGE_PROMPT}]
        }),
    );
    let client = reqwest::Client::new();
    let url = format!("{}/responses", fixture.base_url());
    let response = client.post(&url).json(&body).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let wire = response.bytes().await.unwrap();
    let observed = events(&wire);
    let wait = observed
        .iter()
        .find(|event| {
            event["type"] == "response.output_item.done" && event["item"]["name"] == "wait"
        })
        .unwrap();
    let arguments: Value =
        serde_json::from_str(wait["item"]["arguments"].as_str().unwrap()).unwrap();
    assert_eq!(
        arguments["taskIds"],
        json!([
            "task:concept-image-a",
            "task:concept-image-b",
            "task:concept-image-c"
        ])
    );
    assert!(!String::from_utf8_lossy(&wire).contains(IMAGE_DONE));
    for index in [2, 0, 1] {
        let call = ["concept-image-a", "concept-image-b", "concept-image-c"][index];
        body["input"].as_array_mut().unwrap().push(json!({"role":"user","content":[
            {"type":"input_text","text":format!("Task task:{call} for tool view_image finished: Succeeded.")},
            media["content"][index * 2 + 1]
        ]}));
    }
    let response = client.post(&url).json(&body).send().await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert!(String::from_utf8_lossy(&response.bytes().await.unwrap()).contains(IMAGE_DONE));
    let report = fixture.shutdown().await.unwrap();
    assert_eq!(report.consumed_steps, 1);
    assert_eq!(report.requests.len(), 2);
    assert!(report.requests.iter().all(|request| request.accepted));
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
    observe_script(control, vec![step], prompt, counts).await
}

async fn observe_script(
    control: Control,
    steps: Vec<Step>,
    prompt: &str,
    counts: &[usize],
) -> Vec<Value> {
    let names = control.names.clone();
    assert_eq!(names.len(), counts.len());
    let fixture = FixtureServer::start_with_options(
        steps,
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
async fn realtime_text_gates_preserve_the_first_token_and_terminal_body() {
    let control = Control::realtime();
    let delayed = control
        .realtime_script("fixture-host-cwd", RealtimeScope::Full)
        .into_iter()
        .find(|step| {
            matches!(&step.request, RequestMatch::Prompt { text, .. } if text == GUI_REALTIME_DELAYED_PROMPT)
        })
        .unwrap();
    let observer = Control {
        names: control.names[..2].to_vec(),
        stages: control.stages[..2].to_vec(),
    };
    let step = Step::prompt(
        Protocol::ResponsesHttp,
        GUI_REALTIME_DELAYED_PROMPT,
        0,
        delayed.reply,
    );
    let observed = observe(observer, step, GUI_REALTIME_DELAYED_PROMPT, &[1, 3]).await;
    assert_eq!(observed.len(), 8);
    assert_eq!(observed[0]["type"], "response.created");
    assert_eq!(observed[2]["type"], "response.output_text.delta");
    assert_eq!(observed[2]["delta"], "realtime ");
    assert_eq!(observed[6]["type"], "response.output_item.done");
    assert_eq!(
        observed[6]["item"]["content"][0]["text"],
        "realtime delayed first token"
    );
    assert_eq!(observed[7]["type"], "response.completed");
}

#[tokio::test]
async fn realtime_observer_gate_precedes_both_original_parallel_calls() {
    for scope in [RealtimeScope::Full, RealtimeScope::StopBackground] {
        let control = Control::realtime();
        let parallel = control
            .realtime_script("fixture-host-cwd", scope)
            .into_iter()
            .find(|step| {
                matches!(
                    &step.request,
                    RequestMatch::Prompt { text, .. } if text == GUI_REALTIME_PARALLEL_PROMPT
                )
            })
            .expect("realtime observation must have its explicit gate");
        let step = Step::prompt(
            Protocol::ResponsesHttp,
            GUI_REALTIME_PARALLEL_PROMPT,
            0,
            parallel.reply,
        );
        let observer = Control {
            names: vec![control.names[2]],
            stages: vec![control.stages[2].clone()],
        };
        // The real HTTP observer sees only created/added/delta/done reasoning before
        // release. observe also rejects premature or repeated release requests.
        let observed = observe(observer, step, GUI_REALTIME_PARALLEL_PROMPT, &[4]).await;
        assert_eq!(observed[3]["item"]["type"], "reasoning");
        assert_eq!(
            observed[3]["item"]["summary"][0]["text"],
            "realtime parallel observers ready"
        );
        let calls = observed
            .iter()
            .filter(|event| {
                event["type"] == "response.output_item.done"
                    && event["item"]["type"] == "function_call"
            })
            .map(|event| &event["item"])
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 2);
        for (call, tag, lines) in [
            (&calls[0], "a", GUI_REALTIME_PARALLEL_A_OUTPUT_LINES),
            (&calls[1], "b", GUI_REALTIME_PARALLEL_B_OUTPUT_LINES),
        ] {
            assert_eq!(call["call_id"], format!("realtime-parallel-call-{tag}"));
            assert_eq!(call["name"], TOOL_EXEC_NAME);
            assert_eq!(
                call["arguments"],
                realtime_exec_arguments(&realtime_parallel_command(tag, lines), None)
            );
        }
    }
}

#[tokio::test]
async fn realtime_first_reply_holds_waiting_and_live_text_phases() {
    let control = Control::realtime();
    let first = control
        .realtime_script("fixture-host-cwd", RealtimeScope::Full)
        .into_iter()
        .find(|step| {
            matches!(&step.request, RequestMatch::Prompt { text, .. } if text == GUI_REALTIME_DELAYED_PROMPT)
        })
        .expect("first realtime prompt must exist");
    let Reply::SegmentedSse { segments, .. } = &first.reply else {
        panic!("first realtime response must hold both observation phases");
    };
    assert!(!segments[0].is_empty());
    assert!(segments[0].iter().all(|event| {
        event["type"] != "response.output_item.added"
            && event["type"] != "response.output_text.delta"
    }));
    let first_text = segments[1].last().unwrap();
    assert_eq!(first_text["type"], "response.output_text.delta");
    assert!(!first_text["delta"].as_str().unwrap().is_empty());
    let prefix_events = [segments[0].len(), segments[0].len() + segments[1].len()];
    let observer = Control {
        names: control.names[..2].to_vec(),
        stages: control.stages[..2].to_vec(),
    };
    let step = Step::prompt(
        Protocol::ResponsesHttp,
        GUI_REALTIME_DELAYED_PROMPT,
        0,
        first.reply,
    );
    let observed = observe(observer, step, GUI_REALTIME_DELAYED_PROMPT, &prefix_events).await;
    assert!(
        observed
            .iter()
            .any(|event| event["type"] == "response.completed"),
        "release must deliver the original terminal event"
    );
    assert_eq!(
        control.names,
        [
            "realtime-first-token",
            "realtime-text-readable",
            "realtime-parallel-observer",
            "realtime-background-result",
            "realtime-host-cwd-observer"
        ]
    );
}

#[tokio::test]
async fn realtime_background_gate_keeps_reasoning_open_before_original_wait_b() {
    for scope in [RealtimeScope::Full, RealtimeScope::StopBackground] {
        let control = Control::realtime();
        let delivery = control
            .realtime_script("fixture-host-cwd", scope)
            .into_iter()
            .find(|step| {
                matches!(&step.request, RequestMatch::Delivery { marker, .. }
                if marker == &realtime_delivery_marker("realtime-parallel-call-a"))
            })
            .expect("the observer must follow A's real independent delivery");
        let observer = Control {
            names: vec![control.names[3]],
            stages: vec![control.stages[3].clone()],
        };
        // Exercise the original reply through the real HTTP gate/stream helper.
        // The prompt wrapper only isolates this reply from preceding script steps.
        let step = Step::prompt(
            Protocol::ResponsesHttp,
            GUI_REALTIME_PARALLEL_PROMPT,
            0,
            delivery.reply,
        );
        let observed = observe(observer, step, GUI_REALTIME_PARALLEL_PROMPT, &[3]).await;
        assert_eq!(observed.len(), 8);
        assert_eq!(observed[1]["item"]["type"], "reasoning");
        assert_eq!(observed[2]["type"], "response.reasoning_summary_text.delta");
        assert!(observed[..3].iter().all(|event| {
            event["type"] != "response.output_item.done" && event["type"] != "response.completed"
        }));
        assert_eq!(observed[3]["item"]["type"], "reasoning");
        assert_eq!(observed[3]["type"], "response.output_item.done");
        assert_eq!(
            observed[6]["item"]["call_id"],
            "realtime-parallel-wait-b-call"
        );
        assert_eq!(observed[6]["item"]["name"], TOOL_WAIT_NAME);
        assert_eq!(
            observed[6]["item"]["arguments"],
            realtime_wait_arguments(&["realtime-parallel-call-b"])
        );
        assert_eq!(observed[7]["type"], "response.completed");
    }
}

#[tokio::test]
async fn realtime_observer_gate_precedes_original_host_cwd_call() {
    let host_cwd = "fixture-host-cwd";
    let control = Control::realtime();
    let host = control
        .realtime_script(host_cwd, RealtimeScope::Full)
        .into_iter()
        .find(|step| {
            matches!(&step.request, RequestMatch::Prompt { text, .. } if text == GUI_REALTIME_HOST_CWD_PROMPT)
        })
        .expect("host-cwd observation must have its original prompt");
    let step = Step::prompt(
        Protocol::ResponsesHttp,
        GUI_REALTIME_HOST_CWD_PROMPT,
        0,
        host.reply,
    );
    let observer = Control {
        names: vec![control.names[4]],
        stages: vec![control.stages[4].clone()],
    };
    let observed = observe(observer, step, GUI_REALTIME_HOST_CWD_PROMPT, &[4]).await;
    assert_eq!(observed.len(), 8);
    assert_eq!(observed[3]["type"], "response.output_item.done");
    assert_eq!(observed[3]["item"]["type"], "reasoning");
    assert_eq!(
        observed[3]["item"]["summary"][0]["text"],
        "realtime host cwd observers ready"
    );
    assert_eq!(observed[4]["type"], "response.output_item.added");
    assert_eq!(observed[4]["item"]["type"], "function_call");
    let calls = observed
        .iter()
        .filter(|event| {
            event["type"] == "response.output_item.done" && event["item"]["type"] == "function_call"
        })
        .map(|event| &event["item"])
        .collect::<Vec<_>>();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0]["id"], "realtime-host-cwd-item");
    assert_eq!(calls[0]["call_id"], "realtime-host-cwd-call");
    assert_eq!(calls[0]["name"], TOOL_EXEC_NAME);
    assert_eq!(
        calls[0]["arguments"],
        realtime_exec_arguments(&realtime_host_cwd_command(), Some(host_cwd))
    );
    assert_eq!(observed[7]["type"], "response.completed");
}

#[tokio::test]
async fn a07_completes_b_then_readable_text_then_the_earlier_a() {
    let control = Control::boundary();
    let steps = control.boundary_script();
    assert_eq!(
        steps.iter().filter(|step| !step.optional).count(),
        1,
        "one real A07 request and no unrelated journey requests"
    );
    let observed = observe_script(control, steps, OVERLAP_PROMPT, &[3, 6, 8, 9, 10, 11]).await;
    assert_eq!(observed.len(), 12);
    assert_eq!(observed[1]["item"]["type"], "reasoning");
    assert_eq!(observed[3]["type"], "response.output_item.added");
    assert_eq!(observed[3]["item"]["id"], "concept-a07-reason-b");
    assert_eq!(
        observed[5],
        reasoning_done("concept-a07-reason-b", 1, OVERLAP_EARLY_REASONING)
    );
    assert_eq!(observed[6]["item"]["id"], "concept-a07-text");
    assert_eq!(observed[7]["item_id"], "concept-a07-text");
    assert_eq!(observed[8]["item_id"], "concept-a07-text");
    assert_eq!(
        format!(
            "{}{}",
            observed[7]["delta"].as_str().unwrap(),
            observed[8]["delta"].as_str().unwrap()
        ),
        OVERLAP_TEXT
    );
    assert_eq!(observed[9], text_done("concept-a07-text", 2, OVERLAP_TEXT));
    assert_eq!(observed[10]["type"], "response.output_item.done");
    assert_eq!(observed[10]["item"]["id"], "concept-a07-reason");
    assert_eq!(observed[11]["type"], "response.completed");
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
