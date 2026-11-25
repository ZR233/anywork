//! Fixtures shared by Session, Studio and the real storage owners.

use std::collections::BTreeMap;

use crate::thread_assembler::StudioThreadSpec;

pub(crate) mod storage {
    pub(crate) use crate::studio::storage::thread_writer::storage_fault_tests::{
        CloseFactoryFixture, close_factory, register_test_thread, save_terminal_report,
        spawn_live_projection_for_thread,
    };
    pub(crate) use crate::studio::storage::thread_writer::{HistoryChannel, ThreadStorageSink};
}

pub(crate) fn archive_test_spec(
    id: String,
    parent_id: Option<String>,
    root: &std::path::Path,
) -> StudioThreadSpec {
    let info = pl_model::model::ModelDefinition::compatible("archive-fixture");
    let route = pl_model::config::ResolvedModelRoute {
        pricing_mode: Default::default(),
        role: crate::config::root_agent_route_id(),
        account_id: pl_model::config::AccountId::new("archive-fixture").unwrap(),
        endpoint: pl_model::protocol::providers::openai::compatible_endpoint(
            "archive fixture",
            "http://127.0.0.1:0",
        ),
        context: info.resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled),
        model: info,
        effort: None,
        service_tier: None,
    };
    let profile = crate::AgentProfileSnapshot {
        profile_id: "fixture".into(),
        display_name: "fixture".into(),
        description: String::new(),
        when_to_use: String::new(),
        system_instructions: String::new(),
        account_id: "archive-fixture".into(),
        model_id: "archive-fixture".into(),
        effort: None,
        source: "fixture".into(),
        revision: "1".into(),
        content_hash: "fixture".into(),
        system: false,
        enabled: true,
        workspace_mode: crate::AgentWorkspaceMode::Directory,
    };
    StudioThreadSpec {
        workspace_usage: None,
        preparation_guard: None,
        agent_controls: Vec::new(),
        execution: pl_core::thread::input::InputDriverOptions {
            max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
        },
        id,
        parent_id,
        route,
        model: None,
        current: None,
        initial_context: Vec::new(),
        initial_runtime_facts: Vec::new(),
        initial_extensions: BTreeMap::from([(
            crate::studio::model_route::AGENT_PROFILE_EXTENSION.into(),
            crate::studio::model_route::encode_profile(&profile).unwrap(),
        )]),
        tools: Vec::new(),
        resources: pl_core::context::ResourceAccess::new(
            crate::resource_store::FileResourceStore::new(root.join("resources")),
        ),
        capacity: Default::default(),
        history_sink: None,
    }
}

pub(crate) fn bounded_future<Input, F: std::future::Future + Send>(
    name: &str,
    _: impl FnOnce(Input) -> F,
) {
    let bytes = std::mem::size_of::<F>();
    assert!(
        bytes <= 16 * 1024,
        "{name} has {bytes} bytes of inline state"
    );
}
