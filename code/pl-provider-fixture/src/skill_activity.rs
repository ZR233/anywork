//! Deterministic model endpoint for the native skill activity acceptance.
//!
//! The journey loads real synthetic skills next to ordinary tools, forces one
//! failing and one succeeding manual context compaction, then reloads a skill.
//! Phase two reopens the same home with a one-token automatic threshold: the first
//! Turn's automatic compaction must really commit and clear the restored
//! activation, and the last Turn loads a Skill again before its own compaction
//! becomes the cancellation target. No Turn is submitted after the stop.
//!
//! The script is strict and ordinal: every request is an identity check on the
//! prompt or on one delivered tool result, so a missing, duplicated or
//! reordered request fails the acceptance instead of silently passing.

use super::*;

/// Phase-one first Turn: one short skill load plus one ordinary command.
pub const PROMPT_FIRST: &str = "skill-activity-first";
/// Phase-one mixed Turn: repeated loads, the long name, a support file and a
/// failing load in one Turn.
pub const PROMPT_MIXED: &str = "skill-activity-mixed";
/// Phase-one reload after the successful manual compaction.
pub const PROMPT_RELOAD: &str = "skill-activity-reload";
/// Phase-two Turn that the Driver cancels while the automatic compaction is
/// still streaming; it never reaches a model step.
pub const PROMPT_CANCEL: &str = "skill-activity-cancel-turn";
/// Phase-two Turn admitted while the automatic threshold is one token.
pub const PROMPT_REOPEN: &str = "skill-activity-reopen-turn";

/// Short synthetic skill seeded in the isolated `[skills].user_dir`.
pub const SKILL_SHORT: &str = "skill-activity-short";
/// Long synthetic skill name that must stay readable in a narrow window.
pub const SKILL_LONG: &str = "skill-activity-long-name-for-narrow-window-layout-review";
/// Skill name that is deliberately absent, so the load fails for real.
pub const SKILL_MISSING: &str = "skill-activity-missing";
/// Support file of the short skill; reading it is not a main-document load.
pub const SUPPORT_FILE: &str = "references/notes.md";
/// Marker kept in the support file and in both skill bodies.
pub const SUPPORT_MARKER: &str = "skill-activity-support-marker";

/// Body markers of the seeded synthetic skills.
///
/// They only appear in a skill's own document, so the native journey can prove
/// that the paired `skill_view` result is really readable from the skill row
/// instead of matching the activation label.
pub const BODY_MARKER_SHORT: &str = "skill-activity-body-alpha";
pub const BODY_MARKER_LONG: &str = "skill-activity-body-beta";

/// The local context-compaction requirement the runtime sends as the last user
/// message of a compaction request (`pl-studio-runtime` compaction wording).
pub const COMPACTION_PROMPT: &str = "请根据以上完整上下文生成压缩摘要。";

/// Committed command marker of the ordinary tool in the first Turn.
pub const EXEC_MARKER: &str = "skill-activity-exec-marker";

/// Answers the journey asserts by exact text.
pub const ANSWER_FIRST: &str = "skill-activity first answer";
pub const ANSWER_MIXED: &str = "skill-activity mixed answer";
pub const ANSWER_RELOAD: &str = "skill-activity reload answer";
pub const ANSWER_REOPEN: &str = "skill-activity reopen answer";

/// The strict script both GUI lifecycles share.
pub fn script() -> Vec<Step> {
    let mut script = RealtimeScript::new();
    // The runtime names the session from the first user request, so the title
    // steps keep that prompt. Every title step stays optional: a Thread that
    // already owns a title simply never issues the request, and the later
    // candidates tolerate a runtime that names the session from a newer input.
    let first_title = session_title_prompt(PROMPT_FIRST);
    let mixed_title = session_title_prompt(PROMPT_MIXED);
    let reload_title = session_title_prompt(PROMPT_RELOAD);
    let cancel_title = session_title_prompt(PROMPT_CANCEL);
    let reopen_title = session_title_prompt(PROMPT_REOPEN);
    script.optional_title(&first_title);

    // Turn 1: one real main-document load, then one ordinary command, then the
    // answer. A `skill_view` writes the `pl.tool.skill-view` extension, so the
    // runtime declares it solo: every model response may carry at most one tool
    // call, and each load needs its own iteration.
    script.add(|step| {
        let calls = vec![Call::skill("skill-first-load", SKILL_SHORT, None)];
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_FIRST,
            step,
            Reply::Sse(responses_reasoning_tool_calls(
                &["Load the synthetic short skill first."],
                "skill-first-tools",
                "fixture-model",
                &Call::refs(&calls),
            )),
        )
    });
    script.add(|step| {
        let calls = vec![Call::exec("skill-first-exec", &marker_command(EXEC_MARKER))];
        Step::tool_output(
            Protocol::ResponsesHttp,
            "skill-first-load-call",
            "",
            step,
            Reply::Sse(responses_tool_calls(
                "skill-first-exec-tools",
                "fixture-model",
                &Call::refs(&calls),
            )),
        )
    });
    script.add(|step| {
        Step::tool_output(
            Protocol::ResponsesHttp,
            "skill-first-exec-call",
            EXEC_MARKER,
            step,
            Reply::Sse(responses_text(
                ANSWER_FIRST,
                "skill-first-answer",
                "fixture-model",
            )),
        )
    });
    script.optional_title(&first_title);
    script.optional_title(&mixed_title);

    // Turn 2: the same skill twice, the long name, one support-file read and
    // one deliberately unknown name in a single Turn. Each solo load owns one
    // model response, so the repeated loads stay separate real calls.
    script.add(|step| {
        let calls = vec![Call::skill("skill-mixed-first", SKILL_SHORT, None)];
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_MIXED,
            step,
            Reply::Sse(responses_reasoning_tool_calls(
                &[
                    "Reload the same short skill twice, load the long name once, read one support",
                    "file and try one name that does not exist so the failed load stays visible.",
                ],
                "skill-mixed-tools",
                "fixture-model",
                &Call::refs(&calls),
            )),
        )
    });
    for (index, call) in [
        Call::skill("skill-mixed-second", SKILL_SHORT, None),
        Call::skill("skill-mixed-long", SKILL_LONG, None),
        Call::skill("skill-mixed-support", SKILL_SHORT, Some(SUPPORT_FILE)),
        Call::skill("skill-mixed-missing", SKILL_MISSING, None),
    ]
    .into_iter()
    .enumerate()
    {
        let previous = match index {
            0 => "skill-mixed-first-call",
            1 => "skill-mixed-second-call",
            2 => "skill-mixed-long-call",
            _ => "skill-mixed-support-call",
        };
        script.add(move |step| {
            let calls = [call];
            // Later iterations carry no reasoning: the Turn already owns one
            // thinking member, so each remaining load is a plain real call.
            Step::tool_output(
                Protocol::ResponsesHttp,
                previous,
                "",
                step,
                Reply::Sse(responses_tool_calls(
                    "skill-mixed-tools",
                    "fixture-model",
                    &Call::refs(&calls),
                )),
            )
        });
    }
    script.add(|step| {
        Step::tool_output(
            Protocol::ResponsesHttp,
            "skill-mixed-missing-call",
            "",
            step,
            Reply::Sse(responses_text(
                ANSWER_MIXED,
                "skill-mixed-answer",
                "fixture-model",
            )),
        )
    });
    script.optional_title(&mixed_title);
    script.optional_title(&reload_title);

    // Manual compaction that fails: the fixture answers the summarization
    // request with a structured account error, so nothing may be cleared.
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            COMPACTION_PROMPT,
            step,
            Reply::HttpError {
                status: 400,
                code: "fixture_compaction_failed".to_owned(),
                message: "synthetic skill-activity compaction failure".to_owned(),
            },
        )
    });
    // Manual compaction that succeeds.
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            COMPACTION_PROMPT,
            step,
            Reply::Sse(responses_text(
                "skill-activity manual compaction summary",
                "skill-manual-compaction",
                "fixture-model",
            )),
        )
    });
    script.optional_title(&reload_title);

    // Turn 3: only the long name is loaded after the successful compaction.
    script.add(|step| {
        let calls = vec![Call::skill("skill-reload-long", SKILL_LONG, None)];
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_RELOAD,
            step,
            Reply::Sse(responses_reasoning_tool_calls(
                &["Reload only the long skill after the successful compaction."],
                "skill-reload-tools",
                "fixture-model",
                &Call::refs(&calls),
            )),
        )
    });
    script.add(|step| {
        Step::tool_output(
            Protocol::ResponsesHttp,
            "skill-reload-long-call",
            "",
            step,
            Reply::Sse(responses_text(
                ANSWER_RELOAD,
                "skill-reload-answer",
                "fixture-model",
            )),
        )
    });
    script.optional_title(&reload_title);
    script.optional_title(&cancel_title);

    // Phase two, reopened Turn: the same one-token threshold compacts the restored
    // history first, and the answer stays plain text. Re-accumulating a Skill is
    // the last Turn's job, so this Turn owns no tool call at all.
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            COMPACTION_PROMPT,
            step,
            Reply::Sse(responses_text(
                "skill-activity reopen compaction summary",
                "skill-reopen-compaction-summary",
                "fixture-model",
            )),
        )
        .optional()
    });
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_REOPEN,
            step,
            Reply::Sse(responses_text(
                ANSWER_REOPEN,
                "skill-reopen-answer",
                "fixture-model",
            )),
        )
    });

    // Phase two, last Turn: the threshold compacts its admission first, the model
    // then loads the synthetic short Skill through one real solo call, and the
    // automatic compaction that follows the tool result is the cancellation
    // target. That target is the last required step and is paced, so the fixture
    // publishes `remaining_optional` only after the target was really accepted.
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            COMPACTION_PROMPT,
            step,
            Reply::Sse(responses_text(
                "skill-activity cancel admission compaction summary",
                "skill-cancel-admission-summary",
                "fixture-model",
            )),
        )
        .optional()
    });
    script.add(|step| {
        let calls = vec![Call::skill("skill-cancel-load", SKILL_SHORT, None)];
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT_CANCEL,
            step,
            Reply::Sse(responses_reasoning_tool_calls(
                &["Reload the synthetic short skill before the next compaction."],
                "skill-cancel-tools",
                "fixture-model",
                &Call::refs(&calls),
            )),
        )
    });
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            COMPACTION_PROMPT,
            step,
            Reply::PacedEvents {
                initial_delay_ms: 30_000,
                step_millis: 150,
                events: responses_text(
                    "skill-activity cancelled compaction summary",
                    "skill-cancel-target-summary",
                    "fixture-model",
                ),
            },
        )
    });
    script.optional_title(&cancel_title);
    script.optional_title(&reopen_title);
    script.finish()
}

/// One assistant tool call with owned identity, converted at the call site.
struct Call {
    item_id: String,
    call_id: String,
    name: &'static str,
    arguments: String,
}

impl Call {
    /// A real `skill_view` load; `file` reads a support file instead of the
    /// main document, which is not an activation.
    fn skill(slug: &str, name: &str, file: Option<&str>) -> Self {
        let arguments = match file {
            Some(file) => json!({ "name": name, "filePath": file }),
            None => json!({ "name": name }),
        };
        Self::new(slug, "skill_view", arguments)
    }

    fn exec(slug: &str, command: &str) -> Self {
        Self::new(slug, "exec", json!({ "command": command }))
    }

    fn new(slug: &str, name: &'static str, arguments: Value) -> Self {
        Self {
            item_id: format!("{slug}-item"),
            call_id: format!("{slug}-call"),
            name,
            arguments: arguments.to_string(),
        }
    }

    fn refs(calls: &[Self]) -> Vec<RealtimeToolCall<'_>> {
        calls
            .iter()
            .map(|call| RealtimeToolCall {
                item_id: &call.item_id,
                call_id: &call.call_id,
                name: call.name,
                arguments: call.arguments.clone(),
            })
            .collect()
    }
}

/// A real command that prints one marker on either host platform.
fn marker_command(marker: &str) -> String {
    if cfg!(windows) {
        format!("Write-Output '{marker}'")
    } else {
        format!("printf '%s\\n' '{marker}'")
    }
}
