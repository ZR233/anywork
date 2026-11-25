#[path = "integration/cancellation.rs"]
mod cancellation;
#[path = "integration/cancelled_live_usage.rs"]
mod cancelled_live_usage;
#[path = "integration/chat_detail.rs"]
mod chat_detail;
#[path = "integration/chat_page.rs"]
mod chat_page;
#[path = "integration/chat_performance.rs"]
mod chat_performance;
#[path = "integration/chat_producer.rs"]
mod chat_producer;
#[path = "integration/chat_tail.rs"]
mod chat_tail;
#[path = "integration/checkpoint_recovery.rs"]
mod checkpoint_recovery;
#[path = "integration/context_preparation.rs"]
mod context_preparation;
#[path = "integration/continuation_execution.rs"]
mod continuation_execution;
#[path = "integration/digest_compatibility.rs"]
mod digest_compatibility;
#[cfg(feature = "sqlite")]
#[path = "integration/durable_tool_task.rs"]
mod durable_tool_task;
#[cfg(feature = "sqlite")]
#[allow(dead_code)]
#[path = "support/effect_fixture.rs"]
mod effect_fixture;
#[path = "integration/flush_reachability.rs"]
mod flush_reachability;
#[path = "integration/interaction_collection_revision.rs"]
mod interaction_collection_revision;
#[path = "integration/interaction_recovery.rs"]
mod interaction_recovery;
#[allow(dead_code)]
#[path = "support/legacy_usage.rs"]
mod legacy_usage;
#[path = "integration/model_execution_phases.rs"]
mod model_execution_phases;
#[path = "integration/model_members.rs"]
mod model_members;
#[path = "integration/model_output_correction.rs"]
mod model_output_correction;
#[path = "integration/model_progress.rs"]
mod model_progress;
#[path = "integration/model_recovery_observation.rs"]
mod model_recovery_observation;
#[path = "integration/owner_loop_latency.rs"]
mod owner_loop_latency;
#[allow(dead_code)]
#[path = "support/preparation.rs"]
mod preparation;
#[path = "integration/preparation_failure.rs"]
mod preparation_failure;
#[path = "integration/resume_control.rs"]
mod resume_control;
#[path = "integration/runtime_bundle.rs"]
mod runtime_bundle;
#[cfg(feature = "sqlite")]
#[path = "integration/sqlite_persistence.rs"]
mod sqlite_persistence;
#[path = "integration/storage_pause.rs"]
mod storage_pause;
#[path = "integration/storage_request_retention.rs"]
mod storage_request_retention;
#[allow(dead_code)]
mod support;
#[cfg(feature = "sqlite")]
#[path = "integration/task_index_migration.rs"]
mod task_index_migration;
#[path = "integration/task_wait.rs"]
mod task_wait;
#[path = "integration/thread_current.rs"]
mod thread_current;
#[path = "integration/thread_turn.rs"]
mod thread_turn;
#[path = "support/timeline.rs"]
mod timeline_support;
#[path = "integration/tool_presentation_contract.rs"]
mod tool_presentation_contract;
#[path = "integration/tool_progress.rs"]
mod tool_progress;
#[allow(dead_code)]
#[path = "support/tool.rs"]
mod tool_support;
#[path = "integration/usage_accounting.rs"]
mod usage_accounting;
