//! Text and attachment projection from immutable input facts, independent from current tool renderers.
use crate::{MessagePresentation, ThreadAttachment};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::input::{
        CONTINUATION_PAYLOAD_FORMAT, CONTINUATION_PAYLOAD_VERSION, InputPurpose, InputRecord,
    },
};
use serde::Deserialize;

#[derive(Debug, PartialEq)]
pub(in crate::studio) struct InputContent {
    pub text: String,
    pub attachments: Vec<ThreadAttachment>,
    pub presentation: MessagePresentation,
    pub original: OpaquePayload,
}

#[derive(Debug, thiserror::Error)]
pub(in crate::studio) enum ContentError {
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
    _request: Option<crate::StudioPromptInput>,
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
pub(in crate::studio) enum InputView {
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
pub(in crate::studio) fn input_view(input: &InputRecord) -> Result<InputView, ContentError> {
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
