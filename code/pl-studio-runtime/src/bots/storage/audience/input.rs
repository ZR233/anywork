//! Local input readiness, derived from existing creation and authorization facts only.

mod budget;

use super::{authorization, proof, read, unreadable};
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{BotStateStore, statement, storage, strict_text, strict_watermark};
use crate::studio::thread_audience::BotThreadInputReadiness;
use budget::SourceBudget;
use pl_protocol::studio::BotAuthorizationPhase;
use sea_orm::{ConnectionTrait, TransactionTrait};

/// A creating row has no origin yet. Require its exact pre-existing binding operation or frozen
/// inbound identity, and reject every independently known conflicting field instead of borrowing
/// the current route to reconstruct historical ownership.
async fn prove_creating(
    budget: &mut SourceBudget<'_>,
    bot: &str,
    thread: &str,
    project: &str,
) -> Result<bool, FeishuError> {
    budget.creating(thread).await?;
    let db = budget.db;
    let rows = db
        .query_all_raw(statement(
            "SELECT * FROM thread_bindings INDEXED BY bot_route_thread_lookup WHERE thread_id=?1
             UNION ALL SELECT * FROM thread_bindings INDEXED BY bot_route_creation_lookup
             WHERE creation_id=?1 AND thread_id<>?1 LIMIT 2",
            vec![thread.into()],
        ))
        .await
        .map_err(storage)?;
    if rows.len() != 1 {
        return Err(unreadable());
    }
    let row = &rows[0];
    let chat = strict_text(row, "chat_id")?;
    let creation = strict_text(row, "creation_id")?;
    let bound = strict_text(row, "thread_id")?;
    let revision = strict_watermark(row, "revision")?;
    let generation = strict_watermark(row, "generation")?;
    if strict_text(row, "status")? != "creating"
        || creation != thread
        || !bound.is_empty() && bound != thread
        || chat.is_empty()
        || project.is_empty()
        || strict_text(row, "project_id")? != project
        || revision == 0
        || generation == 0
    {
        return Err(unreadable());
    }
    proof::check_creation_thread(db, thread, thread).await?;
    if db
        .query_one_raw(statement(
            "SELECT 1 FROM bot_authorizations INDEXED BY bot_authorizations_thread WHERE thread_id=?1 LIMIT 1",
            vec![thread.into()],
        ))
        .await
        .map_err(storage)?
        .is_some()
    {
        // A generation cannot precede this initial creating boundary. In particular, a missing
        // origin must not turn an already initialized/closed Thread into a new creation.
        return Err(unreadable());
    }
    let revision = i64::try_from(revision).map_err(|_| unreadable())?;
    let conflict = db.query_one_raw(statement(
        "SELECT 1 FROM binding_operations INDEXED BY bot_binding_creation_lookup WHERE creation_id=?1 AND
          (bot_id<>?2 OR chat_id<>?3 OR expected_revision<0 OR expected_revision>=9223372036854775807
           OR expected_revision+1<>?4 OR (thread_id<>'' AND thread_id<>?1))
         UNION ALL SELECT 1 FROM inbound_work INDEXED BY inbound_source_creation WHERE creation_id=?1 AND
          (bot_id<>?2 OR chat_id<>?3 OR project_id<>?5 OR binding_revision<>?4) LIMIT 1",
        vec![thread.into(),bot.into(),chat.clone().into(),revision.into(),project.into()],
    )).await.map_err(storage)?;
    if conflict.is_some() {
        return Err(unreadable());
    }
    Ok(db
        .query_one_raw(statement(
            "SELECT 1 FROM binding_operations INDEXED BY bot_binding_creation_lookup WHERE creation_id=?1 AND bot_id=?2 AND chat_id=?3
           AND expected_revision=?4-1 AND (thread_id='' OR thread_id=?1)
         UNION ALL SELECT 1 FROM inbound_work INDEXED BY inbound_source_creation WHERE creation_id=?1 AND bot_id=?2 AND chat_id=?3
           AND project_id=?5 AND binding_revision=?4 LIMIT 1",
            vec![
                thread.into(),
                bot.into(),
                chat.into(),
                revision.into(),
                project.into(),
            ],
        ))
        .await
        .map_err(storage)?
        .is_some())
}

impl BotStateStore {
    pub(in crate::bots) async fn thread_input_readiness(
        &self,
        bot: &str,
        thread: &str,
        project: &str,
    ) -> Result<BotThreadInputReadiness, FeishuError> {
        // audience_db does not open, initialize or migrate a missing/closed store.
        let tx = self.audience_db()?.begin().await.map_err(storage)?;
        let mut budget = SourceBudget::new(&tx);
        let Some(origin) = budget.proven_origin(thread, bot).await? else {
            if !prove_creating(&mut budget, bot, thread, project).await? {
                return Err(unreadable());
            }
            tx.commit().await.map_err(storage)?;
            return Ok(BotThreadInputReadiness::Preparing);
        };
        if origin.project_id != project {
            return Err(unreadable());
        }
        // Admit every matching authorization before the complete conflict check. LIMIT 1 on the
        // conflict result itself does not bound a no-conflict history scan.
        budget.authorizations(thread).await?;
        let mismatch = tx
            .query_one_raw(statement(
                "SELECT 1 FROM bot_authorizations INDEXED BY bot_authorizations_thread WHERE thread_id=?1 AND
             (chat_id<>?2 OR json_extract(state_json,'$.intent.authorization.botId') IS NOT ?3
              OR json_extract(state_json,'$.projectId') IS NOT ?4
              OR json_extract(state_json,'$.creationId') IS NOT ?5
              OR json_extract(state_json,'$.intent.bindingRevision') IS NOT ?6
              OR phase NOT IN ('pending','active','paused','closed')
              OR generation<=0 OR control_revision<=0
              OR json_extract(state_json,'$.revision') IS NOT control_revision
              OR json_extract(state_json,'$.intent.authorization.generation') IS NOT generation
              OR json_extract(state_json,'$.phase') IS NOT CASE phase WHEN 'pending' THEN 'pendingStart' ELSE phase END) LIMIT 1",
                vec![
                    thread.into(),
                    origin.chat_id.clone().into(),
                    bot.into(),
                    project.into(),
                    origin.creation_id.clone().into(),
                    i64::try_from(origin.binding_revision)
                        .map_err(|_| unreadable())?
                        .into(),
                ],
            ))
            .await
            .map_err(storage)?;
        if mismatch.is_some() {
            return Err(unreadable());
        }
        budget.route(&origin.chat_id).await?;
        let route = tx
            .query_one_raw(statement(
                "SELECT * FROM thread_bindings WHERE chat_id=?",
                vec![origin.chat_id.clone().into()],
            ))
            .await
            .map_err(storage)?
            .ok_or_else(unreadable)?;
        let bound = strict_text(&route, "thread_id")?;
        let creation = strict_text(&route, "creation_id")?;
        let status = strict_text(&route, "status")?;
        let revision = strict_watermark(&route, "revision")?;
        if strict_text(&route, "project_id")? != project
            || !matches!(status.as_str(), "bound" | "creating" | "needs_attention")
            || revision == 0
        {
            return Err(unreadable());
        }
        budget.head(&origin.chat_id).await?;
        let head = read::head(&tx, &origin.chat_id).await?;
        if head.as_ref().is_some_and(|auth| {
            auth.intent.authorization.bot_id != bot
                || auth.project_id != project
                || bound == thread
                    && auth.intent.thread_id != thread
                    && auth.phase != BotAuthorizationPhase::Closed
        }) {
            return Err(unreadable());
        }
        // The first generation is an indexed one-row proof. A successor cannot exist until it
        // closed, so later PendingStart cannot erase the already established local semantics.
        let first = tx
            .query_one_raw(statement(
                "SELECT * FROM bot_authorizations INDEXED BY bot_authorizations_thread WHERE thread_id=? ORDER BY generation LIMIT 1",
                vec![thread.into()],
            ))
            .await
            .map_err(storage)?
            .as_ref()
            .map(authorization)
            .transpose()?;
        if first.as_ref().is_some_and(|first| {
            first.phase == BotAuthorizationPhase::PendingStart
                && head.as_ref().is_none_or(|head| head.intent != first.intent)
        }) {
            return Err(unreadable());
        }
        let initialized = first
            .as_ref()
            .is_some_and(|a| a.phase != BotAuthorizationPhase::PendingStart);
        let readiness = if origin.requires_upgrade || initialized {
            BotThreadInputReadiness::Ready
        } else if bound != thread
            && creation != origin.creation_id
            && revision > origin.binding_revision
        {
            // Replaced means a provable successor, not merely a missing current pointer.
            if creation.is_empty() {
                return Err(unreadable());
            }
            if status == "bound" {
                let successor = budget
                    .proven_origin(&bound, bot)
                    .await?
                    .ok_or_else(unreadable)?;
                if successor.chat_id != origin.chat_id
                    || successor.project_id != project
                    || successor.creation_id != creation
                    || successor.binding_revision != revision
                {
                    return Err(unreadable());
                }
            } else if status != "creating"
                || !bound.is_empty()
                || !prove_creating(&mut budget, bot, &creation, project).await?
            {
                return Err(unreadable());
            }
            BotThreadInputReadiness::Ready
        } else if status == "bound" && bound == thread && creation == origin.creation_id {
            let preparing = head
                .as_ref()
                .is_some_and(|auth| auth.intent.thread_id == thread);
            if head.as_ref().is_some_and(|auth| {
                if preparing {
                    auth.phase != BotAuthorizationPhase::PendingStart
                } else {
                    auth.phase != BotAuthorizationPhase::Closed
                }
            }) {
                return Err(unreadable());
            }
            // `Preparing` 只表示「确有本 Thread 的 PendingStart，正在准备 cut」。没有授权
            // 头的已绑定 Thread 在本机可正常使用（前端不活跃由受众视图表达），不能借用
            // 输入就绪来长期阻塞它。
            if preparing {
                BotThreadInputReadiness::Preparing
            } else {
                BotThreadInputReadiness::Ready
            }
        } else {
            return Err(unreadable());
        };
        tx.commit().await.map_err(storage)?;
        Ok(readiness)
    }
}
