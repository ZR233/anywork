use std::time::Duration;

use pl_model::config::AccountConfig;
use pl_model::protocol::ProtocolEndpoint;
use reqwest::header::{ACCEPT_LANGUAGE, AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderValue};
use serde::Deserialize;
use serde_json::Value;

use crate::PureError;
use crate::protocol::{
    AccountMoneyBalance, AccountQuota, AccountQuotaDetail, AccountQuotaWindow, AccountUsageFailure,
    AccountUsageFailureCode, AccountUsageValue,
};
use crate::studio::unix_seconds;

const ZHIPU_TOKEN_LIMIT_TYPE: &str = "TOKENS_LIMIT";
const ZHIPU_TIME_LIMIT_TYPE: &str = "TIME_LIMIT";

#[derive(Debug, Clone)]
pub(crate) enum AccountUsageQueryOutcome {
    Ready {
        checked_at: i64,
        value: AccountUsageValue,
    },
    Unsupported,
    MissingCredential,
    Failed(AccountUsageFailure),
}

#[derive(Debug, Deserialize)]
struct DeepSeekBalanceResponse {
    is_available: bool,
    balance_infos: Vec<DeepSeekBalanceInfoResponse>,
}

#[derive(Debug, Deserialize)]
struct DeepSeekBalanceInfoResponse {
    currency: String,
    total_balance: String,
    granted_balance: String,
    topped_up_balance: String,
}

#[derive(Debug, Deserialize)]
struct ZhipuEnvelope {
    #[serde(default)]
    code: Option<i64>,
    #[serde(default)]
    msg: Option<String>,
    #[serde(default)]
    success: Option<bool>,
    #[serde(default)]
    data: Option<ZhipuQuotaData>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ZhipuQuotaData {
    #[serde(default)]
    level: Option<String>,
    #[serde(default)]
    limits: Vec<ZhipuQuotaLimitResponse>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ZhipuQuotaLimitResponse {
    #[serde(rename = "type")]
    limit_type: String,
    #[serde(default)]
    unit: Option<i64>,
    #[serde(default)]
    number: Option<i64>,
    #[serde(default)]
    percentage: Option<f64>,
    #[serde(default)]
    current_value: Option<f64>,
    #[serde(default)]
    usage: Option<f64>,
    #[serde(default)]
    next_reset_time: Option<i64>,
    #[serde(default)]
    usage_details: Option<Value>,
}

async fn query_deepseek_balance(info: &ProtocolEndpoint) -> crate::Result<AccountUsageValue> {
    let token = required_token(info)?;
    let url = endpoint_url(&info.base_url, "/user/balance")?;
    let response = reqwest_client()?
        .get(url)
        .bearer_auth(token)
        .send()
        .await
        .map_err(http_error)?;
    let status = response.status();
    let body = response.text().await.map_err(http_error)?;
    if !status.is_success() {
        return Err(PureError::HttpError(format!(
            "DeepSeek balance request failed: HTTP {status}"
        )));
    }
    parse_deepseek_balance(&body)
}

async fn query_zhipu_coding_plan_usage(
    info: &ProtocolEndpoint,
) -> crate::Result<AccountUsageValue> {
    let token = required_token(info)?;
    let url = endpoint_url(&info.base_url, "/api/monitor/usage/quota/limit")?;
    let mut headers = HeaderMap::new();
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_str(&token).map_err(|error| PureError::HttpError(error.to_string()))?,
    );
    headers.insert(ACCEPT_LANGUAGE, HeaderValue::from_static("en-US,en"));
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    let response = reqwest_client()?
        .get(url)
        .headers(headers)
        .send()
        .await
        .map_err(http_error)?;
    let status = response.status();
    let body = response.text().await.map_err(http_error)?;
    if !status.is_success() {
        return Err(PureError::HttpError(format!(
            "Zhipu Coding Plan quota request failed: HTTP {status}"
        )));
    }
    parse_zhipu_coding_plan_usage(&body)
}

fn parse_deepseek_balance(body: &str) -> crate::Result<AccountUsageValue> {
    let response: DeepSeekBalanceResponse = serde_json::from_str(body)?;
    Ok(AccountUsageValue::Balance {
        available: response.is_available,
        balances: response
            .balance_infos
            .into_iter()
            .map(|balance| AccountMoneyBalance {
                currency: balance.currency,
                total: balance.total_balance,
                granted: balance.granted_balance,
                topped_up: balance.topped_up_balance,
            })
            .collect(),
    })
}

fn parse_zhipu_coding_plan_usage(body: &str) -> crate::Result<AccountUsageValue> {
    let envelope: ZhipuEnvelope = serde_json::from_str(body)?;
    if matches!(envelope.success, Some(false)) {
        let message = envelope
            .msg
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| {
                envelope
                    .code
                    .map(|code| format!("endpoint returned code {code}"))
                    .unwrap_or_else(|| "endpoint returned unsuccessful response".to_string())
            });
        return Err(PureError::HttpError(format!(
            "Zhipu Coding Plan quota request failed: {message}"
        )));
    }
    let data = envelope.data.ok_or_else(|| {
        PureError::HttpError("Zhipu Coding Plan quota response missing data".into())
    })?;
    Ok(AccountUsageValue::Subscription {
        level: data.level,
        quotas: data.limits.into_iter().map(zhipu_quota_limit).collect(),
    })
}

fn zhipu_quota_limit(limit: ZhipuQuotaLimitResponse) -> AccountQuota {
    let total = limit.usage;
    let used = limit.current_value;
    AccountQuota {
        window: zhipu_quota_window(&limit),
        percentage: limit.percentage.unwrap_or(0.0),
        used,
        total,
        remaining: match (total, used) {
            (Some(total), Some(current)) => Some((total - current).max(0.0)),
            _ => None,
        },
        reset_at: limit.next_reset_time.map(|value| value / 1_000),
        details: limit
            .usage_details
            .as_ref()
            .map(zhipu_tool_usage_details)
            .unwrap_or_default(),
    }
}

fn zhipu_quota_window(limit: &ZhipuQuotaLimitResponse) -> AccountQuotaWindow {
    match (limit.limit_type.as_str(), limit.unit, limit.number) {
        (ZHIPU_TOKEN_LIMIT_TYPE, Some(3), Some(5)) => AccountQuotaWindow::FiveHour,
        (ZHIPU_TOKEN_LIMIT_TYPE, Some(6), Some(1)) => AccountQuotaWindow::Weekly,
        (ZHIPU_TIME_LIMIT_TYPE, _, _) => AccountQuotaWindow::McpMonthly,
        _ => AccountQuotaWindow::Other(limit.limit_type.clone()),
    }
}

fn zhipu_tool_usage_details(value: &Value) -> Vec<AccountQuotaDetail> {
    match value {
        Value::Array(items) => items.iter().filter_map(zhipu_tool_usage_detail).collect(),
        Value::Object(map) => map
            .iter()
            .map(|(name, value)| {
                zhipu_tool_usage_detail(value).unwrap_or_else(|| AccountQuotaDetail {
                    name: humanize_tool_name(name),
                    used: value.as_f64(),
                    total: None,
                    percentage: None,
                })
            })
            .collect(),
        _ => Vec::new(),
    }
}

fn zhipu_tool_usage_detail(value: &Value) -> Option<AccountQuotaDetail> {
    let object = value.as_object()?;
    let name = first_string(
        object,
        &[
            "name",
            "tool",
            "toolName",
            "type",
            "id",
            "service",
            "serviceName",
        ],
    )?;
    Some(AccountQuotaDetail {
        name: humanize_tool_name(&name),
        used: first_number(object, &["currentValue", "current", "count", "used"]),
        total: first_number(object, &["total", "limit", "quota", "usage"]),
        percentage: first_number(object, &["percentage", "percent"]),
    })
}

fn first_string(map: &serde_json::Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        map.get(*key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    })
}

fn first_number(map: &serde_json::Map<String, Value>, keys: &[&str]) -> Option<f64> {
    keys.iter()
        .find_map(|key| map.get(*key).and_then(number_value))
}

fn number_value(value: &Value) -> Option<f64> {
    value
        .as_f64()
        .or_else(|| value.as_str().and_then(|text| text.parse::<f64>().ok()))
}

fn humanize_tool_name(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.eq_ignore_ascii_case("web_search_prime")
        || trimmed.eq_ignore_ascii_case("web_search")
    {
        "Web Search".to_string()
    } else if trimmed.eq_ignore_ascii_case("web_reader") {
        "Web Reader".to_string()
    } else if trimmed.eq_ignore_ascii_case("zread") {
        "ZRead".to_string()
    } else {
        trimmed
            .replace(['_', '-'], " ")
            .split_whitespace()
            .map(|part| {
                let mut chars = part.chars();
                chars.next().map_or_else(String::new, |first| {
                    let mut word = first.to_uppercase().collect::<String>();
                    word.push_str(chars.as_str());
                    word
                })
            })
            .collect::<Vec<_>>()
            .join(" ")
    }
}

fn required_token(info: &ProtocolEndpoint) -> crate::Result<String> {
    info.bearer_token
        .as_ref()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| PureError::ConfigError("account API key is not configured".to_string()))
}

fn endpoint_url(base_url: &str, path: &str) -> crate::Result<String> {
    let mut url = reqwest::Url::parse(base_url.trim())
        .map_err(|error| PureError::ConfigError(format!("invalid account base_url: {error}")))?;
    url.set_path(path);
    url.set_query(None);
    Ok(url.to_string())
}

fn reqwest_client() -> crate::Result<reqwest::Client> {
    reqwest::Client::builder()
        .retry(reqwest::retry::never())
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(http_error)
}

fn http_error(error: reqwest::Error) -> PureError {
    PureError::HttpError(error.to_string())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AccountUsageQueryKind {
    DeepSeek,
    Subscription,
}

pub(crate) fn account_usage_query_kind(template_id: Option<&str>) -> Option<AccountUsageQueryKind> {
    let normalized = template_id?.trim().replace('_', "-");
    match normalized.as_str() {
        "deepseek" => Some(AccountUsageQueryKind::DeepSeek),
        "zhipu-coding-plan" => Some(AccountUsageQueryKind::Subscription),
        _ => None,
    }
}

pub(crate) async fn query_account_usage(provider: AccountConfig) -> AccountUsageQueryOutcome {
    if provider.authentication == crate::AccountAuthenticationMethod::ChatGpt {
        return query_chatgpt_usage(&provider).await;
    }
    match account_usage_query_kind(provider.template_id().map(|id| id.as_str())) {
        Some(AccountUsageQueryKind::DeepSeek) => account_usage_data(provider, query_deepseek).await,
        Some(AccountUsageQueryKind::Subscription) => {
            account_usage_data(provider, query_zhipu).await
        }
        None => AccountUsageQueryOutcome::Unsupported,
    }
}

async fn query_chatgpt_usage(provider: &AccountConfig) -> AccountUsageQueryOutcome {
    use pl_model_openai::codex_usage::CodexUsageError;
    let Some(session) = &provider.chatgpt_session else {
        return AccountUsageQueryOutcome::MissingCredential;
    };
    let result = match pl_model_openai::codex_usage::query_usage(session).await {
        Ok(usage) => usage,
        Err(CodexUsageError::Unsupported) => return AccountUsageQueryOutcome::Unsupported,
        Err(error) => {
            return AccountUsageQueryOutcome::Failed(AccountUsageFailure {
                code: AccountUsageFailureCode::Query,
                retryable: matches!(
                    error,
                    CodexUsageError::Network
                        | CodexUsageError::Http {
                            status: 429 | 500..=599
                        }
                ),
            });
        }
    };
    AccountUsageQueryOutcome::Ready {
        checked_at: unix_seconds(),
        value: AccountUsageValue::Subscription {
            level: result.plan_type,
            quotas: result
                .windows
                .into_iter()
                .map(|window| AccountQuota {
                    window: if window.name == "Codex" {
                        match window.duration_seconds {
                            18_000 => AccountQuotaWindow::FiveHour,
                            604_800 => AccountQuotaWindow::Weekly,
                            seconds => AccountQuotaWindow::Other(format!("Codex · {seconds}s")),
                        }
                    } else {
                        AccountQuotaWindow::Other(format!(
                            "{} · {}s",
                            window.name, window.duration_seconds
                        ))
                    },
                    percentage: window.used_percent,
                    used: None,
                    total: None,
                    remaining: None,
                    reset_at: window.reset_at,
                    details: Vec::new(),
                })
                .collect(),
        },
    }
}

async fn account_usage_data<Query, QueryFuture>(
    provider: AccountConfig,
    query: Query,
) -> AccountUsageQueryOutcome
where
    Query: FnOnce(ProtocolEndpoint) -> QueryFuture,
    QueryFuture: std::future::Future<Output = crate::Result<AccountUsageValue>>,
{
    if provider
        .resolved_bearer_token()
        .as_ref()
        .is_none_or(|token| token.trim().is_empty())
    {
        return AccountUsageQueryOutcome::MissingCredential;
    }
    let info = match provider.to_endpoint() {
        Ok(info) => info,
        Err(_) => {
            return AccountUsageQueryOutcome::Failed(AccountUsageFailure {
                code: AccountUsageFailureCode::Configuration,
                retryable: false,
            });
        }
    };
    match query(info).await {
        Ok(value) => AccountUsageQueryOutcome::Ready {
            checked_at: unix_seconds(),
            value,
        },
        Err(_) => AccountUsageQueryOutcome::Failed(AccountUsageFailure {
            code: AccountUsageFailureCode::Query,
            retryable: true,
        }),
    }
}

async fn query_deepseek(info: ProtocolEndpoint) -> crate::Result<AccountUsageValue> {
    query_deepseek_balance(&info).await
}

async fn query_zhipu(info: ProtocolEndpoint) -> crate::Result<AccountUsageValue> {
    query_zhipu_coding_plan_usage(&info).await
}
