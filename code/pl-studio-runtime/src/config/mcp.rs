//! Studio built-in MCP directory and credential selection.
use pl_tool::approval::ToolEffect;
use pl_tool::mcp::config::*;
use std::collections::BTreeMap;
pub const ZHIPU_SEARCH_MCP_ID: &str = "zhipu_search";
pub const ZHIPU_READER_MCP_ID: &str = "zhipu_reader";
pub const ZHIPU_ZREAD_MCP_ID: &str = "zhipu_zread";
pub const ZHIPU_VISION_MCP_ID: &str = "zhipu_vision";

const BUILTIN_MCP_SERVERS: &[BuiltinMcpServerDefinition] = &[
    BuiltinMcpServerDefinition {
        id: ZHIPU_SEARCH_MCP_ID,
        transport: McpServerTransport::StreamableHttp,
        url: Some("https://open.bigmodel.cn/api/mcp/web_search_prime/mcp"),
        command: None,
        args: &[],
        credential: ZHIPU_CREDENTIAL,
        source_detail: "Zhipu Coding Plan",
        tool_effect: Some(ToolEffect::Read),
        env: &[],
        credential_env_var: None,
        startup_timeout_secs: None,
        tool_timeout_secs: None,
    },
    BuiltinMcpServerDefinition {
        id: ZHIPU_READER_MCP_ID,
        transport: McpServerTransport::StreamableHttp,
        url: Some("https://open.bigmodel.cn/api/mcp/web_reader/mcp"),
        command: None,
        args: &[],
        credential: ZHIPU_CREDENTIAL,
        source_detail: "Zhipu Coding Plan",
        tool_effect: Some(ToolEffect::Read),
        env: &[],
        credential_env_var: None,
        startup_timeout_secs: None,
        tool_timeout_secs: None,
    },
    BuiltinMcpServerDefinition {
        id: ZHIPU_ZREAD_MCP_ID,
        transport: McpServerTransport::StreamableHttp,
        url: Some("https://open.bigmodel.cn/api/mcp/zread/mcp"),
        command: None,
        args: &[],
        credential: ZHIPU_CREDENTIAL,
        source_detail: "Zhipu Coding Plan",
        tool_effect: Some(ToolEffect::Read),
        env: &[],
        credential_env_var: None,
        startup_timeout_secs: None,
        tool_timeout_secs: None,
    },
    BuiltinMcpServerDefinition {
        id: ZHIPU_VISION_MCP_ID,
        transport: McpServerTransport::Stdio,
        url: None,
        command: Some("npx"),
        args: &["-y", "@z_ai/mcp-server"],
        credential: ZHIPU_CREDENTIAL,
        source_detail: "Zhipu Coding Plan",
        tool_effect: Some(ToolEffect::Read),
        env: &[
            ("Z_AI_MODE", "ZHIPU"),
            // npm server 默认 32768，会显著放大简单图片冒烟的延迟和上下文。
            ("Z_AI_VISION_MODEL_MAX_TOKENS", "4096"),
        ],
        credential_env_var: Some("Z_AI_API_KEY"),
        // 首次运行可能需要由 npx 下载内置 server；后续 generation 会复用 npm cache。
        startup_timeout_secs: Some(60),
        // 上游 vision server 自身的默认请求超时为 300 秒；仅对该 server 放宽，
        // 不改变其他 MCP 的快速失败语义。
        tool_timeout_secs: Some(360),
    },
];

const ZHIPU_CREDENTIAL: BuiltinMcpCredentialSource = BuiltinMcpCredentialSource::Account {
    template_ids: &["zhipu-coding-plan"],
};

pub fn builtin_mcp_server_ids() -> Vec<&'static str> {
    BUILTIN_MCP_SERVERS
        .iter()
        .map(|definition| definition.id)
        .collect()
}

pub fn is_builtin_mcp_server_id(server_id: &str) -> bool {
    BUILTIN_MCP_SERVERS
        .iter()
        .any(|definition| definition.id == server_id)
}

pub fn build_builtin_effective_config(
    builtin_id: &str,
    enabled: bool,
    required: bool,
    cwd: Option<String>,
    models: &pl_model::config::AgentModelConfig,
) -> Option<EffectiveMcpServerConfig> {
    let definition = BUILTIN_MCP_SERVERS
        .iter()
        .find(|def| def.id == builtin_id)?;
    let token = definition.credential.resolve(models);
    let status_kind = if !enabled {
        McpServerStatusKind::Disabled
    } else if token.is_some() {
        McpServerStatusKind::Enabled
    } else {
        McpServerStatusKind::MissingCredential
    };
    let mut config = definition.config(token.as_deref());
    config.enabled = enabled;
    config.required = required;
    if definition.transport == McpServerTransport::Stdio {
        config.cwd = cwd;
    }
    Some(EffectiveMcpServerConfig {
        id: definition.id.to_string(),
        config,
        source_kind: McpServerSourceKind::BuiltIn,
        source_label: "Built-in".to_string(),
        source_detail: Some(definition.source_detail.to_string()),
        status_kind,
        status_message: match status_kind {
            McpServerStatusKind::Enabled => {
                Some("Using the configured Zhipu Coding Plan account token".to_string())
            }
            McpServerStatusKind::MissingCredential => Some(
                "Configure a Zhipu Coding Plan account token to enable this server".to_string(),
            ),
            McpServerStatusKind::Disabled => None,
        },
        mutation_policy: McpServerMutationPolicy::LockedIdentity,
        bearer_token: token,
        tool_effect: definition.tool_effect,
        execution_context: pl_tool::mcp::config::McpExecutionContext::Host,
    })
}

#[derive(Debug, Clone, Copy)]
struct BuiltinMcpServerDefinition {
    id: &'static str,
    transport: McpServerTransport,
    url: Option<&'static str>,
    command: Option<&'static str>,
    args: &'static [&'static str],
    credential: BuiltinMcpCredentialSource,
    source_detail: &'static str,
    tool_effect: Option<ToolEffect>,
    env: &'static [(&'static str, &'static str)],
    credential_env_var: Option<&'static str>,
    startup_timeout_secs: Option<u64>,
    tool_timeout_secs: Option<u64>,
}

#[derive(Debug, Clone, Copy)]
enum BuiltinMcpCredentialSource {
    Account {
        template_ids: &'static [&'static str],
    },
}

impl BuiltinMcpCredentialSource {
    fn resolve(self, models: &pl_model::config::AgentModelConfig) -> Option<String> {
        let Self::Account { template_ids } = self;
        models
            .accounts
            .values()
            .filter(|account| {
                account
                    .template_id()
                    .is_some_and(|template| template_ids.contains(&template.as_str()))
            })
            .find_map(pl_model::config::AccountConfig::resolved_bearer_token)
    }
}

impl BuiltinMcpServerDefinition {
    fn config(&self, zhipu_token: Option<&str>) -> McpServerConfig {
        let mut env = self
            .env
            .iter()
            .map(|(key, value)| ((*key).to_string(), (*value).to_string()))
            .collect::<BTreeMap<_, _>>();
        if let (Some(key), Some(token)) = (self.credential_env_var, zhipu_token) {
            env.insert(key.to_string(), token.to_string());
        }
        McpServerConfig {
            enabled: true,
            required: false,
            transport: self.transport,
            startup_mode: Default::default(),
            command: self.command.map(ToOwned::to_owned),
            args: self.args.iter().map(|arg| (*arg).to_string()).collect(),
            env,
            cwd: None,
            url: self.url.map(ToOwned::to_owned),
            bearer_token_env_var: None,
            headers: BTreeMap::new(),
            startup_timeout_secs: self.startup_timeout_secs,
            tool_timeout_secs: self.tool_timeout_secs,
            enabled_tools: None,
            disabled_tools: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::StudioConfig;

    #[test]
    fn required_builtin_without_credential_keeps_enabled_intent() {
        let config = StudioConfig::default_config().unwrap();
        let effective =
            build_builtin_effective_config(ZHIPU_SEARCH_MCP_ID, true, true, None, &config.models)
                .unwrap();
        assert_eq!(
            effective.status_kind,
            McpServerStatusKind::MissingCredential
        );
        assert!(effective.config.enabled);
        assert!(effective.config.required);

        let disabled =
            build_builtin_effective_config(ZHIPU_SEARCH_MCP_ID, false, true, None, &config.models)
                .unwrap();
        assert_eq!(disabled.status_kind, McpServerStatusKind::Disabled);
        assert!(!disabled.config.enabled);
        assert!(disabled.config.required);
    }
}
