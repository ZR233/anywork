//! Finite, independently consumed timeline journey. Gates delay the provider,
//! never supply application state or emulate display-unit grouping.

use axum::{
    extract::{Path, State},
    http::StatusCode,
};
use serde_json::{Value, json};

use super::*;

pub const PROMPT: &str = "把会话设计稿组件化，检查工作组与正文的交接边界。";
pub const TEXT_A: &str = "已确认共享组件与交接边界，接下来检查收尾。";
pub const TEXT_B: &str = "收尾检查完成，工作组与正文分别保留。";
pub const IMAGE_PROMPT: &str = "读取三张设计截图，并说明无法读取的图片。";
pub const IMAGE_DONE: &str = "三张设计截图已读取；目录不是图片，读取失败已保留。";
pub const MEDIA_HANDOFF_DONE: &str = "纯附件已收到，后台图片已读取。";
pub const FAILED_PROMPT: &str = "保留这段部分结果，再展示供应商失败。";
pub const PARTIAL_TEXT: &str = "已经完成的部分结果必须保留，不能因后续失败而消失。";
pub const OVERLAP_PROMPT: &str = "A07：推理尚未结束时开始正文，并保留可读流。";
pub const OVERLAP_TEXT: &str = "正文已经开始且可以读取，先前推理稍后才结束。";
pub const OVERLAP_EARLY_REASONING: &str = "后开始的推理 B 已先完成，推理 A 仍在进行。";
pub const EMPTY_TEXT_PROMPT: &str = "A13：始终空正文不切组，前后工作继续使用同一尾组。";
pub const EMPTY_TEXT_ANSWER: &str = "空正文不显示卡片，前后工作保留在同一尾组。";
pub const HOT_UPDATE_PROMPT: &str = "同一正文内依次追加二十个可控增量，保持展示身份不变。";
const HOT_UPDATE_HEAD: &str = "热更新正文：";
pub const REQUIRED_STEPS: usize = 10;
// Distinct production assets, copied by the isolated harness for ONE input.
// All are below production's 2000px / 5MiB base64 normalization limits;
// together they also fit the fixture's existing 1MiB request-body limit.
const INPUT_IMAGES: [(&str, &str); 3] = [
    (
        "concept-input-a.png",
        "e75b8140cad993ca5a23db4170bf70d3a4db3d7af55c9e8b43d432022aa58cd4",
    ),
    (
        "concept-input-b.png",
        "316558a02d6a9d35fc19480c9397cdab46a0b1ff83132e25fa184af837e4cfc2",
    ),
    (
        "concept-input-c.png",
        "eee576e2d47e68f0b0a185080f6b6e063d43cdee506cd6df180bd598a4034929",
    ),
];
const OVERLAP_STAGES: &[&str] = &[
    "a07-reasoning-start",
    "a07-b-terminal",
    "a07-text-start",
    "a07-text-readable",
    "a07-text-terminal",
    "a07-reasoning-terminal",
];
const EMPTY_TEXT_STAGES: &[&str] = &[
    "a14-before-empty",
    "a14-empty-start",
    "a14-empty-terminal",
    "a14-after-empty",
    "a14-text-readable",
    "a14-before-turn-end",
];
pub const STAGES: &[&str] = &[
    "thinking",
    "workgroup",
    "group-idle",
    "text",
    "after-text",
    "next-group",
    "second-group-idle",
    "second-text",
    "before-turn-end",
    "compacting",
    "images-ready",
    "failed-partial",
    "a07-reasoning-start",
    "a07-b-terminal",
    "a07-text-start",
    "a07-text-readable",
    "a07-text-terminal",
    "a07-reasoning-terminal",
    "a14-before-empty",
    "a14-empty-start",
    "a14-empty-terminal",
    "a14-after-empty",
    "a14-text-readable",
    "a14-before-turn-end",
    "hot-ready",
    "hot-01",
    "hot-02",
    "hot-03",
    "hot-04",
    "hot-05",
    "hot-06",
    "hot-07",
    "hot-08",
    "hot-09",
    "hot-10",
    "hot-11",
    "hot-12",
    "hot-13",
    "hot-14",
    "hot-15",
    "hot-16",
    "hot-17",
    "hot-18",
    "hot-19",
    "hot-20",
];

/// The listener and strict script share these existing ReplyStage tokens.
/// Only the loopback observer can release a reached stage in declared order.
#[derive(Debug, Clone)]
pub struct Control {
    names: Vec<&'static str>,
    stages: Vec<ReplyStage>,
}

impl Default for Control {
    fn default() -> Self {
        Self {
            names: STAGES.to_vec(),
            stages: STAGES.iter().map(|_| ReplyStage::new()).collect(),
        }
    }
}

impl Control {
    pub fn boundary() -> Self {
        Self {
            names: OVERLAP_STAGES.to_vec(),
            stages: OVERLAP_STAGES.iter().map(|_| ReplyStage::new()).collect(),
        }
    }

    /// The A07 request uses the same lifecycle events and gates as the journey.
    pub fn boundary_script(&self) -> Vec<Step> {
        let mut script = RealtimeScript::new();
        script.optional_title(&session_title_prompt(OVERLAP_PROMPT));
        script.add(|index| self.overlap_step(index));
        script.finish()
    }

    /// Independent two-step media story; no reasoning/hot-update journey gates.
    pub fn media_handoff_script(&self) -> Vec<Step> {
        vec![
            Step {
                protocol: Protocol::ResponsesHttp,
                request: RequestMatch::PromptImages {
                    text: None,
                    images: INPUT_IMAGES
                        .iter()
                        .map(|(filename, hash)| PromptImage {
                            filename: (*filename).into(),
                            png_sha256: (*hash).into(),
                        })
                        .collect(),
                    step: 0,
                },
                reply: Reply::Sse(responses_tool_calls(
                    "media-handoff-image",
                    "fixture-model",
                    &[RealtimeToolCall {
                        item_id: "concept-image-a-item",
                        call_id: "concept-image-a",
                        name: "view_image",
                        arguments: json!({"path":"concept-image-a.png"}).to_string(),
                    }
                    .program("view_image")],
                )),
                optional: false,
            },
            Step {
                protocol: Protocol::ResponsesHttp,
                request: RequestMatch::ToolImages {
                    images: vec![ToolImage {
                        call_id: "concept-image-a".into(),
                        png_sha256:
                            "0a23b4c2e99e7de221fedb9e4e96d910c786d32385a17dc44dbc1138c13a2b4b"
                                .into(),
                    }],
                    outputs: vec![],
                    step: 1,
                },
                reply: Reply::Sse(responses_text(
                    MEDIA_HANDOFF_DONE,
                    "media-handoff-answer",
                    "fixture-model",
                )),
                optional: false,
            },
        ]
    }

    /// Holds the first real model response while the UI submits a second input.
    pub fn message_submission() -> Self {
        Self {
            names: vec!["submission-first-running"],
            stages: vec![ReplyStage::new()],
        }
    }

    pub fn message_submission_script(&self) -> Vec<Step> {
        let first = "请保持第一轮运行，我将继续发送一条消息。";
        let second = "这是运行中的第二条消息，请确认收到。";
        let mut script = RealtimeScript::new();
        script.optional_title(&session_title_prompt(first));
        script.add(|index| {
            let events = responses_text("第一轮处理完成。", "submission-first", "fixture-model");
            Step::prompt(
                Protocol::ResponsesHttp,
                first,
                index,
                self.stages[0].gated(events[..1].to_vec(), events[1..].to_vec()),
            )
        });
        // Title generation is independent of the foreground request. The first
        // Turn can be interrupted before that background request is scheduled.
        script.optional_title(&session_title_prompt(first));
        script.add(|index| {
            Step::prompt(
                Protocol::ResponsesHttp,
                second,
                index,
                Reply::Sse(responses_text(
                    "第二条消息已处理。",
                    "submission-second",
                    "fixture-model",
                )),
            )
        });
        script.optional_title(&session_title_prompt(first));
        script.finish()
    }

    pub fn realtime() -> Self {
        Self {
            names: vec![
                "realtime-first-token",
                "realtime-text-readable",
                "realtime-parallel-observer",
                "realtime-background-result",
                "realtime-host-cwd-observer",
            ],
            stages: (0..5).map(|_| ReplyStage::new()).collect(),
        }
    }

    pub fn realtime_script(&self, host_cwd: &str, scope: RealtimeScope) -> Vec<Step> {
        super::gui_realtime_script(
            host_cwd,
            Some(RealtimeObservers {
                first_token: &self.stages[0],
                readable_text: &self.stages[1],
                parallel: &self.stages[2],
                background_result: &self.stages[3],
                host_cwd: &self.stages[4],
            }),
            scope,
        )
    }

    pub fn questions() -> Self {
        Self {
            names: vec!["questions-pending"],
            stages: vec![ReplyStage::new()],
        }
    }

    pub fn question_script(&self) -> Vec<Step> {
        super::question_history::script(Some(&self.stages[0]))
    }

    pub fn script(&self) -> Vec<Step> {
        let mut script = RealtimeScript::new();
        script.optional_title(&session_title_prompt(PROMPT));
        script.add(|index| {
            let events = responses_reasoning_tool_calls(
                &["梳理 **会话共享组件** 与 `LiveStatusBar` 锁定边界"],
                "concept-read",
                "fixture-model",
                &[RealtimeToolCall {
                    item_id: "concept-read-item",
                    call_id: "concept-read-call",
                    name: TOOL_EXEC_NAME,
                    arguments: realtime_exec_arguments(
                        if cfg!(windows) {
                            "Get-Content concept-boundary.txt"
                        } else {
                            "cat concept-boundary.txt"
                        },
                        None,
                    ),
                }
                .program("exec_command")],
            );
            Step::prompt(
                Protocol::ResponsesHttp,
                PROMPT,
                index,
                ReplyStage::staged(
                    vec![
                        events[..1].to_vec(),
                        events[1..3].to_vec(),
                        events[3..].to_vec(),
                    ],
                    &[&self.stages[0], &self.stages[1]],
                ),
            )
        });
        script.add(|index| {
            Step::tool_output(
                Protocol::ResponsesHttp,
                "concept-read-call",
                "concept-boundary-source",
                index,
                Reply::Sse(responses_tool_calls(
                    "concept-parallel",
                    "fixture-model",
                    &[
                        RealtimeToolCall {
                            item_id: "concept-command-a-item",
                            call_id: "concept-command-a",
                            name: TOOL_EXEC_NAME,
                            arguments: realtime_exec_arguments(
                                if cfg!(windows) {
                                    "Write-Output concept-command-a-done"
                                } else {
                                    "printf 'concept-command-a-done\\n'"
                                },
                                None,
                            ),
                        }
                        .program("exec_command"),
                        RealtimeToolCall {
                            item_id: "concept-command-b-item",
                            call_id: "concept-command-b",
                            name: TOOL_EXEC_NAME,
                            arguments: realtime_exec_arguments(
                                if cfg!(windows) {
                                    "Write-Output concept-command-b-done"
                                } else {
                                    "printf 'concept-command-b-done\\n'"
                                },
                                None,
                            ),
                        }
                        .program("exec_command"),
                    ],
                )),
            )
        });
        script.add(|index| Step {
            protocol: Protocol::ResponsesHttp,
            request: RequestMatch::ToolOutputs {
                outputs: vec![
                    ("concept-command-a".into(), "concept-command-a-done".into()),
                    ("concept-command-b".into(), "concept-command-b-done".into()),
                ],
                step: index,
            },
            reply: ReplyStage::staged(
                vec![
                    vec![json!({"type":"response.created","response":{"id":"concept-answer","model":"fixture-model"}})],
                    text_start("concept-text-a", 0, TEXT_A),
                    vec![text_done("concept-text-a", 0, TEXT_A)],
                    vec![
                        json!({"type":"response.output_item.added","output_index":1,"item":{"id":"concept-thinking-b","type":"reasoning","summary":[],"content":[]}}),
                        json!({"type":"response.reasoning_summary_text.delta","output_index":1,"item_id":"concept-thinking-b","summary_index":0,"delta":"确认收尾检查"}),
                    ],
                    vec![json!({"type":"response.output_item.done","output_index":1,"item":{"id":"concept-thinking-b","type":"reasoning","summary":[{"type":"summary_text","text":"确认收尾检查"}]}})],
                    text_start("concept-text-b", 2, TEXT_B),
                    vec![text_done("concept-text-b", 2, TEXT_B)],
                    vec![json!({"type":"response.completed","response":{"id":"concept-answer","model":"fixture-model","usage":{"input_tokens":30,"output_tokens":20}}})],
                ],
                &self.stages[2..9].iter().collect::<Vec<_>>(),
            ),
            optional: false,
        });
        script.add(|step| Step {
            protocol: Protocol::ResponsesHttp,
            request: RequestMatch::Compaction { marker: TEXT_A.into(), step },
            reply: self.stages[9].gated(
                vec![json!({"type":"response.created","response":{"id":"concept-compaction","model":"fixture-model"}})],
                vec![
                    json!({"type":"response.output_item.done","item":{"type":"compaction","encrypted_content":"concept-context-checkpoint"}}),
                    json!({"type":"response.completed","response":{"id":"concept-compaction","usage":{"input_tokens":30,"output_tokens":2}}}),
                ],
            ),
            optional: false,
        });
        script.add(|step| {
            let calls = (0..4).map(|index| RealtimeToolCall {
                item_id: ["concept-image-a-item", "concept-image-b-item", "concept-image-c-item", "concept-image-failed-item"][index],
                call_id: ["concept-image-a", "concept-image-b", "concept-image-c", "concept-image-failed"][index],
                name: "view_image",
                arguments: json!({"path": (["concept-image-a.png", "concept-image-b.png", "concept-image-c.png", "."][index])}).to_string(),
            }.program("view_image")).collect::<Vec<_>>();
            let mut events = vec![json!({"type":"response.created","response":{"id":"concept-images","model":"fixture-model"}})];
            // A bounded ordinary-atom history for real paging/fill observations.
            // It specifies no backend page size, presentation range, page-count
            // cap, or constant-time promise for filling an arbitrarily long group.
            for index in 0..40 {
                let id = format!("concept-image-reason-{index}");
                let text = format!("检查设计截图与读取边界 {index}");
                events.extend([
                    json!({"type":"response.output_item.added","output_index":index,"item":{"id":id,"type":"reasoning","summary":[],"content":[]}}),
                    json!({"type":"response.reasoning_summary_text.delta","output_index":index,"item_id":id,"summary_index":0,"delta":text}),
                    json!({"type":"response.output_item.done","output_index":index,"item":{"id":id,"type":"reasoning","summary":[{"type":"summary_text","text":text}]}}),
                ]);
            }
            for mut event in responses_tool_calls("concept-images", "fixture-model", &calls).into_iter().skip(1) {
                if let Some(index) = event.get("output_index").and_then(Value::as_u64) {
                    event["output_index"] = (index + 40).into();
                }
                events.push(event);
            }
            Step {
                protocol: Protocol::ResponsesHttp,
                request: RequestMatch::PromptImages {
                    text: Some(IMAGE_PROMPT.into()),
                    images: INPUT_IMAGES.iter().map(|(filename, hash)| PromptImage {
                        filename: (*filename).into(),
                        png_sha256: (*hash).into(),
                    }).collect(),
                    step,
                },
                reply: Reply::Sse(events),
                optional: false,
            }
        });
        script.add(|step| Step {
            protocol: Protocol::ResponsesHttp,
            request: RequestMatch::ToolImages {
                images: ["concept-image-a", "concept-image-b", "concept-image-c"]
                    .iter().map(|call_id| ToolImage {
                        call_id: (*call_id).into(),
                        png_sha256: "0a23b4c2e99e7de221fedb9e4e96d910c786d32385a17dc44dbc1138c13a2b4b".into(),
                    }).collect(),
                outputs: vec![
                    ("concept-image-failed".into(), "image source is not a regular file".into()),
                ],
                step,
            },
            reply: self.stages[10].gated(
                vec![json!({"type":"response.created","response":{"id":"concept-images-answer","model":"fixture-model"}})],
                responses_text(IMAGE_DONE, "concept-images-answer", "fixture-model").into_iter().skip(1).collect(),
            ),
            optional: false,
        });
        script.add(|step| {
            let mut before = vec![json!({"type":"response.created","response":{"id":"concept-failed","model":"fixture-model"}})];
            before.extend(text_start("concept-partial-text", 0, PARTIAL_TEXT));
            Step::prompt(Protocol::ResponsesHttp, FAILED_PROMPT, step,
                self.stages[11].gated(before, vec![
                    json!({"type":"response.failed","response":{"id":"concept-failed","error":{"code":"invalid_request_error","message":"concept provider permanent failure"}}}),
                ]))
        });
        script.add(|step| self.overlap_step(step));
        script.add(|step| self.empty_text_step(step));
        script.add(|step| self.hot_update_step(step));
        script.finish()
    }

    fn hot_update_step(&self, step: usize) -> Step {
        // One request, one item/content identity, and twenty independently held
        // deltas. No done/turn boundary is sent until hot-20 is released.
        let id = "concept-hot-text";
        let mut first = vec![created("concept-hot")];
        first.extend(text_start(id, 0, HOT_UPDATE_HEAD));
        let mut chunks = vec![first];
        let mut full_text = HOT_UPDATE_HEAD.to_owned();
        for index in 1..=20 {
            // The sample observes four literal glyphs, not Markdown's numeric
            // source-tag chip. Use inline code without changing the
            // displayed marker or the independently held delta gates.
            let delta = format!(" `[{index:02}]`");
            full_text.push_str(&delta);
            chunks.push(vec![json!({
                "type":"response.output_text.delta",
                "output_index":0, "item_id":id, "content_index":0, "delta":delta
            })]);
        }
        chunks.push(vec![
            text_done(id, 0, &full_text),
            json!({"type":"response.completed","response":{"id":"concept-hot","model":"fixture-model"}}),
        ]);
        let gates = self
            .names
            .iter()
            .zip(&self.stages)
            .filter_map(|(name, stage)| name.starts_with("hot-").then_some(stage))
            .collect::<Vec<_>>();
        Step::prompt(
            Protocol::ResponsesHttp,
            HOT_UPDATE_PROMPT,
            step,
            ReplyStage::staged(chunks, &gates),
        )
    }

    fn named_stages(&self, names: &[&str]) -> Vec<&ReplyStage> {
        names
            .iter()
            .map(|name| {
                let index = self
                    .names
                    .iter()
                    .position(|known| known == name)
                    .expect("concept script references an undeclared gate");
                &self.stages[index]
            })
            .collect()
    }

    /// A07 holds A open while B completes, then completes text and finally A.
    /// Every boundary is a provider lifecycle event, not a display projection.
    fn overlap_step(&self, step: usize) -> Step {
        let head = "正文已经开始且可以读取，";
        let tail = "先前推理稍后才结束。";
        Step::prompt(
            Protocol::ResponsesHttp,
            OVERLAP_PROMPT,
            step,
            ReplyStage::staged(
                vec![
                    vec![
                        created("concept-a07"),
                        reasoning_start("concept-a07-reason", 0),
                        reasoning_delta(
                            "concept-a07-reason",
                            0,
                            "这段推理在正文开始后继续保持活动。",
                        ),
                    ],
                    vec![
                        reasoning_start("concept-a07-reason-b", 1),
                        reasoning_delta("concept-a07-reason-b", 1, OVERLAP_EARLY_REASONING),
                        reasoning_done("concept-a07-reason-b", 1, OVERLAP_EARLY_REASONING),
                    ],
                    text_start("concept-a07-text", 2, head),
                    vec![
                        json!({"type":"response.output_text.delta","output_index":2,"item_id":"concept-a07-text","content_index":0,"delta":tail}),
                    ],
                    vec![text_done("concept-a07-text", 2, OVERLAP_TEXT)],
                    vec![reasoning_done(
                        "concept-a07-reason",
                        0,
                        "这段推理在正文开始后继续保持活动。",
                    )],
                    vec![completed("concept-a07")],
                ],
                &self.named_stages(OVERLAP_STAGES),
            ),
        )
    }

    /// A14 has a genuine empty message identity and explicit lifecycle edges.
    /// No whitespace delta, fake tool, or Flutter state replacement stands in for it.
    fn empty_text_step(&self, step: usize) -> Step {
        Step::prompt(
            Protocol::ResponsesHttp,
            EMPTY_TEXT_PROMPT,
            step,
            ReplyStage::staged(
                vec![
                    vec![
                        created("concept-a14"),
                        reasoning_start("concept-a14-work-a", 0),
                        reasoning_delta("concept-a14-work-a", 0, "空正文之前的工作。"),
                        reasoning_done("concept-a14-work-a", 0, "空正文之前的工作。"),
                    ],
                    vec![
                        json!({"type":"response.output_item.added","output_index":1,"item":{"id":"concept-a14-empty","type":"message","role":"assistant","content":[]}}),
                        json!({"type":"response.content_part.added","output_index":1,"item_id":"concept-a14-empty","content_index":0,"part":{"type":"output_text","text":""}}),
                    ],
                    vec![
                        json!({"type":"response.content_part.done","output_index":1,"item_id":"concept-a14-empty","content_index":0,"part":{"type":"output_text","text":""}}),
                        text_done("concept-a14-empty", 1, ""),
                    ],
                    vec![
                        reasoning_start("concept-a14-work-b", 2),
                        reasoning_delta("concept-a14-work-b", 2, "空正文之后的独立工作。"),
                        reasoning_done("concept-a14-work-b", 2, "空正文之后的独立工作。"),
                    ],
                    text_start("concept-a14-text", 3, EMPTY_TEXT_ANSWER),
                    vec![text_done("concept-a14-text", 3, EMPTY_TEXT_ANSWER)],
                    vec![completed("concept-a14")],
                ],
                &self.named_stages(EMPTY_TEXT_STAGES),
            ),
        )
    }
}

fn created(id: &str) -> Value {
    json!({"type":"response.created","response":{"id":id,"model":"fixture-model"}})
}

fn completed(id: &str) -> Value {
    json!({"type":"response.completed","response":{"id":id,"model":"fixture-model","usage":{"input_tokens":31,"output_tokens":17}}})
}

fn reasoning_start(id: &str, index: usize) -> Value {
    json!({"type":"response.output_item.added","output_index":index,"item":{"id":id,"type":"reasoning","summary":[],"content":[]}})
}

fn reasoning_delta(id: &str, index: usize, text: &str) -> Value {
    json!({"type":"response.reasoning_summary_text.delta","output_index":index,"item_id":id,"summary_index":0,"delta":text})
}

fn reasoning_done(id: &str, index: usize, text: &str) -> Value {
    json!({"type":"response.output_item.done","output_index":index,"item":{"id":id,"type":"reasoning","summary":[{"type":"summary_text","text":text}]}})
}

fn text_start(id: &str, index: usize, text: &str) -> Vec<Value> {
    vec![
        json!({"type":"response.output_item.added","output_index":index,"item":{"id":id,"type":"message","role":"assistant","content":[]}}),
        json!({"type":"response.output_text.delta","output_index":index,"item_id":id,"content_index":0,"delta":text}),
    ]
}

fn text_done(id: &str, index: usize, text: &str) -> Value {
    json!({"type":"response.output_item.done","output_index":index,"item":{"id":id,"type":"message","role":"assistant","content":[{"type":"output_text","text":text}]}})
}

pub(super) async fn reached(State(state): State<AppState>, Path(name): Path<String>) -> StatusCode {
    let Some(control) = &state.timeline_concept else {
        return StatusCode::NOT_FOUND;
    };
    let Some(index) = control.names.iter().position(|stage| *stage == name) else {
        return StatusCode::NOT_FOUND;
    };
    tokio::select! {
        () = state.stopping.cancelled() => StatusCode::SERVICE_UNAVAILABLE,
        result = tokio::time::timeout(Duration::from_secs(30), control.stages[index].wait_reached()) => {
            if result.is_ok() { StatusCode::NO_CONTENT } else { StatusCode::REQUEST_TIMEOUT }
        }
    }
}

pub(super) async fn release(State(state): State<AppState>, Path(name): Path<String>) -> StatusCode {
    let Some(control) = &state.timeline_concept else {
        return StatusCode::NOT_FOUND;
    };
    let Some(index) = control.names.iter().position(|stage| *stage == name) else {
        return StatusCode::NOT_FOUND;
    };
    let stage = &control.stages[index];
    if !stage.reached.is_cancelled()
        || stage.is_released()
        || control.stages[..index]
            .iter()
            .any(|prior| !prior.is_released())
    {
        return StatusCode::CONFLICT;
    }
    stage.release();
    StatusCode::NO_CONTENT
}

// This proves fixture pacing/identity only, not native layout or latency.

#[cfg(test)]
mod tests {
    //! Wire and gate evidence only. These tests do not implement a presentation
    //! reducer or claim that Flutter/Core consumed any lifecycle fact.

    use super::*;
    use futures::{Stream, StreamExt};

    fn realtime_completion_call(id: &str) -> String {
        id.into()
    }

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
                        realtime_completion_call("realtime-long-call"),
                    ]);
                }
                expected.extend([
                    GUI_REALTIME_PARALLEL_PROMPT.to_owned(),
                    GUI_REALTIME_PARALLEL_PROMPT.to_owned(),
                    realtime_completion_call("realtime-parallel-call-a"),
                    realtime_completion_call("realtime-parallel-call-b"),
                ]);
                if scope == RealtimeScope::Full {
                    expected.extend([
                        GUI_REALTIME_HOST_CWD_PROMPT.to_owned(),
                        GUI_REALTIME_HOST_CWD_PROMPT.to_owned(),
                        realtime_completion_call("realtime-host-cwd-call"),
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
                    | RequestMatch::ToolOutput { step: actual, .. }) = &step.request
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
                let send = |text: String| {
                    let mut input = vec![json!({"role":"user","content":[{"type":"input_text","text":text}]})];
                    if text.starts_with("realtime-") && text.contains("-call") {
                        input.push(json!({"type":"function_call_output","call_id":text,"output":"{\"state\":{\"kind\":\"final\"}}"}));
                    }
                    client.post(&url).json(&json!({"model":"fixture-model","stream":true,"input":input})).send()
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
                    if text == &realtime_completion_call("realtime-parallel-call-a") {
                        let response = send(text.replace("call-a", "call-unrelated"))
                            .await
                            .unwrap();
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
        let valid = json!({"model":"fixture-model","stream":true,"input":[{"role":"user","content":content}]});
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
        invalid_data["input"][0]["content"][2]["image_url"] =
            "data:image/png;base64,broken!".into();
        let mut remote_url = valid.clone();
        remote_url["input"][0]["content"][2]["image_url"] =
            "https://example.invalid/image.png".into();
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
        assert_eq!(
            calls[3]["arguments"],
            crate::lua::arguments("view_image", &json!({"path":"."})).to_string()
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
        wrong_label["input"][4]["content"][0]["text"] =
            "Image from view_image call unrelated".into();
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
                event["type"] == "response.output_item.done"
                    && event["item"]["type"] == "function_call"
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
        let gate =
            |name: &str| format!("{}/__timeline_concept/{name}", base.trim_end_matches("/v1"));
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
                    crate::lua::arguments(
                        "exec_command",
                        &json!({"command":realtime_parallel_command(tag, lines)})
                    )
                    .to_string()
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
                    matches!(&step.request, RequestMatch::ToolOutput { call_id, .. } if call_id == "realtime-parallel-call-a")
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
                event["type"] != "response.output_item.done"
                    && event["type"] != "response.completed"
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
                event["type"] == "response.output_item.done"
                    && event["item"]["type"] == "function_call"
            })
            .map(|event| &event["item"])
            .collect::<Vec<_>>();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0]["id"], "realtime-host-cwd-item");
        assert_eq!(calls[0]["call_id"], "realtime-host-cwd-call");
        assert_eq!(calls[0]["name"], TOOL_EXEC_NAME);
        assert_eq!(
            calls[0]["arguments"],
            crate::lua::arguments(
                "exec_command",
                &json!({"command":realtime_host_cwd_command(),"cwd":host_cwd})
            )
            .to_string()
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
}

#[cfg(test)]
mod hot_update_wire_tests {
    use super::*;
    use futures::StreamExt;
    use std::time::Duration;

    fn events(wire: &[u8]) -> Vec<Value> {
        String::from_utf8_lossy(wire)
            .split_inclusive("\n\n")
            .filter(|frame| frame.ends_with("\n\n"))
            .filter_map(|frame| frame.trim().strip_prefix("data: ").map(str::to_owned))
            .filter(|frame| frame != "[DONE]")
            .map(|frame| serde_json::from_str(&frame).unwrap())
            .collect()
    }

    #[tokio::test]
    async fn hot_updates_hold_twenty_deltas_on_one_text_identity() {
        let mut control = Control::default();
        let first = control
            .names
            .iter()
            .position(|name| *name == "hot-ready")
            .unwrap();
        control.names.drain(..first);
        control.stages.drain(..first);
        assert_eq!(control.names.len(), 21);
        let fixture = FixtureServer::start_with_options(
            vec![control.hot_update_step(0)],
            FixtureOptions {
                timeline_concept: Some(control.clone()),
                ..FixtureOptions::default()
            },
        )
        .await
        .unwrap();
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap();
        let base = fixture.base_url();
        let gate =
            |name: &str| format!("{}/__timeline_concept/{name}", base.trim_end_matches("/v1"));
        let response = client
            .post(format!("{base}/responses"))
            .json(&json!({
                "model":"fixture-model", "stream":true,
                "input":[{"role":"user","content":[{"type":"input_text","text":HOT_UPDATE_PROMPT}]}],
            }))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let mut stream = response.bytes_stream();
        let mut wire = Vec::new();
        let mut full_text = HOT_UPDATE_HEAD.to_owned();
        for (index, name) in control.names.iter().enumerate() {
            assert_eq!(
                client.get(gate(name)).send().await.unwrap().status(),
                StatusCode::NO_CONTENT
            );
            while events(&wire).len() < 3 + index {
                let chunk = tokio::time::timeout(Duration::from_secs(5), stream.next())
                    .await
                    .expect("held hot update was not emitted")
                    .expect("text ended before its gate")
                    .unwrap();
                wire.extend_from_slice(&chunk);
            }
            let observed = events(&wire);
            assert_eq!(observed.len(), 3 + index);
            assert_eq!(observed[1]["item"]["id"], "concept-hot-text");
            let delta = &observed[2 + index];
            assert_eq!(delta["type"], "response.output_text.delta");
            assert_eq!(delta["item_id"], "concept-hot-text");
            assert_eq!(delta["output_index"], 0);
            assert_eq!(delta["content_index"], 0);
            if index == 0 {
                assert_eq!(delta["delta"], HOT_UPDATE_HEAD);
            } else {
                let expected = format!(" `[{index:02}]`");
                assert_eq!(delta["delta"], expected);
                full_text.push_str(&expected);
            }
            assert_eq!(
                client.post(gate(name)).send().await.unwrap().status(),
                StatusCode::NO_CONTENT
            );
        }
        while let Some(chunk) = tokio::time::timeout(Duration::from_secs(5), stream.next())
            .await
            .expect("released hot update did not finish")
        {
            wire.extend_from_slice(&chunk.unwrap());
        }
        let observed = events(&wire);
        assert_eq!(observed.len(), 25);
        assert_eq!(observed[23], text_done("concept-hot-text", 0, &full_text));
        assert_eq!(observed[24]["type"], "response.completed");
        let requests = fixture.finish().await.unwrap();
        assert_eq!(requests.len(), 1);
        assert!(requests[0].accepted);
    }
}
