//! Text and attachment projection from immutable input facts, independent from current tool renderers.
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::input::{
        CONTINUATION_PAYLOAD_FORMAT, CONTINUATION_PAYLOAD_VERSION, InputPurpose, InputRecord,
    },
};
use pl_protocol::{MessagePresentation, ThreadAttachment};
use serde::Deserialize;

#[derive(Debug, PartialEq)]
pub(super) struct InputContent {
    pub text: String,
    pub attachments: Vec<ThreadAttachment>,
    pub presentation: MessagePresentation,
    pub original: OpaquePayload,
}

#[derive(Debug, thiserror::Error)]
pub(super) enum ContentError {
    #[error("invalid saved product input")]
    Decode(#[from] serde_json::Error),
    #[error("unsupported saved product input {format} version {version}")]
    Unsupported { format: String, version: u32 },
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Prompt {
    text: String,
    presentation: MessagePresentation,
    attachments: Vec<crate::studio::AttachmentRecord>,
    // Admission metadata is validated but does not replace the saved display content.
    #[serde(rename = "request")]
    _request: Option<pl_protocol::studio::StudioPromptInput>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Continuation {
    interaction_id: String,
    presentation: MessagePresentation,
}

/// The body-less control input a continuation is submitted with.
///
/// It names the point it claims and the Turn it continues; it never carries task content, which is why
/// the projection below renders it as one runtime notice instead of as user input.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ContinuationControl {
    point_id: String,
    #[serde(default)]
    source_turn_id: Option<String>,
}

/// What one saved input projects to.
pub(super) enum InputView {
    /// Real saved input: the prompt itself, or the hidden answer a decision carries.
    Content(InputContent),
    /// A framework control input that has no user body of its own.
    ControlNotice {
        /// The runtime sentence shown where the input would otherwise appear.
        notice: String,
    },
}

/// The runtime sentence that stands in for a continuation's control input.
///
/// It says what happened at the context boundary and nothing else: no user question is repeated, no
/// task content is invented, and the control payload itself stays out of the transcript.
pub(super) const CONTINUATION_NOTICE: &str = "This session continued after it was stopped. This entry is a runtime notice; it carries no user input.";

/// Produces the projected view of one saved input, or the runtime notice a control input stands for.
///
/// The classification starts from the typed [`InputPurpose`], never from the payload text: a normal
/// message that happens to carry the control format is still a message, and it keeps its content
/// (or its visible raw fallback) instead of turning into a framework notice.
pub(super) fn input_view(input: &InputRecord) -> Result<InputView, ContentError> {
    if input.input.purpose == InputPurpose::Continuation {
        return control_notice(&input.input.payload);
    }
    input_content(input).map(InputView::Content)
}

/// The notice a typed control input projects to, after its payload proves it is one.
///
/// A control input that cannot be decoded is an error, not a reassuring sentence: callers keep the
/// original payload as a visible raw record so corruption stays diagnosable.
fn control_notice(payload: &OpaquePayload) -> Result<InputView, ContentError> {
    if payload.format() != CONTINUATION_PAYLOAD_FORMAT
        || payload.version() != CONTINUATION_PAYLOAD_VERSION
    {
        return Err(ContentError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        });
    }
    let control: ContinuationControl = serde_json::from_str(payload.content())?;
    if control.point_id.trim().is_empty() {
        return Err(ContentError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        });
    }
    let _ = control.source_turn_id;
    Ok(InputView::ControlNotice {
        notice: CONTINUATION_NOTICE.to_owned(),
    })
}

/// Produces display content from the input's saved product metadata. Unknown formats are errors;
/// callers retain the original payload for a generic historical record view.
pub(super) fn input_content(input: &InputRecord) -> Result<InputContent, ContentError> {
    let payload = &input.input.payload;
    if payload.version() != 1 {
        return Err(ContentError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        });
    }
    match payload.format() {
        "pl.studio.prompt" => {
            let prompt: Prompt = serde_json::from_str(payload.content())?;
            Ok(InputContent {
                text: prompt.text,
                presentation: prompt.presentation,
                attachments: prompt
                    .attachments
                    .iter()
                    .map(crate::studio::store::attachment::thread_attachment)
                    .collect(),
                original: payload.clone(),
            })
        }
        "pl.studio.interaction-continuation" => {
            let continuation: Continuation = serde_json::from_str(payload.content())?;
            if continuation.interaction_id.is_empty() {
                return Err(ContentError::Unsupported {
                    format: payload.format().into(),
                    version: payload.version(),
                });
            }
            Ok(InputContent {
                text: text_content(&input.input.context),
                presentation: continuation.presentation,
                attachments: Vec::new(),
                original: payload.clone(),
            })
        }
        _ => Err(ContentError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        }),
    }
}

/// Unknown product payloads project as visible Raw items, not hidden omissions.
pub(in crate::studio) fn input_presentation(input: &InputRecord) -> MessagePresentation {
    match input_view(input) {
        Ok(InputView::Content(content)) => content.presentation,
        // A runtime control notice is always visible, and an unknown format keeps the visible raw
        // fallback: only a decodable hidden answer may disappear from the transcript.
        Ok(InputView::ControlNotice { .. }) | Err(_) => MessagePresentation::Visible,
    }
}

/// Attachment identities the current state still references through its accepted inputs.
///
/// Publishing a checkpoint that names a blob must not outrun that blob's durability, so this is the
/// fence's input: it is derived from the same saved payloads the projection reads, not from the
/// order in which drafts happened to be promoted. Inputs of an unknown format reference nothing.
pub(in crate::studio) fn referenced_attachment_ids(
    state: &pl_core::thread::ThreadSnapshot,
) -> Vec<String> {
    let mut ids = std::collections::BTreeSet::new();
    for record in state.inputs.iter() {
        let Ok(content) = input_content(record) else {
            continue;
        };
        for attachment in content.attachments {
            ids.insert(attachment.id);
        }
    }
    ids.into_iter().collect()
}

/// Concatenates actual text chunks without trimming, inserting separators or parsing opaque content.
pub(super) fn text_content(content: &[ContextContent]) -> String {
    content
        .iter()
        .filter_map(|part| match part {
            ContextContent::Text { text } => Some(text.as_ref()),
            ContextContent::Resource { .. } | ContextContent::Opaque { .. } => None,
        })
        .collect()
}

/// Host 提交身份的稳定摘要，用于跨重启校验重复提交的正文。
///
/// 摘要只覆盖幂等受理真正比对的字段（原始 request 与 presentation），因此可以从保存的载荷
/// 重新计算；它不覆盖框架路由回执、附件解析结果、序列号或展示正文。
pub(in crate::studio) fn prompt_request_digest(
    request: &pl_protocol::studio::StudioPromptInput,
    presentation: MessagePresentation,
) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(b"pl.studio.prompt-request\0");
    hasher.update(serde_json::to_vec(request).unwrap_or_default());
    hasher.update([0]);
    hasher.update(match presentation {
        MessagePresentation::Visible => b"visible".as_slice(),
        MessagePresentation::Hidden => b"hidden".as_slice(),
    });
    format!("sha256:{}", hex::encode(hasher.finalize()))
}

/// 无正文控制输入的请求摘要：绑定会话、用途、继续点与调用方冻结的模型路由版本。
///
/// 控制输入没有 host 提交正文可摘要，它的「内容」就是这次继续针对的继续点与它观察到的路由
/// 版本。三项都在首次受理时确定并由身份索引保留首写值，所以同一 operationId 的同一请求永远
/// 得到同一个摘要；继续点或路由版本不同即明确冲突，而不是被当成原回执重放。
pub(in crate::studio) fn continuation_request_digest(
    thread_id: &str,
    point_id: &str,
    expected_model_route_revision: Option<u64>,
) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(b"pl.studio.continuation-request\0");
    hasher.update(thread_id.as_bytes());
    hasher.update([0]);
    hasher.update(b"continuation");
    hasher.update([0]);
    hasher.update(point_id.as_bytes());
    hasher.update([0]);
    match expected_model_route_revision {
        Some(revision) => hasher.update(revision.to_le_bytes()),
        // 无法证明路由版本时也必须是一个确定的值，不能让缺失退化成「任意版本都匹配」。
        None => hasher.update(b"unknown-route-revision"),
    };
    format!("sha256:{}", hex::encode(hasher.finalize()))
}

/// 从已保存的 `pl.studio.prompt` 载荷重建 host 提交身份摘要。
///
/// 返回 `None` 表示这份载荷无法证明正文身份（格式/版本不符、缺少原始 request 或结构未知）。
/// 调用方必须把无法校验的持久化幂等命中当作身份冲突，不能退回只按 ID 命中的 no-op。
pub(in crate::studio) fn saved_prompt_request_digest(payload: &OpaquePayload) -> Option<String> {
    if payload.format() != "pl.studio.prompt" || payload.version() != 1 {
        return None;
    }
    let prompt: Prompt = serde_json::from_str(payload.content()).ok()?;
    Some(prompt_request_digest(
        prompt._request.as_ref()?,
        prompt.presentation,
    ))
}
