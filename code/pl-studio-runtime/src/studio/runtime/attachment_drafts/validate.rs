//! 附件准入校验：来源模态预测、模型能力、数量/字节/混合策略等批次约束，以及拒绝错误的包装。

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_model::model::{
    MediaMixPolicy, MediaRepresentation, ModelInfo, ModelInputSource, ModelModality,
};
use pl_protocol::studio::{StudioAttachmentDraftSource, StudioAttachmentModality, StudioError};
use url::Url;

use crate::studio::store::attachment::AttachmentDraftObject;

use super::normalize::{NormalizedSource, sanitize_filename};
use super::source::validate_remote_url;

fn validate_predicted_counts(
    model: &ModelInfo,
    modalities: impl Iterator<Item = StudioAttachmentModality>,
) -> Result<()> {
    let mut counts = BTreeMap::new();
    for modality in modalities {
        *counts.entry(modality).or_insert(0_u32) += 1;
    }
    for (modality, count) in counts {
        let capability = model
            .capabilities
            .input_capability(model_modality(modality))
            .with_context(|| unsupported_modality(modality))?;
        if let Some(max_count) = capability.limits.max_count {
            ensure!(
                count <= max_count,
                StudioError::invalid_argument("附件数量超过当前模型限制。")
            );
        }
    }
    Ok(())
}

fn validate_total_bytes(model: &ModelInfo, drafts: &[AttachmentDraftObject]) -> Result<()> {
    let mut totals = BTreeMap::new();
    for draft in drafts {
        let total = totals.entry(draft.modality).or_insert(0_u64);
        *total = total
            .checked_add(draft.byte_size)
            .context("attachment batch byte count overflowed")?;
    }
    for (modality, total) in totals {
        let capability = model
            .capabilities
            .input_capability(model_modality(modality))
            .with_context(|| unsupported_modality(modality))?;
        if let Some(max_total_bytes) = capability.limits.max_total_bytes {
            ensure!(
                total <= max_total_bytes,
                StudioError::invalid_argument("附件总大小超过当前模型限制。")
            );
        }
    }
    Ok(())
}

pub(super) fn validate_actual_limits(model: &ModelInfo, source: &NormalizedSource) -> Result<()> {
    let capability = model
        .capabilities
        .input_capability(model_modality(source.modality))
        .with_context(|| unsupported_modality(source.modality))?;
    if let Some(max_bytes) = capability.limits.max_bytes {
        ensure!(
            source.bytes.len() as u64 <= max_bytes,
            StudioError::invalid_argument("附件大小超过当前模型限制。")
        );
    }
    if let Some(max_width) = capability.limits.max_width {
        ensure!(
            source.width.is_some_and(|width| width <= max_width),
            StudioError::invalid_argument("附件图片宽度超过当前模型限制。")
        );
    }
    if let Some(max_height) = capability.limits.max_height {
        ensure!(
            source.height.is_some_and(|height| height <= max_height),
            StudioError::invalid_argument("附件图片高度超过当前模型限制。")
        );
    }
    if !capability.limits.media_types.is_empty() {
        ensure!(
            capability
                .limits
                .media_types
                .iter()
                .any(|media_type| media_type == &source.media_type),
            StudioError::invalid_argument("当前模型不支持该附件的媒体类型。")
        );
    }
    Ok(())
}

pub(super) fn validate_draft_batch(
    model: &ModelInfo,
    drafts: &[AttachmentDraftObject],
) -> Result<()> {
    validate_mix_policy(model, drafts.iter().map(|draft| draft.modality))?;
    validate_predicted_counts(model, drafts.iter().map(|draft| draft.modality))?;
    validate_total_bytes(model, drafts)?;
    for draft in drafts {
        validate_model_source(
            model,
            draft.modality,
            if draft.initial_remote_url.is_some() {
                DraftSourceKind::RemoteUrl
            } else {
                DraftSourceKind::Local
            },
        )?;
        let source = NormalizedSource {
            modality: draft.modality,
            media_type: draft.media_type.clone(),
            bytes: Vec::new(),
            width: draft.width,
            height: draft.height,
        };
        let capability = model
            .capabilities
            .input_capability(model_modality(draft.modality))
            .with_context(|| unsupported_modality(draft.modality))?;
        if let Some(max_bytes) = capability.limits.max_bytes {
            ensure!(
                draft.byte_size <= max_bytes,
                StudioError::invalid_argument("附件大小超过当前模型限制。")
            );
        }
        if let Some(max_width) = capability.limits.max_width {
            ensure!(
                draft.width.is_some_and(|width| width <= max_width),
                StudioError::invalid_argument("附件图片宽度超过当前模型限制。")
            );
        }
        if let Some(max_height) = capability.limits.max_height {
            ensure!(
                draft.height.is_some_and(|height| height <= max_height),
                StudioError::invalid_argument("附件图片高度超过当前模型限制。")
            );
        }
        if !capability.limits.media_types.is_empty() {
            ensure!(
                capability
                    .limits
                    .media_types
                    .iter()
                    .any(|media_type| media_type == &source.media_type),
                StudioError::invalid_argument("当前模型不支持该附件的媒体类型。")
            );
        }
    }
    Ok(())
}

pub(super) fn preflight_sources(
    sources: &[StudioAttachmentDraftSource],
    model: &ModelInfo,
) -> Result<Vec<(String, StudioAttachmentModality, DraftSourceKind)>> {
    ensure!(
        !sources.is_empty(),
        StudioError::invalid_argument("请选择要添加的附件。")
    );
    let mut predicted = Vec::with_capacity(sources.len());
    for source in sources {
        let (filename, modality, source_kind) = predict_source(source)?;
        validate_model_source(model, modality, source_kind)?;
        predicted.push((filename, modality, source_kind));
    }
    validate_mix_policy(model, predicted.iter().map(|entry| entry.1))?;
    validate_predicted_counts(model, predicted.iter().map(|entry| entry.1))?;
    Ok(predicted)
}

fn unsupported_modality(modality: StudioAttachmentModality) -> StudioError {
    let label = match modality {
        StudioAttachmentModality::Image => "图片",
        StudioAttachmentModality::Video => "视频",
        StudioAttachmentModality::File => "文件",
    };
    StudioError::invalid_argument(format!("当前模型不支持{label}附件。"))
}

#[derive(Debug, Clone, Copy)]
pub(super) enum DraftSourceKind {
    Local,
    RemoteUrl,
}

fn predict_source(
    source: &StudioAttachmentDraftSource,
) -> Result<(String, StudioAttachmentModality, DraftSourceKind)> {
    match source {
        StudioAttachmentDraftSource::LocalFile { path } => {
            let filename = Path::new(path)
                .file_name()
                .and_then(|name| name.to_str())
                .map(sanitize_filename)
                .filter(|name| !name.is_empty())
                .context(StudioError::invalid_argument("附件文件名无效。"))?;
            let modality = modality_from_filename(&filename)?;
            Ok((filename, modality, DraftSourceKind::Local))
        }
        StudioAttachmentDraftSource::RemoteUrl { url, filename } => {
            let parsed =
                Url::parse(url).context(StudioError::invalid_argument("附件 URL 无效。"))?;
            let parsed = validate_remote_url(parsed).context(StudioError::invalid_argument(
                "附件 URL 必须是无凭据、无片段的公网 HTTPS 地址。",
            ))?;
            let filename = filename
                .as_deref()
                .map(sanitize_filename)
                .filter(|name| !name.is_empty())
                .or_else(|| parsed.path_segments()?.next_back().map(sanitize_filename))
                .filter(|name| !name.is_empty())
                .context(StudioError::invalid_argument(
                    "远端附件需要带扩展名的文件名。",
                ))?;
            let modality = modality_from_filename(&filename)?;
            Ok((filename, modality, DraftSourceKind::RemoteUrl))
        }
    }
}

pub(super) fn validate_model_source(
    model: &ModelInfo,
    modality: StudioAttachmentModality,
    source: DraftSourceKind,
) -> Result<()> {
    let model_modality = model_modality(modality);
    let capability = model
        .capabilities
        .input_capability(model_modality)
        .with_context(|| unsupported_modality(modality))?;
    let source = match source {
        DraftSourceKind::Local => ModelInputSource::Local,
        DraftSourceKind::RemoteUrl => ModelInputSource::RemoteUrl,
    };
    ensure!(
        capability.supports_source(source),
        StudioError::invalid_argument("当前模型不支持该附件来源。")
    );
    let profile = model
        .binding
        .request
        .media_profile(model_modality)
        .context(StudioError::invalid_argument(
            "当前模型未配置该类附件的请求格式。",
        ))?;
    ensure!(
        profile.replay.iter().any(|representation| matches!(
            representation,
            MediaRepresentation::DataUrl | MediaRepresentation::ProviderFile
        )),
        StudioError::invalid_argument("当前模型不支持重放该类附件。")
    );
    Ok(())
}

fn validate_mix_policy(
    model: &ModelInfo,
    modalities: impl Iterator<Item = StudioAttachmentModality>,
) -> Result<()> {
    if model.binding.request.media_mix_policy != MediaMixPolicy::SingleModality {
        return Ok(());
    }
    let unique = modalities.collect::<BTreeSet<_>>();
    ensure!(
        unique.len() <= 1,
        StudioError::invalid_argument("当前模型每次请求只支持一种附件类型。")
    );
    Ok(())
}

pub(super) fn model_modality(modality: StudioAttachmentModality) -> ModelModality {
    match modality {
        StudioAttachmentModality::Image => ModelModality::Image,
        StudioAttachmentModality::Video => ModelModality::Video,
        StudioAttachmentModality::File => ModelModality::File,
    }
}

fn modality_from_filename(filename: &str) -> Result<StudioAttachmentModality> {
    let extension = Path::new(filename)
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .context(StudioError::invalid_argument("附件文件名需要扩展名。"))?;
    Ok(match extension.as_str() {
        "png" | "jpg" | "jpeg" | "gif" | "webp" => StudioAttachmentModality::Image,
        "mp4" | "mov" | "webm" | "mkv" => StudioAttachmentModality::Video,
        _ => StudioAttachmentModality::File,
    })
}
