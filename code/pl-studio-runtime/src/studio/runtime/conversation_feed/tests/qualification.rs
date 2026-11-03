//! Existing opaque history qualification, content ownership and revocation.
use super::atoms::{Harness, finish, start};
use super::*;

fn position(batch: &ChatBatch) -> Result<u64> {
    let [ChatEntry::Item(item)] = batch.entries.as_slice() else {
        bail!("one-item Main page returned a member or wrong count");
    };
    item.position.context("history position")
}
fn invalid(result: Result<ChatBatch>) {
    let error = result.expect_err("mixed qualification was accepted");
    assert!(
        matches!(
            error.downcast_ref::<core::ChatError>(),
            Some(core::ChatError::InvalidArgument(_))
        ),
        "{error:#}"
    );
}
#[tokio::test]
async fn opaque_older_cut_survives_append_and_writeback_and_rejects_other_scopes() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = Harness::new(&env).await?;
        let one = ReadDemand {
            max_items: 1,
            ..demand()
        };
        for id in ["old-a", "old-b"] {
            let prepared = harness
                .effect(vec![start(id, false)], vec![finish(id, false, id)?])
                .await?;
            harness.save(&prepared).await?;
        }
        let mut feed = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, one)
            .await?;
        let initial = chat(&mut feed).await?;
        assert_eq!(position(&initial)?, 1);
        let h0 = initial.before.clone().context("original continuation")?;
        let reader = feed.reader().clone();
        assert_eq!(reader.inner.ceiling, 2);
        let durable = harness.session.durable_seq();
        let newer = harness
            .effect(
                vec![start("new", false)],
                vec![finish("new", false, &"body".repeat(32768))?],
            )
            .await?;
        let append = chat(&mut feed).await?;
        assert_eq!(position(&append)?, 2);
        assert!(append.before.is_none());
        assert_eq!(
            harness.session.durable_seq(),
            durable,
            "delivery forced persistence"
        );
        let ChatEntry::Item(item) = &append.entries[0] else {
            unreachable!()
        };
        let PayloadData::Inline { bytes: original } =
            item.payload.as_ref().context("original envelope")?
        else {
            bail!("small envelope around large body was not Inline");
        };
        let reference = ContentRef {
            database_id: harness
                .history
                .conversation_database_id()
                .await?
                .context("database")?,
            target: ContentTarget::ItemPayload {
                item_id: item.content_item_id.clone().context("content owner")?,
            },
        };
        let bytes = reader
            .read_content(
                &reference,
                ContentRange {
                    offset: 0,
                    max_bytes: u32::try_from(original.len())?,
                },
            )
            .await?;
        assert_eq!(&bytes.bytes, original);
        let envelope: serde_json::Value = serde_json::from_slice(&bytes.bytes)?;
        assert_eq!(envelope["type"], "text");
        assert!(
            envelope["bodies"]
                .as_array()
                .context("manifest")?
                .iter()
                .any(|body| body["byteLength"] == 131072)
        );
        assert!(
            envelope["bodies"]
                .as_array()
                .unwrap()
                .iter()
                .any(|body| body["reference"].is_object() && body.get("inline").is_none())
        );
        let exact = ReadDemand {
            max_items: 1,
            max_bytes: u32::try_from(append.encoded_len()?)?,
        };
        reader.finish_batch(append.clone(), exact)?;
        assert!(
            reader
                .finish_batch(
                    append,
                    ReadDemand {
                        max_bytes: exact.max_bytes - 1,
                        ..exact
                    }
                )
                .is_err()
        );
        let later = harness
            .effect(
                vec![start("later", false)],
                vec![finish("later", false, "later")?],
            )
            .await?;
        // The old cursor stays at its original item cut across RAM->SQLite handoff.
        harness.save(&newer).await?;
        harness.save(&later).await?;
        let oldest = reader.load_older(&h0, one).await?;
        assert_eq!(position(&oldest)?, 0);
        assert!(oldest.before.is_none());
        assert!(oldest.current.is_none());
        assert_eq!(position(&reader.load_older(&h0, one).await?)?, 0);
        invalid(reader.load_older("bad token", one).await);
        let started = harness.effect(vec![start("work", true)], vec![]).await?;
        let reference = started
            .current
            .projection
            .items
            .iter()
            .find_map(|item| item.members.clone())
            .context("member scope")?;
        let mut group = env
            .runtime
            .open_conversation_feed(
                &harness.thread.id,
                ChatScope::GroupMembers { reference },
                one,
            )
            .await?;
        let members = chat(&mut group).await?;
        assert!(matches!(members.entries.as_slice(), [ChatEntry::Atom(_)]));
        invalid(group.reader().load_older(&h0, one).await);
        let mut other = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, one)
            .await?;
        let _ = chat(&mut other).await?;
        invalid(other.reader().load_older(&h0, one).await);
        // Source ABA retires the original read qualification, not just feed receive.
        let slot = env
            .runtime
            .thread_observations
            .observation_slot(&harness.thread.id);
        slot.retire(&harness.source);
        slot.install(harness.source.clone());
        assert!(reader.load_older(&h0, one).await.is_err());
        group.close().await?;
        group.reader().close().await?;
        other.close().await?;
        other.reader().close().await?;
        feed.close().await?;
        reader.close().await?;
        slot.retire(&harness.source);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
