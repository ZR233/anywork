//! One-time evidence for text retained only in a schema-17 display summary.
//! This reads original members and bounded content windows, never replays the old fold.
use super::*;
use crate::studio::storage::history::{
    conversation::content::{self, CHUNK_BYTES, MANIFEST_BYTES},
    schema::{
        legacy_completion_projection::{THINKING_SUMMARY_TAIL_BYTES, thinking_summary_tail},
        legacy_timeline_types::TimelineItem,
    },
};
use pl_core::chat::ChatContentKey;
use pl_protocol::{ChatAtomKind, ChatContentRole, ContentTarget};

pub(super) async fn prove(
    db: &impl ConnectionTrait,
    item: &TimelineItem,
    database: &str,
) -> Result<()> {
    let Some(expected) = item
        .summary
        .as_ref()
        .and_then(|summary| summary.latest_thinking_summary.as_deref())
        .filter(|text| !text.is_empty())
    else {
        return Ok(());
    };
    let mut after = -1i64;
    let mut failure = None;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT member_order,metadata FROM timeline_item_members
             WHERE item_id=? AND member_order>? ORDER BY member_order LIMIT 128",
                vec![item.id.clone().into(), after.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "member_order")?;
            // The caller already proved these exact member bytes are retained terminal facts.
            let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
            if atom.kind != ChatAtomKind::Reasoning {
                continue;
            }
            for reference in atom
                .contents
                .iter()
                .filter(|c| c.role == ChatContentRole::ReasoningSummary)
            {
                let ContentTarget::Body { owner, key } = &reference.reference.target else {
                    failure = Some(anyhow::anyhow!(
                        "reasoning summary is not an original body reference"
                    ));
                    continue;
                };
                if reference.reference.database_id != database {
                    failure = Some(anyhow::anyhow!(
                        "reasoning summary belongs to another database"
                    ));
                    continue;
                }
                let key = ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                    key: key.clone(),
                };
                for (directory, chunks) in [
                    ("conversation_contents", "conversation_content_chunks"),
                    (
                        "completion_boundary_archive_contents",
                        "completion_boundary_archive_content_chunks",
                    ),
                ] {
                    match original_summary(db, &key, directory, chunks).await {
                        Ok(Some(actual)) if actual == expected => return Ok(()),
                        Ok(_) => {
                            failure =
                                Some(anyhow::anyhow!("original reasoning summary text differs"))
                        }
                        Err(error) => failure = Some(error),
                    }
                }
            }
        }
    }
    Err(failure
        .unwrap_or_else(|| anyhow::anyhow!("group has no original reasoning summary member")))
    .with_context(|| {
        format!(
            "display summary text is not covered for {}; original database preserved",
            item.id
        )
    })
}

async fn original_summary(
    db: &impl ConnectionTrait,
    key: &ChatContentKey,
    directory: &'static str,
    chunks: &'static str,
) -> Result<Option<String>> {
    // Table names are exclusively the two fixed original/managed archive pairs above.
    let row = db
        .query_one_raw(statement(
            &format!(
                "SELECT length(payload) AS bytes,substr(payload,1,?) AS payload
                  FROM {directory} WHERE owner_key=? AND content_key=?"
            ),
            vec![
                (MANIFEST_BYTES as i64 + 1).into(),
                key.owner.as_str().into(),
                key.key.clone().into(),
            ],
        ))
        .await?
        .context("reasoning summary original/archived manifest is missing")?;
    ensure!(
        row.try_get::<i64>("", "bytes")? <= MANIFEST_BYTES as i64,
        "oversized reasoning summary manifest"
    );
    let manifest = content::manifest(&row.try_get::<Vec<u8>>("", "payload")?)?;

    // Check every chunk's coverage using only indexed offsets/lengths. A missing prefix must
    // fail even when the final 4 KiB still happen to contain the complete display summary.
    let mut after = -1i64;
    let mut end = 0u64;
    loop {
        let rows = db
            .query_all_raw(statement(
                &format!(
                    "SELECT byte_offset,length(data) AS bytes FROM {chunks}
                      WHERE owner_key=? AND content_key=? AND byte_offset>?
                      ORDER BY byte_offset LIMIT 128"
                ),
                vec![
                    key.owner.as_str().into(),
                    key.key.clone().into(),
                    after.into(),
                ],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "byte_offset")?;
            let start = u64::try_from(after)?;
            let size = u64::try_from(row.try_get::<i64>("", "bytes")?)?;
            ensure!(
                start == end && size > 0 && size <= CHUNK_BYTES as u64,
                "reasoning summary original/archived chunks have a gap, overlap or invalid size"
            );
            end = end
                .checked_add(size)
                .context("reasoning summary content length overflow")?;
            ensure!(
                end <= manifest.byte_length,
                "reasoning summary exceeds its manifest"
            );
        }
    }
    ensure!(
        end == manifest.byte_length,
        "reasoning summary original/archived chunks are missing"
    );
    let length = manifest.byte_length.min(THINKING_SUMMARY_TAIL_BYTES as u64);
    let mut position = manifest.byte_length - length;
    let mut tail = Vec::with_capacity(length as usize);
    while position < manifest.byte_length {
        let row = db
            .query_one_raw(statement(
                &format!(
                    "SELECT substr(data,?-byte_offset+1,?) AS bytes FROM {chunks}
                      WHERE owner_key=? AND content_key=? AND byte_offset<=?
                      ORDER BY byte_offset DESC LIMIT 1"
                ),
                vec![
                    integer(position)?.into(),
                    integer(manifest.byte_length - position)?.into(),
                    key.owner.as_str().into(),
                    key.key.clone().into(),
                    integer(position)?.into(),
                ],
            ))
            .await?
            .context("reasoning summary tail chunk is missing")?;
        let part: Vec<u8> = row.try_get("", "bytes")?;
        ensure!(
            !part.is_empty() && part.len() <= THINKING_SUMMARY_TAIL_BYTES - tail.len(),
            "reasoning summary tail does not advance within its bound"
        );
        position += part.len() as u64;
        tail.extend_from_slice(&part);
    }
    Ok(thinking_summary_tail(&tail)?)
}
