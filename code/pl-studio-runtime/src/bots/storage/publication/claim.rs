//! 独立 delivery claim 与每次新外写的 route/auth/token 围栏。结算不消费此许可。
use super::super::{BotStateStore, audience, statement, stored_i64, strict_text};
use super::records::read_scope;
use super::store::storage;
use super::*;
use crate::bots::config::BotConfigFile;
use crate::bots::storage::BoundThreadExpectation;
use crate::bots::storage::target::TargetKind;
use crate::studio::unix_seconds;
use sea_orm::{ConnectionTrait, QueryResult, TransactionTrait, Value};

pub(super) enum WriteFence {
    Permitted(Box<DeliveryScope>),
    LostClaim,
    Stopped,
}

pub(super) enum ClaimFence {
    Held,
    Lost,
    Stopped,
}

/// 关闭原绑定只能命中原范围；替换聊天则封闭该聊天所有已存在的有限义务。
pub(in crate::bots::storage) enum LegacyScopeClosure<'a> {
    Chat(&'a str),
    Binding {
        expected: &'a BoundThreadExpectation,
        bot_id: Option<&'a str>,
    },
}

/// 与控制变更共用原事务。每页有界，完整遍历集合；不因已停止范围而停在同一页。
pub(in crate::bots::storage) async fn stop_legacy_scopes_in<C: ConnectionTrait>(
    db: &C,
    closure: LegacyScopeClosure<'_>,
    reason: &str,
) -> Result<bool, FeishuError> {
    let (chat, predicate, extra): (&str, &str, Vec<Value>) = match closure {
        LegacyScopeClosure::Chat(chat) => (chat, "", vec![]),
        LegacyScopeClosure::Binding { expected, bot_id } => {
            let bot: Value = bot_id.map(str::to_string).into();
            (
                expected.chat_id.as_str(),
                "AND thread_id=? AND project_id=? AND creation_id=? AND binding_revision=?
                 AND (? IS NULL OR bot_id=?)",
                vec![
                    expected.thread_id.clone().into(),
                    expected.project_id.clone().into(),
                    expected.creation_id.clone().into(),
                    i64::try_from(expected.revision)
                        .map_err(|_| unreadable())?
                        .into(),
                    bot.clone(),
                    bot,
                ],
            )
        }
    };
    let mut after = String::new();
    let mut changed = false;
    loop {
        let mut values = vec![chat.to_string().into(), after.clone().into()];
        values.extend(extra.iter().cloned());
        let rows = db
            .query_all_raw(statement(
                &format!(
                    "SELECT scope_key,scope_json FROM bot_delivery_scopes
             WHERE kind='legacyFinal' AND chat_id=? AND scope_key>? {predicate}
             ORDER BY scope_key LIMIT 32"
                ),
                values,
            ))
            .await
            .map_err(storage)?;
        let full = rows.len() == 32;
        for row in rows {
            let scope = read_legacy_scope(db, &row).await?;
            after = scope.key.storage_key()?;
            changed |= stop_scope_in(db, &scope, reason).await?;
        }
        if !full {
            return Ok(changed);
        }
    }
}

async fn read_legacy_scope<C: ConnectionTrait>(
    db: &C,
    row: &QueryResult,
) -> Result<DeliveryScope, FeishuError> {
    let key = DeliveryScopeKey::decode_stored(
        &strict_text(row, "scope_key")?,
        &strict_text(row, "scope_json")?,
    )?;
    if !matches!(key, DeliveryScopeKey::LegacyFinal { .. }) {
        return Err(unreadable());
    }
    read_scope(db, &key).await?.ok_or_else(unreadable)
}

/// 永久关闭的唯一写入：无 claim 也登记；保留第一次关闭原因，只为真实变化失效摘要。
async fn stop_scope_in<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScope,
    reason: &str,
) -> Result<bool, FeishuError> {
    if reason.is_empty() {
        return Err(rejected("a stopped delivery scope needs a real reason"));
    }
    let updated = db
        .execute_raw(statement(
            "INSERT INTO bot_delivery_claims
           (scope_key,owner_id,lease_generation,work_version,expires_at,stopped_reason,updated_at)
         VALUES(?,'',1,1,0,?,?)
         ON CONFLICT(scope_key) DO UPDATE SET
           owner_id='',expires_at=0,stopped_reason=excluded.stopped_reason,
           updated_at=excluded.updated_at
         WHERE bot_delivery_claims.stopped_reason=''",
            vec![
                scope.key.storage_key()?.into(),
                reason.to_string().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
    let changed = updated.rows_affected() == 1;
    if changed {
        let authorization = match &scope.key {
            DeliveryScopeKey::Frontend { authorization } => Some(authorization),
            DeliveryScopeKey::LegacyFinal { .. } => None,
        };
        audience::note_delivery_change(db, authorization, &scope.thread_id).await?;
    }
    Ok(changed)
}

impl BotStateStore {
    /// 原配置重授信/重启连接前与提交后都可调用；只关闭原有 Legacy 范围，不建立授权头。
    /// after 是上一扫描页的稳定 scope key；即使该页已全部停止，游标仍继续推进。
    pub(in crate::bots) async fn prune_legacy_delivery_page(
        &self,
        config: &BotConfigFile,
        after: Option<&str>,
    ) -> Result<(bool, Option<String>), FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let rows = tx
            .query_all_raw(statement(
                "SELECT scope_key,scope_json FROM bot_delivery_scopes
             WHERE kind='legacyFinal' AND scope_key>? ORDER BY scope_key LIMIT 32",
                vec![after.unwrap_or_default().into()],
            ))
            .await
            .map_err(storage)?;
        let full = rows.len() == 32;
        let mut last = None;
        let mut changed = false;
        for row in rows {
            let scope = read_legacy_scope(&tx, &row).await?;
            if scope.bot_id != config.id {
                return Err(unreadable());
            }
            let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
                return Err(unreadable());
            };
            super::super::target::matches_origin(
                &legacy.target,
                &scope.thread_id,
                &scope.chat_id,
                &scope.project_id,
                &scope.creation_id,
                scope.binding_revision,
            )?;
            if let TargetProof::Created { evidence } = &legacy.target
                && (evidence.bot_id != scope.bot_id || evidence.app_id != scope.app_id)
            {
                return Err(unreadable());
            }
            let trusted = match legacy.target.kind() {
                Some(TargetKind::Group) => {
                    config.feishu().trusted_chat_ids.contains(&scope.chat_id)
                }
                Some(TargetKind::Direct { open_id }) => {
                    config.feishu().trusted_open_ids.contains(open_id)
                }
                None => false,
            };
            let reason = if !config.enabled {
                Some("legacy delivery bot disabled")
            } else if scope.app_id != config.feishu().app_id
                || scope.project_id != config.project_id
            {
                Some("legacy delivery application or project changed")
            } else if !trusted {
                Some("legacy delivery target unproven or trust revoked")
            } else {
                None
            };
            if let Some(reason) = reason {
                changed |= stop_scope_in(&tx, &scope, reason).await?;
            }
            last = Some(scope.key.storage_key()?);
        }
        tx.commit().await.map_err(storage)?;
        Ok((changed, if full { last } else { None }))
    }

    /// 独立认领：同 scope 串行；另一 owner 的有效租约返回 `Busy`。
    pub(in crate::bots) async fn claim_delivery_scope(
        &self,
        key: &DeliveryScopeKey,
        owner_id: &str,
    ) -> Result<DeliveryClaimOutcome, FeishuError> {
        if owner_id.is_empty() {
            return Err(unreadable());
        }
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let Some(scope) = read_scope(&tx, key).await? else {
            return Ok(DeliveryClaimOutcome::Missing);
        };
        if scope.needs_recovery {
            return Ok(DeliveryClaimOutcome::Stopped {
                reason: "delivery scope needs local recovery".to_string(),
            });
        }
        if let Some(reason) = authorization_gap(&tx, &scope).await? {
            return Ok(DeliveryClaimOutcome::Stopped { reason });
        }
        let authorization_revision = scope_control_revision(&tx, &scope).await?;
        let now = unix_seconds();
        let current = tx
            .query_one_raw(statement(
                "SELECT owner_id,lease_generation,work_version,expires_at,stopped_reason
                 FROM bot_delivery_claims WHERE scope_key=?",
                vec![key.storage_key()?.into()],
            ))
            .await
            .map_err(storage)?;
        let (lease_generation, work_version) = match &current {
            Some(row) => {
                let stopped = strict_text(row, "stopped_reason")?;
                if !stopped.is_empty() {
                    return Ok(DeliveryClaimOutcome::Stopped { reason: stopped });
                }
                let owner = strict_text(row, "owner_id")?;
                let expires_at = stored_i64(row, "expires_at")?;
                if owner != owner_id && expires_at > now {
                    return Ok(DeliveryClaimOutcome::Busy { expires_at });
                }
                (
                    u64::try_from(stored_i64(row, "lease_generation")?)
                        .map_err(|_| unreadable())?
                        .checked_add(1)
                        .ok_or_else(unreadable)?,
                    u64::try_from(stored_i64(row, "work_version")?)
                        .map_err(|_| unreadable())?
                        .checked_add(1)
                        .ok_or_else(unreadable)?,
                )
            }
            None => (1, 1),
        };
        let expires_at = now.saturating_add(DELIVERY_CLAIM_TTL_SECONDS);
        tx.execute_raw(statement(
            "INSERT INTO bot_delivery_claims
               (scope_key,owner_id,lease_generation,work_version,authorization_revision,expires_at,stopped_reason,updated_at)
             VALUES(?,?,?,?,?,?,'',?)
             ON CONFLICT(scope_key) DO UPDATE SET
               owner_id=excluded.owner_id,
               lease_generation=excluded.lease_generation,
               work_version=excluded.work_version,
               authorization_revision=excluded.authorization_revision,
               expires_at=excluded.expires_at,
               stopped_reason='',
               updated_at=excluded.updated_at",
            vec![
                key.storage_key()?.into(),
                owner_id.to_string().into(),
                i64::try_from(lease_generation)
                    .map_err(|_| unreadable())?
                    .into(),
                i64::try_from(work_version).map_err(|_| unreadable())?.into(),
                i64::try_from(authorization_revision).map_err(|_| unreadable())?.into(),
                expires_at.into(),
                now.into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(DeliveryClaimOutcome::Acquired(DeliveryClaimToken {
            scope: key.clone(),
            owner_id: owner_id.to_string(),
            lease_generation,
            work_version,
            authorization_revision,
            expires_at,
        }))
    }

    /// 续约：同 owner、同代次、同工作版本才延长完整租约；0 行即失租。
    pub(in crate::bots) async fn renew_delivery_claim(
        &self,
        token: &DeliveryClaimToken,
    ) -> Result<DeliveryClaimOutcome, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        match fence_write(&tx, token).await? {
            WriteFence::Permitted(_) => {}
            WriteFence::LostClaim => return Ok(DeliveryClaimOutcome::LostClaim),
            WriteFence::Stopped => {
                return Ok(DeliveryClaimOutcome::Stopped {
                    reason: "delivery scope is stopped".to_string(),
                });
            }
        }
        let now = unix_seconds();
        let expires_at = now.saturating_add(DELIVERY_CLAIM_TTL_SECONDS);
        let updated = tx
            .execute_raw(statement(
                "UPDATE bot_delivery_claims SET expires_at=?,updated_at=?
                 WHERE scope_key=? AND owner_id=? AND lease_generation=? AND work_version=?
                   AND stopped_reason=''",
                vec![
                    expires_at.into(),
                    now.into(),
                    token.scope.storage_key()?.into(),
                    token.owner_id.clone().into(),
                    i64::try_from(token.lease_generation)
                        .map_err(|_| unreadable())?
                        .into(),
                    i64::try_from(token.work_version)
                        .map_err(|_| unreadable())?
                        .into(),
                ],
            ))
            .await
            .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        if updated.rows_affected() != 1 {
            return Ok(DeliveryClaimOutcome::LostClaim);
        }
        Ok(DeliveryClaimOutcome::Acquired(DeliveryClaimToken {
            expires_at,
            ..token.clone()
        }))
    }

    /// 释放认领：只释放自己那一代，后继租约不受影响。
    pub(in crate::bots) async fn release_delivery_claim(
        &self,
        token: &DeliveryClaimToken,
    ) -> Result<bool, FeishuError> {
        let db = self.db().await?;
        let updated = db
            .execute_raw(statement(
                "UPDATE bot_delivery_claims SET owner_id='',expires_at=0,updated_at=?
                 WHERE scope_key=? AND owner_id=? AND lease_generation=? AND work_version=?",
                vec![
                    unix_seconds().into(),
                    token.scope.storage_key()?.into(),
                    token.owner_id.clone().into(),
                    i64::try_from(token.lease_generation)
                        .map_err(|_| unreadable())?
                        .into(),
                    i64::try_from(token.work_version)
                        .map_err(|_| unreadable())?
                        .into(),
                ],
            ))
            .await
            .map_err(storage)?;
        Ok(updated.rows_affected() == 1)
    }

    /// 封闭作用域：只用于已确定的封闭/需处理（撤权、替换、绑定不可用、迁移不可证）。
    ///
    /// 暂停不调用本入口；暂停只是 `claim` 的本次 Stopped，不删除范围或未知义务。
    /// 封闭后任何认领都返回 `Stopped`，已启动结果仍可按原操作结算。
    pub(in crate::bots) async fn stop_delivery_scope(
        &self,
        key: &DeliveryScopeKey,
        reason: &str,
    ) -> Result<bool, FeishuError> {
        if reason.is_empty() {
            return Err(rejected("a stopped delivery scope needs a real reason"));
        }
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let Some(scope) = read_scope(&tx, key).await? else {
            tx.commit().await.map_err(storage)?;
            return Ok(false);
        };
        let changed = stop_scope_in(&tx, &scope, reason).await?;
        tx.commit().await.map_err(storage)?;
        Ok(changed)
    }
}
pub(super) async fn fence_write<C: ConnectionTrait>(
    db: &C,
    token: &DeliveryClaimToken,
) -> Result<WriteFence, FeishuError> {
    let Some(scope) = read_scope(db, &token.scope).await? else {
        return Ok(WriteFence::Stopped);
    };
    if scope.needs_recovery {
        return Ok(WriteFence::Stopped);
    }
    if authorization_gap(db, &scope).await?.is_some() {
        return Ok(WriteFence::Stopped);
    }
    if scope_control_revision(db, &scope).await? != token.authorization_revision {
        return Ok(WriteFence::Stopped);
    }
    Ok(match fence_claim(db, token).await? {
        ClaimFence::Held => WriteFence::Permitted(Box::new(scope)),
        ClaimFence::Lost => WriteFence::LostClaim,
        ClaimFence::Stopped => WriteFence::Stopped,
    })
}

/// 原认领是否仍存活，与当前 route/auth phase/control revision 的新写许可分离。
/// 单独使用只可用于本地未启动退役；新写仍须完整 fence_write。永久 stop 清空 owner/期限，
/// 绝不因忽略授权而复活认领。
pub(super) async fn fence_claim<C: ConnectionTrait>(
    db: &C,
    token: &DeliveryClaimToken,
) -> Result<ClaimFence, FeishuError> {
    let now = unix_seconds();
    let row = db
        .query_one_raw(statement(
            "SELECT owner_id,lease_generation,work_version,authorization_revision,expires_at,stopped_reason
             FROM bot_delivery_claims WHERE scope_key=?",
            vec![token.scope.storage_key()?.into()],
        ))
        .await
        .map_err(storage)?;
    let Some(row) = row else {
        return Ok(ClaimFence::Lost);
    };
    if !strict_text(&row, "stopped_reason")?.is_empty() {
        return Ok(ClaimFence::Stopped);
    }
    let held = strict_text(&row, "owner_id")? == token.owner_id
        && u64::try_from(stored_i64(&row, "lease_generation")?).ok()
            == Some(token.lease_generation)
        && u64::try_from(stored_i64(&row, "work_version")?).ok() == Some(token.work_version)
        && u64::try_from(stored_i64(&row, "authorization_revision")?).ok()
            == Some(token.authorization_revision)
        && stored_i64(&row, "expires_at")? > now;
    Ok(if held {
        ClaimFence::Held
    } else {
        ClaimFence::Lost
    })
}

async fn scope_control_revision<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScope,
) -> Result<u64, FeishuError> {
    match &scope.key {
        DeliveryScopeKey::Frontend { authorization } => Ok(audience::load_auth(db, authorization)
            .await?
            .ok_or_else(unreadable)?
            .revision),
        DeliveryScopeKey::LegacyFinal { .. } => Ok(0),
    }
}

/// 前端范围每次写入都回读原授权：PendingStart/Closed/Paused 都不许可新平台写。
async fn authorization_gap<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScope,
) -> Result<Option<String>, FeishuError> {
    let row = db.query_one_raw(statement("SELECT chat_id,thread_id,status,project_id,creation_id,revision FROM thread_bindings WHERE chat_id=?", vec![scope.chat_id.clone().into()])).await.map_err(storage)?;
    let Some(row) = row else {
        return Ok(Some("delivery route is missing".into()));
    };
    if strict_text(&row, "chat_id")? != scope.chat_id
        || strict_text(&row, "thread_id")? != scope.thread_id
        || strict_text(&row, "status")? != "bound"
        || strict_text(&row, "project_id")? != scope.project_id
        || strict_text(&row, "creation_id")? != scope.creation_id
        || u64::try_from(stored_i64(&row, "revision")?).map_err(|_| unreadable())?
            != scope.binding_revision
    {
        return Ok(Some(
            "delivery route no longer matches its original binding".into(),
        ));
    }
    if let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin {
        super::legacy::validate(db, scope).await?;
        if let Some(reason) = super::legacy::write_gap(db, legacy).await? {
            return Ok(Some(reason));
        }
        if db.query_one_raw(statement("SELECT 1 FROM bot_delivery_items WHERE scope_key=? AND json_extract(state_json,'$.card.lifecycle')='needsAttention' LIMIT 1",vec![scope.key.storage_key()?.into()])).await.map_err(storage)?.is_some() {
            return Ok(Some("legacy card needs local attention".into()));
        }
    }
    let DeliveryScopeKey::Frontend { authorization } = &scope.key else {
        return Ok(None);
    };
    let Some(auth) = audience::load_auth(db, authorization).await? else {
        return Ok(Some("delivery authorization is missing".to_string()));
    };
    if auth.intent.authorization != *authorization
        || auth.intent.thread_id != scope.thread_id
        || auth.app_id != scope.app_id
        || auth.project_id != scope.project_id
        || auth.creation_id != scope.creation_id
        || auth.intent.binding_revision != scope.binding_revision
    {
        return Err(unreadable());
    }
    if !authorization_active(&auth) {
        return Ok(Some("delivery authorization is not active".to_string()));
    }
    Ok(None)
}
