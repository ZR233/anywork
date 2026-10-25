//! Concrete FRB detail owners over the original immutable Models runtime scopes.
pub mod agent_profiles;
pub mod bot_conversations;
pub mod bots;
pub mod catalog;
pub mod configuration;
pub(crate) mod configuration_command_registry;
pub mod configuration_commands;
pub mod configuration_pages;
pub mod configuration_values;
mod convert;
pub mod delegation_model_values;
pub mod delegation_models;
pub mod model_source_status;
pub mod model_values;
mod owner;
pub mod pages;
pub mod primitives;
pub mod profile_commands;
pub mod profile_values;
pub mod template_values;
pub mod templates;

pub mod mcp;

pub mod lsp;

pub mod skills;

pub mod agent_directory;

pub mod project_directory;

pub mod persistence;
pub mod persistence_queue;
pub mod recovery;
pub mod remote_directory;
pub mod startup;
pub mod thread_directory;

pub mod account_usage;
pub mod modes;
pub mod statistics;
pub mod updates;
