//! Counters at the actual chunk read/write sites. They retain no body material.
use super::*;
use std::cell::RefCell;

#[derive(Default, Clone)]
struct BodyWork {
    materialized_old_rows: u64,
    materialized_old_bytes: u64,
    written_chunk_rows: u64,
    written_chunk_bytes: u64,
}
thread_local! {
    static WORK: RefCell<Option<BodyWork>> = const { RefCell::new(None) };
}
pub(super) fn materialized(bytes: usize) {
    WORK.with_borrow_mut(|work| {
        if let Some(work) = work {
            work.materialized_old_rows += 1;
            work.materialized_old_bytes += bytes as u64;
        }
    });
}
pub(super) fn written(bytes: usize) {
    WORK.with_borrow_mut(|work| {
        if let Some(work) = work {
            work.written_chunk_rows += 1;
            work.written_chunk_bytes += bytes as u64;
        }
    });
}

#[tokio::test]
async fn complete_body_is_written_once_and_replay_verifies_every_byte() -> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let bytes: Arc<[u8]> = Arc::from(vec![b'x'; CHUNK_BYTES * 2 + 37]);
    let content = ChatContent {
        descriptor: ContentDescriptor {
            key: ChatContentKey {
                owner: ChatKey::new("item", "whole")?,
                key: "body".into(),
            },
            byte_length: bytes.len() as u64,
            generation: 1,
            media_type: Some("text/plain".into()),
        },
        data: ContentData::Bytes(bytes.clone()),
    };
    WORK.set(Some(BodyWork::default()));
    write_content(&db, &content, true).await?;
    let initial = WORK.take().unwrap();
    assert_eq!(initial.written_chunk_bytes, bytes.len() as u64);
    assert_eq!(initial.written_chunk_rows, 3);
    assert_eq!(initial.materialized_old_bytes, 0);
    WORK.set(Some(BodyWork::default()));
    write_content(&db, &content, true).await?;
    let replay = WORK.take().unwrap();
    assert_eq!(replay.written_chunk_bytes, 0);
    assert_eq!(replay.materialized_old_rows, 3);
    assert_eq!(replay.materialized_old_bytes, bytes.len() as u64);
    db.execute_raw(statement(
        "UPDATE conversation_content_chunks SET data=? WHERE owner_key=? AND content_key='body' AND byte_offset=0",
        vec![vec![b'y'; CHUNK_BYTES].into(), content.descriptor.key.owner.as_str().into()],
    )).await?;
    assert!(write_content(&db, &content, true).await.is_err());
    Ok(())
}
