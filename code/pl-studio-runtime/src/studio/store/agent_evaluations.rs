//! Indexed, transactionally updated final-task evaluations in the existing product database.
use super::StudioStore;
use anyhow::{Result, ensure};
use pl_protocol::{
    AgentEvaluation, AgentEvaluationSummary, AgentEvaluationWrite, EvaluateAgentReceipt,
    EvaluateAgentRequest, LabeledEnum,
};
use sea_orm::{ConnectionTrait, DatabaseBackend, QueryResult, Statement, TransactionTrait};

const COLUMNS: &str = "agent_id,parent_agent_id,account_id,model_id,effort,profile_id,mode,preference,turn_id,revision,task_category,outcome,quality,instruction_following,comment,created_at,updated_at";

impl StudioStore {
    pub(crate) async fn read_agent_evaluation(
        &self,
        agent_id: &str,
    ) -> Result<Option<AgentEvaluation>> {
        read(&self.db, agent_id).await
    }

    /// Caller is the managed collaboration operation, holding the child admission permit until
    /// commit (or rollback) is known. Dropping a tool waiter never cancels this future.
    pub(crate) async fn write_agent_evaluation(
        &self,
        request: &EvaluateAgentRequest,
        mut candidate: AgentEvaluation,
    ) -> Result<EvaluateAgentReceipt> {
        request.validate()?;
        let tx = self.db.begin().await?;
        let staged: Result<EvaluateAgentReceipt> = async {
        let previous = read(&tx, &request.target).await?;
        let write = if let Some(previous) = previous {
            ensure!(previous.parent_agent_id == candidate.parent_agent_id && previous.model == candidate.model
                && previous.profile_id == candidate.profile_id && previous.mode == candidate.mode
                && previous.preference == candidate.preference, "evaluation frozen identity conflict");
            if previous.turn_id == request.expected_turn_id {
                ensure!(same_content(&previous, request), "evaluation content conflicts with the same final Turn");
                ensure!(request.expected_revision == previous.revision || request.expected_revision.checked_add(1) == Some(previous.revision),
                    "evaluation revision conflict: expected {}, actual {}", request.expected_revision, previous.revision);
                return Ok(receipt(previous, AgentEvaluationWrite::Unchanged));
            }
            ensure!(request.expected_revision == previous.revision,
                "evaluation revision conflict: expected {}, actual {}", request.expected_revision, previous.revision);
            candidate.revision = previous.revision.checked_add(1).ok_or_else(|| anyhow::anyhow!("evaluation revision overflow"))?;
            candidate.created_at = previous.created_at;
            AgentEvaluationWrite::Updated
        } else {
            ensure!(request.expected_revision == 0, "initial evaluation requires expectedRevision 0");
            candidate.revision = 1;
            AgentEvaluationWrite::Created
        };
        tx.execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            format!("INSERT INTO agent_evaluations ({COLUMNS}) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(agent_id) DO UPDATE SET turn_id=excluded.turn_id,revision=excluded.revision,
                task_category=excluded.task_category,outcome=excluded.outcome,quality=excluded.quality,
                instruction_following=excluded.instruction_following,comment=excluded.comment,updated_at=excluded.updated_at"),
            [candidate.agent_id.clone().into(), candidate.parent_agent_id.clone().into(),
                candidate.model.account_id.clone().into(), candidate.model.model_id.clone().into(), candidate.model.effort.clone().into(),
                candidate.profile_id.clone().into(), candidate.mode.label().into(), candidate.preference.label().into(),
                candidate.turn_id.clone().into(), i64::try_from(candidate.revision)?.into(), candidate.task_category.label().into(),
                candidate.outcome.label().into(), candidate.quality.map(i32::from).into(), candidate.instruction_following.map(i32::from).into(),
                candidate.comment.clone().into(), candidate.created_at.into(), candidate.updated_at.into()])).await?;
        Ok(receipt(candidate, write))
        }.await;
        match staged {
            Ok(receipt) => {
                tx.commit().await?;
                Ok(receipt)
            }
            Err(error) => {
                // Await rollback under the operation permit instead of relying on Drop cleanup.
                if let Err(rollback) = tx.rollback().await {
                    return Err(anyhow::anyhow!(
                        "evaluation failed ({error:#}); rollback failed ({rollback})"
                    ));
                }
                Err(error)
            }
        }
    }

    pub(crate) async fn recent_agent_evaluations(
        &self,
        account: &str,
        model: &str,
    ) -> Result<Vec<AgentEvaluation>> {
        let rows = self.db.query_all_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            format!("SELECT {COLUMNS} FROM agent_evaluations WHERE account_id=? AND model_id=? ORDER BY updated_at DESC,agent_id DESC LIMIT 10"),
            [account.into(), model.into()])).await?;
        rows.into_iter().map(decode).collect()
    }

    /// SQL reads only the bounded window's scalar values; list queries never load comments.
    pub(crate) async fn agent_evaluation_summary(
        &self,
        account: &str,
        model: &str,
    ) -> Result<AgentEvaluationSummary> {
        let row = self.db.query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "SELECT count(CASE WHEN outcome != 'notRated' THEN 1 END) AS rated,
                count(CASE WHEN outcome = 'passed' THEN 1 END) AS passed,
                count(CASE WHEN outcome = 'failed' THEN 1 END) AS failed,
                count(CASE WHEN outcome = 'notRated' THEN 1 END) AS not_rated,
                avg(quality) AS quality,avg(instruction_following) AS instruction_following
             FROM (SELECT outcome,quality,instruction_following FROM agent_evaluations WHERE account_id=? AND model_id=?
                ORDER BY updated_at DESC,agent_id DESC LIMIT 10)", [account.into(),model.into()])).await?
            .ok_or_else(|| anyhow::anyhow!("evaluation summary query returned no row"))?;
        Ok(AgentEvaluationSummary {
            window: 10,
            rated_samples: u32::try_from(row.try_get::<i64>("", "rated")?)?,
            passed: u32::try_from(row.try_get::<i64>("", "passed")?)?,
            failed: u32::try_from(row.try_get::<i64>("", "failed")?)?,
            not_rated: u32::try_from(row.try_get::<i64>("", "not_rated")?)?,
            average_quality: row
                .try_get::<Option<f64>>("", "quality")?
                .map(|value| value as f32),
            average_instruction_following: row
                .try_get::<Option<f64>>("", "instruction_following")?
                .map(|value| value as f32),
        })
    }
}

async fn read(db: &impl ConnectionTrait, id: &str) -> Result<Option<AgentEvaluation>> {
    db.query_one_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        format!("SELECT {COLUMNS} FROM agent_evaluations WHERE agent_id=?"),
        [id.into()],
    ))
    .await?
    .map(decode)
    .transpose()
}

fn decode(row: QueryResult) -> Result<AgentEvaluation> {
    let evaluation = AgentEvaluation {
        agent_id: row.try_get("", "agent_id")?,
        parent_agent_id: row.try_get("", "parent_agent_id")?,
        model: pl_protocol::studio::NewThreadModelRoute {
            account_id: row.try_get("", "account_id")?,
            model_id: row.try_get("", "model_id")?,
            effort: row.try_get("", "effort")?,
        },
        profile_id: row.try_get("", "profile_id")?,
        mode: pl_protocol::DelegationMode::from_label(&row.try_get::<String>("", "mode")?)?,
        preference: pl_protocol::DelegationPreference::from_label(
            &row.try_get::<String>("", "preference")?,
        )?,
        turn_id: row.try_get("", "turn_id")?,
        revision: u64::try_from(row.try_get::<i64>("", "revision")?)?,
        task_category: pl_protocol::AgentTaskCategory::from_label(
            &row.try_get::<String>("", "task_category")?,
        )?,
        outcome: pl_protocol::AgentEvaluationOutcome::from_label(
            &row.try_get::<String>("", "outcome")?,
        )?,
        quality: row
            .try_get::<Option<i32>>("", "quality")?
            .map(u8::try_from)
            .transpose()?,
        instruction_following: row
            .try_get::<Option<i32>>("", "instruction_following")?
            .map(u8::try_from)
            .transpose()?,
        comment: row.try_get("", "comment")?,
        created_at: row.try_get("", "created_at")?,
        updated_at: row.try_get("", "updated_at")?,
    };
    EvaluateAgentRequest {
        target: evaluation.agent_id.clone(),
        expected_turn_id: evaluation.turn_id.clone(),
        expected_revision: evaluation.revision,
        task_category: evaluation.task_category,
        outcome: evaluation.outcome,
        quality: evaluation.quality,
        instruction_following: evaluation.instruction_following,
        comment: evaluation.comment.clone(),
    }
    .validate()?;
    Ok(evaluation)
}

pub(crate) fn same_content(previous: &AgentEvaluation, request: &EvaluateAgentRequest) -> bool {
    previous.turn_id == request.expected_turn_id
        && previous.task_category == request.task_category
        && previous.outcome == request.outcome
        && previous.quality == request.quality
        && previous.instruction_following == request.instruction_following
        && previous.comment == request.comment
}

fn receipt(evaluation: AgentEvaluation, write: AgentEvaluationWrite) -> EvaluateAgentReceipt {
    EvaluateAgentReceipt {
        target: evaluation.agent_id.clone(),
        write,
        evaluation,
    }
}

/// Detail and its summary consume exactly the same bounded window, even during an update.
pub(crate) fn summarize_window(records: &[AgentEvaluation]) -> Result<AgentEvaluationSummary> {
    let mut summary = AgentEvaluationSummary::default();
    let mut quality = 0u32;
    let mut following = 0u32;
    for record in records.iter().take(10) {
        match record.outcome {
            pl_protocol::AgentEvaluationOutcome::Passed => summary.passed += 1,
            pl_protocol::AgentEvaluationOutcome::Failed => summary.failed += 1,
            pl_protocol::AgentEvaluationOutcome::NotRated => {
                summary.not_rated += 1;
                continue;
            }
        }
        summary.rated_samples += 1;
        quality += u32::from(
            record
                .quality
                .ok_or_else(|| anyhow::anyhow!("rated evaluation has no quality score"))?,
        );
        following += u32::from(record.instruction_following.ok_or_else(|| {
            anyhow::anyhow!("rated evaluation has no instruction-following score")
        })?);
    }
    if summary.rated_samples > 0 {
        summary.average_quality = Some(quality as f32 / summary.rated_samples as f32);
        summary.average_instruction_following =
            Some(following as f32 / summary.rated_samples as f32);
    }
    Ok(summary)
}
