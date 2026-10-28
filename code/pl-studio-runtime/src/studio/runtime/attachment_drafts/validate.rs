//! Product admission budgets are independent of provider-native media capabilities.

use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{StudioAttachmentDraftSource, StudioError};
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
        StudioError::invalid_argument("一次最多添加 32 个附件。")
    );
    let mut total = 0_u64;
    for draft in drafts {
        ensure!(
            draft.byte_size <= MAX_FILE_BYTES,
            StudioError::invalid_argument("单个附件不能超过 50 MiB。")
        );
        total = total
            .checked_add(draft.byte_size)
            .context(StudioError::invalid_argument("附件总大小超出限制。"))?;
        ensure!(
            total <= MAX_BATCH_BYTES,
            StudioError::invalid_argument("附件总大小不能超过 128 MiB。")
        );
    }
    Ok(())
}

pub(super) fn preflight_sources(sources: &[StudioAttachmentDraftSource]) -> Result<Vec<String>> {
    ensure!(
        !sources.is_empty(),
        StudioError::invalid_argument("请选择要添加的附件。")
    );
    ensure!(
        sources.len() <= MAX_BATCH_FILES,
        StudioError::invalid_argument("一次最多添加 32 个附件。")
    );
    sources
        .iter()
        .map(|source| match source {
            StudioAttachmentDraftSource::LocalFile { path } => Path::new(path)
                .file_name()
                .and_then(|name| name.to_str())
                .map(sanitize_filename)
                .filter(|name| !name.is_empty())
                .context(StudioError::invalid_argument("附件文件名无效。")),
            StudioAttachmentDraftSource::RemoteUrl { url, filename } => {
                let parsed =
                    Url::parse(url).context(StudioError::invalid_argument("附件 URL 无效。"))?;
                let parsed = validate_remote_url(parsed).context(StudioError::invalid_argument(
                    "附件 URL 必须是无凭据、无片段的公网 HTTPS 地址。",
                ))?;
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
