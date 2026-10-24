//! Product admission budgets are independent of provider-native media capabilities.

use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_protocol::{PureError, studio::StudioAttachmentDraftSource};
use url::Url;

use crate::studio::store::attachment::AttachmentDraftObject;

use super::{normalize::sanitize_filename, source::validate_remote_url};

pub(super) use pl_protocol::studio::{
    ATTACHMENT_MAX_BATCH_BYTES as MAX_BATCH_BYTES, ATTACHMENT_MAX_BATCH_FILES as MAX_BATCH_FILES,
    ATTACHMENT_MAX_FILE_BYTES as MAX_FILE_BYTES,
};

pub(super) fn validate_draft_batch(drafts: &[AttachmentDraftObject]) -> Result<()> {
    ensure!(
        drafts.len() <= MAX_BATCH_FILES,
        "attachment batch exceeds 32 files"
    );
    let mut total = 0_u64;
    for draft in drafts {
        ensure!(
            draft.byte_size <= MAX_FILE_BYTES,
            "attachment exceeds 50 MiB"
        );
        total = total
            .checked_add(draft.byte_size)
            .context("attachment batch byte count overflowed")?;
        ensure!(total <= MAX_BATCH_BYTES, "attachment batch exceeds 128 MiB");
    }
    Ok(())
}

pub(super) fn preflight_sources(sources: &[StudioAttachmentDraftSource]) -> Result<Vec<String>> {
    ensure!(!sources.is_empty(), "attachment source batch is empty");
    ensure!(
        sources.len() <= MAX_BATCH_FILES,
        "attachment batch exceeds 32 files"
    );
    sources
        .iter()
        .map(|source| match source {
            StudioAttachmentDraftSource::LocalFile { path } => Path::new(path)
                .file_name()
                .and_then(|name| name.to_str())
                .map(sanitize_filename)
                .filter(|name| !name.is_empty())
                .context("attachment local file has no safe filename"),
            StudioAttachmentDraftSource::RemoteUrl { url, filename } => {
                let parsed =
                    validate_remote_url(Url::parse(url).context("invalid attachment URL")?)?;
                Ok(filename
                    .as_deref()
                    .map(sanitize_filename)
                    .filter(|name| !name.is_empty())
                    .or_else(|| parsed.path_segments()?.next_back().map(sanitize_filename))
                    .filter(|name| !name.is_empty())
                    .unwrap_or_else(|| "attachment".into()))
            }
        })
        .collect()
}

pub(super) fn admission_rejection(error: anyhow::Error) -> anyhow::Error {
    anyhow::Error::new(PureError::ConfigError(format!(
        "attachment admission rejected: {error:#}"
    )))
}
