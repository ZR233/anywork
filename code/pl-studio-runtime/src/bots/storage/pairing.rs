use super::*;

const PAIRING_LIMIT: i64 = 32;
const PAIRING_TTL_SECONDS: i64 = 7 * 24 * 60 * 60;

#[derive(Debug, Clone)]
pub struct ObservedDirect {
    pub chat_id: String,
    pub name: Option<String>,
    pub last_observed_at: i64,
}

#[derive(Debug, Clone)]
pub struct PairingRow {
    pub request_id: String,
    pub open_id: String,
    pub display_name: Option<String>,
    pub created_at: i64,
}

impl BotStateStore {
    pub async fn observe_direct(
        &self,
        chat_id: &str,
        open_id: Option<&str>,
        name: Option<&str>,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "INSERT INTO observed_directs(chat_id, open_id, name, last_observed_at)
             VALUES(?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               open_id=excluded.open_id,
               name=COALESCE(NULLIF(excluded.name,''), observed_directs.name),
               last_observed_at=excluded.last_observed_at",
            vec![
                chat_id.to_string().into(),
                open_id.unwrap_or("").to_string().into(),
                name.unwrap_or("").to_string().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }

    pub(crate) async fn last_activity_at(&self) -> Result<Option<i64>, FeishuError> {
        let db = self.db().await?;
        let row = db.query_one_raw(statement(
            "SELECT MAX(at) AS at FROM (SELECT MAX(admitted_at) AS at FROM inbound_identities UNION ALL SELECT MAX(updated_at) AS at FROM send_operations)", vec![]
        )).await.map_err(storage)?.ok_or_else(|| storage("missing bot activity aggregate"))?;
        row.try_get::<Option<i64>>("", "at").map_err(storage)
    }

    pub async fn list_observed_directs(&self) -> Result<Vec<ObservedDirect>, FeishuError> {
        let db = self.db().await?;
        let rows = db
            .query_all_raw(statement(
                "SELECT chat_id, name, last_observed_at FROM observed_directs ORDER BY last_observed_at DESC",
                vec![],
            ))
            .await
            .map_err(storage)?;
        rows.into_iter()
            .map(|row| {
                Ok(ObservedDirect {
                    chat_id: stored_text(&row, "chat_id")?,
                    name: empty_to_none(stored_text(&row, "name")?),
                    last_observed_at: stored_i64(&row, "last_observed_at")?,
                })
            })
            .collect()
    }

    pub async fn record_pairing(
        &self,
        request_id: &str,
        open_id: &str,
        display_name: Option<&str>,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let cutoff = unix_seconds().saturating_sub(PAIRING_TTL_SECONDS);
        tx.execute_raw(statement(
            "DELETE FROM pairing_requests WHERE created_at < ?",
            vec![cutoff.into()],
        ))
        .await
        .map_err(storage)?;
        let count = tx
            .query_one_raw(statement(
                "SELECT COUNT(*) AS n FROM pairing_requests",
                vec![],
            ))
            .await
            .map_err(storage)?;
        // 配额计数只接受可解码值：损坏不能静默放宽配对上限。
        let n: i64 = match &count {
            Some(row) => stored_i64(row, "n")?,
            None => 0,
        };
        let existing = tx
            .query_one_raw(statement(
                "SELECT open_id FROM pairing_requests WHERE open_id=?",
                vec![open_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        if existing.is_none() && n >= PAIRING_LIMIT {
            tx.commit().await.map_err(storage)?;
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "pairing request budget is full",
                true,
                None,
            ));
        }
        tx.execute_raw(statement(
            "INSERT INTO pairing_requests(request_id, open_id, display_name, created_at)
             VALUES(?,?,?,?)
             ON CONFLICT(open_id) DO UPDATE SET
               display_name=excluded.display_name,
               created_at=excluded.created_at",
            vec![
                request_id.to_string().into(),
                open_id.to_string().into(),
                display_name.unwrap_or("").to_string().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    pub async fn list_pairings(&self) -> Result<Vec<PairingRow>, FeishuError> {
        let db = self.db().await?;
        let cutoff = unix_seconds().saturating_sub(PAIRING_TTL_SECONDS);
        db.execute_raw(statement(
            "DELETE FROM pairing_requests WHERE created_at < ?",
            vec![cutoff.into()],
        ))
        .await
        .map_err(storage)?;
        let rows = db
            .query_all_raw(statement(
                "SELECT request_id, open_id, display_name, created_at FROM pairing_requests
                 ORDER BY created_at DESC LIMIT ?",
                vec![PAIRING_LIMIT.into()],
            ))
            .await
            .map_err(storage)?;
        rows.into_iter()
            .map(|row| {
                Ok(PairingRow {
                    request_id: stored_text(&row, "request_id")?,
                    open_id: stored_text(&row, "open_id")?,
                    display_name: empty_to_none(stored_text(&row, "display_name")?),
                    created_at: stored_i64(&row, "created_at")?,
                })
            })
            .collect()
    }

    pub async fn clear_pairing(&self, open_id: &str) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "DELETE FROM pairing_requests WHERE open_id=?",
            vec![open_id.to_string().into()],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }
}
