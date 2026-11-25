use super::*;

#[derive(Debug, Clone)]
pub enum ThreadBindingClaim {
    Bound { thread_id: String },
    Creating { creation_id: String },
    NeedsAttention { diagnostic: String },
}

#[derive(Debug, Clone)]
pub struct BindingProjection {
    pub chat_id: String,
    pub workspace_id: String,
    /// 当前行记录的创建身份；缺失行为空串。用于证明部分现场是否属于本次请求。
    pub creation_id: String,
    pub thread_id: Option<String>,
    pub revision: u64,
    pub status: String,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BindingOperation {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub content_hash: String,
    pub expected_revision: u64,
    pub creation_id: String,
    pub thread_id: Option<String>,
}

impl BotStateStore {
    pub async fn owns_thread(&self, thread_id: &str) -> Result<bool, FeishuError> {
        let db = self.db().await?;
        db.query_one_raw(statement(
            "SELECT chat_id FROM thread_bindings WHERE thread_id=? OR (status='creating' AND creation_id=?) LIMIT 1",
            vec![thread_id.to_owned().into(), thread_id.to_owned().into()],
        ))
        .await
        .map(|row| row.is_some())
        .map_err(storage)
    }

    pub async fn claim_thread_binding(
        &self,
        chat_id: &str,
        creation_id: &str,
        workspace_id: &str,
    ) -> Result<ThreadBindingClaim, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = match tx
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?
        {
            Some(row) => row,
            None => {
            // 真正 NoRow：首次受理在此写入新行，随后才提交。
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)",
            vec![
                chat_id.to_string().into(),
                "".to_string().into(),
                "creating".to_string().into(),
                creation_id.to_string().into(),
                workspace_id.to_string().into(),
                1i64.into(),
                1i64.into(),
                "".to_string().into(),
                unix_seconds().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
            return Ok(ThreadBindingClaim::Creating {
            creation_id: creation_id.to_string(),
            });
            }
        };
        // 只读事务先提交：解码出的既有身份（可能来自更大的历史创建）与诊断不跨提交
        // 等待保留，随后只由调用方按真实长度计权。
        tx.commit().await.map_err(storage)?;
        // 路由与创建身份只接受持久值：解码失败不得默认成 bound/空创建。
        let stored_chat = stored_text(&row, "chat_id")?;
        let status = stored_text(&row, "status")?;
        let thread_id = stored_text(&row, "thread_id")?;
        let stored_creation = stored_text(&row, "creation_id")?;
        let stored_project = stored_text(&row, "workspace_id")?;
        let diagnostic = stored_text(&row, "diagnostic")?;
        // 水位同样严格解码：坏行不能继续被当成可用绑定。
        let _revision = strict_watermark(&row, "revision")?;
        let _generation = strict_watermark(&row, "generation")?;
        if stored_chat != chat_id {
            return Err(corrupt_binding());
        }
        // 合法 bound/creating 必须有可证明的创建身份与项目：空项目不是通配。
        // 迁移后的 needs_attention 行允许保留空的创建/项目，仍走它自己的诊断路径。
        let needs_proof = status == "bound" || status == "creating";
        if needs_proof
            && (stored_creation.is_empty()
                || stored_project.is_empty()
                || stored_project != workspace_id)
        {
            return Err(binding_needs_recovery());
        }
        // 合法状态只有 bound/creating/needs_attention；旧 pending/absent 已由迁移
        // 规范为 attention，运行时不再兼容，也不默认成任一可用状态。
        match status.as_str() {
            "bound" if !thread_id.is_empty() && thread_id != "pending" => {
                Ok(ThreadBindingClaim::Bound { thread_id })
            }
            // bound 缺少可用 Thread 身份：不可证明归属，保留现场要求本机恢复。
            "bound" => Err(binding_needs_recovery()),
            // creating 的创建身份已由上面的 needs_proof 判定非空。
            "creating" => Ok(ThreadBindingClaim::Creating {
                creation_id: stored_creation,
            }),
            "needs_attention" => Ok(ThreadBindingClaim::NeedsAttention {
                diagnostic: if diagnostic.is_empty() {
                    "conversation Thread binding needs local recovery".to_string()
                } else {
                    diagnostic
                },
            }),
            _ => Err(binding_state_unreadable()),
        }
    }

    pub async fn bind_thread(
        &self,
        chat_id: &str,
        thread_id: &str,
        creation_id: &str,
        workspace_id: &str,
    ) -> Result<String, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT thread_id, status, creation_id, workspace_id, revision, generation FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let (revision, generation) = if let Some(row) = existing {
            // 路由、创建身份与项目归属只接受持久值：解码失败不得默认成 bound 或空创建。
            let status = stored_text(&row, "status")?;
            let bound = stored_text(&row, "thread_id")?;
            let stored_creation = stored_text(&row, "creation_id")?;
            let stored_project = stored_text(&row, "workspace_id")?;
            // 水位只接受无损解码：缺列或损坏不得回退到 1 覆盖既有水位。
            let revision = strict_watermark(&row, "revision")?;
            let generation = strict_watermark(&row, "generation")?;
            if status != "bound" && status != "creating" {
                // 未知状态不得被本次绑定的 UPSERT 覆盖成 bound。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            if status == "bound" && !bound.is_empty() && bound != thread_id && bound != "pending" {
                tx.commit().await.map_err(storage)?;
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "chat is already bound to another Thread",
                    false,
                    None,
                ));
            }
            if stored_creation.is_empty() {
                // 既有行没有创建身份：无法证明属于本次创建，拒绝覆盖。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            if stored_creation != creation_id {
                tx.commit().await.map_err(storage)?;
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "chat Thread creation identity conflict",
                    false,
                    None,
                ));
            }
            if stored_project.is_empty() || stored_project != workspace_id {
                // 项目归属未知或不一致：不覆盖成当前项目，也不把 Thread 迁到另一项目。
                tx.commit().await.map_err(storage)?;
                return Err(binding_needs_recovery());
            }
            (revision, generation)
        } else {
            (1u64, 1u64)
        };
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id=excluded.thread_id,
               status='bound',
               creation_id=excluded.creation_id,
               workspace_id=excluded.workspace_id,
               diagnostic='',
               updated_at=excluded.updated_at",
            vec![
                chat_id.to_string().into(),
                thread_id.to_string().into(),
                "bound".to_string().into(),
                creation_id.to_string().into(),
                workspace_id.to_string().into(),
                i64::try_from(revision)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                i64::try_from(generation)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                "".to_string().into(),
                unix_seconds().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(thread_id.to_string())
    }

    pub async fn mark_binding_attention(
        &self,
        chat_id: &str,
        diagnostic: &str,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "UPDATE thread_bindings SET status='needs_attention', diagnostic=?, updated_at=? WHERE chat_id=?",
            vec![
                diagnostic.to_string().into(),
                unix_seconds().into(),
                chat_id.to_string().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }

    pub async fn binding_for_chat(
        &self,
        chat_id: &str,
        bot_id: &str,
        workspace_id: &str,
    ) -> Result<BindingProjection, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT chat_id, thread_id, status, revision, generation, workspace_id, creation_id, diagnostic FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let projection = match row {
            Some(row) => {
                // 只接受与查询键一致的持久行；状态分类先于归属判定，
                // 迁移保留的 needs_attention 缺创建/项目是合法事实，不用当前请求补齐。
                let stored_chat: String = stored_text(&row, "chat_id")?;
                if stored_chat != chat_id {
                    return Err(corrupt_binding());
                }
                let stored_status: String = stored_text(&row, "status")?;
                let stored_project: String = stored_text(&row, "workspace_id")?;
                let stored_creation: String = stored_text(&row, "creation_id")?;
                let thread_id = empty_to_none(stored_text(&row, "thread_id")?)
                    .filter(|value| value != "pending");
                let revision = strict_watermark(&row, "revision")?;
                // 已选水位两列都严格解码，不静默忽略 generation。
                let _generation = strict_watermark(&row, "generation")?;
                match stored_status.as_str() {
                    // bound 必须带真实 Thread 身份：缺失或旧 pending sentinel 都不是可路由绑定。
                    "bound" if thread_id.is_none() => return Err(binding_needs_recovery()),
                    // 合法绑定/创建必须有可证明的创建身份与同项目归属（空项目不是通配）。
                    "bound" | "creating" => {
                        if stored_creation.is_empty()
                            || stored_project.is_empty()
                            || stored_project != workspace_id
                        {
                            return Err(binding_needs_recovery());
                        }
                    }
                    // 合法 attention 允许缺创建/项目与诊断，原样保留既有事实。
                    "needs_attention" => {}
                    _ => {
                        // 旧 pending/absent 已由迁移规范为 attention；未知状态同样
                        // 不得默认成 NeedsAttention 或任何可用绑定。
                        return Err(binding_state_unreadable());
                    }
                }
                BindingProjection {
                    chat_id: stored_chat,
                    workspace_id: stored_project,
                    // 创建身份与绑定水位是归属判据：损坏必须显式失败，不能默认化。
                    creation_id: stored_creation,
                    thread_id,
                    revision,
                    status: stored_status,
                    diagnostic: empty_to_none(stored_text(&row, "diagnostic")?),
                }
            }
            None => BindingProjection {
                chat_id: chat_id.to_string(),
                workspace_id: workspace_id.to_string(),
                creation_id: String::new(),
                thread_id: None,
                revision: 0,
                status: "absent".to_string(),
                diagnostic: None,
            },
        };
        let _ = bot_id;
        Ok(projection)
    }

    /// 首次绑定操作的原子起点：绑定水位切换与该操作的持久记录在同一次提交中生效。
    ///
    /// 调用方已用 [`Self::load_binding_operation`] 与 [`Self::binding_for_chat`] 判定这是首次受理；
    /// 本方法仍在事务内重做 CAS 判定，避免两次读取之间的并发切换被覆盖。
    pub async fn begin_binding_operation(
        &self,
        chat_id: &str,
        expected_revision: u64,
        workspace_id: &str,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT revision, generation FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let (current_revision, current_generation) = match &existing {
            Some(row) => (
                strict_watermark(row, "revision")?,
                strict_watermark(row, "generation")?,
            ),
            None => (0, 0),
        };
        if current_revision != expected_revision {
            tx.commit().await.map_err(storage)?;
            return Err(stale_binding_revision());
        }
        let next_revision = current_revision
            .checked_add(1)
            .ok_or_else(corrupt_binding)?;
        let next_generation = current_generation
            .checked_add(1)
            .ok_or_else(corrupt_binding)?;
        tx.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, workspace_id, revision, generation, diagnostic, created_at, updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?)
             ON CONFLICT(chat_id) DO UPDATE SET
               thread_id='',
               status='creating',
               creation_id=excluded.creation_id,
               workspace_id=excluded.workspace_id,
               revision=excluded.revision,
               generation=excluded.generation,
               diagnostic='',
               updated_at=excluded.updated_at",
            vec![
                chat_id.to_string().into(),
                "".to_string().into(),
                "creating".to_string().into(),
                operation.creation_id.clone().into(),
                workspace_id.to_string().into(),
                i64::try_from(next_revision)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                i64::try_from(next_generation)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                "".to_string().into(),
                unix_seconds().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        if !insert_binding_operation(&tx, operation).await? {
            // 同一 operationId 已存在不同记录：保留原记录，不覆盖他人操作。
            return Err(binding_needs_recovery());
        }
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    /// 补齐可证明归属的部分现场：只有创建身份、项目与恰好下一绑定 revision 都匹配时，
    /// 才写入缺失的操作记录；不再次切换绑定水位，也不覆盖其他创建。
    pub async fn adopt_binding_operation(
        &self,
        chat_id: &str,
        expected_revision: u64,
        workspace_id: &str,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let row = tx
            .query_one_raw(statement(
                "SELECT status, thread_id, creation_id, workspace_id, revision FROM thread_bindings WHERE chat_id=?",
                vec![chat_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            tx.commit().await.map_err(storage)?;
            return Err(binding_needs_recovery());
        };
        let status = stored_text(&row, "status")?;
        let thread_id = stored_text(&row, "thread_id")?;
        let creation_id = stored_text(&row, "creation_id")?;
        let stored_project = stored_text(&row, "workspace_id")?;
        let revision = strict_watermark(&row, "revision")?;
        let claimed = status == "creating"
            && thread_id.is_empty()
            && creation_id == operation.creation_id
            && stored_project == workspace_id
            && revision
                == expected_revision
                    .checked_add(1)
                    .ok_or_else(corrupt_binding)?;
        if !claimed {
            tx.commit().await.map_err(storage)?;
            return Err(binding_needs_recovery());
        }
        if !insert_binding_operation(&tx, operation).await? {
            tx.commit().await.map_err(storage)?;
            return Err(binding_needs_recovery());
        }
        tx.commit().await.map_err(storage)?;
        Ok(())
    }

    pub async fn load_binding_operation(
        &self,
        operation_id: &str,
    ) -> Result<Option<BindingOperation>, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id
                 FROM binding_operations WHERE operation_id=?",
                vec![operation_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        row.map(|row| {
            // 操作身份与冻结 revision 是接续判据：损坏必须显式失败，不能默认化。
            let stored_operation: String = stored_text(&row, "operation_id")?;
            if stored_operation != operation_id {
                return Err(corrupt_binding());
            }
            Ok(BindingOperation {
                operation_id: stored_operation,
                bot_id: stored_text(&row, "bot_id")?,
                chat_id: stored_text(&row, "chat_id")?,
                content_hash: stored_text(&row, "content_hash")?,
                expected_revision: strict_watermark(&row, "expected_revision")?,
                creation_id: stored_text(&row, "creation_id")?,
                thread_id: empty_to_none(stored_text(&row, "thread_id")?),
            })
        })
        .transpose()
    }

    pub async fn save_binding_operation(
        &self,
        operation: &BindingOperation,
    ) -> Result<(), FeishuError> {
        let db = self.db().await?;
        db.execute_raw(statement(
            "INSERT INTO binding_operations(operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id, updated_at)
             VALUES(?,?,?,?,?,?,?,?)
             ON CONFLICT(operation_id) DO UPDATE SET
               thread_id=excluded.thread_id,
               updated_at=excluded.updated_at",
            vec![
                operation.operation_id.clone().into(),
                operation.bot_id.clone().into(),
                operation.chat_id.clone().into(),
                operation.content_hash.clone().into(),
                i64::try_from(operation.expected_revision)
                    .map_err(|_| corrupt_binding())?
                    .into(),
                operation.creation_id.clone().into(),
                operation.thread_id.clone().unwrap_or_default().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        Ok(())
    }
}

pub(super) fn strict_watermark(row: &QueryResult, column: &str) -> Result<u64, FeishuError> {
    let raw = stored_i64(row, column)?;
    u64::try_from(raw).map_err(|_| corrupt_binding())
}

/// 持久字段解码失败：坏类型/坏行是不可恢复的本地事实，不能当作临时 IO 重试。
/// 只用于已取回行的字段解码；查询/执行/提交本身的失败仍按 `storage` 分类为可重试。
fn corrupt_binding() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot conversation binding record is unreadable",
        false,
        None,
    )
}

fn stale_binding_revision() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "stale conversation Thread binding revision",
        true,
        None,
    )
}

/// 无法证明归属的既有绑定记录：保留现场，明确报告需本机恢复，不冒充正常进行中。
pub(crate) fn binding_needs_recovery() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "conversation Thread binding needs local recovery: reuse the operation that created it",
        false,
        None,
    )
}

/// 已完成操作的原绑定已被后继显式本地操作替代：固定安全错误。
///
/// 不返回后继操作的结果、不切回旧绑定、不新建，也不靠联网预检改写归属。
pub(crate) fn binding_superseded() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "the conversation Thread binding created by this operation was superseded by a later local operation",
        false,
        None,
    )
}

/// 已受理身份缺少可解码的持久工作行：不从当前请求或配置回填，明确需本机恢复。
/// 绑定状态不是已知集合：不能默认投影成 needs_attention。
fn binding_state_unreadable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "conversation Thread binding state is unreadable; local recovery required",
        false,
        None,
    )
}

/// 在给定连接/事务内写入操作记录；返回是否真正插入（否则已有同 operationId 记录）。
async fn insert_binding_operation<C: ConnectionTrait>(
    db: &C,
    operation: &BindingOperation,
) -> Result<bool, FeishuError> {
    let expected_revision =
        i64::try_from(operation.expected_revision).map_err(|_| corrupt_binding())?;
    let inserted = db
        .execute_raw(statement(
            "INSERT OR IGNORE INTO binding_operations(operation_id, bot_id, chat_id, content_hash, expected_revision, creation_id, thread_id, updated_at)
             VALUES(?,?,?,?,?,?,?,?)",
            vec![
                operation.operation_id.clone().into(),
                operation.bot_id.clone().into(),
                operation.chat_id.clone().into(),
                operation.content_hash.clone().into(),
                expected_revision.into(),
                operation.creation_id.clone().into(),
                operation.thread_id.clone().unwrap_or_default().into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
    Ok(inserted.rows_affected() == 1)
}
