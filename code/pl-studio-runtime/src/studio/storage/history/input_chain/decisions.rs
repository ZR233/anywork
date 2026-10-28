//! Borrowed decision projections, not execution snapshots or a second decision ledger.

use super::*;

// Narrow, borrowed JSON views. Unknown business fields remain in the hashed raw row, never in an
// observation-owned snapshot. Identity strings are reserved before a Core decoder can own them.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct IdentityStrings<'a> {
    #[serde(borrow, default)] id: Option<&'a RawValue>,
    #[serde(borrow, default)] digest: Option<&'a RawValue>,
    #[serde(borrow, default)] thread_id: Option<&'a RawValue>,
    #[serde(borrow, default)] turn_id: Option<&'a RawValue>,
    #[serde(borrow, default)] input_id: Option<&'a RawValue>,
    #[serde(borrow, default)] point_id: Option<&'a RawValue>,
    #[serde(borrow, default)] source_turn_id: Option<&'a RawValue>,
    #[serde(borrow, default)] attempt_id: Option<&'a RawValue>,
    #[serde(borrow, default)] task_id: Option<&'a RawValue>,
    #[serde(borrow, default)] call_id: Option<&'a RawValue>,
    #[serde(borrow, default)] tool_id: Option<&'a RawValue>,
    #[serde(borrow, default)] content_digest: Option<&'a RawValue>,
    #[serde(borrow, default)] media_type: Option<&'a RawValue>,
    #[serde(borrow, default)] continuation: Option<&'a RawValue>,
    #[serde(borrow, default)] state: Option<&'a RawValue>,
    #[serde(borrow, default)] delivery: Option<&'a RawValue>,
    #[serde(borrow, default)] value: Option<&'a RawValue>,
    #[serde(borrow, default)] reference: Option<&'a RawValue>,
}

pub(super) fn reserve_record_identities(raw: &str, budget: &mut ChainBudget, depth: u8) -> Result<()> {
    ensure!(depth <= 4, "identity record has an unsupported nested shape");
    let fields: IdentityStrings<'_> = serde_json::from_str(raw)?;
    for value in [fields.id, fields.digest, fields.thread_id, fields.turn_id, fields.input_id,
        fields.point_id, fields.source_turn_id, fields.attempt_id, fields.task_id, fields.call_id,
        fields.tool_id, fields.content_digest, fields.media_type].into_iter().flatten() {
        if value.get() != "null" {
            budget.own((value.get().len() as u64).checked_mul(2)
                .and_then(|bytes| bytes.checked_add(std::mem::size_of::<String>() as u64))
                .context("identity size overflow")?)?;
        }
    }
    for nested in [fields.continuation, fields.state, fields.delivery, fields.value, fields.reference]
        .into_iter().flatten() {
        if nested.get().starts_with('{') { reserve_record_identities(nested.get(), budget, depth + 1)?; }
    }
    Ok(())
}

pub(super) fn each_raw<'de>(raw: &'de str, mut visit: impl FnMut(&'de RawValue) -> Result<()>) -> Result<()> {
    use serde::de::{DeserializeSeed, SeqAccess, Visitor};
    struct Array<'a, F>(&'a mut F);
    impl<'de, F: FnMut(&'de RawValue) -> Result<()>> DeserializeSeed<'de> for Array<'_, F> {
        type Value = ();
        fn deserialize<D: serde::Deserializer<'de>>(self, deserializer: D) -> std::result::Result<(), D::Error> {
            impl<'de, F: FnMut(&'de RawValue) -> Result<()>> Visitor<'de> for Array<'_, F> {
                type Value = ();
                fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str("an array") }
                fn visit_seq<A: SeqAccess<'de>>(self, mut sequence: A) -> std::result::Result<(), A::Error> {
                    while let Some(value) = sequence.next_element::<&'de RawValue>()? {
                        (self.0)(value).map_err(serde::de::Error::custom)?;
                    }
                    Ok(())
                }
            }
            deserializer.deserialize_seq(self)
        }
    }
    let mut decoder = serde_json::Deserializer::from_str(raw);
    Array(&mut visit).deserialize(&mut decoder)?;
    decoder.end()?;
    Ok(())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
enum InteractionTag { Pending, Resolved, Cancelled }

#[derive(serde::Deserialize)]
struct InteractionStateView<'a> {
    kind: InteractionTag,
    #[serde(borrow, default)] value: Option<&'a RawValue>,
}

fn interaction_state(raw: &RawValue) -> Result<InteractionDecisionState> {
    let view: InteractionStateView<'_> = serde_json::from_str(raw.get())?;
    Ok(match view.kind {
        InteractionTag::Pending => { if let Some(value) = view.value { serde_json::from_str::<()>(value.get())?; } InteractionDecisionState::Pending }
        InteractionTag::Cancelled => { if let Some(value) = view.value { serde_json::from_str::<()>(value.get())?; } InteractionDecisionState::Cancelled }
        InteractionTag::Resolved => { ensure!(view.value.is_some(), "resolved interaction has no response"); InteractionDecisionState::Resolved }
    })
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct InteractionView<'a> {
    created_at: i64,
    updated_at: i64,
    revision: u64,
    #[serde(borrow)] request: &'a RawValue,
    #[serde(borrow)] state: &'a RawValue,
    #[serde(borrow, default)] continuation_id: Option<&'a RawValue>,
    #[serde(borrow)] extension_mutations: &'a RawValue,
}

pub(super) fn decision_identity_bytes(summary: &DecisionReceiptSummary) -> Result<u64> {
    (std::mem::size_of::<DecisionReceiptSummary>() as u64).checked_mul(2)
        .and_then(|bytes| bytes.checked_add(summary.decision.id.len() as u64))
        .and_then(|bytes| bytes.checked_add(summary.decision.turn_id.len() as u64))
        .and_then(|bytes| bytes.checked_add(summary.continuation_input.as_ref().map_or(0, |id| id.len()) as u64))
        .context("decision identity size overflow")
}

pub(super) struct ParsedDecision {
    pub(super) summary: DecisionReceiptSummary,
    pub(super) request_hash: String,
}

impl ParsedDecision {
    pub(super) fn identity_bytes(&self) -> Result<u64> {
        decision_identity_bytes(&self.summary)?.checked_add(self.request_hash.len() as u64)
            .and_then(|bytes| bytes.checked_add(std::mem::size_of::<String>() as u64))
            .context("decision identity size overflow")
    }

    pub(super) fn follows(&self, previous: &Self) -> Result<()> {
        ensure!(self.request_hash == previous.request_hash
            && self.summary.decision.id == previous.summary.decision.id
            && self.summary.decision.turn_id == previous.summary.decision.turn_id
            && self.summary.decision.revision > previous.summary.decision.revision,
            "decision receipt changed its request identity or revision order");
        use DecisionState::{Interaction, Permission};
        use InteractionDecisionState::{Pending, Resolved, Cancelled};
        match (&previous.summary.decision.state, &self.summary.decision.state) {
            (Interaction(Pending), Interaction(next)) => ensure!(*next != Pending,
                "interaction receipt repeats a pending revision"),
            (Interaction(Resolved), Interaction(Resolved)) => ensure!(
                self.summary.continuation_input == previous.summary.continuation_input,
                "interaction receipt reached conflicting terminal revisions"),
            (Interaction(Cancelled | Resolved), _) => anyhow::bail!(
                "interaction receipt has a revision after cancellation or a conflicting terminal"),
            (Permission(PermissionState::Pending), Permission(next)) => ensure!(
                *next != PermissionState::Pending
                    && previous.summary.decision.revision.checked_add(1) == Some(self.summary.decision.revision),
                "permission receipt has an impossible transition"),
            (Permission(_), _) => anyhow::bail!("permission receipt reached conflicting terminal revisions"),
            _ => anyhow::bail!("decision receipt changed its kind"),
        }
        Ok(())
    }
}

pub(super) fn receipt_decision(kind: &str, raw: &str, budget: &mut ChainBudget) -> Result<ParsedDecision> {
    budget.own((std::mem::size_of::<DecisionReceiptSummary>() as u64) * 2 + 256)?;
    if kind == "permission" {
        reserve_record_identities(raw, budget, 0)?;
        let record: PermissionRecord = serde_json::from_str(raw)?;
        ensure!(!record.call_id.is_empty() && !record.task_id.is_empty() && !record.turn_id.is_empty()
            && !record.tool_id.is_empty() && record.id.strip_prefix("permission:") == Some(record.call_id.as_str()),
            "permission receipt has inconsistent framework identity");
        ensure!(match record.state {
            PermissionState::Pending => record.revision == 1 && record.response.is_none(),
            PermissionState::Cancelled => record.revision == 2 && record.response.is_none(),
            PermissionState::Allowed | PermissionState::Denied => record.revision == 2,
        }, "permission receipt has an impossible state/revision/response");
        let identity = serde_json::to_vec(&(record.created_at, &record.id, &record.task_id,
            &record.call_id, &record.turn_id, &record.tool_id, &record.payload))?;
        let request_hash = pl_core::context::content_hash(&identity);
        Ok(ParsedDecision {
            summary: DecisionReceiptSummary { decision: DecisionSummary {
                id: record.id, turn_id: record.turn_id, revision: record.revision,
                state: DecisionState::Permission(record.state),
            }, continuation_input: None }, request_hash,
        })
    } else {
        ensure!(kind == "interaction", "unknown decision kind");
        let view: InteractionView<'_> = serde_json::from_str(raw)?;
        reserve_record_identities(view.request.get(), budget, 0)?;
        let request: InteractionRequest = serde_json::from_str(view.request.get())?;
        ensure!(!request.id.is_empty() && !request.turn_id.is_empty() && view.revision > 0,
            "interaction receipt has an empty identity or invalid revision");
        let request_hash = pl_core::context::content_hash(&serde_json::to_vec(&request)?);
        let state = interaction_state(view.state)?;
        if state == InteractionDecisionState::Resolved {
            #[derive(serde::Deserialize)]
            struct Response<'a> { payload: pl_core::context::OpaquePayload, #[serde(borrow)] context: &'a RawValue }
            let state_view: InteractionStateView<'_> = serde_json::from_str(view.state.get())?;
            let response: Response<'_> = serde_json::from_str(state_view.value.context("resolved response is absent")?.get())?;
            // Validate the original Core content vocabulary one element at a time, rather than
            // retaining the whole resolved response or all resource identities in the ledger.
            let _payload = response.payload;
            each_raw(response.context.get(), |value| {
                let mark = budget.mark();
                reserve_record_identities(value.get(), budget, 0)?;
                let _content: pl_core::context::ContextContent = serde_json::from_str(value.get())?;
                drop(_content);
                budget.retain(mark, 0)
            })?;
        }
        each_raw(view.extension_mutations.get(), |value| {
            let mark = budget.mark();
            reserve_record_identities(value.get(), budget, 0)?;
            let mutation: pl_core::thread::extensions::ExtensionMutation = serde_json::from_str(value.get())?;
            drop(mutation);
            budget.retain(mark, 0)
        })?;
        let continuation_input = view.continuation_id.map(|value| budget.json_string(value)).transpose()?;
        ensure!(continuation_input.as_ref().is_none_or(|id| !id.is_empty()
            && state == InteractionDecisionState::Resolved), "interaction claims continuation without resolving");
        let _times = (view.created_at, view.updated_at);
        Ok(ParsedDecision { summary: DecisionReceiptSummary { decision: DecisionSummary {
            id: request.id, turn_id: request.turn_id, revision: view.revision,
            state: DecisionState::Interaction(state),
        }, continuation_input }, request_hash })
    }
}

/// Checkpoint observations deliberately consume only these fields, not business prompts/responses.
/// A checkpoint never supplies continuation authority, even if the stored record carries one.
pub(super) fn checkpoint_decision(kind: &str, raw: &str, budget: &mut ChainBudget) -> Result<DecisionSummary> {
    #[derive(serde::Deserialize)]
    struct Request<'a> { #[serde(borrow)] id: &'a RawValue, #[serde(borrow, rename="turnId")] turn_id: &'a RawValue }
    #[derive(serde::Deserialize)]
    struct Interaction<'a> { #[serde(borrow)] request: Request<'a>, revision: u64, #[serde(borrow)] state: &'a RawValue }
    #[derive(serde::Deserialize)]
    struct Permission<'a> { #[serde(borrow)] id: &'a RawValue, #[serde(borrow, rename="turnId")] turn_id: &'a RawValue,
        revision: u64, state: PermissionState }
    budget.own((std::mem::size_of::<DecisionSummary>() as u64) * 2)?;
    let summary = if kind == "interaction" {
        let value: Interaction<'_> = serde_json::from_str(raw)?;
        DecisionSummary { id: budget.json_string(value.request.id)?, turn_id: budget.json_string(value.request.turn_id)?,
            revision: value.revision, state: DecisionState::Interaction(interaction_state(value.state)?) }
    } else {
        let value: Permission<'_> = serde_json::from_str(raw)?;
        DecisionSummary { id: budget.json_string(value.id)?, turn_id: budget.json_string(value.turn_id)?,
            revision: value.revision, state: DecisionState::Permission(value.state) }
    };
    ensure!(!summary.id.is_empty() && !summary.turn_id.is_empty() && summary.revision > 0,
        "checkpoint decision identity is invalid");
    Ok(summary)
}
