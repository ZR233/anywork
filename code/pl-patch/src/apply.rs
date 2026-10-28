//! 通过 `PatchBackend` 执行解析后的 hunk 并产出 `PatchOutcome`。

use std::path::Path;

use crate::backend::PatchBackend;
use crate::error::{PATCH_RETRY_GUIDANCE, PatchError, PatchResult};
use crate::matching::{
    find_preserved_json_context_sequence, find_sequence, lines_equivalent,
    supports_preserved_json_context,
};
use crate::outcome::{AppliedChange, PatchOutcome};
use crate::parse::{Hunk, UpdateChunk, parse_patch};

pub async fn apply_patch(
    patch: &str,
    backend: &(impl PatchBackend + Sync),
) -> PatchResult<PatchOutcome> {
    let hunks = parse_patch(patch)?;
    let mut outcome = PatchOutcome::default();

    for hunk in hunks {
        if let Err(error) = apply_hunk(hunk, backend, &mut outcome).await {
            return Err(PatchError::new(format!(
                "{error}{}",
                outcome.failure_suffix(backend)
            )));
        }
    }

    Ok(outcome)
}

async fn apply_hunk(
    hunk: Hunk,
    backend: &(impl PatchBackend + Sync),
    outcome: &mut PatchOutcome,
) -> PatchResult<()> {
    match hunk {
        Hunk::Add { path, content } => {
            let target = backend.resolve_for_write(&path).await?;
            backend.reject_symlink_write(&target).await?;
            let overwritten_content = backend.read_optional_text(&target).await?;
            backend.create_parent_dirs(&target).await?;
            write_text(backend, &target, &content, outcome).await?;
            outcome.record(AppliedChange::Add {
                path: target,
                content,
                overwritten_content,
            });
        }
        Hunk::Delete { path } => {
            let target = backend.resolve_existing(&path).await?;
            backend.reject_symlink_write(&target).await?;
            backend.ensure_file(&target).await?;
            let content = backend.read_to_string(&target).await?;
            backend.remove_file(&target).await?;
            outcome.record(AppliedChange::Delete {
                path: target,
                content,
            });
        }
        Hunk::Update {
            path,
            move_path,
            chunks,
        } => {
            let source = backend.resolve_existing(&path).await?;
            backend.reject_symlink_write(&source).await?;
            let old_content = backend.read_to_string(&source).await?;
            let new_content = if chunks.is_empty() {
                old_content.clone()
            } else {
                apply_chunks(&old_content, &source, &chunks)?
            };

            if let Some(move_path) = move_path {
                let target = backend.resolve_for_write(&move_path).await?;
                backend.reject_symlink_write(&target).await?;
                if target == source {
                    write_text(backend, &source, &new_content, outcome).await?;
                    outcome.record(AppliedChange::Update {
                        path: source,
                        old_content,
                        new_content,
                    });
                    return Ok(());
                }
                let overwritten_target_content = backend.read_optional_text(&target).await?;
                backend.create_parent_dirs(&target).await?;
                write_text(backend, &target, &new_content, outcome).await?;
                let target_change_index = outcome.record(AppliedChange::Add {
                    path: target.clone(),
                    content: new_content.clone(),
                    overwritten_content: overwritten_target_content.clone(),
                });
                backend.remove_file(&source).await?;
                outcome.replace(
                    target_change_index,
                    AppliedChange::Move {
                        source,
                        target,
                        old_content,
                        new_content,
                        overwritten_target_content,
                    },
                );
            } else {
                write_text(backend, &source, &new_content, outcome).await?;
                outcome.record(AppliedChange::Update {
                    path: source,
                    old_content,
                    new_content,
                });
            }
        }
    }
    Ok(())
}

async fn write_text(
    backend: &(impl PatchBackend + Sync),
    path: &Path,
    content: &str,
    outcome: &mut PatchOutcome,
) -> PatchResult<()> {
    backend
        .write_text(path, content)
        .await
        .inspect_err(|_| outcome.mark_inexact())
}

fn apply_chunks(content: &str, path: &Path, chunks: &[UpdateChunk]) -> PatchResult<String> {
    let mut lines: Vec<String> = content.split('\n').map(String::from).collect();
    if lines.last().is_some_and(String::is_empty) {
        lines.pop();
    }
    let mut cursor = 0;
    let mut replacements = Vec::new();
    let allow_preserved_json_context = supports_preserved_json_context(path);

    for chunk in chunks {
        if let Some(context) = &chunk.context {
            let Some(context_index) =
                find_sequence(&lines, std::slice::from_ref(context), cursor, false)
            else {
                return Err(PatchError::new(format!(
                    "failed to find context '{context}' in {}. {PATCH_RETRY_GUIDANCE}",
                    path.display(),
                )));
            };
            cursor = context_index + 1;
        }

        if chunk.old_lines.is_empty() {
            let insert_at = lines.len();
            replacements.push((insert_at, 0, chunk.new_lines.clone()));
            // 纯新增安排在 EOF，但后续块仍需从原游标匹配尚未修改的内容。
            continue;
        }

        let Some((start, old_len, new_lines)) =
            find_chunk_replacement(&lines, chunk, cursor, allow_preserved_json_context)
        else {
            return Err(PatchError::new(format!(
                "failed to find expected lines in {}:\n{}\n{PATCH_RETRY_GUIDANCE}",
                path.display(),
                chunk.old_lines.join("\n")
            )));
        };
        replacements.push((start, old_len, new_lines));
        cursor = start + old_len;
    }

    replacements.sort_by_key(|(start, _, _)| *start);
    for (start, old_len, new_lines) in replacements.into_iter().rev() {
        lines.splice(start..start + old_len, new_lines);
    }
    if !lines.last().is_some_and(String::is_empty) {
        lines.push(String::new());
    }
    Ok(lines.join("\n"))
}

fn find_chunk_replacement(
    lines: &[String],
    chunk: &UpdateChunk,
    cursor: usize,
    allow_preserved_json_context: bool,
) -> Option<(usize, usize, Vec<String>)> {
    let mut candidates = vec![chunk.clone()];
    if let Some(candidate) = duplicated_edge_context_candidate(chunk) {
        candidates.push(candidate);
    }

    for mut candidate in candidates {
        if let Some(replacement) =
            find_candidate_replacement(lines, &candidate, cursor, allow_preserved_json_context)
        {
            return Some(replacement);
        }
        if candidate.old_lines.last().is_some_and(String::is_empty) {
            candidate.old_lines.pop();
            if candidate.new_lines.last().is_some_and(String::is_empty) {
                candidate.new_lines.pop();
            }
            candidate
                .context_line_indices
                .retain(|&(old_index, new_index)| {
                    old_index < candidate.old_lines.len() && new_index < candidate.new_lines.len()
                });
            if let Some(replacement) =
                find_candidate_replacement(lines, &candidate, cursor, allow_preserved_json_context)
            {
                return Some(replacement);
            }
        }
    }
    None
}

fn find_candidate_replacement(
    lines: &[String],
    candidate: &UpdateChunk,
    cursor: usize,
    allow_preserved_json_context: bool,
) -> Option<(usize, usize, Vec<String>)> {
    let start =
        find_sequence(lines, &candidate.old_lines, cursor, candidate.eof).or_else(|| {
            if allow_preserved_json_context {
                find_preserved_json_context_sequence(
                    lines,
                    &candidate.old_lines,
                    &candidate.context_line_indices,
                    cursor,
                    candidate.eof,
                )
            } else {
                None
            }
        })?;
    let matched_lines = &lines[start..start + candidate.old_lines.len()];
    let new_lines = preserve_matched_context_lines(
        &candidate.new_lines,
        &candidate.context_line_indices,
        matched_lines,
    );
    Some((start, candidate.old_lines.len(), new_lines))
}

fn preserve_matched_context_lines(
    new_lines: &[String],
    context_line_indices: &[(usize, usize)],
    matched_lines: &[String],
) -> Vec<String> {
    let mut preserved_lines = new_lines.to_vec();
    for &(old_index, new_index) in context_line_indices {
        preserved_lines[new_index] = matched_lines[old_index].clone();
    }
    preserved_lines
}

fn duplicated_edge_context_candidate(chunk: &UpdateChunk) -> Option<UpdateChunk> {
    if chunk.old_lines.len() != 2 || chunk.new_lines.len() <= chunk.old_lines.len() {
        return None;
    }
    // 两端必须各有解析期的 old/new 上下文配对，不能由同文的删除或新增行推断。
    let &(first_old_context, _) = chunk.context_line_indices.first()?;
    let &(last_old_context, _) = chunk.context_line_indices.last()?;
    if first_old_context != 0 || last_old_context != chunk.old_lines.len() - 1 {
        return None;
    }
    let first_old = chunk.old_lines.first()?;
    let last_old = chunk.old_lines.last()?;
    if !lines_equivalent(first_old, last_old) {
        return None;
    }
    let first_new = chunk.new_lines.first()?;
    let last_new = chunk.new_lines.last()?;
    if !lines_equivalent(first_new, first_old) || !lines_equivalent(last_new, last_old) {
        return None;
    }
    // 新首行移除后，保留第一个仍有新行的上下文对应的旧行。
    // 该旧行索引归零，新行索引减一，其余配对随被丢弃的旧行移除。
    let retained_old_context = chunk
        .context_line_indices
        .iter()
        .find_map(|&(old_index, new_index)| (new_index > 0).then_some(old_index))?;
    let mut candidate = chunk.clone();
    candidate.old_lines = vec![chunk.old_lines[retained_old_context].clone()];
    candidate.new_lines.remove(0);
    candidate
        .context_line_indices
        .retain_mut(|(old_index, new_index)| {
            if *old_index != retained_old_context || *new_index == 0 {
                return false;
            }
            *old_index = 0;
            *new_index -= 1;
            true
        });
    Some(candidate)
}
