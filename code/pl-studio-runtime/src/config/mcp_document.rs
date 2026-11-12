//! 单文件 MCP 配置文档 schema（`schema_version = 1`）与严格校验。

use std::collections::BTreeMap;

use pl_protocol::{McpScope, PureError, Result};
use pl_tool::mcp::config::{
    McpServerConfig, McpServerStartupMode, McpServerTransport, validate_mcp_identifier,
};
use serde::{Deserialize, Serialize};

use super::mcp::{
    ZHIPU_READER_MCP_ID, ZHIPU_SEARCH_MCP_ID, ZHIPU_VISION_MCP_ID, ZHIPU_ZREAD_MCP_ID,
    builtin_mcp_server_ids, is_builtin_mcp_server_id,
};

pub const MCP_DOCUMENT_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct McpFileV1 {
    pub schema_version: u32,
    pub id: String,
    pub spec: McpFileSpecV1,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum McpFileSpecV1 {
    Server(Box<McpServerConfig>),
    Builtin {
        enabled: bool,
        required: bool,
        builtin_id: String,
        cwd: Option<String>,
    },
    Disabled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StdioServerWire {
    schema_version: i64,
    id: String,
    kind: String,
    #[serde(default = "default_true")]
    enabled: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    required: bool,
    transport: McpServerTransport,
    #[serde(default, skip_serializing_if = "McpServerStartupMode::is_default")]
    startup_mode: McpServerStartupMode,
    command: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    args: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    env: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cwd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    startup_timeout_secs: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    tool_timeout_secs: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    enabled_tools: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    disabled_tools: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct StreamableHttpServerWire {
    schema_version: i64,
    id: String,
    kind: String,
    #[serde(default = "default_true")]
    enabled: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    required: bool,
    transport: McpServerTransport,
    #[serde(default, skip_serializing_if = "McpServerStartupMode::is_default")]
    startup_mode: McpServerStartupMode,
    url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    bearer_token_env_var: Option<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    headers: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    startup_timeout_secs: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    tool_timeout_secs: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    enabled_tools: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    disabled_tools: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct BuiltinDocWire {
    schema_version: i64,
    id: String,
    kind: String,
    #[serde(default = "default_true")]
    enabled: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    required: bool,
    builtin_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cwd: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct DisabledDocWire {
    schema_version: i64,
    id: String,
    kind: String,
}

impl McpFileV1 {
    pub fn new_server(id: impl Into<String>, config: McpServerConfig) -> Self {
        Self {
            schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
            id: id.into(),
            spec: McpFileSpecV1::Server(Box::new(config)),
        }
    }

    pub fn new_builtin(id: impl Into<String>, enabled: bool, cwd: Option<String>) -> Self {
        let id = id.into();
        Self {
            schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
            id: id.clone(),
            spec: McpFileSpecV1::Builtin {
                enabled,
                required: false,
                builtin_id: id,
                cwd,
            },
        }
    }

    pub fn new_disabled(id: impl Into<String>) -> Self {
        Self {
            schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
            id: id.into(),
            spec: McpFileSpecV1::Disabled,
        }
    }

    pub fn default_host_builtins() -> Vec<Self> {
        builtin_mcp_server_ids()
            .into_iter()
            .map(|builtin_id| Self {
                schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
                id: builtin_id.to_owned(),
                spec: McpFileSpecV1::Builtin {
                    enabled: true,
                    required: false,
                    builtin_id: builtin_id.to_owned(),
                    cwd: None,
                },
            })
            .collect()
    }

    /// Best-effort extraction of `id` from raw TOML so diagnostics can report the target id.
    pub fn peek_id(raw_toml: &str) -> Option<String> {
        let table: toml::Table = toml::from_str(raw_toml).ok()?;
        let id = table.get("id")?.as_str()?.trim();
        if id.is_empty() {
            None
        } else {
            Some(id.to_owned())
        }
    }

    pub fn parse_and_validate(raw_toml: &str, scope: &McpScope) -> Result<Self> {
        let value: toml::Value = toml::from_str(raw_toml)
            .map_err(|error| PureError::ConfigError(format!("invalid MCP TOML: {error}")))?;
        let table = value
            .as_table()
            .ok_or_else(|| PureError::ConfigError("MCP document root must be a table".into()))?;

        let version = table
            .get("schema_version")
            .and_then(toml::Value::as_integer)
            .ok_or_else(|| {
                PureError::ConfigError("MCP document requires integer schema_version = 1".into())
            })?;
        if version != i64::from(MCP_DOCUMENT_SCHEMA_VERSION) {
            return Err(PureError::ConfigError(format!(
                "unsupported MCP document schema_version {version} (expected {MCP_DOCUMENT_SCHEMA_VERSION})"
            )));
        }

        let id = table
            .get("id")
            .and_then(toml::Value::as_str)
            .ok_or_else(|| {
                PureError::ConfigError("MCP document requires string field 'id'".into())
            })?
            .to_owned();
        validate_mcp_identifier(&id, "MCP server id")?;

        let kind = table
            .get("kind")
            .and_then(toml::Value::as_str)
            .ok_or_else(|| {
                PureError::ConfigError(
                    "MCP document requires field 'kind' (\"server\", \"builtin\", or \"disabled\")"
                        .into(),
                )
            })?
            .to_owned();

        let doc = match kind.as_str() {
            "server" => {
                let transport = table
                    .get("transport")
                    .and_then(toml::Value::as_str)
                    .ok_or_else(|| {
                        PureError::ConfigError(format!(
                            "mcp server '{id}': field 'transport' (\"stdio\" or \"streamableHttp\") is required"
                        ))
                    })?
                    .to_owned();
                let config = match transport.as_str() {
                    "stdio" => {
                        let wire: StdioServerWire = value.try_into().map_err(|error| {
                            PureError::ConfigError(format!("mcp server '{id}': {error}"))
                        })?;
                        McpServerConfig {
                            enabled: wire.enabled,
                            required: wire.required,
                            transport: McpServerTransport::Stdio,
                            startup_mode: wire.startup_mode,
                            command: Some(wire.command),
                            args: wire.args,
                            env: wire.env,
                            cwd: wire.cwd,
                            url: None,
                            bearer_token_env_var: None,
                            headers: BTreeMap::new(),
                            startup_timeout_secs: wire.startup_timeout_secs,
                            tool_timeout_secs: wire.tool_timeout_secs,
                            enabled_tools: wire.enabled_tools,
                            disabled_tools: wire.disabled_tools,
                        }
                    }
                    "streamableHttp" => {
                        let wire: StreamableHttpServerWire = value.try_into().map_err(|error| {
                            PureError::ConfigError(format!("mcp server '{id}': {error}"))
                        })?;
                        McpServerConfig {
                            enabled: wire.enabled,
                            required: wire.required,
                            transport: McpServerTransport::StreamableHttp,
                            startup_mode: wire.startup_mode,
                            command: None,
                            args: Vec::new(),
                            env: BTreeMap::new(),
                            cwd: None,
                            url: Some(wire.url),
                            bearer_token_env_var: wire.bearer_token_env_var,
                            headers: wire.headers,
                            startup_timeout_secs: wire.startup_timeout_secs,
                            tool_timeout_secs: wire.tool_timeout_secs,
                            enabled_tools: wire.enabled_tools,
                            disabled_tools: wire.disabled_tools,
                        }
                    }
                    other => {
                        return Err(PureError::ConfigError(format!(
                            "mcp server '{id}': unknown transport '{other}'"
                        )));
                    }
                };
                Self {
                    schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
                    id,
                    spec: McpFileSpecV1::Server(Box::new(config)),
                }
            }
            "builtin" => {
                let wire: BuiltinDocWire = value.try_into().map_err(|error| {
                    PureError::ConfigError(format!("mcp builtin '{id}': {error}"))
                })?;
                Self {
                    schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
                    id: wire.id,
                    spec: McpFileSpecV1::Builtin {
                        enabled: wire.enabled,
                        required: wire.required,
                        builtin_id: wire.builtin_id,
                        cwd: wire.cwd,
                    },
                }
            }
            "disabled" => {
                let wire: DisabledDocWire = value.try_into().map_err(|error| {
                    PureError::ConfigError(format!("mcp disabled '{id}': {error}"))
                })?;
                Self {
                    schema_version: MCP_DOCUMENT_SCHEMA_VERSION,
                    id: wire.id,
                    spec: McpFileSpecV1::Disabled,
                }
            }
            other => {
                return Err(PureError::ConfigError(format!(
                    "mcp document '{id}': unknown kind '{other}'"
                )));
            }
        };

        doc.validate(scope)?;
        Ok(doc)
    }

    pub fn validate(&self, scope: &McpScope) -> Result<()> {
        if self.schema_version != MCP_DOCUMENT_SCHEMA_VERSION {
            return Err(PureError::ConfigError(format!(
                "unsupported MCP document schema_version {}",
                self.schema_version
            )));
        }
        validate_mcp_identifier(&self.id, "MCP server id")?;

        match &self.spec {
            McpFileSpecV1::Server(config) => {
                validate_server_config_strict(&self.id, config)?;
            }
            McpFileSpecV1::Builtin {
                builtin_id, cwd, ..
            } => {
                if !is_builtin_mcp_server_id(builtin_id) {
                    return Err(PureError::ConfigError(format!(
                        "unknown built-in mcp server id '{builtin_id}'"
                    )));
                }
                if self.id != *builtin_id {
                    return Err(PureError::ConfigError(format!(
                        "built-in mcp document id '{}' must match builtin_id '{builtin_id}'",
                        self.id
                    )));
                }
                if let Some(cwd_val) = cwd {
                    if builtin_id != ZHIPU_VISION_MCP_ID {
                        return Err(PureError::ConfigError(format!(
                            "built-in HTTP mcp server '{builtin_id}' does not accept 'cwd'"
                        )));
                    }
                    if cwd_val.trim().is_empty() {
                        return Err(PureError::ConfigError(format!(
                            "mcp server '{}': cwd must not be empty when specified",
                            self.id
                        )));
                    }
                }
            }
            McpFileSpecV1::Disabled => {
                if matches!(scope, McpScope::Host) {
                    return Err(PureError::ConfigError(format!(
                        "mcp server '{}': kind = \"disabled\" tombstone is only allowed in SSH scope",
                        self.id
                    )));
                }
            }
        }
        Ok(())
    }

    pub fn encode(&self) -> Result<String> {
        let content = match &self.spec {
            McpFileSpecV1::Server(config) => match config.transport {
                McpServerTransport::Stdio => {
                    let wire = StdioServerWire {
                        schema_version: i64::from(self.schema_version),
                        id: self.id.clone(),
                        kind: "server".to_owned(),
                        enabled: config.enabled,
                        required: config.required,
                        transport: McpServerTransport::Stdio,
                        startup_mode: config.startup_mode,
                        command: config.command.clone().unwrap_or_default(),
                        args: config.args.clone(),
                        env: config.env.clone(),
                        cwd: config.cwd.clone(),
                        startup_timeout_secs: config.startup_timeout_secs,
                        tool_timeout_secs: config.tool_timeout_secs,
                        enabled_tools: config.enabled_tools.clone(),
                        disabled_tools: config.disabled_tools.clone(),
                    };
                    toml::to_string_pretty(&wire)
                }
                McpServerTransport::StreamableHttp => {
                    let wire = StreamableHttpServerWire {
                        schema_version: i64::from(self.schema_version),
                        id: self.id.clone(),
                        kind: "server".to_owned(),
                        enabled: config.enabled,
                        required: config.required,
                        transport: McpServerTransport::StreamableHttp,
                        startup_mode: config.startup_mode,
                        url: config.url.clone().unwrap_or_default(),
                        bearer_token_env_var: config.bearer_token_env_var.clone(),
                        headers: config.headers.clone(),
                        startup_timeout_secs: config.startup_timeout_secs,
                        tool_timeout_secs: config.tool_timeout_secs,
                        enabled_tools: config.enabled_tools.clone(),
                        disabled_tools: config.disabled_tools.clone(),
                    };
                    toml::to_string_pretty(&wire)
                }
            },
            McpFileSpecV1::Builtin {
                enabled,
                required,
                builtin_id,
                cwd,
            } => {
                let wire = BuiltinDocWire {
                    schema_version: i64::from(self.schema_version),
                    id: self.id.clone(),
                    kind: "builtin".to_owned(),
                    enabled: *enabled,
                    required: *required,
                    builtin_id: builtin_id.clone(),
                    cwd: cwd.clone(),
                };
                toml::to_string_pretty(&wire)
            }
            McpFileSpecV1::Disabled => {
                let wire = DisabledDocWire {
                    schema_version: i64::from(self.schema_version),
                    id: self.id.clone(),
                    kind: "disabled".to_owned(),
                };
                toml::to_string_pretty(&wire)
            }
        }
        .map_err(|error| PureError::ConfigError(format!("failed to encode MCP TOML: {error}")))?;
        Ok(content)
    }
}

/// Validates a `kind = "server"` configuration strictly regardless of `enabled`.
pub fn validate_server_config_strict(server_id: &str, config: &McpServerConfig) -> Result<()> {
    validate_mcp_identifier(server_id, "MCP server id")?;
    if let Some(cwd) = config.cwd.as_deref()
        && cwd.trim().is_empty()
    {
        return Err(PureError::ConfigError(format!(
            "mcp server '{server_id}': cwd must not be empty when specified"
        )));
    }
    match config.transport {
        McpServerTransport::Stdio => {
            if config.url.is_some()
                || config.bearer_token_env_var.is_some()
                || !config.headers.is_empty()
            {
                return Err(PureError::ConfigError(format!(
                    "mcp server '{server_id}': stdio transport cannot specify HTTP fields (url, headers, bearer_token_env_var)"
                )));
            }
        }
        McpServerTransport::StreamableHttp => {
            if config.command.is_some()
                || !config.args.is_empty()
                || !config.env.is_empty()
                || config.cwd.is_some()
            {
                return Err(PureError::ConfigError(format!(
                    "mcp server '{server_id}': streamableHttp transport cannot specify stdio fields (command, args, env, cwd)"
                )));
            }
        }
    }
    if let Some(enabled) = &config.enabled_tools {
        for tool in enabled {
            if tool.trim().is_empty() {
                return Err(PureError::ConfigError(format!(
                    "mcp server '{server_id}': enabled_tools must not contain empty tool names"
                )));
            }
        }
    }
    for tool in &config.disabled_tools {
        if tool.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "mcp server '{server_id}': disabled_tools must not contain empty tool names"
            )));
        }
    }
    // Validate required endpoint/command/timeouts even when `enabled = false`.
    let mut enabled_copy = config.clone();
    enabled_copy.enabled = true;
    enabled_copy.validate(server_id)
}

fn default_true() -> bool {
    true
}

fn is_false(value: &bool) -> bool {
    !value
}

pub const ALL_BUILTIN_IDS: [&str; 4] = [
    ZHIPU_SEARCH_MCP_ID,
    ZHIPU_READER_MCP_ID,
    ZHIPU_ZREAD_MCP_ID,
    ZHIPU_VISION_MCP_ID,
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn startup_mode_round_trips_for_both_transports_and_defaults_to_auto() {
        for fields in [
            "transport = \"stdio\"\ncommand = \"mcp-server\"\n",
            "transport = \"streamableHttp\"\nurl = \"https://example.com/mcp\"\n",
        ] {
            let base = format!("schema_version = 1\nid = \"probe\"\nkind = \"server\"\n{fields}");
            for (mode, expected) in [
                ("", McpServerStartupMode::Auto),
                ("auto", McpServerStartupMode::Auto),
                ("initialize", McpServerStartupMode::Initialize),
                ("discover", McpServerStartupMode::Discover),
            ] {
                let raw = if mode.is_empty() {
                    base.clone()
                } else {
                    format!("{base}startup_mode = \"{mode}\"\n")
                };
                let parsed = McpFileV1::parse_and_validate(&raw, &McpScope::Host).unwrap();
                let McpFileSpecV1::Server(config) = &parsed.spec else {
                    panic!("expected custom server");
                };
                assert_eq!(config.startup_mode, expected);
                let encoded = parsed.encode().unwrap();
                assert_eq!(
                    encoded.contains("startup_mode"),
                    expected != McpServerStartupMode::Auto
                );
                assert_eq!(
                    parsed,
                    McpFileV1::parse_and_validate(&encoded, &McpScope::Host).unwrap()
                );
            }
            for enabled in [true, false] {
                let invalid = format!("{base}enabled = {enabled}\nstartup_mode = \"automatic\"\n");
                assert!(McpFileV1::parse_and_validate(&invalid, &McpScope::Host).is_err());
            }
        }
    }

    #[test]
    fn required_round_trips_for_server_transports_and_builtin() {
        let host = McpScope::Host;
        for (id, transport_fields) in [
            (
                "required_stdio",
                "transport = \"stdio\"\ncommand = \"mcp-server\"\n",
            ),
            (
                "required_http",
                "transport = \"streamableHttp\"\nurl = \"https://example.com/mcp\"\n",
            ),
        ] {
            let raw = format!(
                "schema_version = 1\nid = \"{id}\"\nkind = \"server\"\nrequired = true\n{transport_fields}"
            );
            let parsed = McpFileV1::parse_and_validate(&raw, &host).unwrap();
            let encoded = parsed.encode().unwrap();
            let reparsed = McpFileV1::parse_and_validate(&encoded, &host).unwrap();
            assert_eq!(parsed, reparsed);
            assert!(encoded.contains("required = true"));
        }

        let builtin_raw = format!(
            "schema_version = 1\nid = \"{}\"\nkind = \"builtin\"\nrequired = true\nbuiltin_id = \"{}\"\n",
            ZHIPU_SEARCH_MCP_ID, ZHIPU_SEARCH_MCP_ID
        );
        let builtin = McpFileV1::parse_and_validate(&builtin_raw, &host).unwrap();
        let encoded = builtin.encode().unwrap();
        let reparsed = McpFileV1::parse_and_validate(&encoded, &host).unwrap();
        assert_eq!(builtin, reparsed);
        assert!(encoded.contains("required = true"));

        for (id, raw) in [
            (
                "legacy_stdio",
                "schema_version = 1\nid = \"legacy_stdio\"\nkind = \"server\"\ntransport = \"stdio\"\ncommand = \"mcp-server\"\n",
            ),
            (
                ZHIPU_SEARCH_MCP_ID,
                "schema_version = 1\nid = \"zhipu_search\"\nkind = \"builtin\"\nbuiltin_id = \"zhipu_search\"\n",
            ),
        ] {
            let legacy = McpFileV1::parse_and_validate(raw, &host).unwrap();
            let encoded = legacy.encode().unwrap();
            assert!(!encoded.contains("required"));
            match legacy.spec {
                McpFileSpecV1::Server(config) => assert!(!config.required),
                McpFileSpecV1::Builtin { required, .. } => assert!(!required),
                _ => panic!("unexpected MCP spec for {id}"),
            }
        }
    }
}
