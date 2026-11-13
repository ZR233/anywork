//! Skill discovery options supplied by the host. This module performs no persistence.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Immutable host policy, never serialized into the user's SkillsConfig.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SkillSearchOptions {
    pub include_default_user_dir: bool,
    pub additional_dirs: Vec<PathBuf>,
}

impl Default for SkillSearchOptions {
    fn default() -> Self {
        Self {
            include_default_user_dir: true,
            additional_dirs: Vec::new(),
        }
    }
}

impl SkillSearchOptions {
    /// Resolves explicit collection roots against the original host cwd and keeps the first duplicate.
    pub fn resolve(
        include_default_user_dir: bool,
        directories: impl IntoIterator<Item = PathBuf>,
        startup_cwd: &Path,
    ) -> pl_protocol::Result<Self> {
        let mut additional_dirs = Vec::new();
        for directory in directories {
            let expanded = match directory.to_str() {
                Some(text) => super::util::expand_home(text)?,
                None => directory,
            };
            let resolved = crate::workspace::resolve_absolute_path(startup_cwd, &expanded)?;
            super::util::validate_explicit_skill_directory(&resolved)?;
            if !additional_dirs.contains(&resolved) {
                additional_dirs.push(resolved);
            }
        }
        Ok(Self {
            include_default_user_dir,
            additional_dirs,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct SkillsConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub auto_learn: bool,
    #[serde(default)]
    pub system: SystemSkillsConfig,
    #[serde(default = "default_project_skills_dir")]
    pub project_dir: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub external_dirs: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub disabled: Vec<String>,
    #[serde(default = "default_auto_learn_min_tool_calls")]
    pub auto_learn_min_tool_calls: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SystemSkillsConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
}

impl Default for SkillsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            auto_learn: true,
            system: SystemSkillsConfig::default(),
            project_dir: default_project_skills_dir(),
            external_dirs: Vec::new(),
            disabled: Vec::new(),
            auto_learn_min_tool_calls: default_auto_learn_min_tool_calls(),
        }
    }
}

impl Default for SystemSkillsConfig {
    fn default() -> Self {
        Self { enabled: true }
    }
}

impl SkillsConfig {
    pub fn is_default(&self) -> bool {
        self == &Self::default()
    }
}

fn default_true() -> bool {
    true
}

fn default_project_skills_dir() -> String {
    ".agents/skills".to_string()
}

fn default_auto_learn_min_tool_calls() -> u32 {
    5
}
