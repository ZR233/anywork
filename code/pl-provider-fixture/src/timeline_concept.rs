//! Finite, independently consumed timeline journey. Gates delay the provider,
//! never supply application state or emulate display-unit grouping.

#[cfg(test)]
mod tests;

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
pub const FAILED_PROMPT: &str = "保留这段部分结果，再展示供应商失败。";
pub const PARTIAL_TEXT: &str = "已经完成的部分结果必须保留，不能因后续失败而消失。";
pub const OVERLAP_PROMPT: &str = "A07：推理尚未结束时开始正文，并保留可读流。";
pub const OVERLAP_TEXT: &str = "正文已经开始且可以读取，先前推理稍后才结束。";
pub const EMPTY_TEXT_PROMPT: &str = "A14：空正文开始和结束仍然分开前后两段工作。";
pub const EMPTY_TEXT_ANSWER: &str = "空正文没有可见气泡，但前后工作不属于同一段。";
pub const REQUIRED_STEPS: usize = 9;
// Distinct production assets, copied by the isolated harness for ONE input.
// All are below production's 2000px / 5MiB base64 normalization limits;
// together they also fit the fixture's existing 1MiB request-body limit.
const INPUT_PNG_SHA256: [&str; 3] = [
    "e75b8140cad993ca5a23db4170bf70d3a4db3d7af55c9e8b43d432022aa58cd4",
    "316558a02d6a9d35fc19480c9397cdab46a0b1ff83132e25fa184af837e4cfc2",
    "eee576e2d47e68f0b0a185080f6b6e063d43cdee506cd6df180bd598a4034929",
];
const OVERLAP_STAGES: &[&str] = &[
    "a07-reasoning-start",
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
                &["梳理会话共享组件与锁定边界"],
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
                }],
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
                        },
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
                        },
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
            }).collect::<Vec<_>>();
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
                    text: IMAGE_PROMPT.into(),
                    png_sha256: INPUT_PNG_SHA256.iter().map(|hash| (*hash).into()).collect(),
                    step,
                },
                reply: Reply::Sse(events),
                optional: false,
            }
        });
        script.add(|step| Step {
            protocol: Protocol::ResponsesHttp,
            request: RequestMatch::ToolOutputs {
                outputs: vec![
                    ("concept-image-a".into(), "concept-image-a.png".into()),
                    ("concept-image-b".into(), "concept-image-b.png".into()),
                    ("concept-image-c".into(), "concept-image-c.png".into()),
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
        script.finish()
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

    /// A07 uses one real response: text is readable while the earlier reasoning
    /// identity remains active, and even text terminal precedes reasoning terminal.
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
                    text_start("concept-a07-text", 1, head),
                    vec![
                        json!({"type":"response.output_text.delta","output_index":1,"item_id":"concept-a07-text","content_index":0,"delta":tail}),
                    ],
                    vec![text_done("concept-a07-text", 1, OVERLAP_TEXT)],
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
