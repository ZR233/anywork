//! Minimal public HTTP ceiling proof: the one 128MiB positive batch also
//! contains exact-50MiB files, avoiding a redundant giant positive upload.

use super::super::Session;
use super::write_json;
use crate::http::PatternUpload;
use anyhow::{Context, Result, ensure};
use pl_protocol::studio::{
    StudioAttachmentAdmissionContext, StudioAttachmentModality, StudioErrorCode,
};
use pl_provider_fixture::bots_observe as model;
use serde::Serialize;

const MIB: u64 = 1024 * 1024;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AcceptedOriginal {
    draft_id: String,
    filename: String,
    byte_len: u64,
    sha256: String,
    removed: bool,
}

pub(super) async fn run(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let context = StudioAttachmentAdmissionContext::NewThread {
        mode: pl_protocol::ThreadModeId::SIMPLE.into(),
    };
    let tiny = (0..32)
        .map(|index| PatternUpload {
            filename: format!("边界 文件 {index}.data"),
            byte_len: if index == 0 { 0 } else { 17 + index },
            byte: 0x80 + index as u8,
        })
        .collect::<Vec<_>>();
    let mut accepted = verify_accepted(session, &context, &tiny).await?;
    ensure!(
        accepted
            .iter()
            .filter(|file| file.byte_len == 0 && file.sha256 == model::sha256(&[]) && file.removed)
            .count()
            == 1,
        "the 32-file positive must include one real empty DTO/GET/deleted draft"
    );
    evidence.push("32 real files including one 0B file admitted; public DTO sizes and independent GET bytes/digests checked; all drafts explicitly removed".into());
    let mut too_many = tiny;
    too_many.push(PatternUpload {
        filename: "第 33 项.data".into(),
        byte_len: 1,
        byte: 0xff,
    });
    verify_rejected(session, &context, &too_many).await?;
    evidence.push("33-file public multipart request rejected through typed InvalidArgument".into());

    let batch = vec![
        PatternUpload {
            filename: "单文件 上限 A.data".into(),
            byte_len: 50 * MIB,
            byte: 0x80,
        },
        PatternUpload {
            filename: "单文件 上限 B.data".into(),
            byte_len: 50 * MIB,
            byte: 0x90,
        },
        PatternUpload {
            filename: "批次 尾部.data".into(),
            byte_len: 28 * MIB,
            byte: 0xa0,
        },
    ];
    accepted.extend(verify_accepted(session, &context, &batch).await?);
    evidence.push("one real 128MiB batch (50MiB + 50MiB + 28MiB) admitted; each raw original read back and hashed; no second redundant large positive sample".into());
    verify_rejected(
        session,
        &context,
        &[PatternUpload {
            filename: "超过单文件 上限.data".into(),
            byte_len: 50 * MIB + 1,
            byte: 0x80,
        }],
    )
    .await?;
    let mut oversized_batch = batch;
    oversized_batch[2].byte_len += 1;
    verify_rejected(session, &context, &oversized_batch).await?;
    evidence.push("50MiB+1 single file and 128MiB+1 three-file batch rejected by the real typed public admission path".into());
    ensure!(
        session.model_executions() == 0
            && session
                .control()?
                .snapshot_report()
                .await
                .uploads
                .is_empty(),
        "ordinary admission ceilings unexpectedly executed the model or uploaded to Feishu"
    );
    write_json(session, "admission-ceiling-originals.json", &accepted)?;
    Ok("ordinary public multipart admission accepted 32 files including a real 0B original, exact 50MiB originals and exact 128MiB batch with unchanged DTO sizes/display names/raw GET hashes; rejected 33 files, 50MiB+1 and 128MiB+1; all accepted drafts explicitly removed".into())
}

async fn verify_accepted(
    session: &Session,
    context: &StudioAttachmentAdmissionContext,
    files: &[PatternUpload],
) -> Result<Vec<AcceptedOriginal>> {
    let admitted = session
        .http()?
        .upload_patterns_result(context, files)
        .await?
        .map_err(|error| {
            anyhow::anyhow!(
                "valid public ceiling request rejected: {} ({:?})",
                error.message,
                error.code
            )
        })?;
    let verification = async {
        ensure!(admitted.drafts.len() == files.len(), "admission silently dropped a boundary file");
        let mut result = Vec::new();
        for (draft, expected) in admitted.drafts.iter().zip(files) {
            ensure!(draft.filename == expected.filename && draft.byte_size == expected.byte_len && draft.modality == StudioAttachmentModality::File, "ordinary admission lost user display name, bytes or generic-file classification: {draft:?}");
            let bytes = session.http()?.draft_bytes(&draft.draft_id).await?;
            let digest = model::sha256(&bytes);
            ensure!(bytes.len() as u64 == expected.byte_len && digest == model::repeated_sha256(expected.byte, expected.byte_len), "ordinary admitted raw bytes changed at the public GET boundary");
            result.push(AcceptedOriginal { draft_id: draft.draft_id.clone(), filename: draft.filename.clone(), byte_len: draft.byte_size, sha256: digest, removed: false });
        }
        Ok::<_, anyhow::Error>(result)
    }.await;
    let mut cleanup = Vec::new();
    for draft in &admitted.drafts {
        if let Err(error) = session.http()?.remove_draft(&draft.draft_id).await {
            cleanup.push(format!("{error:#}"));
        }
    }
    ensure!(
        cleanup.is_empty(),
        "accepted boundary draft cleanup failed: {}",
        cleanup.join("; ")
    );
    verification.map(|mut originals| {
        for original in &mut originals {
            original.removed = true;
        }
        originals
    })
}

async fn verify_rejected(
    session: &Session,
    context: &StudioAttachmentAdmissionContext,
    files: &[PatternUpload],
) -> Result<()> {
    let error = session
        .http()?
        .upload_patterns_result(context, files)
        .await?
        .err()
        .context("out-of-budget original file batch was admitted")?;
    ensure!(
        error.code == StudioErrorCode::InvalidArgument,
        "boundary failed for a different reason than input admission: {:?}: {}",
        error.code,
        error.message
    );
    Ok(())
}
