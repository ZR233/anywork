//! User-level ACP definitions. Only this document boundary decodes launch settings.
use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::{PureError, Result};

pub const ACP_DOCUMENT_SCHEMA_VERSION: u32 = 1;
pub const MAX_ACP_NAME_BYTES: usize = 200;

/// A managed launch template, not a whitelist of ACP protocol implementations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AcpProvider {
    Antigravity,
}

impl AcpProvider {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Antigravity => "antigravity",
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub enum AcpLaunch {
    Command { command: String, args: Vec<String> },
    Template(AcpProvider),
}

/// Immutable desired launch values. Resolved executable paths never enter this document.
#[derive(Clone, PartialEq, Eq)]
pub struct AcpServiceDefinition {
    pub id: String,
    pub display_name: String,
    pub enabled: bool,
    pub launch: AcpLaunch,
    pub env: BTreeMap<String, String>,
}

impl std::fmt::Debug for AcpServiceDefinition {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AcpServiceDefinition")
            .field("id", &self.id)
            .field("enabled", &self.enabled)
            .finish_non_exhaustive()
    }
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    schema_version: u32,
    id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
    #[serde(default = "enabled")]
    enabled: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    command: Option<String>,
    // Option distinguishes an explicitly supplied empty args from an absent field.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    args: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    template: Option<AcpProvider>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    env: BTreeMap<String, String>,
}

const fn enabled() -> bool {
    true
}

pub fn validate_acp_account_id(id: &str) -> Result<()> {
    if id.is_empty()
        || matches!(id, "." | "..")
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
    {
        return Err(invalid(
            "ACP id must contain only ASCII letters, digits, '-', '_' or '.', and cannot be empty, '.' or '..'",
        ));
    }
    Ok(())
}

pub fn validate_acp_name(name: &str) -> Result<()> {
    if name.trim().is_empty()
        || name.len() > MAX_ACP_NAME_BYTES
        || name.chars().any(char::is_control)
    {
        return Err(invalid(
            "ACP display name must be nonempty, bounded and contain no control characters",
        ));
    }
    Ok(())
}

fn invalid(message: &str) -> PureError {
    PureError::ConfigError(message.into())
}

impl AcpServiceDefinition {
    pub fn template(id: String, display_name: String, template: AcpProvider) -> Self {
        Self {
            id,
            display_name,
            enabled: true,
            launch: AcpLaunch::Template(template),
            env: BTreeMap::new(),
        }
    }

    pub fn template_kind(&self) -> Option<AcpProvider> {
        match self.launch {
            AcpLaunch::Template(template) => Some(template),
            AcpLaunch::Command { .. } => None,
        }
    }

    pub fn validate(&self) -> Result<()> {
        validate_acp_account_id(&self.id)?;
        validate_acp_name(&self.display_name)?;
        if let AcpLaunch::Command { command, args } = &self.launch {
            let path = Path::new(command);
            if command.is_empty()
                || command.contains('\0')
                || (!path.is_absolute()
                    && (command.contains('/')
                        || command.contains('\\')
                        || matches!(command.as_str(), "." | "..")))
                || args.iter().any(|arg| arg.contains('\0'))
            {
                return Err(invalid(
                    "ACP command must be a PATH program name or absolute path, with NUL-free arguments",
                ));
            }
        }
        if self
            .env
            .iter()
            .any(|(key, value)| key.is_empty() || key.contains(['=', '\0']) || value.contains('\0'))
        {
            return Err(invalid(
                "ACP environment contains an invalid key or NUL value",
            ));
        }
        Ok(())
    }

    /// Safe decoding: never expose TOML parser snippets or environment values.
    pub fn decode(content: &str, filename_id: &str) -> Result<Self> {
        let document: Document = toml::from_str(content)
            .map_err(|_| invalid("invalid ACP TOML structure, field type or unknown field"))?;
        if document.schema_version != ACP_DOCUMENT_SCHEMA_VERSION {
            return Err(invalid("unsupported ACP document schema_version"));
        }
        if document.id != filename_id {
            return Err(invalid("ACP document id does not match its filename"));
        }
        let launch = match (document.command, document.args, document.template) {
            (Some(command), args, None) => AcpLaunch::Command {
                command,
                args: args.unwrap_or_default(),
            },
            (None, None, Some(template)) => AcpLaunch::Template(template),
            _ => {
                return Err(invalid(
                    "ACP requires command or template exclusively; template cannot specify args",
                ));
            }
        };
        let definition = Self {
            display_name: document.display_name.unwrap_or_else(|| document.id.clone()),
            id: document.id,
            enabled: document.enabled,
            launch,
            env: document.env,
        };
        definition.validate()?;
        Ok(definition)
    }

    pub fn encode(&self) -> Result<String> {
        self.validate()?;
        let (command, args, template) = match &self.launch {
            AcpLaunch::Command { command, args } => {
                (Some(command.clone()), Some(args.clone()), None)
            }
            AcpLaunch::Template(template) => (None, None, Some(*template)),
        };
        toml::to_string_pretty(&Document {
            schema_version: ACP_DOCUMENT_SCHEMA_VERSION,
            id: self.id.clone(),
            display_name: (self.display_name != self.id).then(|| self.display_name.clone()),
            enabled: self.enabled,
            command,
            args,
            template,
            env: self.env.clone(),
        })
        .map_err(|_| invalid("could not encode ACP definition"))
    }

    pub(crate) fn same_connection(&self, other: &Self) -> bool {
        self.launch == other.launch && self.env == other.env
    }
}
