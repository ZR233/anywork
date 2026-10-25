use std::collections::BTreeMap;
use std::time::Duration;

mod state;

pub use state::{
    AccountUsageState, FailedAccountUsage, MissingCredentialAccountUsage, ReadyAccountUsage,
    UnsupportedAccountUsage,
};

use futures::FutureExt;
use futures::future::BoxFuture;
use pl_model::protocol::ProtocolEndpoint;
use pl_protocol::{PureError, StateError};
use reqwest::header::{ACCEPT_LANGUAGE, AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderValue};
use serde_json::Value;

use crate::config_editor::account_template_kind;
use crate::studio::unix_seconds;
use pl_model::config::AccountConfig;
use serde::{Deserialize, Serialize};

const ZHIPU_TOKEN_LIMIT_TYPE: &str = "TOKENS_LIMIT";
const ZHIPU_TIME_LIMIT_TYPE: &str = "TIME_LIMIT";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DeepSeekBalanceUsage {
    pub is_available: bool,
    pub balances: Vec<DeepSeekBalanceInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DeepSeekBalanceInfo {
    pub currency: String,
    pub total_balance: String,
    pub granted_balance: String,
    pub topped_up_balance: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ZhipuCodingPlanUsage {
    pub level: Option<String>,
    pub limits: Vec<ZhipuQuotaLimit>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ZhipuQuotaLimit {
    pub window: ZhipuQuotaWindow,
    pub percentage: f64,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub remaining: Option<f64>,
    pub next_reset_at: Option<i64>,
    pub usage_details: Vec<ZhipuToolUsageDetail>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ZhipuQuotaWindow {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ZhipuToolUsageDetail {
    pub name: String,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub percentage: Option<f64>,
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

async fn query_deepseek_balance(info: &ProtocolEndpoint) -> crate::Result<DeepSeekBalanceUsage> {
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
) -> crate::Result<ZhipuCodingPlanUsage> {
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

fn parse_deepseek_balance(body: &str) -> crate::Result<DeepSeekBalanceUsage> {
    let response: DeepSeekBalanceResponse = serde_json::from_str(body)?;
    Ok(DeepSeekBalanceUsage {
        is_available: response.is_available,
        balances: response
            .balance_infos
            .into_iter()
            .map(|balance| DeepSeekBalanceInfo {
                currency: balance.currency,
                total_balance: balance.total_balance,
                granted_balance: balance.granted_balance,
                topped_up_balance: balance.topped_up_balance,
            })
            .collect(),
    })
}

fn parse_zhipu_coding_plan_usage(body: &str) -> crate::Result<ZhipuCodingPlanUsage> {
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
    Ok(ZhipuCodingPlanUsage {
        level: data.level,
        limits: data.limits.into_iter().map(zhipu_quota_limit).collect(),
    })
}

fn zhipu_quota_limit(limit: ZhipuQuotaLimitResponse) -> ZhipuQuotaLimit {
    let total = limit.usage;
    let current_value = limit.current_value;
    ZhipuQuotaLimit {
        window: zhipu_quota_window(&limit),
        percentage: limit.percentage.unwrap_or(0.0),
        current_value,
        total,
        remaining: match (total, current_value) {
            (Some(total), Some(current)) => Some((total - current).max(0.0)),
            _ => None,
        },
        next_reset_at: limit.next_reset_time.map(|value| value / 1_000),
        usage_details: limit
            .usage_details
            .as_ref()
            .map(zhipu_tool_usage_details)
            .unwrap_or_default(),
    }
}

fn zhipu_quota_window(limit: &ZhipuQuotaLimitResponse) -> ZhipuQuotaWindow {
    match (limit.limit_type.as_str(), limit.unit, limit.number) {
        (ZHIPU_TOKEN_LIMIT_TYPE, Some(3), Some(5)) => ZhipuQuotaWindow::FiveHour,
        (ZHIPU_TOKEN_LIMIT_TYPE, Some(6), Some(1)) => ZhipuQuotaWindow::Weekly,
        (ZHIPU_TIME_LIMIT_TYPE, _, _) => ZhipuQuotaWindow::McpMonthly,
        _ => ZhipuQuotaWindow::Other(limit.limit_type.clone()),
    }
}

fn zhipu_tool_usage_details(value: &Value) -> Vec<ZhipuToolUsageDetail> {
    match value {
        Value::Array(items) => items.iter().filter_map(zhipu_tool_usage_detail).collect(),
        Value::Object(map) => map
            .iter()
            .map(|(name, value)| {
                zhipu_tool_usage_detail(value).unwrap_or_else(|| ZhipuToolUsageDetail {
                    name: humanize_tool_name(name),
                    current_value: value.as_f64(),
                    total: None,
                    percentage: None,
                })
            })
            .collect(),
        _ => Vec::new(),
    }
}

fn zhipu_tool_usage_detail(value: &Value) -> Option<ZhipuToolUsageDetail> {
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
    Some(ZhipuToolUsageDetail {
        name: humanize_tool_name(&name),
        current_value: first_number(object, &["currentValue", "current", "count", "used"]),
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

pub fn zhipu_limit_by_window(
    limits: &[ZhipuQuotaLimit],
) -> BTreeMap<&'static str, &ZhipuQuotaLimit> {
    limits
        .iter()
        .filter_map(|limit| {
            let key = match limit.window {
                ZhipuQuotaWindow::FiveHour => "five_hour",
                ZhipuQuotaWindow::Weekly => "weekly",
                ZhipuQuotaWindow::McpMonthly => "mcp_monthly",
                ZhipuQuotaWindow::Other(_) => return None,
            };
            Some((key, limit))
        })
        .collect()
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AccountUsageRecord {
    account_id: String,
    revision: u64,
    updated_at: i64,
    last_operation_id: String,
    state: AccountUsageState,
}

impl AccountUsageRecord {
    pub fn new(account_id: impl Into<String>) -> Self {
        Self {
            account_id: account_id.into(),
            revision: 0,
            updated_at: 0,
            last_operation_id: String::new(),
            state: AccountUsageState::unsupported(),
        }
    }

    pub fn account_id(&self) -> &str {
        &self.account_id
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn updated_at(&self) -> i64 {
        self.updated_at
    }

    pub fn state(&self) -> &AccountUsageState {
        &self.state
    }

    pub fn last_operation_id(&self) -> &str {
        &self.last_operation_id
    }

    pub fn decide(
        &self,
        command: AccountUsageCommand,
    ) -> Result<AccountUsageTransitionDecision, AccountUsageTransitionError> {
        let AccountUsageCommand::Observe {
            expected_revision,
            operation_id,
            observed_at,
            state,
        } = command;
        if expected_revision != self.revision {
            return Err(AccountUsageTransitionError::StaleRevision {
                account_id: self.account_id.clone(),
                expected: expected_revision,
                actual: self.revision,
            });
        }
        if operation_id == self.last_operation_id {
            if observed_at == self.updated_at && state == self.state {
                return Ok(AccountUsageTransitionDecision {
                    next_state: self.clone(),
                    changed: false,
                });
            }
            return Err(AccountUsageTransitionError::OperationConflict {
                account_id: self.account_id.clone(),
                operation_id,
            });
        }
        Ok(AccountUsageTransitionDecision {
            next_state: Self {
                account_id: self.account_id.clone(),
                revision: self.revision.saturating_add(1),
                updated_at: observed_at,
                last_operation_id: operation_id,
                state,
            },
            changed: true,
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum AccountUsageCommand {
    Observe {
        expected_revision: u64,
        operation_id: String,
        observed_at: i64,
        state: AccountUsageState,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct AccountUsageTransitionDecision {
    pub next_state: AccountUsageRecord,
    pub changed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AccountUsageTransitionError {
    #[error("account usage {account_id} revision is stale: expected {expected}, actual {actual}")]
    StaleRevision {
        account_id: String,
        expected: u64,
        actual: u64,
    },
    #[error("account usage {account_id} operation {operation_id} conflicts with prior payload")]
    OperationConflict {
        account_id: String,
        operation_id: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum AccountUsageData {
    DeepSeekBalance(DeepSeekBalanceUsage),
    ZhipuCodingPlan(ZhipuCodingPlanUsage),
}

pub(crate) async fn query_account_usage(
    record: AccountUsageRecord,
    provider: AccountConfig,
    operation_id: String,
) -> Result<AccountUsageRecord, AccountUsageTransitionError> {
    let state = match account_template_kind(&provider) {
        Ok(kind) => match kind.as_ref().map(|kind| kind.key()) {
            Some("deepseek") => account_usage_data(provider, query_deepseek).await,
            Some("zhipu-coding-plan") => account_usage_data(provider, query_zhipu).await,
            Some(_) | None => AccountUsageState::unsupported(),
        },
        Err(error) => AccountUsageState::failed(StateError {
            code: "accountUsageConfigurationFailed".to_string(),
            message: error.to_string(),
            retryable: false,
        }),
    };
    record
        .decide(AccountUsageCommand::Observe {
            expected_revision: record.revision(),
            operation_id,
            observed_at: unix_seconds(),
            state,
        })
        .map(|decision| decision.next_state)
}

type AccountUsageQueryFuture = BoxFuture<'static, crate::Result<AccountUsageData>>;

async fn account_usage_data(
    provider: AccountConfig,
    query: impl FnOnce(pl_model::protocol::ProtocolEndpoint) -> AccountUsageQueryFuture,
) -> AccountUsageState {
    if provider
        .resolved_bearer_token()
        .as_ref()
        .is_none_or(|token| token.trim().is_empty())
    {
        return AccountUsageState::missing_credential("account API key is not configured");
    }
    let info = match provider.to_endpoint() {
        Ok(info) => info,
        Err(error) => {
            return AccountUsageState::failed(StateError {
                code: "accountUsageConfigurationFailed".to_string(),
                message: error.to_string(),
                retryable: false,
            });
        }
    };
    match query(info).await {
        Ok(data) => AccountUsageState::ready(data),
        Err(error) => AccountUsageState::failed(StateError {
            code: "accountUsageQueryFailed".to_string(),
            message: error.to_string(),
            retryable: true,
        }),
    }
}

fn query_deepseek(info: pl_model::protocol::ProtocolEndpoint) -> AccountUsageQueryFuture {
    async move {
        query_deepseek_balance(&info)
            .await
            .map(AccountUsageData::DeepSeekBalance)
    }
    .boxed()
}

fn query_zhipu(info: pl_model::protocol::ProtocolEndpoint) -> AccountUsageQueryFuture {
    async move {
        query_zhipu_coding_plan_usage(&info)
            .await
            .map(AccountUsageData::ZhipuCodingPlan)
    }
    .boxed()
}
