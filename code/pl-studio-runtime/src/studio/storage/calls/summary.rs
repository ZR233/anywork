//! root/thread/purpose 维度的累计费用摘要。
//!
//! 摘要是 revision 绝对投影：可靠 writer 通过 [`super::CallsStore::replace_session_usage`] 提交某个
//! root/thread 的完整累计值，只有当 revision 更大时才整体替换既有行。摘要与正文/日志解耦，因此
//! 日志过期、截断或清理都不会丢失累计费用；幂等更新也不依赖任何将被删除的正文。

use super::*;

/// 单个 root/thread 的绝对累计投影。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct SessionUsageProjection {
    pub(crate) root_thread_id: String,
    pub(crate) thread_id: String,
    /// 单调投影 revision；更小的投影被忽略，相同的投影幂等替换。
    pub(crate) revision: u64,
    pub(crate) has_unpriced_usage: bool,
    pub(crate) purpose_costs: Vec<PurposeUsageProjection>,
}

/// 单个 purpose 的绝对累计投影。
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PurposeUsageProjection {
    pub(crate) purpose: Option<String>,
    pub(crate) estimated_costs: Vec<RuntimeCostAmount>,
}

/// 无费用仅标记未定价用量的行的占位币种；真实币种不会为空。
const UNPRICED_CURRENCY: &str = "";

/// 用 revision 绝对投影替换某个 root/thread 的累计摘要。
pub(super) async fn replace(
    db: &impl ConnectionTrait,
    projection: &SessionUsageProjection,
    content_hash: &str,
    #[cfg(feature = "benchmarks")] observation: Option<&observation::Observation>,
) -> Result<bool> {
    let revision = integer(projection.revision)?;
    let tx = db;
    #[cfg(feature = "benchmarks")]
    if let Some(observation) = observation {
        observation.increment(observation::Metric::SummaryRevisionSql);
    }
    let identity = tx.query_one_raw(statement(
        "SELECT revision,content_hash,root_thread_id FROM call_usage_summary WHERE thread_id=? ORDER BY revision DESC LIMIT 1",
        vec![projection.thread_id.clone().into()],
    )).await?;
    let known_hash = identity
        .as_ref()
        .map(|row| row.try_get::<Option<String>>("", "content_hash"))
        .transpose()?
        .flatten();
    if let Some(row) = identity.as_ref().filter(|_| known_hash.is_some()) {
        let current: i64 = row.try_get("", "revision")?;
        if revision == current {
            ensure!(
                row.try_get::<String>("", "content_hash")? == content_hash
                    && row.try_get::<String>("", "root_thread_id")? == projection.root_thread_id,
                "conflicting call summary revision"
            );
        }
        if revision <= current {
            #[cfg(feature = "benchmarks")]
            if let Some(observation) = observation {
                observation.increment(observation::Metric::SummarySkipped);
            }
            return Ok(false);
        }
    } else if identity.is_some() {
        #[cfg(feature = "benchmarks")]
        if let Some(observation) = observation {
            observation.increment(observation::Metric::SummaryRevisionSql);
        }
        // schema7 retained the absolute rows but not a hash. Compare those real facts at
        // this one migration boundary; do not silently accept a conflicting equal revision.
        let rows = tx
            .query_all_raw(statement(
                "SELECT * FROM call_usage_summary WHERE thread_id=?",
                vec![projection.thread_id.clone().into()],
            ))
            .await?;
        let current = rows
            .iter()
            .map(|row| row.try_get::<i64>("", "revision"))
            .collect::<std::result::Result<Vec<_>, _>>()?
            .into_iter()
            .max();
        if let Some(current) = current
            && revision <= current
        {
            if revision == current {
                let mut stored = std::collections::BTreeMap::new();
                for row in rows {
                    ensure!(
                        row.try_get::<String>("", "root_thread_id")? == projection.root_thread_id
                            && row.try_get::<i64>("", "has_unpriced_usage")?
                                == i64::from(projection.has_unpriced_usage),
                        "conflicting call summary revision"
                    );
                    stored.insert(
                        (
                            row.try_get::<String>("", "purpose")?,
                            row.try_get::<String>("", "cost_currency")?,
                        ),
                        row.try_get::<f64>("", "amount")?,
                    );
                }
                let mut expected = std::collections::BTreeMap::new();
                if projection.purpose_costs.is_empty() {
                    expected.insert((String::new(), String::new()), 0.0);
                }
                for purpose in &projection.purpose_costs {
                    let key = purpose.purpose.clone().unwrap_or_default();
                    if purpose.estimated_costs.is_empty() {
                        expected.insert((key, String::new()), 0.0);
                    } else {
                        for cost in &purpose.estimated_costs {
                            expected.insert((key.clone(), cost.currency.clone()), cost.amount);
                        }
                    }
                }
                ensure!(stored == expected, "conflicting call summary revision");
            }
            #[cfg(feature = "benchmarks")]
            if let Some(observation) = observation {
                observation.increment(observation::Metric::SummarySkipped);
            }
            return Ok(false);
        }
    }
    #[cfg(feature = "benchmarks")]
    if let Some(observation) = observation {
        observation.increment(observation::Metric::SummaryWriteSql);
    }
    tx.execute_raw(statement(
        "DELETE FROM call_usage_summary WHERE thread_id=?",
        vec![projection.thread_id.clone().into()],
    ))
    .await?;
    if projection.purpose_costs.is_empty() {
        #[cfg(feature = "benchmarks")]
        if let Some(observation) = observation {
            observation.increment(observation::Metric::SummaryWriteSql);
        }
        insert_row(
            tx,
            projection,
            "",
            UNPRICED_CURRENCY,
            0.0,
            revision,
            content_hash,
        )
        .await?;
    }
    for purpose in &projection.purpose_costs {
        let purpose_key = purpose.purpose.clone().unwrap_or_default();
        if purpose.estimated_costs.is_empty() {
            #[cfg(feature = "benchmarks")]
            if let Some(observation) = observation {
                observation.increment(observation::Metric::SummaryWriteSql);
            }
            insert_row(
                tx,
                projection,
                &purpose_key,
                UNPRICED_CURRENCY,
                0.0,
                revision,
                content_hash,
            )
            .await?;
            continue;
        }
        for cost in &purpose.estimated_costs {
            #[cfg(feature = "benchmarks")]
            if let Some(observation) = observation {
                observation.increment(observation::Metric::SummaryWriteSql);
            }
            insert_row(
                tx,
                projection,
                &purpose_key,
                &cost.currency,
                cost.amount,
                revision,
                content_hash,
            )
            .await?;
        }
    }
    #[cfg(feature = "benchmarks")]
    if let Some(observation) = observation {
        observation.increment(observation::Metric::SummaryReplaced);
    }
    Ok(true)
}

async fn insert_row(
    db: &impl ConnectionTrait,
    projection: &SessionUsageProjection,
    purpose: &str,
    currency: &str,
    amount: f64,
    revision: i64,
    content_hash: &str,
) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO call_usage_summary(
            root_thread_id,thread_id,purpose,cost_currency,amount,has_unpriced_usage,revision,content_hash)
         VALUES(?,?,?,?,?,?,?,?)
         ON CONFLICT(root_thread_id,thread_id,purpose,cost_currency) DO UPDATE SET
            amount=excluded.amount,
            has_unpriced_usage=excluded.has_unpriced_usage,
            revision=excluded.revision,content_hash=excluded.content_hash",
        vec![
            projection.root_thread_id.clone().into(),
            projection.thread_id.clone().into(),
            purpose.to_owned().into(),
            currency.to_owned().into(),
            amount.into(),
            (projection.has_unpriced_usage as i32).into(),
            revision.into(),
            content_hash.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// 迁移时先把旧 `model_calls` 的累计费用保全为摘要（revision 0，供可靠 writer 后续覆盖）。
pub(super) async fn migrate_from_legacy(db: &impl ConnectionTrait) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO call_usage_summary(
            root_thread_id,thread_id,purpose,cost_currency,amount,has_unpriced_usage,revision)
         SELECT root_thread_id,thread_id,COALESCE(purpose,''),cost_currency,
                SUM(cost_amount),MAX(has_unpriced_usage),0
         FROM model_calls
         WHERE terminal=1 AND root_thread_id IS NOT NULL
           AND cost_currency IS NOT NULL AND cost_amount IS NOT NULL
         GROUP BY root_thread_id,thread_id,COALESCE(purpose,''),cost_currency
         ON CONFLICT(root_thread_id,thread_id,purpose,cost_currency) DO UPDATE SET
            amount=excluded.amount,
            has_unpriced_usage=MAX(call_usage_summary.has_unpriced_usage,excluded.has_unpriced_usage)",
        vec![],
    ))
    .await?;
    db.execute_raw(statement(
        "INSERT INTO call_usage_summary(
            root_thread_id,thread_id,purpose,cost_currency,amount,has_unpriced_usage,revision)
         SELECT root_thread_id,thread_id,COALESCE(purpose,''),?,0.0,1,0
         FROM model_calls
         WHERE terminal=1 AND root_thread_id IS NOT NULL AND has_unpriced_usage=1
           AND (cost_currency IS NULL OR cost_amount IS NULL)
         GROUP BY root_thread_id,thread_id,COALESCE(purpose,'')
         ON CONFLICT(root_thread_id,thread_id,purpose,cost_currency) DO UPDATE SET
            has_unpriced_usage=1",
        vec![UNPRICED_CURRENCY.into()],
    ))
    .await?;
    Ok(())
}

/// 按 root/purpose 聚合调用库的累计摘要。
pub(super) async fn read_rollups(
    db: &impl ConnectionTrait,
    #[cfg(feature = "benchmarks")] observation: &observation::Observation,
) -> Result<Vec<SessionCostRollup>> {
    let mut rollups = std::collections::BTreeMap::<String, SessionCostRollup>::new();
    let mut purposes =
        std::collections::BTreeMap::<(String, Option<String>), Vec<RuntimeCostAmount>>::new();
    #[cfg(feature = "benchmarks")]
    observation.increment(observation::Metric::SummaryReadSql);
    let roots = db
        .query_all_raw(statement(
            "SELECT root_thread_id, MAX(has_unpriced_usage) AS unpriced
             FROM call_usage_summary
             GROUP BY root_thread_id
             ORDER BY root_thread_id",
            vec![],
        ))
        .await?;
    for row in &roots {
        let root: String = row.try_get("", "root_thread_id")?;
        rollups.insert(
            root.clone(),
            SessionCostRollup {
                root_thread_id: root,
                estimated_costs: Vec::new(),
                purpose_costs: Vec::new(),
                has_unpriced_usage: row.try_get::<i64>("", "unpriced")? != 0,
            },
        );
    }
    #[cfg(feature = "benchmarks")]
    observation.increment(observation::Metric::SummaryReadSql);
    let costs = db
        .query_all_raw(statement(
            "SELECT root_thread_id, purpose, cost_currency, SUM(amount) AS amount
             FROM call_usage_summary
             WHERE cost_currency <> ?
             GROUP BY root_thread_id, purpose, cost_currency
             ORDER BY root_thread_id, purpose, cost_currency",
            vec![UNPRICED_CURRENCY.into()],
        ))
        .await?;
    for row in &costs {
        let root_thread_id: String = row.try_get("", "root_thread_id")?;
        let purpose_raw: String = row.try_get("", "purpose")?;
        let purpose = (!purpose_raw.is_empty()).then_some(purpose_raw);
        let cost = RuntimeCostAmount {
            currency: row.try_get("", "cost_currency")?,
            amount: row.try_get("", "amount")?,
        };
        let rollup = rollups
            .entry(root_thread_id.clone())
            .or_insert_with(|| SessionCostRollup {
                root_thread_id: root_thread_id.clone(),
                ..Default::default()
            });
        merge_costs(&mut rollup.estimated_costs, std::slice::from_ref(&cost));
        purposes
            .entry((root_thread_id, purpose))
            .or_default()
            .push(cost);
    }
    for ((root, purpose), estimated_costs) in purposes {
        let rollup = rollups.get_mut(&root).context("missing grouped root")?;
        rollup.purpose_costs.push(PurposeCostRollup {
            purpose,
            estimated_costs,
            has_unpriced_usage: rollup.has_unpriced_usage,
        });
    }
    for rollup in rollups.values_mut() {
        for entry in &mut rollup.purpose_costs {
            entry.has_unpriced_usage = rollup.has_unpriced_usage;
        }
        if rollup.purpose_costs.is_empty()
            && (!rollup.estimated_costs.is_empty() || rollup.has_unpriced_usage)
        {
            rollup.purpose_costs.push(PurposeCostRollup {
                purpose: None,
                estimated_costs: rollup.estimated_costs.clone(),
                has_unpriced_usage: rollup.has_unpriced_usage,
            });
        }
    }
    Ok(rollups.into_values().collect())
}
