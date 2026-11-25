#![recursion_limit = "256"]
#[path = "integration/delegation_models.rs"]
mod delegation_models;
#[path = "integration/history_execution_facts.rs"]
mod history_execution_facts;
#[path = "integration/history_store.rs"]
mod history_store;
#[path = "integration/runtime_file_display.rs"]
mod runtime_file_display;
#[path = "integration/runtime_live_tool_skill.rs"]
mod runtime_live_tool_skill;
#[cfg(target_os = "linux")]
#[path = "integration/runtime_lsp_configuration.rs"]
mod runtime_lsp_configuration;
#[path = "integration/runtime_mcp_refresh.rs"]
mod runtime_mcp_refresh;
#[path = "integration/runtime_model_handoff.rs"]
mod runtime_model_handoff;
#[path = "integration/runtime_worktree_identity.rs"]
mod runtime_worktree_identity;
#[expect(dead_code, reason = "shared isolated runtime fixtures")]
mod support;
#[path = "integration/workflow_plan_restart_recovery.rs"]
mod workflow_plan_restart_recovery;
#[path = "integration/worktree_lifecycle.rs"]
mod worktree_lifecycle;
