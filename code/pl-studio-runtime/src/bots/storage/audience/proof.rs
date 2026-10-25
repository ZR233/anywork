//! Reconcile only evidence for the same Thread. Empty legacy fields are missing proof, not values
//! to borrow from whichever Thread currently occupies the same chat.

use super::{ThreadOrigin, unreadable};
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{statement, storage, strict_text, strict_watermark};
use sea_orm::{ConnectionTrait, QueryResult};

// Already part of schema eight, not an unversioned schema-nine structure. The normal owner may
// install this derived index when absent; current validation still rejects a wrong declaration.
pub(super) const INHERITED_INDEXES: &[(&str, &str)] = &[(
    "inbound_source_creation",
    "CREATE INDEX inbound_source_creation ON inbound_work(creation_id, status)",
)];

pub(super) const INDEXES: &[(&str, &str)] = &[
    (
        "bot_binding_thread_lookup",
        "CREATE INDEX bot_binding_thread_lookup ON binding_operations(thread_id)",
    ),
    (
        "bot_route_thread_lookup",
        "CREATE INDEX bot_route_thread_lookup ON thread_bindings(thread_id)",
    ),
    (
        "bot_card_thread_lookup",
        "CREATE INDEX bot_card_thread_lookup ON bot_card_streams(thread_id)",
    ),
    (
        "bot_route_creation_lookup",
        "CREATE INDEX bot_route_creation_lookup ON thread_bindings(creation_id)",
    ),
];

#[derive(Clone, Copy)]
pub(super) enum Boundary {
    SchemaEight,
    Current,
}

#[derive(Default)]
pub(super) struct OriginProof {
    bot: Option<String>,
    chat: Option<String>,
    project: Option<String>,
    creation: Option<String>,
    revision: Option<u64>,
}

impl OriginProof {
    pub(super) fn check(
        &self,
        origin: &ThreadOrigin,
        bot: Option<&str>,
    ) -> Result<bool, FeishuError> {
        for (known, actual) in [
            (self.chat.as_deref(), origin.chat_id.as_str()),
            (self.project.as_deref(), origin.project_id.as_str()),
            (self.creation.as_deref(), origin.creation_id.as_str()),
        ] {
            if known.is_some_and(|known| known != actual) {
                return Err(unreadable());
            }
        }
        if self
            .revision
            .is_some_and(|known| known != origin.binding_revision)
            || self.bot.as_deref().zip(bot).is_some_and(|(a, b)| a != b)
        {
            return Err(unreadable());
        }
        Ok(self.chat.is_some()
            && self.project.is_some()
            && self.creation.is_some()
            && self.revision.is_some())
    }

    pub(super) fn into_legacy_origin(self, thread: String) -> Option<ThreadOrigin> {
        Some(ThreadOrigin {
            thread_id: thread,
            chat_id: self.chat?,
            project_id: self.project?,
            creation_id: self.creation?,
            binding_revision: self.revision?,
            requires_upgrade: true,
            summary_version: 1,
            target: super::super::target::TargetProof::Unproven,
        })
    }

    fn source(&mut self, row: &QueryResult) -> Result<(), FeishuError> {
        self.source_identity(row)?;
        merge_revision(
            &mut self.revision,
            strict_watermark(row, "binding_revision")?,
        )
    }

    fn source_identity(&mut self, row: &QueryResult) -> Result<(), FeishuError> {
        merge_text(&mut self.bot, strict_text(row, "bot_id")?)?;
        merge_text(&mut self.chat, strict_text(row, "chat_id")?)?;
        merge_text(&mut self.project, strict_text(row, "project_id")?)?;
        merge_text(&mut self.creation, strict_text(row, "creation_id")?)
    }
}

/// Current origins are immutable, transactionally recorded facts. Check all independently known
/// source fields using indexed conflict probes; displaying one Thread must not load its history.
pub(super) async fn check_known<C: ConnectionTrait>(
    db: &C,
    origin: &ThreadOrigin,
    bot: &str,
) -> Result<bool, FeishuError> {
    if origin.project_id.is_empty() || origin.creation_id.is_empty() || origin.binding_revision == 0
    {
        return Ok(false);
    }
    let revision = i64::try_from(origin.binding_revision).map_err(|_| unreadable())?;
    super::super::target::check_sources(db, origin, bot).await?;
    check_creation_thread(db, &origin.creation_id, &origin.thread_id).await?;
    let probes = [
        ("SELECT 1 FROM thread_bindings INDEXED BY bot_route_thread_lookup WHERE thread_id=?1 AND
          (chat_id<>?2 OR (project_id<>'' AND project_id<>?3) OR (creation_id<>'' AND creation_id<>?4)
          OR (status='bound' AND revision<>?5)) LIMIT 1",
            vec![origin.thread_id.clone().into(),origin.chat_id.clone().into(),origin.project_id.clone().into(),origin.creation_id.clone().into(),revision.into()]),
        ("SELECT 1 FROM binding_operations INDEXED BY bot_binding_thread_lookup WHERE thread_id=?1 AND
          (chat_id<>?2 OR (creation_id<>'' AND creation_id<>?3) OR expected_revision<0
          OR expected_revision>=9223372036854775807 OR expected_revision+1<>?4 OR bot_id<>?5) LIMIT 1",
            vec![origin.thread_id.clone().into(),origin.chat_id.clone().into(),origin.creation_id.clone().into(),revision.into(),bot.into()]),
        ("SELECT 1 FROM bot_card_streams c INDEXED BY bot_card_thread_lookup LEFT JOIN inbound_work w ON c.identity=w.identity WHERE c.thread_id=?1 AND
          (c.chat_id<>?2 OR c.bot_id<>?6 OR (w.chat_id<>'' AND w.chat_id<>?2)
          OR (w.project_id<>'' AND w.project_id<>?3) OR (w.creation_id<>'' AND w.creation_id<>?4)
          OR (w.binding_revision>0 AND w.binding_revision<>?5) OR (w.bot_id<>'' AND w.bot_id<>?6)) LIMIT 1",
            vec![origin.thread_id.clone().into(),origin.chat_id.clone().into(),origin.project_id.clone().into(),origin.creation_id.clone().into(),revision.into(),bot.into()]),
        ("SELECT 1 FROM inbound_work w INDEXED BY inbound_source_creation WHERE w.creation_id=?1 AND
          ((w.chat_id<>'' AND w.chat_id<>?2) OR (w.project_id<>'' AND w.project_id<>?3)
          OR (w.bot_id<>'' AND w.bot_id<>?4) OR w.binding_revision<0
          OR (w.binding_revision>0 AND w.binding_revision<>?5 AND EXISTS(
              SELECT 1 FROM thread_bindings b INDEXED BY bot_route_thread_lookup WHERE b.thread_id=?6 AND b.status='bound'))) LIMIT 1",
            vec![origin.creation_id.clone().into(),origin.chat_id.clone().into(),origin.project_id.clone().into(),bot.into(),revision.into(),origin.thread_id.clone().into()]),
    ];
    for (sql, parameters) in probes {
        if db
            .query_one_raw(statement(sql, parameters))
            .await
            .map_err(storage)?
            .is_some()
        {
            return Err(unreadable());
        }
    }
    Ok(true)
}

pub(super) async fn check_creation_thread<C: ConnectionTrait>(
    db: &C,
    creation: &str,
    thread: &str,
) -> Result<(), FeishuError> {
    if db.query_one_raw(statement(
        "SELECT thread_id FROM thread_bindings INDEXED BY bot_route_creation_lookup WHERE creation_id=?1 AND thread_id<>'' AND thread_id<>?2
         UNION ALL SELECT thread_id FROM binding_operations INDEXED BY bot_binding_creation_lookup WHERE creation_id=?1 AND thread_id<>'' AND thread_id<>?2
         UNION ALL SELECT c.thread_id FROM inbound_work w INDEXED BY inbound_source_creation CROSS JOIN bot_card_streams c ON c.identity=w.identity WHERE w.creation_id=?1 AND c.thread_id<>?2
         UNION ALL SELECT thread_id FROM bot_audience_origins INDEXED BY bot_origin_creation_lookup WHERE creation_id=?1 AND thread_id<>?2 LIMIT 1",
        vec![creation.into(),thread.into()],
    )).await.map_err(storage)?.is_some() {return Err(unreadable());}
    Ok(())
}

fn merge_text(known: &mut Option<String>, value: String) -> Result<(), FeishuError> {
    if !value.is_empty() {
        if known.as_ref().is_some_and(|known| *known != value) {
            return Err(unreadable());
        }
        *known = Some(value);
    }
    Ok(())
}

fn merge_revision(known: &mut Option<u64>, value: u64) -> Result<(), FeishuError> {
    if value > 0 {
        if known.is_some_and(|known| known != value) {
            return Err(unreadable());
        }
        *known = Some(value);
    }
    Ok(())
}

pub(super) async fn collect<C: ConnectionTrait>(
    db: &C,
    thread: &str,
    boundary: Boundary,
) -> Result<OriginProof, FeishuError> {
    let mut proof = OriginProof::default();
    let mut current_bound = false;
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT chat_id,project_id,creation_id,revision,status FROM thread_bindings
             WHERE thread_id=? AND chat_id>? ORDER BY chat_id LIMIT 64",
                vec![thread.into(), after.into()],
            ))
            .await
            .map_err(storage)?;
        let done = rows.len() < 64;
        after = String::new();
        for row in rows {
            after = strict_text(&row, "chat_id")?;
            merge_text(&mut proof.chat, after.clone())?;
            merge_text(&mut proof.project, strict_text(&row, "project_id")?)?;
            merge_text(&mut proof.creation, strict_text(&row, "creation_id")?)?;
            // Schema eight's revision is the creation revision. In nine, attention increments
            // the route CAS, not the immutable creation revision retained by the original sources.
            let bound = strict_text(&row, "status")? == "bound";
            current_bound |= bound;
            if matches!(boundary, Boundary::SchemaEight) || bound {
                merge_revision(&mut proof.revision, strict_watermark(&row, "revision")?)?;
            }
        }
        if done {
            break;
        }
    }
    let mut after = String::new();
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT operation_id,bot_id,chat_id,creation_id,expected_revision FROM binding_operations
             WHERE thread_id=? AND operation_id>? ORDER BY operation_id LIMIT 64",
            vec![thread.into(), after.into()],
        )).await.map_err(storage)?;
        let done = rows.len() < 64;
        after = String::new();
        for row in rows {
            after = strict_text(&row, "operation_id")?;
            merge_text(&mut proof.bot, strict_text(&row, "bot_id")?)?;
            merge_text(&mut proof.chat, strict_text(&row, "chat_id")?)?;
            merge_text(&mut proof.creation, strict_text(&row, "creation_id")?)?;
            let revision = strict_watermark(&row, "expected_revision")?
                .checked_add(1)
                .filter(|v| *v <= i64::MAX as u64)
                .ok_or_else(unreadable)?;
            merge_revision(&mut proof.revision, revision)?;
        }
        if done {
            break;
        }
    }
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT c.identity,c.bot_id AS card_bot,c.chat_id AS card_chat,
             COALESCE(w.bot_id,'') AS bot_id,COALESCE(w.chat_id,'') AS chat_id,
             COALESCE(w.project_id,'') AS project_id,COALESCE(w.creation_id,'') AS creation_id,
             COALESCE(w.binding_revision,0) AS binding_revision
             FROM bot_card_streams c LEFT JOIN inbound_work w ON w.identity=c.identity
             WHERE c.thread_id=? AND c.identity>? ORDER BY c.identity LIMIT 64",
                vec![thread.into(), after.into()],
            ))
            .await
            .map_err(storage)?;
        let done = rows.len() < 64;
        after = String::new();
        for row in rows {
            after = strict_text(&row, "identity")?;
            merge_text(&mut proof.bot, strict_text(&row, "card_bot")?)?;
            merge_text(&mut proof.chat, strict_text(&row, "card_chat")?)?;
            proof.source(&row)?;
        }
        if done {
            break;
        }
    }
    if let Some(creation) = proof.creation.clone() {
        check_creation_thread(db, &creation, thread).await?;
        let mut after = String::new();
        loop {
            let rows = db.query_all_raw(statement(
                "SELECT identity,bot_id,chat_id,project_id,creation_id,binding_revision FROM inbound_work
                 WHERE creation_id=? AND identity>? ORDER BY identity LIMIT 64",
                vec![creation.clone().into(), after.into()],
            )).await.map_err(storage)?;
            let done = rows.len() < 64;
            after = String::new();
            for row in rows {
                after = strict_text(&row, "identity")?;
                // An inbound in nine may have observed a later attention CAS. For a non-current
                // route, only the independently joined card/creation operation proves birth rev.
                if matches!(boundary, Boundary::Current) && !current_bound {
                    proof.source_identity(&row)?;
                } else {
                    proof.source(&row)?;
                }
            }
            if done {
                break;
            }
        }
    }
    Ok(proof)
}
