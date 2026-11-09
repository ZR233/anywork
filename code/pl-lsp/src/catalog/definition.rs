use std::collections::BTreeMap;
use std::path::Path;
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use super::collection::LspCatalogServer;
use super::matching::workspace_matches;
use crate::driver::LspResolvedCommand;
use crate::driver::command::CommandDriver;
use crate::query::LspQueryOperation;

const WORKSPACE_ROOT_PLACEHOLDER: &str = "{workspaceRoot}";

/// catalog 中一条 server 的纯数据定义。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LspServerDefinition {
    pub id: String,
    pub display_name: String,
    pub language_ids: Vec<String>,
    pub extensions: Vec<String>,
    pub detection: Vec<String>,
    pub command: LspCommandSpec,
    pub operations: Vec<LspQueryOperation>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "serde_json::Value::is_null")]
    pub initialization_options: serde_json::Value,
    #[serde(default, skip_serializing_if = "serde_json::Value::is_null")]
    pub settings: serde_json::Value,
}

impl LspServerDefinition {
    /// 静态检测当前 workspace 是否适用该 server；只做文件系统检查。
    pub fn matches_workspace(&self, workspace_root: &Path) -> bool {
        workspace_matches(&self.detection, workspace_root)
    }

    /// 与 workspace 无关的定义指纹；用于探测/合并结果的新鲜度判断。
    pub fn fingerprint(&self) -> String {
        serde_json::to_string(self).expect("LSP definition is serializable")
    }
}

/// command 解析：程序与参数模板，`{workspaceRoot}` 会被渲染为 workspace root。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LspCommandSpec {
    pub program: String,
    #[serde(default)]
    pub args: Vec<String>,
}

impl LspCommandSpec {
    pub fn render(&self, workspace_root: &Path) -> LspResolvedCommand {
        let root = workspace_root.display().to_string();
        LspResolvedCommand {
            program: self.program.replace(WORKSPACE_ROOT_PLACEHOLDER, &root),
            args: self
                .args
                .iter()
                .map(|arg| arg.replace(WORKSPACE_ROOT_PLACEHOLDER, &root))
                .collect(),
        }
    }
}

/// 独立服务器文档中的通用配置。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LspUserServerConfig {
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    pub language_ids: Vec<String>,
    #[serde(default)]
    pub detection: Vec<String>,
    #[serde(default)]
    pub extensions: Vec<String>,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default = "all_operations")]
    pub operations: Vec<LspQueryOperation>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
    #[serde(default, skip_serializing_if = "serde_json::Value::is_null")]
    pub initialization_options: serde_json::Value,
    #[serde(default, skip_serializing_if = "serde_json::Value::is_null")]
    pub settings: serde_json::Value,
}

impl Default for LspUserServerConfig {
    fn default() -> Self {
        Self {
            command: String::new(),
            args: Vec::new(),
            language_ids: Vec::new(),
            detection: Vec::new(),
            extensions: Vec::new(),
            display_name: None,
            operations: all_operations(),
            env: BTreeMap::new(),
            initialization_options: serde_json::Value::Null,
            settings: serde_json::Value::Null,
        }
    }
}

impl LspUserServerConfig {
    /// 转换为 catalog 条目：自定义 server 绑定通用命令 driver。
    pub fn to_catalog_server(&self, id: &str) -> LspCatalogServer {
        LspCatalogServer {
            definition: LspServerDefinition {
                id: id.to_string(),
                display_name: self.display_name.clone().unwrap_or_else(|| id.to_string()),
                language_ids: self.language_ids.clone(),
                extensions: self
                    .extensions
                    .iter()
                    .map(|extension| {
                        format!(
                            ".{}",
                            extension.trim_start_matches('.').to_ascii_lowercase()
                        )
                    })
                    .collect(),
                detection: self.detection.clone(),
                command: LspCommandSpec {
                    program: self.command.clone(),
                    args: self.args.clone(),
                },
                operations: self.operations.clone(),
                env: self.env.clone(),
                initialization_options: self.initialization_options.clone(),
                settings: self.settings.clone(),
            },
            driver: Arc::new(CommandDriver::new(
                self.initialization_options.clone(),
                self.settings.clone(),
            )),
        }
    }

    pub fn validate(&self) -> Result<(), LspDocumentError> {
        if self.command.trim().is_empty() || self.command.contains('\0') {
            return Err(LspDocumentError::Invalid(
                "command must be nonempty and contain no NUL".into(),
            ));
        }
        if self.language_ids.is_empty() || self.language_ids.iter().any(|id| id.trim().is_empty()) {
            return Err(LspDocumentError::Invalid(
                "language_ids must contain nonempty language IDs".into(),
            ));
        }
        if self.detection.iter().any(|rule| {
            rule.is_empty() || rule == "." || rule == ".." || rule.contains(['/', '\\', '\0'])
        }) {
            return Err(LspDocumentError::Invalid(
                "detection must contain workspace filenames or single-segment globs".into(),
            ));
        }
        if self
            .env
            .iter()
            .any(|(key, value)| key.is_empty() || key.contains(['=', '\0']) || value.contains('\0'))
            || self.args.iter().any(|arg| arg.contains('\0'))
        {
            return Err(LspDocumentError::Invalid(
                "invalid process argument or environment entry".into(),
            ));
        }
        Ok(())
    }

    pub(crate) fn render(&self, root: &Path) -> Self {
        let mut rendered = self.clone();
        let root = root.to_string_lossy();
        let replace = |text: &str| text.replace(WORKSPACE_ROOT_PLACEHOLDER, &root);
        rendered.command = replace(&self.command);
        rendered.args = self.args.iter().map(|arg| replace(arg)).collect();
        rendered.env = self
            .env
            .iter()
            .map(|(key, value)| (key.clone(), replace(value)))
            .collect();
        render_value(&mut rendered.initialization_options, &root);
        render_value(&mut rendered.settings, &root);
        rendered
    }
}

fn all_operations() -> Vec<LspQueryOperation> {
    LspQueryOperation::all().to_vec()
}

fn render_value(value: &mut serde_json::Value, root: &str) {
    match value {
        serde_json::Value::String(text) => *text = text.replace(WORKSPACE_ROOT_PLACEHOLDER, root),
        serde_json::Value::Array(values) => values
            .iter_mut()
            .for_each(|value| render_value(value, root)),
        serde_json::Value::Object(values) => values
            .values_mut()
            .for_each(|value| render_value(value, root)),
        _ => {}
    }
}

/// 可复用于迁移与执行侧发现的版本化文档。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LspServerDocument {
    pub schema_version: u32,
    pub id: String,
    #[serde(flatten)]
    pub config: LspUserServerConfig,
}

impl<'de> Deserialize<'de> for LspServerDocument {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        use serde::de::Error;
        let mut fields = BTreeMap::<String, serde_json::Value>::deserialize(deserializer)?;
        let schema_version = serde_json::from_value(
            fields
                .remove("schema_version")
                .ok_or_else(|| D::Error::missing_field("schema_version"))?,
        )
        .map_err(D::Error::custom)?;
        let id = serde_json::from_value(
            fields
                .remove("id")
                .ok_or_else(|| D::Error::missing_field("id"))?,
        )
        .map_err(D::Error::custom)?;
        let config =
            serde_json::from_value(serde_json::Value::Object(fields.into_iter().collect()))
                .map_err(D::Error::custom)?;
        Ok(Self {
            schema_version,
            id,
            config,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum LspDocumentError {
    // Never retain the source text: environment/settings may contain secrets.
    #[error("invalid LSP TOML document")]
    Syntax,
    #[error("{0}")]
    Invalid(String),
}

pub fn validate_server_id(id: &str) -> Result<(), LspDocumentError> {
    if id.is_empty()
        || id == "."
        || id == ".."
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
    {
        return Err(LspDocumentError::Invalid("invalid LSP server id".into()));
    }
    Ok(())
}

impl LspServerDocument {
    pub fn parse(source: &str) -> Result<Self, LspDocumentError> {
        // Flatten and deny_unknown_fields cannot be combined in Serde. Validate the
        // top-level table before decoding the flattened public representation.
        let table: toml::Table = toml::from_str(source).map_err(|_| LspDocumentError::Syntax)?;
        const FIELDS: &[&str] = &[
            "schema_version",
            "id",
            "command",
            "args",
            "env",
            "language_ids",
            "extensions",
            "detection",
            "display_name",
            "operations",
            "initialization_options",
            "settings",
        ];
        if table.keys().any(|key| !FIELDS.contains(&key.as_str())) {
            return Err(LspDocumentError::Invalid(
                "unknown LSP document field".into(),
            ));
        }
        let document: Self = toml::from_str(source).map_err(|_| LspDocumentError::Syntax)?;
        document.validate()?;
        Ok(document)
    }

    pub fn validate(&self) -> Result<(), LspDocumentError> {
        if self.schema_version != 1 {
            return Err(LspDocumentError::Invalid(
                "unsupported LSP schema_version (expected 1)".into(),
            ));
        }
        validate_server_id(&self.id)?;
        self.config.validate()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID: &str =
        "schema_version = 1\nid = 'fixture'\ncommand = 'server'\nlanguage_ids = ['fixture']\n";

    #[test]
    fn documents_are_strict_versioned_and_safe_to_diagnose() {
        let document = LspServerDocument::parse(VALID).unwrap();
        assert_eq!(document.config.operations, LspQueryOperation::all());
        assert_eq!(
            document.config.initialization_options,
            serde_json::Value::Null
        );
        for source in [
            VALID.replace("schema_version = 1", "schema_version = 2"),
            VALID.replace("schema_version = 1", "schema_version = 0"),
            VALID.replace("id = 'fixture'", "id = '../fixture'"),
            VALID.replace("command = 'server'", "command = '  '"),
            VALID.replace("language_ids = ['fixture']", "language_ids = []"),
            format!("{VALID}typo = 'private-token'\n"),
            format!("{VALID}detection = ['../Cargo.toml']\n"),
            format!("{VALID}[env]\nSECRET = 9\n"),
            format!("{VALID}args = ['unterminated-private-token\n"),
        ] {
            let error = LspServerDocument::parse(&source).unwrap_err().to_string();
            assert!(!error.contains("private-token"));
        }
        assert!(toml::from_str::<LspServerDocument>(&format!("{VALID}unknown = true")).is_err());
        assert_eq!(
            LspServerDocument::parse(&toml::to_string(&document).unwrap()).unwrap(),
            document
        );
    }

    #[test]
    fn recursive_rendering_and_fingerprints_include_every_configuration_input() {
        let source = format!(
            "{VALID}args = ['{{workspaceRoot}}/arg']\n[env]\nVALUE = '{{workspaceRoot}}/env'\n[initialization_options]\npaths = ['{{workspaceRoot}}/one', {{ nested = '{{workspaceRoot}}/two' }}]\n[settings.fixture]\nroot = '{{workspaceRoot}}/settings'\n"
        );
        let config = LspServerDocument::parse(&source)
            .unwrap()
            .config
            .render(Path::new("/execution"));
        assert_eq!(config.args, ["/execution/arg"]);
        assert_eq!(config.env["VALUE"], "/execution/env");
        assert_eq!(
            config.initialization_options["paths"][1]["nested"],
            "/execution/two"
        );
        assert_eq!(config.settings["fixture"]["root"], "/execution/settings");
        let original = config.to_catalog_server("fixture").definition.fingerprint();
        let mut changed = config.clone();
        changed.command.push('x');
        assert_ne!(
            original,
            changed
                .to_catalog_server("fixture")
                .definition
                .fingerprint()
        );
        let mut changed = config.clone();
        changed.env.insert("VALUE".into(), "new".into());
        assert_ne!(
            original,
            changed
                .to_catalog_server("fixture")
                .definition
                .fingerprint()
        );
        let mut changed = config.clone();
        changed.initialization_options["paths"] = serde_json::json!(["new"]);
        assert_ne!(
            original,
            changed
                .to_catalog_server("fixture")
                .definition
                .fingerprint()
        );
        let mut changed = config.clone();
        changed.settings = serde_json::json!({"new": true});
        assert_ne!(
            original,
            changed
                .to_catalog_server("fixture")
                .definition
                .fingerprint()
        );
        let mut changed = config;
        changed.extensions.push(".new".into());
        assert_ne!(
            original,
            changed
                .to_catalog_server("fixture")
                .definition
                .fingerprint()
        );
    }
}
