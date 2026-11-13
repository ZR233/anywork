//! Fallible boundary material is prepared before any presentation state is committed.
use super::*;

pub(super) struct PreparedObservation {
    pub member: Arc<DisplayMemberWrite>,
    pub contents: Vec<Arc<ChatContent>>,
    pub thinking_summary: Option<String>,
}

pub(super) fn prepare(
    database: &str,
    previous: &DisplayMemberWrite,
    input: ObservationInput,
    at: ChatFactPosition,
    committed_at: i64,
) -> Result<PreparedObservation> {
    let mut atom = input.atom;
    ensure!(
        atom.id == previous.head.record.atom.id
            && atom.source == previous.head.record.atom.source
            && atom.kind == previous.head.record.atom.kind
            && member_key(&atom)? == previous.association_key,
        "boundary capture changed member ownership"
    );
    ensure!(
        matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }),
        "boundary observation is not active"
    );
    ensure!(
        !matches!(atom.payload, Some(PayloadData::Deferred { .. })),
        "boundary public payload must be captured, not a mutable reference"
    );
    crate::studio::runtime::chat_item::validate_observation(&input.state, &atom, &input.thread_id)?;
    for body in &atom.contents {
        let ContentTarget::Body { owner, key } = &body.reference.target else {
            anyhow::bail!("boundary observation is not a Body reference");
        };
        let owner = crate::studio::conversation_identity::content_owner_key(owner)?;
        ensure!(
            input
                .contents
                .iter()
                .any(|content| content.descriptor.key.owner == owner
                    && content.descriptor.key.key == *key),
            "boundary observation lost its immutable body"
        );
    }
    let owner = pl_protocol::ContentOwner::DisplayObservation {
        block_id: previous.block_id.clone(),
        member_key: previous.head.member_key.clone(),
    };
    let owner_key = crate::studio::conversation_identity::content_owner_key(&owner)?;
    let mut captured = BTreeMap::new();
    for content in input.contents {
        let mut value = content.as_ref().clone();
        let key = value.descriptor.key.key.clone();
        value.descriptor.key.owner = owner_key.clone();
        ensure!(
            captured.insert(key, Arc::new(value)).is_none(),
            "duplicate boundary body identity"
        );
    }
    for body in &mut atom.contents {
        let ContentTarget::Body { key, .. } = &body.reference.target else {
            anyhow::bail!("boundary body is not owned content");
        };
        body.reference.target = ContentTarget::Body {
            owner: owner.clone(),
            key: key.clone(),
        };
    }
    let payload = crate::studio::runtime::chat_item::observation_payload(
        &input.state,
        &atom,
        &captured.values().cloned().collect::<Vec<_>>(),
        crate::studio::runtime::chat_item::ObservationStamp {
            thread_id: &input.thread_id,
            database_id: database,
            owner: &owner,
            boundary: at,
            captured_at: committed_at,
        },
    )?;
    let key = "display.payload".to_owned();
    let content = Arc::new(ChatContent {
        descriptor: pl_core::chat::ContentDescriptor {
            key: ChatContentKey {
                owner: owner_key,
                key: key.clone(),
            },
            byte_length: payload.len() as u64,
            generation: 1,
            media_type: Some("application/json".into()),
        },
        data: pl_core::chat::ContentData::Bytes(payload.into()),
    });
    atom.payload = Some(PayloadData::Deferred {
        reference: ContentRef {
            database_id: database.into(),
            target: ContentTarget::Body {
                owner,
                key: key.clone(),
            },
        },
        byte_length: content.descriptor.byte_length,
    });
    ensure!(
        captured.insert(key, content).is_none(),
        "boundary payload identity conflicts"
    );
    let thinking_summary = material_summary(&atom, &captured)?;
    let mut member = previous.clone();
    member.head.record.atom = atom;
    member.head.record.content_source = DisplayContentSource::FrozenObservation {
        captured_at: Some(committed_at),
        available: true,
    };
    Ok(PreparedObservation {
        member: Arc::new(member),
        contents: captured.into_values().collect(),
        thinking_summary,
    })
}
