pub mod attachment_binary;
#[path = "runtime.rs"]
mod bridge_runtime;
pub mod conversation;
mod convert;
pub mod draft_commands;
pub mod handlers;
pub mod observation;
pub mod products;
pub mod subscription;
pub mod types;

// Re-exports from submodules
pub use self::handlers::{
    BridgeStudioUpdateOperation, BridgeTimeline, activate_project, apply_settings_field,
    archive_project, archive_thread, authenticate_ssh_server, browse_remote_directories,
    cancel_bot_registration, check_account_usage, check_studio_update, close_remote_directory,
    compact_thread, create_bot_conversation_thread, delete_ssh_server,
    delete_thread_mode_definition, discover_skills, finish_shutdown_diagnostics,
    get_delegation_model, init_app, interrupt_turn, list_bot_conversations, list_delegation_models,
    list_ssh_servers, list_threads_page, load_account_catalog, open_project, open_remote_project,
    open_timeline, prepare_startup_attempt, prepare_studio_update, preview_thread_mode_workflow,
    probe_lsp_server, query_threads, read_account_usage_state, read_agent_profiles_state,
    read_bot_messages, read_bots, read_deepseek_web_search_settings, read_input_acceptance,
    read_lsp_state, read_mcp_state, read_settings_state, read_skills_state, read_studio_state,
    read_studio_update_state, read_thread, read_thread_activity_detail,
    read_thread_mode_definition, read_web_search_settings, reconnect_ssh_server,
    reload_settings_from_disk, reload_thread_mode_definitions, remove_account,
    remove_attachment_draft, rename_project, rename_thread, repair_lsp_server, reset_lsp,
    reset_mcp, respond_interaction, restore_thread, retry_bot_connection, save_account, save_bot,
    save_runtime_permission_mode, save_ssh_server, save_thread_mode_definition,
    save_user_agent_profile, search_skills, send_bot_message, set_account_billing_kind,
    set_account_model_enabled, set_bot_enabled, set_bot_trusted_chat, set_bot_trusted_user,
    set_default_account, set_system_agent_enabled, set_thread_mode, set_thread_model_route,
    shutdown_runtime, start_bot_registration, start_studio_runtime, test_ssh_connection,
    thread_mode_definition_schema, validate_thread_mode_definition,
};
pub use self::subscription::{
    BridgeEventSubscription, BridgeThreadStreamEnvelope, create_product_topic_subscription,
    subscribe_shutdown_progress, subscribe_thread,
};
pub use self::types::*;
pub use products::feed::persistence_queue_transport::open_persistence_queue;
pub use products::feed::persistence_transport::open_persistence;
pub use products::feed::recovery_transport::open_recovery;
pub use products::feed::startup_transport::{initialize_library, open_startup_progress};
pub use products::read::persistence::{open_persistence_read, retry_persistence};
pub use products::read::persistence_queue::{
    open_persistence_queue_read, resume_thread_history, retry_thread_history,
};
pub use products::read::recovery::{
    cleanup_worktree, open_recovery_read, open_recovery_source_status_read, retry_recovery,
};
pub use products::read::remote_directory::{close_directory, open_directory};
pub use products::read::startup::open_startup_read;

// Native product capabilities; legacy transport removal is owned by the integration task.
pub use products::feed::account_usage_transport::{BridgeAccountUsageFeed, open_account_usage};
pub use products::feed::mode_catalog_transport::{BridgeModeCatalogFeed, open_mode_catalog};
pub use products::feed::performance_history_transport::{
    BridgePerformanceHistoryFeed, open_performance_history,
};
pub use products::feed::performance_summaries_transport::{
    BridgePerformanceSummariesFeed, open_performance_summaries,
};
pub use products::feed::session_costs_transport::{BridgeSessionCostsFeed, open_session_costs};
pub use products::feed::updates_transport::{BridgeUpdatesFeed, open_updates};
pub use products::read::account_usage::*;
pub use products::read::modes::*;
pub use products::read::statistics::*;
pub use products::read::updates::*;
