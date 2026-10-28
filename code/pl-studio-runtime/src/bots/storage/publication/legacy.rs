//! 旧有限资格的迁移核验与当前不可变来源校验。当前 route 只在新写围栏检查。

use super::super::card::CardBinding;
use super::super::target::TargetKind;
use super::super::{audience, inbound_identity, statement, stored_i64, strict_text};
use super::*;
use sea_orm::ConnectionTrait;

pub(super) fn resumable_status(status: &str) -> bool {
    matches!(status, "pending" | "claimed" | "failed")
}

/// 新的本地/网络意图只能修改原单卡实体，不能把续接 Turn 借作新实体身份。
pub(super) fn entity_matches(scope: &DeliveryScope, entity: &DeliveryEntityKey) -> bool {
    let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
        return false;
    };
    let Some(source) = &legacy.source else {
        return false;
    };
    let binding = CardBinding {
        bot_id: scope.bot_id.clone(),
        chat_id: scope.chat_id.clone(),
        message_id: source.message_id.clone(),
        thread_id: scope.thread_id.clone(),
        original_input: legacy.original_input_id.clone(),
    };
    matches!(entity, DeliveryEntityKey::LegacyFinal { entity_id } if *entity_id == binding.reply_operation())
}

pub(super) struct LegacyFacts {
    pub thread_id: String,
    pub app_id: String,
    pub project_id: String,
    pub creation_id: String,
    pub binding_revision: u64,
    pub origin: LegacyFinalOrigin,
}

/// 不造墙钟、线程或轮次；即使当前绑定已替换也仍能按原 origin 核对已有卡片。
pub(super) async fn facts<C: ConnectionTrait>(
    db: &C,
    identity: &str,
    binding: &CardBinding,
    watch_input: &str,
    turn_id: Option<&str>,
) -> Result<LegacyFacts, FeishuError> {
    let mut facts = LegacyFacts {
        thread_id: binding.thread_id.clone(),
        app_id: String::new(),
        project_id: String::new(),
        creation_id: String::new(),
        binding_revision: 0,
        origin: LegacyFinalOrigin {
            inbound_identity: identity.to_string(),
            original_input_id: super::migrate::original_input_id(identity),
            watch_input: watch_input.to_string(),
            original_turn_id: turn_id.map(str::to_string),
            source: None,
            target: TargetProof::Unproven,
            admission: None,
            resumable: false,
            needs_recovery: None,
        },
    };
    let failure = populate(db, binding, &mut facts).await?;
    facts.origin.needs_recovery = failure;
    Ok(facts)
}

async fn populate<C: ConnectionTrait>(
    db: &C,
    binding: &CardBinding,
    facts: &mut LegacyFacts,
) -> Result<Option<String>, FeishuError> {
    let identity = facts.origin.inbound_identity.clone();
    let work = db
        .query_one_raw(statement(
            "SELECT * FROM inbound_work WHERE identity=?",
            vec![identity.clone().into()],
        ))
        .await
        .map_err(super::store::storage)?;
    let admitted = db
        .query_one_raw(statement(
            "SELECT * FROM inbound_identities WHERE identity=?",
            vec![identity.clone().into()],
        ))
        .await
        .map_err(super::store::storage)?;
    let Some(work) = work else {
        return Ok(Some("legacy reply has no original work".into()));
    };
    // 即使受理资格缺失，已知的 Thread/输入归属仍用于互斥，不把旧链误当成新 GUI 输入。
    facts.app_id = strict_text(&work, "app_id")?;
    facts.project_id = strict_text(&work, "project_id")?;
    facts.creation_id = strict_text(&work, "creation_id")?;
    facts.binding_revision =
        u64::try_from(stored_i64(&work, "binding_revision")?).map_err(|_| unreadable())?;
    if facts.thread_id.is_empty() {
        let origins = db.query_all_raw(statement("SELECT thread_id FROM bot_audience_origins WHERE chat_id=? AND project_id=? AND creation_id=? AND binding_revision=? LIMIT 2", vec![binding.chat_id.clone().into(), facts.project_id.clone().into(), facts.creation_id.clone().into(), i64::try_from(facts.binding_revision).map_err(|_| unreadable())?.into()])).await.map_err(super::store::storage)?;
        if origins.len() != 1 {
            return Ok(Some(
                "legacy input has no unique original Thread origin".into(),
            ));
        }
        facts.thread_id = strict_text(&origins[0], "thread_id")?;
    }
    let Some(origin) = audience::read_origin(db, &facts.thread_id).await? else {
        return Ok(Some("legacy reply has no creation origin".into()));
    };
    facts.origin.target = origin.target.clone();
    let Some(admitted) = admitted else {
        return Ok(Some("legacy reply has no admitted identity".into()));
    };
    let hash = strict_text(&work, "content_hash")?;
    let admitted_at = stored_i64(&admitted, "admitted_at")?;
    for (column, expected) in [
        ("identity", identity.as_str()),
        ("bot_id", binding.bot_id.as_str()),
        ("chat_id", binding.chat_id.as_str()),
        ("message_id", binding.message_id.as_str()),
        ("content_hash", hash.as_str()),
    ] {
        if strict_text(&work, column)? != expected || strict_text(&admitted, column)? != expected {
            return Ok(Some("legacy reply identity/work/hash disagree".into()));
        }
    }
    if hash.is_empty()
        || admitted_at <= 0
        || inbound_identity(&binding.bot_id, &binding.chat_id, &binding.message_id) != identity
    {
        return Ok(Some(
            "legacy reply has no immutable admission time/hash".into(),
        ));
    }
    let status = strict_text(&work, "status")?;
    facts.origin.admission = Some(LegacyAdmission {
        content_hash: hash,
        admitted_at,
        status: status.clone(),
    });
    let stored_watch = strict_text(&work, "watch_input")?;
    let stored_watch = if stored_watch.is_empty() {
        facts.origin.original_input_id.as_str()
    } else {
        stored_watch.as_str()
    };
    if stored_watch != facts.origin.watch_input {
        return Ok(Some(
            "legacy watch input conflicts with the admitted work".into(),
        ));
    }
    if facts.app_id.is_empty()
        || facts.project_id.is_empty()
        || facts.creation_id.is_empty()
        || facts.binding_revision == 0
        || origin.chat_id != binding.chat_id
        || origin.project_id != facts.project_id
        || origin.creation_id != facts.creation_id
        || origin.binding_revision != facts.binding_revision
        || binding.original_input != facts.origin.original_input_id
        || facts.origin.watch_input.is_empty()
        || facts
            .origin
            .original_turn_id
            .as_deref()
            .is_some_and(str::is_empty)
    {
        return Ok(Some(
            "legacy origin or input association is incomplete/conflicting".into(),
        ));
    }
    let source = SendSource {
        bot_id: binding.bot_id.clone(),
        chat_id: binding.chat_id.clone(),
        app_id: facts.app_id.clone(),
        project_id: facts.project_id.clone(),
        thread_id: facts.thread_id.clone(),
        input_id: facts.origin.original_input_id.clone(),
        original_input_id: facts.origin.original_input_id.clone(),
        message_id: binding.message_id.clone(),
        open_id: strict_text(&work, "open_id")?,
        chat_kind: strict_text(&work, "chat_kind")?,
        creation_id: facts.creation_id.clone(),
        binding_revision: facts.binding_revision,
    };
    if !target_matches(&facts.origin.target, &source)? {
        return Ok(Some(
            "legacy creation target is unproven/conflicting".into(),
        ));
    }
    facts.origin.source = Some(source);
    if !resumable_status(&status) && status != "completed" {
        return Ok(Some(
            "legacy work status does not authorize continuation".into(),
        ));
    }
    facts.origin.resumable = resumable_status(&status);
    Ok(None)
}

fn target_matches(target: &TargetProof, source: &SendSource) -> Result<bool, FeishuError> {
    target.validate()?;
    let kind = match target {
        TargetProof::Unproven => return Ok(false),
        TargetProof::Legacy { target } => target,
        TargetProof::Created { evidence } => {
            if evidence.bot_id != source.bot_id
                || evidence.app_id != source.app_id
                || evidence.project_id != source.project_id
                || evidence.chat_id != source.chat_id
                || evidence.creation_id != source.creation_id
                || evidence.binding_revision != source.binding_revision
            {
                return Ok(false);
            }
            &evidence.target
        }
    };
    Ok(match kind {
        TargetKind::Group => source.chat_kind == "group",
        TargetKind::Direct { open_id } => {
            source.chat_kind == "direct" && open_id == &source.open_id
        }
    })
}

/// 当前格式只核原不可变资格。route 的合法关闭/替换不使整库打不开。
pub(super) async fn validate<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScope,
) -> Result<(), FeishuError> {
    let DeliveryScopeOrigin::LegacyFinal { legacy } = &scope.origin else {
        return Err(unreadable());
    };
    if legacy.inbound_identity
        != match &scope.key {
            DeliveryScopeKey::LegacyFinal { inbound_identity } => inbound_identity,
            _ => return Err(unreadable()),
        }
        .as_str()
        || scope.needs_recovery != legacy.needs_recovery.is_some()
    {
        return Err(unreadable());
    }
    if scope.needs_recovery {
        return Ok(());
    }
    let source = legacy.source.as_ref().ok_or_else(unreadable)?;
    let admission = legacy.admission.as_ref().ok_or_else(unreadable)?;
    if source.bot_id != scope.bot_id
        || source.chat_id != scope.chat_id
        || source.thread_id != scope.thread_id
        || source.app_id != scope.app_id
        || source.project_id != scope.project_id
        || source.creation_id != scope.creation_id
        || source.binding_revision != scope.binding_revision
        || source.original_input_id != legacy.original_input_id
        || source.input_id != legacy.original_input_id
        || legacy.original_input_id != super::migrate::original_input_id(&legacy.inbound_identity)
        || legacy.resumable != resumable_status(&admission.status)
        || (!legacy.resumable && admission.status != "completed")
        || !target_matches(&legacy.target, source)?
    {
        return Err(unreadable());
    }
    let admitted = db
        .query_one_raw(statement(
            "SELECT * FROM inbound_identities WHERE identity=?",
            vec![legacy.inbound_identity.clone().into()],
        ))
        .await
        .map_err(super::store::storage)?
        .ok_or_else(unreadable)?;
    for (column, expected) in [
        ("bot_id", source.bot_id.as_str()),
        ("chat_id", source.chat_id.as_str()),
        ("message_id", source.message_id.as_str()),
        ("content_hash", admission.content_hash.as_str()),
    ] {
        if strict_text(&admitted, column)? != expected {
            return Err(unreadable());
        }
    }
    let origin = audience::read_origin(db, &scope.thread_id)
        .await?
        .ok_or_else(unreadable)?;
    if stored_i64(&admitted, "admitted_at")? != admission.admitted_at
        || admission.admitted_at <= 0
        || origin.chat_id != scope.chat_id
        || origin.project_id != scope.project_id
        || origin.creation_id != scope.creation_id
        || origin.binding_revision != scope.binding_revision
        || origin.target != legacy.target
        || inbound_identity(&source.bot_id, &source.chat_id, &source.message_id)
            != legacy.inbound_identity
    {
        return Err(unreadable());
    }
    // work 是当前交接状态，不是冻结资格的生命周期。缺失会封闭新准入，但不抹去
    // 已有 identity/origin/有限资格或平台结果；状态变化也不把只读打开变成迁移失败。
    let work = db
        .query_one_raw(statement(
            "SELECT * FROM inbound_work WHERE identity=?",
            vec![legacy.inbound_identity.clone().into()],
        ))
        .await
        .map_err(super::store::storage)?;
    if let Some(work) = work {
        for (column, expected) in [
            ("bot_id", source.bot_id.as_str()),
            ("chat_id", source.chat_id.as_str()),
            ("message_id", source.message_id.as_str()),
            ("content_hash", admission.content_hash.as_str()),
            ("app_id", source.app_id.as_str()),
            ("project_id", source.project_id.as_str()),
            ("creation_id", source.creation_id.as_str()),
            ("open_id", source.open_id.as_str()),
            ("chat_kind", source.chat_kind.as_str()),
        ] {
            if strict_text(&work, column)? != expected {
                return Err(unreadable());
            }
        }
        let watch = strict_text(&work, "watch_input")?;
        let watch = if watch.is_empty() {
            source.original_input_id.as_str()
        } else {
            watch.as_str()
        };
        if watch != legacy.watch_input
            || u64::try_from(stored_i64(&work, "binding_revision")?).map_err(|_| unreadable())?
                != source.binding_revision
        {
            return Err(unreadable());
        }
    }
    Ok(())
}

/// 仅新认领/副作用调用。迁移时已拥有的有限义务不重新依附于入站未完成状态：
/// 当前 completed 是可靠 handoff，仍可投递；needs_attention/未知/缺失则只封新写。
pub(super) async fn write_gap<C: ConnectionTrait>(
    db: &C,
    legacy: &LegacyFinalOrigin,
) -> Result<Option<String>, FeishuError> {
    if !legacy.resumable {
        return Ok(Some(
            "legacy reply has no unfinished continuation obligation".into(),
        ));
    }
    let work = db
        .query_one_raw(statement(
            "SELECT status FROM inbound_work WHERE identity=?",
            vec![legacy.inbound_identity.clone().into()],
        ))
        .await
        .map_err(super::store::storage)?;
    let admitted = work
        .as_ref()
        .and_then(|row| strict_text(row, "status").ok())
        .is_some_and(|status| {
            matches!(
                status.as_str(),
                "pending" | "claimed" | "failed" | "completed"
            )
        });
    Ok((!admitted).then(|| "current legacy work does not permit new delivery writes".into()))
}
