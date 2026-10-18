//! 普通问答历史的 GUI 人工验收样本。
//!
//! 场景先让脚本模型发起一次真正的 `request_user_input`，再由验收操作者在真实 GUI 里作答；
//! 收束步骤严格匹配 runtime 为隐藏 continuation 合成的答案 JSON，因此「历史里的问答回执」
//! 只能来自用户真实提交的那一份答案，不能靠工具成功状态伪造。
use super::*;

/// 验收操作者必须在输入框原样发送的提问文本。
pub const GUI_QUESTION_HISTORY_PROMPT: &str =
    "Local GUI question history fixture: confirm the release note wording";

/// 三题的稳定身份；服务端按 question ID 关联答案，顺序仍由请求里的问题顺序决定。
pub const GUI_QUESTION_HISTORY_STYLE_ID: &str = "style";
pub const GUI_QUESTION_HISTORY_NOTES_ID: &str = "notes";
pub const GUI_QUESTION_HISTORY_TOKEN_ID: &str = "token";

/// 第一题的选项标签：操作者勾选后答案即该标签。
pub const GUI_QUESTION_HISTORY_STYLE_ANSWER: &str = "轻量回执";
/// 第二题的自由文本：保留换行，用来核对窄窗口换行与选择复制。
pub const GUI_QUESTION_HISTORY_NOTES_ANSWER: &str =
    "第一行：发布说明保留两句结论与一条风险提示。\n第二行：这一段用来核对自由文本的换行与复制。";
/// 第三题的合成敏感值：只应出现在私有回执里，公开历史必须隐藏。
pub const GUI_QUESTION_HISTORY_TOKEN_ANSWER: &str = "sk-question-history-fixture";

/// 隐藏 continuation 的严格匹配文本。
///
/// runtime 按 `BTreeMap` 序列化答案映射，因此这里用同一容器重建，键顺序与编码都由权威
/// 结构决定，而不是由本文件的手写顺序决定。
pub fn gui_question_history_answers_json() -> String {
    let answers = std::collections::BTreeMap::from([
        (
            GUI_QUESTION_HISTORY_NOTES_ID,
            GUI_QUESTION_HISTORY_NOTES_ANSWER,
        ),
        (
            GUI_QUESTION_HISTORY_STYLE_ID,
            GUI_QUESTION_HISTORY_STYLE_ANSWER,
        ),
        (
            GUI_QUESTION_HISTORY_TOKEN_ID,
            GUI_QUESTION_HISTORY_TOKEN_ANSWER,
        ),
    ]);
    let encoded = answers
        .into_iter()
        .map(|(id, answer)| (id, json!({ "answers": [answer] })))
        .collect::<std::collections::BTreeMap<_, _>>();
    json!({ "answers": encoded }).to_string()
}

fn question_history_arguments() -> String {
    json!({
        "questions": [
            {
                "id": GUI_QUESTION_HISTORY_STYLE_ID,
                "header": "展示风格",
                "question": "这次时间线里的问答回执，你更想要哪种展示？",
                "isOther": false,
                "isSecret": false,
                "options": [
                    {
                        "label": GUI_QUESTION_HISTORY_STYLE_ANSWER,
                        "description": "只有状态、题数与答案，默认折叠"
                    },
                    {
                        "label": "表单卡片",
                        "description": "每题一个独立输入区"
                    }
                ]
            },
            {
                "id": GUI_QUESTION_HISTORY_NOTES_ID,
                "header": "交付说明",
                "question": "还有哪些交付说明需要我记住？",
                "isOther": true,
                "isSecret": false,
                "options": null
            },
            {
                "id": GUI_QUESTION_HISTORY_TOKEN_ID,
                "header": "访问令牌",
                "question": "请粘贴本次验收的临时令牌。",
                "isOther": true,
                "isSecret": true,
                "options": null
            }
        ]
    })
    .to_string()
}

/// 一次真实的三题问答，再用用户答案的隐藏 continuation 收束这一轮。
pub fn gui_question_history_script() -> Vec<Step> {
    let mut script = RealtimeScript::new();
    let title = session_title_prompt(GUI_QUESTION_HISTORY_PROMPT);
    script.optional_title(&title);
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            GUI_QUESTION_HISTORY_PROMPT,
            step,
            Reply::Sse(responses_tool_calls(
                "question-history",
                "fixture-model",
                &[RealtimeToolCall {
                    item_id: "question-history-call",
                    call_id: "question-history-call",
                    name: "request_user_input",
                    arguments: question_history_arguments(),
                }],
            )),
        )
    });
    script.optional_title(&title);
    script.add(|step| {
        Step::prompt(
            Protocol::ResponsesHttp,
            gui_question_history_answers_json(),
            step,
            Reply::Sse(responses_text(
                "收到：按轻量回执整理发布说明，风险提示单独成句。",
                "question-history-close",
                "fixture-model",
            )),
        )
    });
    script.optional_title(&title);
    script.finish()
}
