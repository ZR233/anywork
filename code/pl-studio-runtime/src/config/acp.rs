//! ACP 接入的 desired 配置段（`[acp.accounts.<id>]`）。
//!
//! 每个稳定 ID 保存名称、接入类型、可执行程序路径与 argv 列表；它不使用空 base URL、空模型
//! 目录或假 API key 伪装 Native account，也不进入 Native 默认账号/模型路由候选。保存参数不做
//! shell 拆分，程序路径是否可执行只在连接时校验：已保存但当前不可用的安装必须保留并在连接时
//! 明确失败，不能凭猜测丢弃用户配置（见 design/20 §20.2、design/27）。

use std::collections::BTreeMap;

use crate::{PureError, Result};
use serde::{Deserialize, Serialize};

/// 程序路径的最大字节数；避免把非路径垃圾写进配置文件。
pub const MAX_ACP_PROGRAM_BYTES: usize = 4096;
/// 显示名称的最大字节数。
pub const MAX_ACP_NAME_BYTES: usize = 200;
/// 单个 argv 元素的最大字节数。
pub const MAX_ACP_ARG_BYTES: usize = 4096;
/// 启动参数的最大个数。
pub const MAX_ACP_ARG_COUNT: usize = 64;

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
    /// 官方 server 程序路径；不经过 shell，也不从 PATH 猜测。
    pub program: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub args: Vec<String>,
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

/// 校验保存时的程序路径：只要求非空、有限长度且不含 NUL/控制字符。
///
/// 绝对路径与可执行性在连接（启动）时校验；保存不伪造存在性，也不允许 shell 片段。
pub fn validate_acp_program(program: &str) -> Result<()> {
    let trimmed = program.trim();
    if trimmed.is_empty() {
        return Err(PureError::ConfigError(
            "ACP server program path is required".to_string(),
        ));
    }
    if trimmed.len() > MAX_ACP_PROGRAM_BYTES {
        return Err(PureError::ConfigError(format!(
            "ACP server program path must not exceed {MAX_ACP_PROGRAM_BYTES} bytes"
        )));
    }
    if trimmed.chars().any(|ch| ch == '\0' || ch.is_control()) {
        return Err(PureError::ConfigError(
            "ACP server program path must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

/// 校验启动参数：逐项字面保留，只限制长度、个数与控制字符。
pub fn validate_acp_args(args: &[String]) -> Result<()> {
    if args.len() > MAX_ACP_ARG_COUNT {
        return Err(PureError::ConfigError(format!(
            "ACP server arguments must not exceed {MAX_ACP_ARG_COUNT} items"
        )));
    }
    for arg in args {
        if arg.len() > MAX_ACP_ARG_BYTES {
            return Err(PureError::ConfigError(format!(
                "each ACP server argument must not exceed {MAX_ACP_ARG_BYTES} bytes"
            )));
        }
        if arg.contains('\0') {
            return Err(PureError::ConfigError(
                "ACP server arguments must not contain NUL".to_string(),
            ));
        }
    }
    Ok(())
}

/// 校验一个完整接入（保存命令与配置文件启动校验共用同一规则）。
pub fn validate_acp_account(account: &AcpAccountConfig) -> Result<()> {
    validate_acp_name(&account.name)?;
    validate_acp_program(&account.program)?;
    validate_acp_args(&account.args)?;
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

/// 归一化一次保存意图：只裁剪标量两端的空白，参数顺序与内容原样保留。
pub fn normalize_acp_account(account: AcpAccountConfig) -> AcpAccountConfig {
    AcpAccountConfig {
        name: account.name.trim().to_string(),
        provider: account.provider,
        program: account.program.trim().to_string(),
        args: account.args,
    }
}
