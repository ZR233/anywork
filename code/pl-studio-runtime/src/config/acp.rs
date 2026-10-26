//! ACP 接入的 desired 配置段（`[acp.accounts.<id>]`）。
//!
//! 每个稳定 ID 只保存名称与接入类型：官方 server 的版本、下载地址与启动 argv 属于产品固定清单
//! 与受管安装事实，不能通过配置提交。接入不使用空 base URL、空模型目录或假 API key 伪装 Native
//! account，也不进入 Native 默认账号/模型路由候选（见 design/20 §20.2、design/28 §28.8）。
//!
//! schema 24 及更早版本里的 `program`/`args` 只由迁移边界读取并退役；当前结构
//! `deny_unknown_fields`，旧执行字段不会静默正常加载。

use std::collections::BTreeMap;

use crate::{PureError, Result};
use serde::{Deserialize, Serialize};

/// 显示名称的最大字节数。
pub const MAX_ACP_NAME_BYTES: usize = 200;

/// 支持的 ACP 接入类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AcpProvider {
    Antigravity,
}

impl AcpProvider {
    /// 稳定的配置/wire 标签。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Antigravity => "antigravity",
        }
    }
}

/// 一条 ACP 接入的 desired 配置。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct AcpAccountConfig {
    pub name: String,
    pub provider: AcpProvider,
}

/// Studio 自有的 ACP 配置段。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct AcpConfig {
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub accounts: BTreeMap<String, AcpAccountConfig>,
}

impl AcpConfig {
    pub fn is_empty(&self) -> bool {
        self.accounts.is_empty()
    }
}

/// 校验接入 ID：与既有账号一致的非空标识，另拒绝控制字符以保持日志/DTO 可读。
pub fn validate_acp_account_id(account_id: &str) -> Result<()> {
    if account_id.trim().is_empty() {
        return Err(PureError::ConfigError(
            "ACP account id cannot be empty".to_string(),
        ));
    }
    if account_id.chars().any(char::is_control) {
        return Err(PureError::ConfigError(
            "ACP account id must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

/// 校验显示名称：非空、有限长度、无控制字符。
pub fn validate_acp_name(name: &str) -> Result<()> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err(PureError::ConfigError(
            "ACP account name is required".to_string(),
        ));
    }
    if trimmed.len() > MAX_ACP_NAME_BYTES {
        return Err(PureError::ConfigError(format!(
            "ACP account name must not exceed {MAX_ACP_NAME_BYTES} bytes"
        )));
    }
    if trimmed.chars().any(char::is_control) {
        return Err(PureError::ConfigError(
            "ACP account name must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

/// 校验一个完整接入（保存命令与配置文件启动校验共用同一规则）。
pub fn validate_acp_account(account: &AcpAccountConfig) -> Result<()> {
    validate_acp_name(&account.name)?;
    Ok(())
}

/// 校验整个 ACP 配置段；ID 与其内容一起校验，非法声明 fail-loud。
pub fn validate_acp_config(config: &AcpConfig) -> Result<()> {
    for (account_id, account) in &config.accounts {
        validate_acp_account_id(account_id)?;
        validate_acp_account(account)?;
    }
    Ok(())
}

/// 归一化一次保存意图：只裁剪名称两端的空白。
pub fn normalize_acp_account(account: AcpAccountConfig) -> AcpAccountConfig {
    AcpAccountConfig {
        name: account.name.trim().to_string(),
        provider: account.provider,
    }
}
