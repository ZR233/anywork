//! Indexed, non-initializing audience reads. Missing proof is never an empty successful scope.

use super::{
    Authorization, DeliveryObservation, SyncOperation, ThreadOrigin, authorization, origin, proof,
    unreadable,
};
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{
    BindingProjection, BotStateStore, statement, storage, strict_text, strict_watermark,
};
use pl_protocol::BotAuthorizationId;
use sea_orm::{ConnectionTrait, TransactionTrait};

pub(in crate::bots) struct AudienceScope {
    pub origin: ThreadOrigin,
    pub binding: BindingProjection,
    pub head: Option<Authorization>,
    pub latest_closed: Option<Authorization>,
    pub has_older_closed: bool,
}

pub(in crate::bots::storage) async fn read_origin<C: ConnectionTrait>(
    db: &C,
    thread: &str,
) -> Result<Option<ThreadOrigin>, FeishuError> {
    db.query_one_raw(statement(
        "SELECT * FROM bot_audience_origins WHERE thread_id=?",
        vec![thread.into()],
    ))
    .await
    .map_err(storage)?
    .as_ref()
    .map(origin)
    .transpose()
}

pub(in crate::bots::storage) async fn proven_origin<C: ConnectionTrait>(
    db: &C,
    thread: &str,
    bot: &str,
) -> Result<Option<ThreadOrigin>, FeishuError> {
    let Some(origin) = read_origin(db, thread).await? else {
        return Ok(None);
    };
    if !proof::check_known(db, &origin, bot).await? {
        return Ok(None);
    }
    Ok(Some(origin))
}

pub(in crate::bots::storage) async fn head<C: ConnectionTrait>(
    db: &C,
    chat: &str,
) -> Result<Option<Authorization>, FeishuError> {
    db.query_one_raw(statement(
        "SELECT * FROM bot_authorizations WHERE chat_id=? ORDER BY generation DESC LIMIT 1",
        vec![chat.into()],
    ))
    .await
    .map_err(storage)?
    .as_ref()
    .map(authorization)
    .transpose()
}

pub(in crate::bots::storage) async fn load_auth<C: ConnectionTrait>(
    db: &C,
    id: &BotAuthorizationId,
) -> Result<Option<Authorization>, FeishuError> {
    let auth = db
        .query_one_raw(statement(
            "SELECT * FROM bot_authorizations WHERE chat_id=? AND generation=?",
            vec![
                id.chat_id.clone().into(),
                i64::try_from(id.generation)
                    .map_err(|_| unreadable())?
                    .into(),
            ],
        ))
        .await
        .map_err(storage)?
        .as_ref()
        .map(authorization)
        .transpose()?;
    if auth
        .as_ref()
        .is_some_and(|auth| auth.intent.authorization != *id)
    {
        return Err(unreadable());
    }
    Ok(auth)
}

pub(super) async fn operation<C: ConnectionTrait>(
    db: &C,
    id: &str,
) -> Result<Option<SyncOperation>, FeishuError> {
    let Some(row)=db.query_one_raw(statement("SELECT operation_id,thread_id,request_json FROM bot_sync_operations WHERE operation_id=?",vec![id.into()])).await.map_err(storage)? else {return Ok(None)};
    let op: SyncOperation =
        serde_json::from_str(&strict_text(&row, "request_json")?).map_err(|_| unreadable())?;
    if op.request.operation_id != strict_text(&row, "operation_id")?
        || op.request.thread_id != strict_text(&row, "thread_id")?
    {
        return Err(unreadable());
    }
    Ok(Some(op))
}

impl BotStateStore {
    pub(in crate::bots) async fn audience_target(
        &self,
        chat: &str,
    ) -> Result<(pl_protocol::studio::BotConversationKind, Option<String>), FeishuError> {
        let db = self.audience_db()?;
        if let Some(row) = db
            .query_one_raw(statement(
                "SELECT open_id FROM observed_directs WHERE chat_id=?",
                vec![chat.into()],
            ))
            .await
            .map_err(storage)?
        {
            let user = strict_text(&row, "open_id")?;
            if user.is_empty() {
                return Err(unreadable());
            }
            return Ok((pl_protocol::studio::BotConversationKind::Direct, Some(user)));
        }
        let rows = db
            .query_all_raw(statement(
                "SELECT DISTINCT chat_kind FROM inbound_work WHERE chat_id=? LIMIT 2",
                vec![chat.into()],
            ))
            .await
            .map_err(storage)?;
        if rows.len() == 1 && strict_text(&rows[0], "chat_kind")? == "group" {
            return Ok((pl_protocol::studio::BotConversationKind::Group, None));
        }
        Err(unreadable())
    }

    pub(in crate::bots) async fn audience_scope(
        &self,
        thread: &str,
        bot_id: &str,
    ) -> Result<Option<AudienceScope>, FeishuError> {
        let tx = self.audience_db()?.begin().await.map_err(storage)?;
        let Some(origin) = proven_origin(&tx, thread, bot_id).await? else {
            return Ok(None);
        };
        if tx
            .query_one_raw(statement(
                "SELECT 1 FROM bot_authorizations WHERE thread_id=?1 AND (chat_id<>?2
             OR json_extract(state_json,'$.intent.authorization.botId') IS NOT ?3
             OR json_extract(state_json,'$.projectId') IS NOT ?4
             OR json_extract(state_json,'$.creationId') IS NOT ?5
             OR json_extract(state_json,'$.intent.bindingRevision') IS NOT ?6) LIMIT 1",
                vec![
                    thread.into(),
                    origin.chat_id.clone().into(),
                    bot_id.into(),
                    origin.project_id.clone().into(),
                    origin.creation_id.clone().into(),
                    i64::try_from(origin.binding_revision)
                        .map_err(|_| unreadable())?
                        .into(),
                ],
            ))
            .await
            .map_err(storage)?
            .is_some()
        {
            return Err(unreadable());
        }
        let row = tx
            .query_one_raw(statement(
                "SELECT * FROM thread_bindings WHERE chat_id=?",
                vec![origin.chat_id.clone().into()],
            ))
            .await
            .map_err(storage)?
            .ok_or_else(unreadable)?;
        let id = strict_text(&row, "thread_id")?;
        let binding = BindingProjection {
            chat_id: strict_text(&row, "chat_id")?,
            project_id: strict_text(&row, "project_id")?,
            creation_id: strict_text(&row, "creation_id")?,
            thread_id: (!id.is_empty()).then_some(id),
            revision: strict_watermark(&row, "revision")?,
            status: strict_text(&row, "status")?,
            diagnostic: None,
        };
        if binding.project_id != origin.project_id
            || !matches!(
                binding.status.as_str(),
                "bound" | "creating" | "needs_attention"
            )
        {
            return Err(unreadable());
        }
        let head = head(&tx, &origin.chat_id).await?;
        let rows=tx.query_all_raw(statement("SELECT * FROM bot_authorizations WHERE thread_id=? AND phase='closed' ORDER BY generation DESC LIMIT 2",vec![thread.into()])).await.map_err(storage)?;
        let latest_closed = rows.first().map(authorization).transpose()?;
        let has_older_closed = rows.len() > 1;
        tx.commit().await.map_err(storage)?;
        Ok(Some(AudienceScope {
            origin,
            binding,
            head,
            latest_closed,
            has_older_closed,
        }))
    }

    pub(in crate::bots) async fn audience_authorization(
        &self,
        id: &BotAuthorizationId,
    ) -> Result<Option<Authorization>, FeishuError> {
        load_auth(self.audience_db()?, id).await
    }

    pub(in crate::bots) async fn closed_authorizations(
        &self,
        thread: &str,
        highest: u64,
        before: Option<u64>,
        limit: u32,
    ) -> Result<Vec<Authorization>, FeishuError> {
        let before = before
            .map(i64::try_from)
            .transpose()
            .map_err(|_| unreadable())?;
        let rows=self.audience_db()?.query_all_raw(statement("SELECT * FROM bot_authorizations WHERE thread_id=?1 AND phase='closed' AND generation<=?2 AND (?3 IS NULL OR generation<?3) ORDER BY generation DESC LIMIT ?4",
            vec![thread.into(),i64::try_from(highest).map_err(|_|unreadable())?.into(),before.into(),i64::from(limit).into()])).await.map_err(storage)?;
        rows.iter().map(authorization).collect()
    }

    pub(in crate::bots) async fn audience_item(
        &self,
        auth: &BotAuthorizationId,
        item: &str,
    ) -> Result<Option<DeliveryObservation>, FeishuError> {
        // 当前唯一账本派生：作用域与完整授权身份共同核对，冷查询不初始化存储。
        self.delivery_observation(auth, item).await
    }
}
