//! Four roots exercise fixed routing and the three prompt-only preferences.

use super::{OTHER_MODEL, SHARED_MODEL, flow::*, journeys::Decision, wire::*};
use anyhow::Context;
use serde_json::json;

pub(super) fn run(flow: &Flow<'_>, prompt: &str) -> Progress<Decision> {
    let preference = ["fixed", "economy", "balanced", "fast"]
        .into_iter()
        .find(|name| prompt.starts_with(&format!("[[delegation:routing:{name}]]")))
        .context("routing requires a fixed/economy/balanced/fast marker in a different root")?;
    let expected_label = match preference {
        "economy" => Some("经济"),
        "balanced" => Some("平衡"),
        "fast" => Some("快速"),
        _ => None,
    };
    for label in ["经济", "平衡", "快速"] {
        let count = flow
            .request
            .instructions
            .matches(&format!("自动分发偏好：{label}。"))
            .count();
        require(
            count == usize::from(expected_label == Some(label)),
            "root did not receive exactly its current single short preference template",
        )?;
    }
    require(
        !flow
            .request
            .instructions
            .contains("DELEGATION_INVENTORY_ONLY")
            && !flow
                .request
                .instructions
                .contains("DELEGATION_EVALUATION_ONLY"),
        "full inventory/evaluation comments leaked into root system instructions",
    )?;
    require(
        flow.request.declared("evaluate_agent"),
        "both root modes must expose foreground final evaluation",
    )?;
    let routes = if preference == "fixed" {
        require(
            !flow.request.declared("list_delegation_models")
                && !flow.request.declared("get_delegation_model"),
            "fixed mode loaded automatic selection tools",
        )?;
        vec![None]
    } else {
        let models = flow.models()?;
        require(
            models.len() > 10,
            "routing inventory needs multiple real bounded query pages",
        )?;
        require(
            models.iter().all(|model| {
                ![
                    "delegation-disabled",
                    "delegation-no-text",
                    "delegation-unknown-context",
                    "delegation-no-tools",
                    "delegation-no-credentials",
                ]
                .contains(&model.model_id.as_str())
            }),
            "production query included an ineligible synthetic boundary model",
        )?;
        let ten: ModelList = flow.read(
            "models-ten",
            "list_delegation_models",
            json!({"limit":10,"taskCategory":"coding"}),
        )?;
        require(
            ten.models.len() == 10 && ten.next_cursor.is_some(),
            "maximum page was not bounded at ten, or unknown task suitability incorrectly excluded candidates",
        )?;
        let first: ModelList = flow.read("models-0", "list_delegation_models", json!({}))?;
        require(
            first.models.len() == 5,
            "omitted limit did not return exactly five models on the qualified first page",
        )?;
        let cursor = first
            .next_cursor
            .context("first bounded query page has no cursor")?;
        flow.rejected(
            "cursor-filter-conflict",
            "list_delegation_models",
            json!({"cursor":cursor,"minContextWindow":42}),
            "stale or belongs to another query",
        )?;
        flow.rejected(
            "invalid-limit-zero",
            "list_delegation_models",
            json!({"limit":0}),
            "between 1 and 10",
        )?;
        flow.rejected(
            "invalid-limit-eleven",
            "list_delegation_models",
            json!({"limit":11}),
            "between 1 and 10",
        )?;
        let a = select(&models, "-a", SHARED_MODEL)?;
        let other = select(&models, "-a", OTHER_MODEL)?;
        let b = select(&models, "-b", SHARED_MODEL)?;
        for (label, route) in [("a", &other), ("b", &b)] {
            let detail: Detail = flow.read(
                &format!("detail-{label}"),
                "get_delegation_model",
                json!({"accountId":route.account_id,"modelId":route.model_id}),
            )?;
            require(
                detail.available && detail.account_id == route.account_id && detail.guide.is_none(),
                "custom model invented verified guide data or lost account identity",
            )?;
            if detail.performance.sample_count == 0 {
                require(
                    detail.performance.tokens_per_second.is_none()
                        && detail.performance.average_ttft_millis.is_none()
                        && detail.performance.ttft_sample_count == 0,
                    "unobserved performance was not honestly unknown",
                )?;
            }
            require(
                detail.billing_kind == "unknown",
                "pricing-disabled custom account was mislabeled as subscription",
            )?;
            let item = models
                .iter()
                .find(|model| {
                    model.account_id == route.account_id && model.model_id == route.model_id
                })
                .context("detail model missing from query")?;
            require(
                item.pricing.is_none()
                    && item.billing_kind == "unknown"
                    && item.performance.ttft_sample_count <= item.performance.sample_count,
                "list invented unknown price/billing/performance",
            )?;
        }
        for model_id in [
            "delegation-disabled",
            "delegation-no-text",
            "delegation-unknown-context",
            "delegation-no-tools",
        ] {
            let detail: Detail = flow.read(
                &format!("unavailable-{model_id}"),
                "get_delegation_model",
                json!({"accountId":a.account_id,"modelId":model_id}),
            )?;
            require(
                !detail.available
                    && detail
                        .unavailable_reason
                        .as_ref()
                        .is_some_and(|reason| !reason.is_empty()),
                "existing ineligible model did not return an honest unavailable detail",
            )?;
        }
        let missing_account = format!(
            "{}-missing",
            a.account_id
                .strip_suffix("-a")
                .context("synthetic account suffix missing")?
        );
        let missing: Detail = flow.read(
            "missing-credentials-detail",
            "get_delegation_model",
            json!({"accountId":missing_account,"modelId":"delegation-no-credentials"}),
        )?;
        require(
            !missing.available
                && missing
                    .unavailable_reason
                    .as_ref()
                    .is_some_and(|reason| !reason.is_empty()),
            "missing credentials were silently considered routable",
        )?;
        // Exact model not in this account's effective catalog must remain absent.
        flow.rejected(
            "withdrawn-detail",
            "get_delegation_model",
            json!({"accountId":a.account_id,"modelId":"delegation-withdrawn"}),
            "not found",
        )?;
        vec![Some(a), Some(other), Some(b)]
    };
    let mut observed = Vec::new();
    for (index, route) in routes.iter().enumerate() {
        let profile = if preference != "fixed" && index == 0 {
            "obsolete_route"
        } else {
            "explorer"
        };
        let child = flow.spawn(
            &format!("routing-spawn-{index}"),
            profile,
            route.as_ref(),
            "[[delegation:child:sample]]",
            None,
        )?;
        if preference == "fixed" {
            require(
                child.model.account_id.ends_with("-a")
                    && child.model.model_id == OTHER_MODEL
                    && child.model.effort.as_deref() == Some("high"),
                "fixed Profile route was replaced by the root model",
            )?;
        }
        let report = flow.report(
            &format!("routing-{index}"),
            &child,
            "delegation sample delivery",
            0,
        )?;
        let review_route = if preference == "fixed" {
            None
        } else {
            routes
                .get(if index == 2 { 1 } else { 2 })
                .and_then(Option::as_ref)
        };
        let reviewer = flow.spawn(
            &format!("routing-review-{index}"),
            "reviewer",
            review_route,
            "[[delegation:child:review-pass]]",
            Some(&child.agent_id),
        )?;
        let approval = flow.report(
            &format!("routing-review-{index}"),
            &reviewer,
            "delegation independent review: approved",
            0,
        )?;
        let evaluation = flow.evaluate(
            &format!("routing-eval-{index}"),
            &child,
            &report,
            0,
            "Synthetic route delivery and independent acceptance completed.",
            "passed",
        )?;
        let _ = flow.evaluate(
            &format!("routing-review-eval-{index}"),
            &reviewer,
            &approval,
            0,
            "Independent route observation delivered.",
            "passed",
        )?;
        require(
            evaluation.evaluation.mode
                == if preference == "fixed" {
                    "profile"
                } else {
                    "automatic"
                },
            "final evaluation lost the frozen root delegation mode",
        )?;
        observed.push(json!({"childId":child.agent_id,"model":child.model,"turnId":report.turn.turn_id,"commitSequence":report.commit_sequence}));
        flow.close(&format!("routing-close-review-{index}"), &reviewer)?;
        flow.close(&format!("routing-close-{index}"), &child)?;
    }
    let mut decision = Decision::answer(
        &format!("routing_{preference}_complete"),
        "delegation routing complete",
    );
    decision.receipt = Some(json!({"policy":preference,"children":observed}));
    Ok(decision)
}
