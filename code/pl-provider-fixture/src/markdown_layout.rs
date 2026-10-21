//! Synthetic Markdown for opt-in native layout and clipboard review.

use crate::{Protocol, Reply, Step, responses_text, responses_text_chunks, session_title_prompt};

/// Submit this through the real composer in the isolated native GUI.
pub const PROMPT: &str = "展示长 Markdown 表格、引用与代码排版样例";

/// One canonical fixture for both streamed output and clipboard expectations.
pub const BODY: &str = include_str!("../assets/markdown-layout.md");

/// Stream complete lines through the normal Responses adapter and Timeline.
pub fn script() -> Vec<Step> {
    let title = session_title_prompt(PROMPT);
    vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            title.clone(),
            0,
            Reply::Sse(responses_text(
                "Markdown 排版",
                "markdown-title",
                "fixture-model",
            )),
        )
        .optional(),
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            1,
            Reply::PacedEvents {
                initial_delay_ms: 250,
                step_millis: 80,
                events: responses_text_chunks(
                    &BODY.split_inclusive('\n').collect::<Vec<_>>(),
                    "markdown-layout-response",
                    "fixture-model",
                ),
            },
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            title,
            2,
            Reply::Sse(responses_text(
                "Markdown 排版",
                "markdown-title",
                "fixture-model",
            )),
        )
        .optional(),
    ]
}
