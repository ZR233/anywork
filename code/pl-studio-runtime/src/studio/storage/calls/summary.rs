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
    let mut rollups: Vec<SessionCostRollup> = Vec::new();
    #[cfg(feature = "benchmarks")]
    observation.increment(observation::Metric::SummaryReadSql);
    let rows = db
        .query_all_raw(statement(
            "SELECT root_thread_id,purpose,cost_currency,SUM(amount) AS amount,
                    MAX(has_unpriced_usage) AS unpriced
             FROM call_usage_summary
             GROUP BY root_thread_id,purpose,cost_currency
             ORDER BY root_thread_id,purpose,cost_currency",
            vec![],
        ))
        .await?;
    for row in rows {
        let root_thread_id: String = row.try_get("", "root_thread_id")?;
        // SQL keeps each root/purpose contiguous. Append instead of constructing
        // another pair of keyed maps or searching all preceding roots.
        if rollups
            .last()
            .is_none_or(|rollup| rollup.root_thread_id != root_thread_id)
        {
            rollups.push(SessionCostRollup {
                root_thread_id,
                ..Default::default()
            });
        }
        let rollup = rollups.last_mut().expect("root group started");
        rollup.has_unpriced_usage |= row.try_get::<i64>("", "unpriced")? != 0;
        let currency: String = row.try_get("", "cost_currency")?;
        // Empty-currency groups still establish their root and its unpriced flag.
        // They are provenance placeholders, not zero-valued monetary contributions.
        if currency == UNPRICED_CURRENCY {
            continue;
        }
        let purpose_raw: String = row.try_get("", "purpose")?;
        let purpose = (!purpose_raw.is_empty()).then_some(purpose_raw);
        let cost = RuntimeCostAmount {
            currency,
            amount: row.try_get("", "amount")?,
        };
        // Preserve the previous purpose/currency accumulation order for f64 totals.
        merge_costs(&mut rollup.estimated_costs, std::slice::from_ref(&cost));
        if rollup
            .purpose_costs
            .last()
            .is_none_or(|entry| entry.purpose != purpose)
        {
            rollup.purpose_costs.push(PurposeCostRollup {
                purpose,
                ..Default::default()
            });
        }
        rollup
            .purpose_costs
            .last_mut()
            .expect("purpose group started")
            .estimated_costs
            .push(cost);
    }
    for rollup in &mut rollups {
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
    Ok(rollups)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn purpose(name: Option<&str>, costs: &[(&str, f64)]) -> PurposeUsageProjection {
        PurposeUsageProjection {
            purpose: name.map(str::to_owned),
            estimated_costs: costs
                .iter()
                .map(|(currency, amount)| RuntimeCostAmount {
                    currency: (*currency).to_owned(),
                    amount: *amount,
                })
                .collect(),
        }
    }

    fn cost_rows(costs: &[RuntimeCostAmount]) -> Vec<(&str, f64)> {
        costs
            .iter()
            .map(|cost| (cost.currency.as_str(), cost.amount))
            .collect()
    }

    #[tokio::test]
    async fn rollups_preserve_ordered_costs_zeroes_and_unpriced_roots() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let empty = store
            .read_statistics(StatisticsReadRequest {
                costs: true,
                performance: false,
            })
            .await?;
        assert!(empty.costs.expect("costs requested").is_empty());
        assert!(empty.history.is_none());
        assert!(empty.summary.is_none());

        let mut progress = store.subscribe_materials();
        for (root, thread, unpriced, purpose_costs) in [
            (
                "root-alpha",
                "alpha-priced-a",
                false,
                vec![
                    purpose(Some("final"), &[("USD", 4.0)]),
                    purpose(Some("analysis"), &[("USD", 1.25), ("EUR", 2.0)]),
                    purpose(None, &[("USD", 0.0)]),
                ],
            ),
            (
                "root-alpha",
                "alpha-priced-b",
                false,
                vec![purpose(Some("analysis"), &[("USD", 2.75)])],
            ),
            // This group sorts after all priced purposes. It must still mark the
            // root and every earlier priced purpose, without inventing its own cost.
            (
                "root-alpha",
                "alpha-unpriced",
                true,
                vec![purpose(Some("zz-unpriced"), &[])],
            ),
            (
                "root-beta",
                "beta-priced",
                false,
                vec![purpose(Some("analysis"), &[("USD", 11.0), ("EUR", 9.0)])],
            ),
            ("root-empty", "empty", false, vec![]),
            (
                "root-rounding",
                "rounding",
                false,
                vec![
                    purpose(Some("c"), &[("USD", 1.0)]),
                    purpose(Some("a"), &[("USD", 1e16)]),
                    purpose(Some("b"), &[("USD", 1.0)]),
                ],
            ),
            (
                "root-unpriced",
                "unpriced",
                true,
                vec![purpose(Some("unknown-price"), &[])],
            ),
            (
                "root-zero",
                "zero",
                false,
                vec![purpose(Some("free"), &[("USD", 0.0)])],
            ),
        ] {
            store.replace_session_usage(SessionUsageProjection {
                root_thread_id: root.into(),
                thread_id: thread.into(),
                revision: 1,
                has_unpriced_usage: unpriced,
                purpose_costs,
            })?;
        }
        let ticket = store.admitted_ticket();
        store.start().await;
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if progress.borrow_and_update().processed_ticket >= ticket {
                    return Ok::<_, anyhow::Error>(());
                }
                progress.changed().await?;
            }
        })
        .await??;
        assert!(progress.borrow().last_error.is_none());
        assert!(!progress.borrow().statistics_gap);

        let read = store
            .read_statistics(StatisticsReadRequest {
                costs: true,
                performance: false,
            })
            .await?;
        let roots = read.costs.expect("costs requested");
        assert_eq!(
            roots
                .iter()
                .map(|root| (root.root_thread_id.as_str(), root.has_unpriced_usage))
                .collect::<Vec<_>>(),
            [
                ("root-alpha", true),
                ("root-beta", false),
                ("root-empty", false),
                ("root-rounding", false),
                ("root-unpriced", true),
                ("root-zero", false),
            ]
        );
        assert_eq!(
            cost_rows(&roots[0].estimated_costs),
            [("EUR", 2.0), ("USD", 8.0)]
        );
        assert_eq!(
            roots[0]
                .purpose_costs
                .iter()
                .map(|entry| (
                    entry.purpose.as_deref(),
                    cost_rows(&entry.estimated_costs),
                    entry.has_unpriced_usage,
                ))
                .collect::<Vec<_>>(),
            vec![
                (None, vec![("USD", 0.0)], true),
                (Some("analysis"), vec![("EUR", 2.0), ("USD", 4.0)], true),
                (Some("final"), vec![("USD", 4.0)], true),
            ]
        );
        assert_eq!(
            cost_rows(&roots[1].estimated_costs),
            [("EUR", 9.0), ("USD", 11.0)]
        );
        assert_eq!(roots[1].purpose_costs.len(), 1);
        assert_eq!(
            roots[1].purpose_costs[0].purpose.as_deref(),
            Some("analysis")
        );
        assert_eq!(
            cost_rows(&roots[1].purpose_costs[0].estimated_costs),
            [("EUR", 9.0), ("USD", 11.0)]
        );
        assert!(!roots[1].purpose_costs[0].has_unpriced_usage);
        assert!(roots[2].estimated_costs.is_empty());
        assert!(
            roots[2].purpose_costs.is_empty(),
            "an unflagged placeholder has no fallback purpose"
        );
        // Keep the previous left-to-right purpose order: (1e16 + 1) + 1 is 1e16,
        // not the 1e16 + 2 obtained by accumulating the smaller purposes first.
        assert_eq!(cost_rows(&roots[3].estimated_costs), [("USD", 1e16)]);
        assert_eq!(
            roots[3]
                .purpose_costs
                .iter()
                .map(|entry| (entry.purpose.as_deref(), cost_rows(&entry.estimated_costs),))
                .collect::<Vec<_>>(),
            vec![
                (Some("a"), vec![("USD", 1e16)]),
                (Some("b"), vec![("USD", 1.0)]),
                (Some("c"), vec![("USD", 1.0)]),
            ]
        );
        assert!(roots[4].estimated_costs.is_empty());
        assert_eq!(roots[4].purpose_costs.len(), 1);
        assert_eq!(roots[4].purpose_costs[0].purpose, None);
        assert!(roots[4].purpose_costs[0].estimated_costs.is_empty());
        assert!(roots[4].purpose_costs[0].has_unpriced_usage);
        assert_eq!(cost_rows(&roots[5].estimated_costs), [("USD", 0.0)]);
        assert_eq!(roots[5].purpose_costs.len(), 1);
        assert_eq!(roots[5].purpose_costs[0].purpose.as_deref(), Some("free"));
        assert_eq!(
            cost_rows(&roots[5].purpose_costs[0].estimated_costs),
            [("USD", 0.0)]
        );
        assert!(!roots[5].purpose_costs[0].has_unpriced_usage);
        store.close().await?;
        Ok(())
    }
}
