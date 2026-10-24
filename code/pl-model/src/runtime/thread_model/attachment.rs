//! Versioned durable attachment metadata. Only this boundary interprets old opaque payloads.
use super::{AdapterError, failure};
use crate::completion::AttachmentModality;
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload, ResourceReference},
    model::{ModelError, ModelFailureKind},
};

pub(super) const FORMAT: &str = "pl.model.attachment";
const VERSION: u32 = 2;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(super) enum Attachment {
    Native {
        reference: ResourceReference,
        modality: AttachmentModality,
    },
    UserFile {
        reference: ResourceReference,
        modality: AttachmentModality,
        filename: String,
    },
}

impl Attachment {
    pub(super) fn reference(&self) -> &ResourceReference {
        match self {
            Self::Native { reference, .. } | Self::UserFile { reference, .. } => reference,
        }
    }
    pub(super) fn modality(&self) -> AttachmentModality {
        match self {
            Self::Native { modality, .. } | Self::UserFile { modality, .. } => *modality,
        }
    }
    pub(super) fn filename(&self) -> Option<&str> {
        match self {
            Self::Native { .. } => None,
            Self::UserFile { filename, .. } => Some(filename),
        }
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyAttachment {
    reference: ResourceReference,
    modality: AttachmentModality,
}

/// Explicit native media, retaining strict capability checks even with a user-file host installed.
///
/// # Errors
/// Rejects malformed resource metadata or projection encoding failure.
pub fn attachment_content(
    reference: ResourceReference,
    modality: AttachmentModality,
) -> Result<ContextContent, ModelError> {
    content(Attachment::Native {
        reference,
        modality,
    })
}

/// A reliable user original. Every request chooses native media or a host workspace file anew.
/// Filenames are display metadata; the host must independently choose a safe physical filename.
///
/// # Errors
/// Rejects malformed references, empty filenames or projection encoding failure.
pub fn user_attachment_content(
    reference: ResourceReference,
    modality: AttachmentModality,
    filename: String,
) -> Result<ContextContent, ModelError> {
    if filename.trim().is_empty() {
        return Err(invalid("user attachment filename is empty"));
    }
    content(Attachment::UserFile {
        reference,
        modality,
        filename,
    })
}

fn content(attachment: Attachment) -> Result<ContextContent, ModelError> {
    attachment
        .reference()
        .validate()
        .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
    let content = serde_json::to_string(&attachment)
        .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
    let payload = OpaquePayload::new(FORMAT, VERSION, content)
        .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
    Ok(ContextContent::Opaque { payload })
}

/// Host-owned media identity and modality decoded without choosing a message role.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolAttachment {
    pub reference: ResourceReference,
    pub modality: AttachmentModality,
}

/// Decodes model-owned attachment metadata; unrelated opaque content returns `Ok(None)`.
///
/// # Errors
/// Rejects unsupported versions, malformed content and invalid resource metadata.
pub fn decode_attachment(payload: &OpaquePayload) -> Result<Option<ToolAttachment>, ModelError> {
    if payload.format() != FORMAT {
        return Ok(None);
    }
    let attachment = decode(payload, None)?;
    Ok(Some(ToolAttachment {
        reference: attachment.reference().clone(),
        modality: attachment.modality(),
    }))
}

pub(super) fn decode(
    payload: &OpaquePayload,
    source: Option<&ContextSource>,
) -> Result<Attachment, ModelError> {
    if payload.format() != FORMAT {
        return Err(invalid("unknown attachment projection"));
    }
    let attachment: Attachment = match payload.version() {
        VERSION => serde_json::from_str(payload.content())
            .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?,
        1 => {
            let old: LegacyAttachment = serde_json::from_str(payload.content())
                .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
            // Version 1 had no origin field. Its original record role is the migration
            // evidence: tool results remain native; user-origin records gain file routing.
            if source.is_some_and(user_source) {
                let filename = match old.reference.media_type() {
                    "image/png" => "attachment.png",
                    "image/jpeg" => "attachment.jpg",
                    "image/gif" => "attachment.gif",
                    "image/webp" => "attachment.webp",
                    "application/pdf" => "attachment.pdf",
                    "text/plain" => "attachment.txt",
                    _ => "attachment",
                }
                .to_owned();
                Attachment::UserFile {
                    reference: old.reference,
                    modality: old.modality,
                    filename,
                }
            } else {
                Attachment::Native {
                    reference: old.reference,
                    modality: old.modality,
                }
            }
        }
        _ => return Err(invalid("unknown attachment projection version")),
    };
    attachment
        .reference()
        .validate()
        .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
    if attachment
        .filename()
        .is_some_and(|filename| filename.trim().is_empty())
    {
        return Err(invalid("user attachment filename is empty"));
    }
    if source.is_some_and(|source| {
        !user_source(source)
            && (!matches!(source, ContextSource::ToolResult { .. })
                || attachment.filename().is_some())
    }) {
        return Err(invalid(
            "user file projection has an unsupported source role",
        ));
    }
    Ok(attachment)
}

fn user_source(source: &ContextSource) -> bool {
    matches!(
        source,
        ContextSource::User
            | ContextSource::Runtime { .. }
            | ContextSource::RuntimeFact { .. }
            | ContextSource::AgentMessage { .. }
    )
}

pub(super) fn invalid(message: &'static str) -> ModelError {
    failure(
        ModelFailureKind::UnsupportedContent,
        AdapterError::Content(message),
    )
}
