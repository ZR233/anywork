//! Original reliable atom facts, independent of any presentation fold.
use super::*;
use pl_protocol::{ChatAtom, ChatAtomLifecycle};

fn lightweight(atom: &ChatAtom) -> ChatAtom {
    let mut atom = atom.clone();
    atom.payload = None;
    atom.wait = None;
    atom.source_state = None;
    atom
}

pub(super) async fn apply(
    db: &impl ConnectionTrait,
    atoms: &[ChatAtom],
    effect: u64,
) -> Result<()> {
    for atom in atoms {
        let (at, phase) = match atom.lifecycle {
            ChatAtomLifecycle::Active { started, .. } => (started, "start"),
            ChatAtomLifecycle::Terminal { ended, .. } => (ended, "terminal"),
        };
        ensure!(
            at.is_none_or(|at| at.effect_seq <= effect),
            "atom fact exceeds its effect"
        );
        let bytes = serde_json::to_vec(&lightweight(atom))?;
        let written = db.execute_raw(statement(
            "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata)
             VALUES(?,?,?,?,?,?) ON CONFLICT(atom_id,phase) DO UPDATE SET metadata=excluded.metadata
             WHERE conversation_atom_facts.metadata=excluded.metadata",
            vec![integer(at.map_or(effect, |at| at.effect_seq))?.into(),
                i64::from(at.map_or(0, |at| at.suborder)).into(), atom.id.clone().into(), phase.into(),
                integer(atom.source_order.or(atom.completion_seq).unwrap_or(0))?.into(), bytes.into()],
        )).await?;
        ensure!(
            written.rows_affected() == 1,
            "canonical atom phase changed for {} ({phase}); original fact preserved",
            atom.id
        );
    }
    Ok(())
}

pub(super) async fn verify(db: &impl ConnectionTrait, atoms: &[ChatAtom]) -> Result<()> {
    for atom in atoms {
        let phase = if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
            "start"
        } else {
            "terminal"
        };
        let row = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_atom_facts WHERE atom_id=? AND phase=?",
                vec![atom.id.clone().into(), phase.into()],
            ))
            .await?
            .context("retried canonical atom fact missing")?;
        ensure!(
            row.try_get::<Vec<u8>>("", "metadata")? == serde_json::to_vec(&lightweight(atom))?,
            "retried canonical atom fact differs"
        );
    }
    Ok(())
}
