//! Original-operation keyset sealing, including notices that never had an authorization head.

use super::*;
use crate::bots::config::BotConfigFile;
use sea_orm::TransactionTrait;

impl BotStateStore {
    pub(in crate::bots) async fn prune_inbound_notice_page(
        &self,
        config: &BotConfigFile,
        after: Option<&str>,
    ) -> Result<(bool, Option<String>), FeishuError> {
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let rows = tx
            .query_all_raw(statement(
                "SELECT o.* FROM send_operations o JOIN inbound_work w
               ON w.bot_id=o.bot_id AND w.chat_id=o.chat_id
                  AND w.message_id=json_extract(o.send_source,'$.messageId')
             WHERE o.operation_id>? AND json_extract(o.send_identity,'$.kind')='inboundNotice'
               AND w.status IN ('pending','claimed','failed')
             ORDER BY o.operation_id LIMIT 33",
                vec![after.unwrap_or("").into()],
            ))
            .await
            .map_err(storage)?;
        let more = rows.len() > 32;
        let mut last = None;
        let mut changed = false;
        for row in rows.into_iter().take(32) {
            let record = crate::bots::storage::send_record_from_row(row)?;
            let identity = operation::identity(&record)?;
            let work = authority::work(&tx, identity).await?;
            let s = &identity.source;
            let trusted = match s.chat_kind.as_str() {
                "direct" => config.feishu().trusted_open_ids.contains(&s.open_id),
                "group" => config.feishu().trusted_chat_ids.contains(&s.chat_id),
                _ => false,
            };
            if !config.enabled
                || config.id != s.bot_id
                || !trusted
                || config.feishu().app_id != s.app_id
                || config.project_id != s.project_id
                || matches!(
                    authority::scope(&tx, identity).await?,
                    authority::Scope::Closed
                )
            {
                let keys = authority::keys(s);
                let updated = tx.execute_raw(statement(
                    "UPDATE inbound_work SET status='needs_attention',diagnostic='original notice is no longer authorized',
                       claimed_by='',claimed_at=0,next_attempt_at=0,updated_at=?
                     WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=? AND content_hash=?
                       AND status IN ('pending','claimed','failed')",
                    vec![crate::studio::unix_seconds().into(),keys.identity.into(),s.bot_id.clone().into(),
                        s.chat_id.clone().into(),s.message_id.clone().into(),work.content_hash.into()],
                )).await.map_err(storage)?;
                changed |= updated.rows_affected() == 1;
            }
            last = Some(record.operation_id);
        }
        tx.commit().await.map_err(storage)?;
        Ok((changed, if more { last } else { None }))
    }
}
