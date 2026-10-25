//! Embedded declarations shared by root Agent selection and the child Profile view.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Component, Path};
use std::sync::OnceLock;

use pl_protocol::{AgentWorkspaceMode, PureError};
use rust_embed::Embed;
use serde::{Deserialize, Serialize};

use super::definition::{
    AgentDefinitionIdentity, AgentDefinitionOrigin, AgentDefinitionScope, AgentRootEntry,
    AgentUsageBinding,
};

#[derive(Embed)]
#[folder = "assets/agents/"]
struct BundledAgents;

static CATALOG: OnceLock<std::result::Result<Vec<BuiltinAgentDefinition>, AgentCatalogError>> =
    OnceLock::new();

/// Typed product-resource failure; startup must not treat this as damaged user data.
#[derive(Debug, Clone, thiserror::Error)]
#[error("invalid bundled Agent declarations: {message}")]
pub(crate) struct AgentCatalogError {
    message: String,
}

impl AgentCatalogError {
    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

/// An immutable product declaration. Usage scope is independent of its builtin origin.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BuiltinAgentDefinition {
    pub identity: AgentDefinitionIdentity,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub instructions: String,
    pub workspace_mode: Option<AgentWorkspaceMode>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
struct Declaration {
    id: String,
    scope: DeclarationScope,
    #[serde(default)]
    entry: Option<AgentRootEntry>,
    display_name: String,
    description: String,
    when_to_use: String,
    instructions: String,
    #[serde(default)]
    workspace_mode: Option<AgentWorkspaceMode>,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum DeclarationScope {
    Root,
    Child,
}

/// Returns the validated embedded catalog. The first caller publishes either the complete
/// immutable catalog or its error; no caller can observe a partially loaded declaration set.
pub(crate) fn definitions() -> Result<&'static [BuiltinAgentDefinition], PureError> {
    definitions_typed().map_err(|error| PureError::ConfigError(error.to_string()))
}

pub(crate) fn definition(id: &str) -> Result<Option<&'static BuiltinAgentDefinition>, PureError> {
    Ok(definitions()?
        .iter()
        .find(|definition| definition.identity.id == id))
}

pub(crate) fn child_ids() -> Result<BTreeSet<String>, PureError> {
    Ok(definitions()?
        .iter()
        .filter(|definition| definition.identity.scope == AgentDefinitionScope::Child)
        .map(|definition| definition.identity.id.clone())
        .collect())
}

/// Validates product-required root entries before configuration recovery or publication starts.
pub(crate) fn validate_startup_entries() -> Result<(), AgentCatalogError> {
    let definitions = definitions_typed()?;
    for entry in [AgentRootEntry::Studio, AgentRootEntry::Bot] {
        let count = definitions
            .iter()
            .filter(|definition| {
                definition.identity.usage_binding == AgentUsageBinding::RootEntry(entry)
            })
            .count();
        if count != 1 {
            return Err(AgentCatalogError::invalid(format!(
                "trusted product entry `{entry:?}` resolves to {count} root declarations; expected exactly one"
            )));
        }
    }
    Ok(())
}

pub(crate) fn root_definition(
    entry: AgentRootEntry,
) -> Result<&'static BuiltinAgentDefinition, PureError> {
    definitions()?
        .iter()
        .find(|definition| definition.identity.usage_binding == AgentUsageBinding::RootEntry(entry))
        .ok_or_else(|| {
            PureError::ConfigError(format!(
                "trusted product entry `{entry:?}` has no bundled root Agent declaration"
            ))
        })
}

fn definitions_typed() -> Result<&'static [BuiltinAgentDefinition], AgentCatalogError> {
    match CATALOG
        .get_or_init(|| load().map_err(|error| AgentCatalogError::invalid(format!("{error:#}"))))
    {
        Ok(definitions) => Ok(definitions),
        Err(error) => Err(error.clone()),
    }
}

fn load() -> anyhow::Result<Vec<BuiltinAgentDefinition>> {
    let mut resources = BTreeMap::new();
    let mut paths = BundledAgents::iter().collect::<Vec<_>>();
    paths.sort_unstable();
    for path in paths {
        let asset = BundledAgents::get(&path)
            .ok_or_else(|| anyhow::anyhow!("embedded Agent resource disappeared: {path}"))?;
        let contents = asset.data.into_owned();
        match Path::new(path.as_ref())
            .extension()
            .and_then(|value| value.to_str())
        {
            Some("toml" | "md") => {
                resources.insert(path.to_string(), contents);
            }
            _ => anyhow::bail!("unsupported embedded Agent resource: {path}"),
        }
    }

    let mut definitions = Vec::new();
    let mut ids = BTreeSet::new();
    for (path, bytes) in resources.iter().filter(|(path, _)| path.ends_with(".toml")) {
        let text = std::str::from_utf8(bytes)
            .map_err(|_| anyhow::anyhow!("Agent declaration is not UTF-8: {path}"))?;
        let declaration: Declaration = toml::from_str(text)
            .map_err(|error| anyhow::anyhow!("invalid Agent declaration {path}: {error}"))?;
        validate_declaration(&declaration, path)?;
        if !ids.insert(declaration.id.clone()) {
            anyhow::bail!("duplicate bundled Agent id `{}`", declaration.id);
        }
        let instruction_path = validate_instruction_path(&declaration.instructions)?;
        let instruction_bytes = resources.get(instruction_path).ok_or_else(|| {
            anyhow::anyhow!(
                "Agent `{}` references missing instruction resource `{instruction_path}`",
                declaration.id
            )
        })?;
        let instructions = std::str::from_utf8(instruction_bytes)
            .map_err(|_| anyhow::anyhow!("Agent instructions are not UTF-8: {instruction_path}"))?
            .trim()
            .to_owned();
        if instructions.is_empty() {
            anyhow::bail!("Agent `{}` has empty instructions", declaration.id);
        }
        let revision = content_revision(&declaration, &instructions)?;
        let usage_binding = match (declaration.scope, declaration.entry) {
            (DeclarationScope::Root, Some(entry)) => AgentUsageBinding::RootEntry(entry),
            (DeclarationScope::Child, None) => AgentUsageBinding::Child,
            _ => anyhow::bail!("invalid Agent usage binding in {path}"),
        };
        let identity = AgentDefinitionIdentity {
            id: declaration.id,
            scope: declaration.scope.into(),
            usage_binding,
            revision,
            origin: AgentDefinitionOrigin::Builtin,
        };
        definitions.push(BuiltinAgentDefinition {
            identity,
            display_name: declaration.display_name,
            description: declaration.description,
            when_to_use: declaration.when_to_use,
            instructions,
            workspace_mode: declaration.workspace_mode,
        });
    }
    if definitions.is_empty() {
        anyhow::bail!("embedded Agent declaration catalog is empty");
    }
    definitions.sort_by(|left, right| left.identity.id.cmp(&right.identity.id));
    Ok(definitions)
}

fn validate_declaration(declaration: &Declaration, path: &str) -> anyhow::Result<()> {
    let id_valid = match declaration.scope {
        DeclarationScope::Root => declaration
            .id
            .strip_prefix("root:")
            .is_some_and(valid_agent_id),
        DeclarationScope::Child => {
            declaration.id != crate::config::ROOT_AGENT_ROUTE_KEY && valid_agent_id(&declaration.id)
        }
    };
    if !id_valid {
        anyhow::bail!("Agent declaration {path} has an invalid id for its scope");
    }
    match (declaration.scope, declaration.entry) {
        (DeclarationScope::Root, Some(_)) | (DeclarationScope::Child, None) => {}
        (DeclarationScope::Root, None) => {
            anyhow::bail!("root Agent declaration {path} must bind one trusted product entry")
        }
        (DeclarationScope::Child, Some(_)) => {
            anyhow::bail!("child Agent declaration {path} cannot bind a root product entry")
        }
    }
    for (field, value) in [
        ("display_name", declaration.display_name.as_str()),
        ("description", declaration.description.as_str()),
        ("when_to_use", declaration.when_to_use.as_str()),
    ] {
        if value.trim().is_empty() {
            anyhow::bail!("Agent declaration {path} has empty {field}");
        }
    }
    match (declaration.scope, declaration.workspace_mode) {
        (DeclarationScope::Root, None) | (DeclarationScope::Child, Some(_)) => Ok(()),
        (DeclarationScope::Root, Some(_)) => {
            anyhow::bail!("root Agent declaration {path} cannot define a child workspace mode")
        }
        (DeclarationScope::Child, None) => {
            anyhow::bail!("child Agent declaration {path} must define a workspace mode")
        }
    }
}

fn validate_instruction_path(path: &str) -> anyhow::Result<&str> {
    if path.is_empty() || path.contains('\\') || path.contains(':') || Path::new(path).is_absolute()
    {
        anyhow::bail!("Agent instruction path is not a normalized relative path");
    }
    if Path::new(path)
        .components()
        .any(|component| !matches!(component, Component::Normal(_)))
    {
        anyhow::bail!("Agent instruction path is not a normalized relative path");
    }
    if !path.starts_with("prompts/") || !path.ends_with(".md") {
        anyhow::bail!("Agent instructions must reference a Markdown file below prompts/");
    }
    Ok(path)
}

fn valid_agent_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        })
}

fn content_revision(declaration: &Declaration, instructions: &str) -> anyhow::Result<String> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Revision<'a> {
        id: &'a str,
        scope: DeclarationScope,
        entry: Option<AgentRootEntry>,
        display_name: &'a str,
        description: &'a str,
        when_to_use: &'a str,
        instructions: &'a str,
        workspace_mode: Option<AgentWorkspaceMode>,
    }
    let revision = Revision {
        id: &declaration.id,
        scope: declaration.scope,
        entry: declaration.entry,
        display_name: &declaration.display_name,
        description: &declaration.description,
        when_to_use: &declaration.when_to_use,
        instructions,
        workspace_mode: declaration.workspace_mode,
    };
    Ok(pl_core::context::content_hash(&serde_json::to_vec(
        &revision,
    )?))
}

impl From<DeclarationScope> for AgentDefinitionScope {
    fn from(scope: DeclarationScope) -> Self {
        match scope {
            DeclarationScope::Root => Self::Root,
            DeclarationScope::Child => Self::Child,
        }
    }
}
