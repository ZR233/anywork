//! Original binding/auth CAS and exact saved-cut activation in the same bot transaction.

use super::{Authorization, SyncOperation, conflict, phase_name, read, unreadable};
use crate::bots::config::BotConfigFile;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{BotStateStore, statement, storage};
use crate::studio::audience_start::{AudienceStartIntent, AudienceStartReceipt};
use crate::studio::unix_seconds;
use pl_protocol::studio::{BotAuthorizationPhase, BotThreadSyncAction, ChangeBotThreadSyncRequest};
use pl_protocol::{BotAudienceCloseReason, BotAuthorizationHead, BotAuthorizationId, BotSyncCas};
use sea_orm::{ConnectionTrait, TransactionTrait};

pub(in crate::bots) struct SyncChange {
    pub authorization: Authorization,
    pub changed: bool,
}

async fn write_auth<C: ConnectionTrait>(db: &C, auth: &Authorization) -> Result<(), FeishuError> {
    auth.validate()?;
    let json = serde_json::to_string(auth).map_err(|_| unreadable())?;
    db.execute_raw(statement("INSERT INTO bot_authorizations(chat_id,generation,thread_id,control_revision,phase,state_json)
        VALUES(?,?,?,?,?,?) ON CONFLICT(chat_id,generation) DO UPDATE SET control_revision=excluded.control_revision,phase=excluded.phase,state_json=excluded.state_json",
        vec![auth.intent.authorization.chat_id.clone().into(),i64::try_from(auth.intent.authorization.generation).map_err(|_|unreadable())?.into(),auth.intent.thread_id.clone().into(),
            i64::try_from(auth.revision).map_err(|_|unreadable())?.into(),phase_name(auth.phase).into(),json.into()])).await.map_err(storage)?;
    let updated=db.execute_raw(statement("UPDATE bot_audience_origins SET summary_version=summary_version+1 WHERE thread_id=? AND summary_version<9223372036854775807",vec![auth.intent.thread_id.clone().into()])).await.map_err(storage)?;
    if updated.rows_affected() != 1 {
        return Err(unreadable());
    }
    Ok(())
}

impl BotStateStore {
    pub(in crate::bots) async fn prune_authorization_page(
        &self,
        config: &BotConfigFile,
        after: (&str, u64),
    ) -> Result<(bool, Option<(String, u64)>), FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let rows=tx.query_all_raw(statement("SELECT * FROM bot_authorizations WHERE phase<>'closed' AND (chat_id,generation)>(?,?) ORDER BY chat_id,generation LIMIT 32",
            vec![after.0.into(),i64::try_from(after.1).map_err(|_|unreadable())?.into()])).await.map_err(storage)?;
        let full = rows.len() == 32;
        let mut changed = false;
        let mut last = None;
        for row in rows {
            let auth = super::authorization(&row)?;
            if auth.intent.authorization.bot_id != config.id {
                return Err(unreadable());
            }
            let chat = &auth.intent.authorization.chat_id;
            let direct = tx
                .query_one_raw(statement(
                    "SELECT open_id FROM observed_directs WHERE chat_id=?",
                    vec![chat.clone().into()],
                ))
                .await
                .map_err(storage)?;
            let trusted = match direct {
                Some(row) => config
                    .feishu()
                    .trusted_open_ids
                    .contains(&super::super::strict_text(&row, "open_id")?),
                None => config.feishu().trusted_chat_ids.contains(chat),
            };
            if !config.enabled
                || !trusted
                || auth.app_id != config.feishu().app_id
                || auth.project_id != config.project_id
            {
                let reason = if !config.enabled {
                    BotAudienceCloseReason::BotDisabled
                } else {
                    BotAudienceCloseReason::TrustRevoked
                };
                changed |= close_generation(&tx, &auth.intent.authorization, reason).await?;
            }
            last = Some((chat.clone(), auth.intent.authorization.generation));
        }
        tx.commit().await.map_err(storage)?;
        Ok((changed, if full { last } else { None }))
    }
    pub(in crate::bots) async fn close_sync_generation(
        &self,
        id: &BotAuthorizationId,
        reason: BotAudienceCloseReason,
    ) -> Result<bool, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let changed = close_generation(&tx, id, reason).await?;
        tx.commit().await.map_err(storage)?;
        Ok(changed)
    }
    pub(in crate::bots) async fn change_sync(
        &self,
        request: &ChangeBotThreadSyncRequest,
        config: &BotConfigFile,
    ) -> Result<SyncChange, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        if let Some(previous) = read::operation(&tx, &request.operation_id).await? {
            if previous.request != *request {
                return Err(conflict());
            }
            let authorization = read::load_auth(&tx, &previous.authorization)
                .await?
                .ok_or_else(unreadable)?;
            tx.commit().await.map_err(storage)?;
            return Ok(SyncChange {
                authorization,
                changed: false,
            });
        }
        let origin = read::proven_origin(&tx, &request.thread_id, &config.id)
            .await?
            .ok_or_else(unreadable)?;
        let route = tx
            .query_one_raw(statement(
                "SELECT thread_id,revision,status,project_id,creation_id FROM thread_bindings WHERE chat_id=?",
                vec![origin.chat_id.clone().into()],
            ))
            .await
            .map_err(storage)?
            .ok_or_else(unreadable)?;
        if super::super::strict_text(&route, "thread_id")? != request.thread_id
            || super::super::strict_text(&route, "status")? != "bound"
            || super::super::strict_watermark(&route, "revision")?
                != request.expected.binding_revision
            || origin.project_id != config.project_id
            || super::super::strict_text(&route, "project_id")? != origin.project_id
            || super::super::strict_text(&route, "creation_id")? != origin.creation_id
            || origin.binding_revision != request.expected.binding_revision
        {
            return Err(conflict());
        }
        let current = read::head(&tx, &origin.chat_id).await?;
        if current
            .as_ref()
            .is_some_and(|a| a.intent.authorization.bot_id != config.id)
        {
            return Err(unreadable());
        }
        let actual = current.as_ref().map_or(BotAuthorizationHead::None {}, |a| {
            BotAuthorizationHead::Present {
                authorization: a.reference(),
            }
        });
        if request.expected.authorization_head != actual {
            return Err(conflict());
        }
        let auth = match request.action {
            BotThreadSyncAction::Enable => {
                if origin.requires_upgrade
                    || current
                        .as_ref()
                        .is_some_and(|a| a.phase != BotAuthorizationPhase::Closed)
                {
                    return Err(conflict());
                }
                let generation = current
                    .as_ref()
                    .map_or(Some(1), |a| {
                        a.intent.authorization.generation.checked_add(1)
                    })
                    .ok_or_else(unreadable)?;
                Authorization {
                    intent: AudienceStartIntent {
                        operation_id: request.operation_id.clone(),
                        thread_id: request.thread_id.clone(),
                        authorization: BotAuthorizationId {
                            bot_id: config.id.clone(),
                            chat_id: origin.chat_id,
                            generation,
                        },
                        binding_revision: request.expected.binding_revision,
                    },
                    app_id: config.feishu().app_id.clone(),
                    project_id: config.project_id.clone(),
                    creation_id: origin.creation_id,
                    revision: 1,
                    phase: BotAuthorizationPhase::PendingStart,
                    start: None,
                    closed: None,
                    delivery_version: 1,
                }
            }
            BotThreadSyncAction::Pause
            | BotThreadSyncAction::Resume
            | BotThreadSyncAction::Close => {
                let mut auth = current.ok_or_else(conflict)?;
                if auth.intent.thread_id != request.thread_id {
                    return Err(conflict());
                }
                match (request.action, auth.phase) {
                    (BotThreadSyncAction::Pause, BotAuthorizationPhase::Active) => {
                        auth.phase = BotAuthorizationPhase::Paused
                    }
                    (BotThreadSyncAction::Resume, BotAuthorizationPhase::Paused) => {
                        auth.phase = BotAuthorizationPhase::Active
                    }
                    (
                        BotThreadSyncAction::Close,
                        BotAuthorizationPhase::PendingStart
                        | BotAuthorizationPhase::Active
                        | BotAuthorizationPhase::Paused,
                    ) => {
                        auth.phase = BotAuthorizationPhase::Closed;
                        auth.closed = Some((BotAudienceCloseReason::LocalClose, unix_seconds()));
                    }
                    _ => return Err(conflict()),
                }
                auth.revision = auth.revision.checked_add(1).ok_or_else(unreadable)?;
                auth
            }
        };
        // The complete source identity is fixed before the operation can acquire its first cut.
        auth.validate()?;
        let op = SyncOperation {
            request: request.clone(),
            authorization: auth.intent.authorization.clone(),
        };
        tx.execute_raw(statement(
            "INSERT INTO bot_sync_operations(operation_id,thread_id,request_json) VALUES(?,?,?)",
            vec![
                request.operation_id.clone().into(),
                request.thread_id.clone().into(),
                serde_json::to_string(&op).map_err(|_| unreadable())?.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        write_auth(&tx, &auth).await?;
        tx.commit().await.map_err(storage)?;
        Ok(SyncChange {
            authorization: auth,
            changed: true,
        })
    }

    pub(in crate::bots) async fn activate_sync(
        &self,
        receipt: &AudienceStartReceipt,
    ) -> Result<SyncChange, FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let mut auth = read::load_auth(&tx, &receipt.intent.authorization)
            .await?
            .ok_or_else(unreadable)?;
        let original = auth.clone();
        if auth.intent != receipt.intent {
            return Err(conflict());
        }
        let head = read::head(&tx, &auth.intent.authorization.chat_id)
            .await?
            .ok_or_else(unreadable)?;
        if head.intent == auth.intent && auth.phase == BotAuthorizationPhase::PendingStart {
            let origin = read::proven_origin(
                &tx,
                &auth.intent.thread_id,
                &auth.intent.authorization.bot_id,
            )
            .await?
            .ok_or_else(unreadable)?;
            let route = tx
            .query_one_raw(statement(
                "SELECT thread_id,revision,status,project_id,creation_id FROM thread_bindings WHERE chat_id=?",
                vec![auth.intent.authorization.chat_id.clone().into()],
            ))
            .await
            .map_err(storage)?
            .ok_or_else(unreadable)?;
            if super::super::strict_text(&route, "thread_id")? == auth.intent.thread_id
                && super::super::strict_watermark(&route, "revision")?
                    == auth.intent.binding_revision
                && super::super::strict_text(&route, "status")? == "bound"
                && super::super::strict_text(&route, "project_id")? == auth.project_id
                && super::super::strict_text(&route, "creation_id")? == auth.creation_id
                && origin.chat_id == auth.intent.authorization.chat_id
                && origin.project_id == auth.project_id
                && origin.creation_id == auth.creation_id
                && origin.binding_revision == auth.intent.binding_revision
                && !origin.requires_upgrade
            {
                auth.start = Some(receipt.clone());
                auth.phase = BotAuthorizationPhase::Active;
                auth.revision = auth.revision.checked_add(1).ok_or_else(unreadable)?;
                write_auth(&tx, &auth).await?;
            }
        }
        tx.commit().await.map_err(storage)?;
        Ok(SyncChange {
            changed: auth != original,
            authorization: auth,
        })
    }

    /// Bounded recovery of durable prepares. Holding this page never holds a Thread execution gate.
    pub(in crate::bots) async fn pending_syncs(
        &self,
        after: (&str, u64),
    ) -> Result<Vec<Authorization>, FeishuError> {
        let rows=self.audience_db()?.query_all_raw(statement("SELECT * FROM bot_authorizations WHERE phase='pending' AND (chat_id,generation)>(?,?) ORDER BY chat_id,generation LIMIT 32",
            vec![after.0.into(),i64::try_from(after.1).map_err(|_|unreadable())?.into()])).await.map_err(storage)?;
        rows.iter().map(super::authorization).collect()
    }
}

/// Commits the automatic first authorization beside the binding it belongs to. It is a
/// durable intent only: the original CAS in `activate_sync` still decides activation, and any
/// existing head (in any phase) forbids opening a second generation automatically.
pub(in crate::bots::storage) async fn first_pending_start<C: ConnectionTrait>(
    db: &C,
    first: &crate::bots::storage::FirstStart,
    chat: &str,
    creation: &str,
    project: &str,
    revision: u64,
    thread: &str,
) -> Result<(), FeishuError> {
    if super::read::head(db, chat).await?.is_some() {
        return Ok(());
    }
    let auth = Authorization {
        intent: AudienceStartIntent {
            operation_id: first.operation_id.clone(),
            thread_id: thread.to_string(),
            authorization: BotAuthorizationId {
                bot_id: first.bot_id.clone(),
                chat_id: chat.to_string(),
                generation: 1,
            },
            binding_revision: revision,
        },
        app_id: first.app_id.clone(),
        project_id: project.to_string(),
        creation_id: creation.to_string(),
        revision: 1,
        phase: BotAuthorizationPhase::PendingStart,
        start: None,
        closed: None,
        delivery_version: 1,
    };
    // 同一事务占用该 operation 身份：后续显式 Enable 复用同一 id 时会在既有幂等查询里
    // 命中「同 id 不同 request」而被拒，避免把跨代复用交给宿主才发现。
    let operation = SyncOperation {
        request: ChangeBotThreadSyncRequest {
            operation_id: first.operation_id.clone(),
            thread_id: thread.to_string(),
            action: BotThreadSyncAction::Enable,
            expected: BotSyncCas {
                binding_revision: revision,
                authorization_head: BotAuthorizationHead::None {},
            },
        },
        authorization: auth.intent.authorization.clone(),
    };
    db.execute_raw(statement(
        "INSERT INTO bot_sync_operations(operation_id,thread_id,request_json) VALUES(?,?,?)",
        vec![
            first.operation_id.clone().into(),
            thread.into(),
            serde_json::to_string(&operation)
                .map_err(|_| unreadable())?
                .into(),
        ],
    ))
    .await
    .map_err(storage)?;
    write_auth(db, &auth).await
}

pub(in crate::bots::storage) async fn close_generation<C: ConnectionTrait>(
    db: &C,
    id: &BotAuthorizationId,
    reason: BotAudienceCloseReason,
) -> Result<bool, FeishuError> {
    let Some(mut auth) = read::load_auth(db, id).await? else {
        return Ok(false);
    };
    if auth.phase == BotAuthorizationPhase::Closed {
        return Ok(false);
    }
    auth.phase = BotAuthorizationPhase::Closed;
    auth.closed = Some((reason, unix_seconds()));
    auth.revision = auth.revision.checked_add(1).ok_or_else(unreadable)?;
    write_auth(db, &auth).await?;
    Ok(true)
}

pub(in crate::bots::storage) async fn close_chat<C: ConnectionTrait>(
    db: &C,
    chat: &str,
    reason: BotAudienceCloseReason,
) -> Result<bool, FeishuError> {
    let Some(auth) = read::head(db, chat).await? else {
        return Ok(false);
    };
    close_generation(db, &auth.intent.authorization, reason).await
}

pub(in crate::bots::storage) async fn close_unavailable_binding<C: ConnectionTrait>(
    db: &C,
    expected: &crate::bots::storage::BoundThreadExpectation,
) -> Result<(), FeishuError> {
    if let Some(auth) = read::head(db, &expected.chat_id).await?
        && auth.phase != BotAuthorizationPhase::Closed
    {
        if auth.intent.thread_id != expected.thread_id
            || auth.project_id != expected.project_id
            || auth.creation_id != expected.creation_id
            || auth.intent.binding_revision != expected.revision
        {
            return Err(unreadable());
        }
        close_generation(
            db,
            &auth.intent.authorization,
            BotAudienceCloseReason::BindingUnavailable,
        )
        .await?;
    }
    Ok(())
}

pub(in crate::bots::storage) async fn bind_origin<C: ConnectionTrait>(
    db: &C,
    thread: &str,
    chat: &str,
    project: &str,
    creation: &str,
    revision: u64,
    target: &crate::bots::storage::target::TargetProof,
) -> Result<(), FeishuError> {
    crate::bots::storage::target::matches_origin(
        target, thread, chat, project, creation, revision,
    )?;
    if thread.is_empty()
        || chat.is_empty()
        || project.is_empty()
        || creation.is_empty()
        || revision == 0
    {
        return Err(unreadable());
    }
    super::proof::check_creation_thread(db, creation, thread).await?;
    match read::read_origin(db, thread).await? {
        Some(origin)
            if origin.chat_id == chat
                && origin.project_id == project
                && origin.creation_id == creation
                && origin.binding_revision == revision =>
        {
            if origin.target != *target {
                return Err(unreadable());
            }
            Ok(())
        }
        Some(_) => Err(unreadable()),
        None => {
            let upgrade = !matches!(
                target,
                crate::bots::storage::target::TargetProof::Created { .. }
            );
            db.execute_raw(statement("INSERT INTO bot_audience_origins(thread_id,chat_id,project_id,creation_id,binding_revision,requires_upgrade,summary_version,target_json) VALUES(?,?,?,?,?,?,1,?)",
                vec![thread.into(),chat.into(),project.into(),creation.into(),i64::try_from(revision).map_err(|_|unreadable())?.into(),i64::from(upgrade).into(),target.encode()?.into()])).await.map_err(storage)?;
            Ok(())
        }
    }
}
