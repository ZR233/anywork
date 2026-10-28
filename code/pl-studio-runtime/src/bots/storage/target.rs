//! Frozen creation-time target evidence, not a current trust or membership grant.

use super::{statement, storage, strict_text};
use crate::bots::protocol::error::FeishuError;
use crate::studio::unix_seconds;
use sea_orm::{ConnectionTrait, QueryResult};
use serde::{Deserialize, Serialize};

pub(super) const UNPROVEN: &str = "{\"kind\":\"unproven\"}";

/// Feishu direct peer identities are fixed-shape (`ou_`/`on_` + 32 hex, i.e. 35 bytes).
/// This is a verified upper bound with explicit rejection, never a transform: values above
/// it fail closed at every entry so no live copy can outgrow the accounting below.
pub(super) const MAX_PEER_BYTES: usize = 256;

/// Rejects an unsupported direct peer identity; empty stays "unknown", never "direct".
pub(in crate::bots) fn ensure_peer(open_id: &str) -> Result<(), FeishuError> {
    if open_id.len() > MAX_PEER_BYTES {
        return Err(super::audience::unreadable());
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum TargetKind {
    Group,
    Direct { open_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum TargetSource {
    Operation { operation_id: String },
    Inbound { message_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct CreatedTarget {
    pub bot_id: String,
    pub app_id: String,
    pub project_id: String,
    pub chat_id: String,
    pub creation_id: String,
    pub binding_revision: u64,
    pub target: TargetKind,
    pub source: TargetSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum TargetProof {
    Unproven,
    /// Old sources can prove the kind without inventing a new creation intent or app identity.
    Legacy {
        target: TargetKind,
    },
    Created {
        evidence: CreatedTarget,
    },
}

/// The creation intent asks storage to freeze this draft in its first write. The
/// binding revision is owned by that write, never guessed by the caller.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct TargetClaim {
    pub bot_id: String,
    pub app_id: String,
    pub project_id: String,
    pub chat_id: String,
    pub creation_id: String,
    pub target: TargetKind,
    pub source: TargetSource,
}

impl TargetClaim {
    pub(in crate::bots) fn from_operation(
        bot_id: &str,
        app_id: &str,
        project_id: &str,
        chat_id: &str,
        creation_id: &str,
        operation_id: &str,
        target: TargetKind,
    ) -> Self {
        Self {
            bot_id: bot_id.to_string(),
            app_id: app_id.to_string(),
            project_id: project_id.to_string(),
            chat_id: chat_id.to_string(),
            creation_id: creation_id.to_string(),
            target,
            source: TargetSource::Operation {
                operation_id: operation_id.to_string(),
            },
        }
    }

    pub(in crate::bots) fn from_inbound(
        bot_id: &str,
        app_id: &str,
        project_id: &str,
        chat_id: &str,
        creation_id: &str,
        message_id: &str,
        target: TargetKind,
    ) -> Self {
        Self {
            bot_id: bot_id.to_string(),
            app_id: app_id.to_string(),
            project_id: project_id.to_string(),
            chat_id: chat_id.to_string(),
            creation_id: creation_id.to_string(),
            target,
            source: TargetSource::Inbound {
                message_id: message_id.to_string(),
            },
        }
    }

    pub(in crate::bots) fn freeze(&self, binding_revision: u64) -> TargetProof {
        TargetProof::Created {
            evidence: CreatedTarget {
                bot_id: self.bot_id.clone(),
                app_id: self.app_id.clone(),
                project_id: self.project_id.clone(),
                chat_id: self.chat_id.clone(),
                creation_id: self.creation_id.clone(),
                binding_revision,
                target: self.target.clone(),
                source: self.source.clone(),
            },
        }
    }
}

impl TargetProof {
    pub(in crate::bots) fn validate(&self) -> Result<(), FeishuError> {
        let kind = match self {
            Self::Unproven => return Ok(()),
            Self::Legacy { target } => target,
            Self::Created { evidence } => {
                if [
                    &evidence.bot_id,
                    &evidence.app_id,
                    &evidence.project_id,
                    &evidence.chat_id,
                    &evidence.creation_id,
                ]
                .iter()
                .any(|id| id.is_empty())
                    || evidence.binding_revision == 0
                    || evidence.binding_revision > i64::MAX as u64
                    || match &evidence.source {
                        TargetSource::Operation { operation_id } => operation_id.is_empty(),
                        TargetSource::Inbound { message_id } => message_id.is_empty(),
                    }
                {
                    return Err(super::audience::unreadable());
                }
                &evidence.target
            }
        };
        if matches!(kind, TargetKind::Direct { open_id } if open_id.is_empty()) {
            return Err(super::audience::unreadable());
        }
        if let TargetKind::Direct { open_id } = kind {
            ensure_peer(open_id)?;
        }
        Ok(())
    }

    /// Exact encoded length: callers charge every live copy of it with the checked sum.
    pub(in crate::bots) fn encoded_len(&self) -> Result<usize, FeishuError> {
        Ok(self.encode()?.len())
    }

    pub(in crate::bots) fn kind(&self) -> Option<&TargetKind> {
        match self {
            Self::Unproven => None,
            Self::Legacy { target } => Some(target),
            Self::Created { evidence } => Some(&evidence.target),
        }
    }

    /// Two states of the same creation intent must agree on the proven kind, including
    /// the direct peer identity. Provenance (which message or operation witnessed it)
    /// is only compared where the caller already pins that source.
    pub(in crate::bots) fn same_intent(&self, other: &Self) -> bool {
        self.kind() == other.kind()
    }

    /// Re-delivery of the very fact that froze the proof may re-establish a source row
    /// that never reached storage: the complete frozen identity (bot/app/project/chat/
    /// creation/revision/target and the exact source) must be identical, not merely the
    /// message id or the kind. Any other fact may not stand in for it.
    pub(in crate::bots) fn same_source(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Created { evidence: mine }, Self::Created { evidence: theirs }) => {
                mine == theirs
            }
            _ => false,
        }
    }

    pub(in crate::bots) fn encode(&self) -> Result<String, FeishuError> {
        self.validate()?;
        serde_json::to_string(self).map_err(|_| super::audience::unreadable())
    }

    pub(super) fn decode(row: &QueryResult) -> Result<Self, FeishuError> {
        let proof: Self = serde_json::from_str(&strict_text(row, "target_json")?)
            .map_err(|_| super::audience::unreadable())?;
        proof.validate()?;
        Ok(proof)
    }
}

/// A recorded kind and the completeness of its direct peer are separate facts: a typed
/// `direct` row with no peer still proves "not a group", so it must conflict with a
/// recorded group instead of disappearing.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Fact {
    Group,
    Direct(Option<String>),
}

impl Fact {
    fn kind(&self) -> Option<TargetKind> {
        match self {
            Self::Group => Some(TargetKind::Group),
            Self::Direct(peer) => peer.clone().map(|open_id| TargetKind::Direct { open_id }),
        }
    }
}

/// Only already stored, relevant source facts participate, and only for the chat the
/// caller owns. No config, network or ID heuristic.
pub(super) async fn legacy<C: ConnectionTrait>(
    db: &C,
    thread: &str,
    creation: &str,
    chat: &str,
    project: &str,
) -> Result<TargetProof, FeishuError> {
    legacy_source(db, thread, creation, chat, project, LegacyCards::Present).await
}

/// Only the fully classified pre-card file6/file7 migration boundary may use this entry.
/// Normal runtime reads still require the current card table and never infer its absence.
pub(super) async fn legacy_file_source<C: ConnectionTrait>(
    db: &C,
    creation: &str,
    chat: &str,
    project: &str,
) -> Result<TargetProof, FeishuError> {
    legacy_source(db, "", creation, chat, project, LegacyCards::Absent).await
}

enum LegacyCards {
    Present,
    Absent,
}

async fn legacy_source<C: ConnectionTrait>(
    db: &C,
    thread: &str,
    creation: &str,
    chat: &str,
    project: &str,
    cards: LegacyCards,
) -> Result<TargetProof, FeishuError> {
    if creation.is_empty() || chat.is_empty() {
        return Ok(TargetProof::Unproven);
    }
    let mut known: Option<Fact> = None;
    let mut after = String::new();
    loop {
        let (select, values) = match cards {
            LegacyCards::Present => (
                "SELECT identity,chat_kind,open_id,project_id FROM inbound_work
             WHERE creation_id=?1 AND identity>?2 AND chat_id=?3
             UNION SELECT w.identity,w.chat_kind,w.open_id,w.project_id FROM bot_card_streams c
             JOIN inbound_work w ON w.identity=c.identity
             WHERE c.thread_id=?4 AND w.identity>?2 AND w.chat_id=?3
             ORDER BY identity LIMIT 64",
                vec![
                    creation.into(),
                    after.clone().into(),
                    chat.into(),
                    thread.into(),
                ],
            ),
            LegacyCards::Absent => (
                "SELECT identity,chat_kind,open_id,project_id FROM inbound_work WHERE creation_id=?1 AND identity>?2 AND chat_id=?3 ORDER BY identity LIMIT 64",
                vec![creation.into(), after.clone().into(), chat.into()],
            ),
        };
        let rows = db
            .query_all_raw(statement(select, values))
            .await
            .map_err(storage)?;
        let done = rows.len() < 64;
        for row in rows {
            after = strict_text(&row, "identity")?;
            // 同一 chat/creation 下的证据只能属于同一项目：异项目的非空归属是真实
            // 冲突，不能先过滤掉它再采纳另一个种类。
            let row_project = strict_text(&row, "project_id")?;
            if !row_project.is_empty() && row_project != project {
                return Err(super::audience::unreadable());
            }
            let fact = match strict_text(&row, "chat_kind")?.as_str() {
                "group" => Some(Fact::Group),
                "direct" => {
                    let open_id = strict_text(&row, "open_id")?;
                    Some(Fact::Direct((!open_id.is_empty()).then_some(open_id)))
                }
                _ => None,
            };
            merge(&mut known, fact)?;
        }
        if done {
            break;
        }
    }
    if let Some(row) = db
        .query_one_raw(statement(
            "SELECT open_id FROM observed_directs WHERE chat_id=?",
            vec![chat.into()],
        ))
        .await
        .map_err(storage)?
    {
        let open_id = strict_text(&row, "open_id")?;
        if !open_id.is_empty() {
            merge(&mut known, Some(Fact::Direct(Some(open_id))))?;
        }
    }
    Ok(known
        .and_then(|fact| fact.kind())
        .map_or(TargetProof::Unproven, |target| TargetProof::Legacy {
            target,
        }))
}

fn merge(known: &mut Option<Fact>, next: Option<Fact>) -> Result<(), FeishuError> {
    let Some(next) = next else {
        return Ok(());
    };
    let merged = match (known.as_ref(), &next) {
        (None, _) => next,
        (Some(Fact::Group), Fact::Group) => return Ok(()),
        // A recorded peer only ever completes the same direct fact.
        (Some(Fact::Direct(Some(stored))), Fact::Direct(Some(next))) if stored == next => {
            return Ok(());
        }
        (Some(Fact::Direct(Some(_))), Fact::Direct(None)) => return Ok(()),
        (Some(Fact::Direct(None)), Fact::Direct(peer)) => Fact::Direct(peer.clone()),
        // Any direct/group disagreement, or two different peers, is a real conflict.
        _ => return Err(super::audience::unreadable()),
    };
    *known = Some(merged);
    Ok(())
}

pub(super) fn matches_origin(
    proof: &TargetProof,
    thread: &str,
    chat: &str,
    project: &str,
    creation: &str,
    revision: u64,
) -> Result<(), FeishuError> {
    proof.validate()?;
    if let TargetProof::Created { evidence } = proof
        && (evidence.chat_id != chat
            || evidence.project_id != project
            || evidence.creation_id != creation
            || evidence.binding_revision != revision
            || thread.is_empty())
    {
        return Err(super::audience::unreadable());
    }
    Ok(())
}

/// The exact already-stored fact that justifies a frozen proof, checked inside the same
/// transaction that is about to reference it. Legacy evidence is only what migration
/// already adopted from old sources; Unproven never justifies a write, and a proof whose
/// source row is missing must not be committed as an origin that can never be opened.
pub(super) async fn source_present<C: ConnectionTrait>(
    db: &C,
    proof: &TargetProof,
    chat: &str,
    project: &str,
    creation: &str,
    revision: u64,
) -> Result<bool, FeishuError> {
    match proof {
        TargetProof::Unproven => Ok(false),
        TargetProof::Legacy { .. } => Ok(true),
        TargetProof::Created { evidence } => {
            if evidence.chat_id != chat
                || evidence.project_id != project
                || evidence.creation_id != creation
                || evidence.binding_revision != revision
            {
                return Ok(false);
            }
            let (kind_name, open) = match &evidence.target {
                TargetKind::Group => ("group", ""),
                TargetKind::Direct { open_id } => ("direct", open_id.as_str()),
            };
            let revision = i64::try_from(revision).map_err(|_| super::audience::unreadable())?;
            let encoded = proof.encode()?;
            let row = match &evidence.source {
                TargetSource::Operation { operation_id } => db
                    .query_one_raw(statement(
                        "SELECT 1 FROM binding_operations
                         WHERE operation_id=?1 AND creation_id=?2 AND bot_id=?3 AND chat_id=?4
                           AND expected_revision=?5 AND target_json=?6 LIMIT 1",
                        vec![
                            operation_id.into(),
                            creation.into(),
                            evidence.bot_id.as_str().into(),
                            chat.into(),
                            revision
                                .checked_sub(1)
                                .ok_or_else(super::audience::unreadable)?
                                .into(),
                            encoded.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?,
                TargetSource::Inbound { message_id } => db
                    .query_one_raw(statement(
                        "SELECT 1 FROM inbound_work
                         WHERE message_id=?1 AND creation_id=?2 AND bot_id=?3 AND chat_id=?4
                           AND project_id=?5 AND app_id=?6 AND binding_revision=?7
                           AND chat_kind=?8 AND (?8<>'direct' OR open_id=?9) LIMIT 1",
                        vec![
                            message_id.into(),
                            creation.into(),
                            evidence.bot_id.as_str().into(),
                            chat.into(),
                            project.into(),
                            evidence.app_id.as_str().into(),
                            revision.into(),
                            kind_name.into(),
                            open.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?,
            };
            Ok(row.is_some())
        }
    }
}

/// An operation-sourced proof must reach its final Thread in the same transaction that
/// writes the route and origin. Two separate commits would leave a restart window where
/// the origin exists while its source operation still points nowhere, and the strict open
/// check would then reject the whole database.
pub(super) async fn bind_operation_thread<C: ConnectionTrait>(
    db: &C,
    proof: &TargetProof,
    chat: &str,
    creation: &str,
    revision: u64,
    thread: &str,
) -> Result<(), FeishuError> {
    let TargetProof::Created { evidence } = proof else {
        return Ok(());
    };
    let TargetSource::Operation { operation_id } = &evidence.source else {
        return Ok(());
    };
    let expected_revision = i64::try_from(revision)
        .map_err(|_| super::audience::unreadable())?
        .checked_sub(1)
        .ok_or_else(super::audience::unreadable)?;
    let updated = db
        .execute_raw(statement(
            "UPDATE binding_operations SET thread_id=?1, updated_at=?2
             WHERE operation_id=?3 AND chat_id=?4 AND creation_id=?5 AND bot_id=?6
               AND expected_revision=?7 AND target_json=?8
               AND (thread_id='' OR thread_id=?1)",
            vec![
                thread.into(),
                unix_seconds().into(),
                operation_id.into(),
                chat.into(),
                creation.into(),
                evidence.bot_id.as_str().into(),
                expected_revision.into(),
                proof.encode()?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
    if updated.rows_affected() != 1 {
        return Err(super::audience::unreadable());
    }
    Ok(())
}

/// The caller has already admitted the Thread/creation selectors in its readiness budget.
/// All probes stay in those same selectors, including the exact original source lookup.
pub(super) async fn check_sources<C: ConnectionTrait>(
    db: &C,
    origin: &super::audience::ThreadOrigin,
    bot: &str,
) -> Result<(), FeishuError> {
    check_sources_at(db, origin, bot, SourceIndexes::Prepared).await
}

/// Nine-format import proves the exact same source before optional secondary indexes exist.
/// This only removes index hints; it does not omit a selector or relax any identity predicate.
pub(super) async fn check_sources_for_import<C: ConnectionTrait>(
    db: &C,
    origin: &super::audience::ThreadOrigin,
    bot: &str,
) -> Result<(), FeishuError> {
    check_sources_at(db, origin, bot, SourceIndexes::BeforeImport).await
}

#[derive(Clone, Copy)]
enum SourceIndexes {
    Prepared,
    BeforeImport,
}

impl SourceIndexes {
    fn hint(self, declared: &'static str) -> &'static str {
        match self {
            Self::Prepared => declared,
            Self::BeforeImport => "",
        }
    }
}

async fn check_sources_at<C: ConnectionTrait>(
    db: &C,
    origin: &super::audience::ThreadOrigin,
    bot: &str,
    indexes: SourceIndexes,
) -> Result<(), FeishuError> {
    let proof = &origin.target;
    matches_origin(
        proof,
        &origin.thread_id,
        &origin.chat_id,
        &origin.project_id,
        &origin.creation_id,
        origin.binding_revision,
    )?;
    let Some(kind) = proof.kind() else {
        return if origin.requires_upgrade {
            Ok(())
        } else {
            Err(super::audience::unreadable())
        };
    };
    let (kind_name, open) = match kind {
        TargetKind::Group => ("group", ""),
        TargetKind::Direct { open_id } => ("direct", open_id.as_str()),
    };
    let app = match proof {
        TargetProof::Created { evidence } => {
            if evidence.bot_id != bot
                || evidence.app_id.is_empty()
                || evidence.chat_id != origin.chat_id
                || evidence.project_id != origin.project_id
                || evidence.creation_id != origin.creation_id
                || evidence.binding_revision != origin.binding_revision
            {
                return Err(super::audience::unreadable());
            }
            // The row that froze the proof in the creation intent is the row the origin
            // was written from: they must still carry the identical typed value.
            let row = db
                .query_one_raw(statement(
                    &format!(
                        "SELECT status,target_json FROM thread_bindings{}
                     WHERE thread_id=?1 AND chat_id=?2 LIMIT 1",
                        indexes.hint(" INDEXED BY bot_route_thread_lookup")
                    ),
                    vec![
                        origin.thread_id.clone().into(),
                        origin.chat_id.clone().into(),
                    ],
                ))
                .await
                .map_err(storage)?
                .ok_or_else(super::audience::unreadable)?;
            if strict_text(&row, "status")? != "bound"
                || strict_text(&row, "target_json")? != proof.encode()?
            {
                return Err(super::audience::unreadable());
            }
            let source = match &evidence.source {
                TargetSource::Operation { operation_id } => db
                    .query_one_raw(statement(
                        &format!(
                            "SELECT 1 FROM binding_operations{}
                     WHERE creation_id=?1 AND operation_id=?2 AND bot_id=?3 AND chat_id=?4
                     AND expected_revision=?5-1 AND target_json=?6 AND thread_id=?7 LIMIT 1",
                            indexes.hint(" INDEXED BY bot_binding_creation_lookup")
                        ),
                        vec![
                            origin.creation_id.clone().into(),
                            operation_id.clone().into(),
                            bot.into(),
                            origin.chat_id.clone().into(),
                            i64::try_from(origin.binding_revision)
                                .map_err(|_| super::audience::unreadable())?
                                .into(),
                            proof.encode()?.into(),
                            origin.thread_id.clone().into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?,
                TargetSource::Inbound { message_id } => db
                    .query_one_raw(statement(
                        &format!(
                            "SELECT 1 FROM inbound_work{}
                     WHERE creation_id=?1 AND message_id=?2 AND bot_id=?3 AND chat_id=?4
                     AND project_id=?5 AND app_id=?6 AND binding_revision=?7 AND chat_kind=?8
                     AND (?8<>'direct' OR open_id=?9) LIMIT 1",
                            indexes.hint(" INDEXED BY inbound_source_creation")
                        ),
                        vec![
                            origin.creation_id.clone().into(),
                            message_id.clone().into(),
                            bot.into(),
                            origin.chat_id.clone().into(),
                            origin.project_id.clone().into(),
                            evidence.app_id.clone().into(),
                            i64::try_from(origin.binding_revision)
                                .map_err(|_| super::audience::unreadable())?
                                .into(),
                            kind_name.into(),
                            open.into(),
                        ],
                    ))
                    .await
                    .map_err(storage)?,
            };
            if source.is_none() {
                return Err(super::audience::unreadable());
            }
            evidence.app_id.as_str()
        }
        TargetProof::Legacy { .. } if origin.requires_upgrade => "",
        _ => return Err(super::audience::unreadable()),
    };
    for sql in [
        format!(
            "SELECT 1 FROM inbound_work w{} WHERE w.creation_id=?1 AND w.chat_id=?6 AND
         ((w.chat_kind IN ('direct','group') AND w.chat_kind<>?3)
          OR (?3='direct' AND w.open_id<>'' AND w.open_id<>?4)
          OR (?5<>'' AND w.app_id<>?5)) LIMIT 1",
            indexes.hint(" INDEXED BY inbound_source_creation")
        ),
        format!(
            "SELECT 1 FROM bot_card_streams c{}
         JOIN inbound_work w ON w.identity=c.identity WHERE c.thread_id=?2 AND w.chat_id=?6 AND
         ((w.chat_kind IN ('direct','group') AND w.chat_kind<>?3)
          OR (?3='direct' AND w.open_id<>'' AND w.open_id<>?4)
          OR (?5<>'' AND w.app_id<>?5)) LIMIT 1",
            indexes.hint(" INDEXED BY bot_card_thread_lookup")
        ),
    ] {
        if db
            .query_one_raw(statement(
                &sql,
                vec![
                    origin.creation_id.clone().into(),
                    origin.thread_id.clone().into(),
                    kind_name.into(),
                    open.into(),
                    app.into(),
                    origin.chat_id.clone().into(),
                ],
            ))
            .await
            .map_err(storage)?
            .is_some()
        {
            return Err(super::audience::unreadable());
        }
    }
    Ok(())
}
