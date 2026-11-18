//! Explicit observations of a complete paused Current through its Core and file owners.

use super::*;
use pl_core::{
    context::{ContextRecord, ContextSource, OpaquePayload},
    model::ToolCallMode,
    thread::{
        ThreadHandle, ThreadLifecycle,
        current::{CurrentModelCall, SavedModelPhase},
        input::InputExecution,
    },
};
use pl_model::completion::{
    ModelStreamCurrent, ModelStreamCurrentState, ModelStreamReplay, ModelStreamToolInput,
    ModelStreamToolInputPhase,
};

use crate::studio::storage::{
    coordinator::ThreadPersistenceCoordinator, current_writer::CurrentSource, state::StateStore,
};
use crate::thread_assembler::ClosePurpose;

/// One size per process; collect the OS peak separately so other sizes cannot inflate it.
/// The samples include confirmed context, private material and a complete partial stream.
#[tokio::test]
#[ignore = "manual Current size/IO observation; set PL_CURRENT_SAMPLE_MIB to 1, 16 or 64"]
async fn current_size_observation() -> Result<()> {
    let mib: usize = std::env::var("PL_CURRENT_SAMPLE_MIB")?.parse()?;
    ensure!(
        [1, 16, 64].contains(&mib),
        "choose one representative sample size"
    );
    tracing_subscriber::fmt()
        .with_env_filter("current_work=debug,conversation_work=debug")
        .with_ansi(false)
        .without_time()
        .try_init()
        .map_err(|error| anyhow::anyhow!("install observation subscriber: {error}"))?;
    let directory = tempfile::tempdir()?;
    std::fs::write(
        directory.path().join("history.sqlite"),
        b"unreadable history",
    )?;
    let thread_id = "size-observation";
    let epoch = RuntimeEpoch::new();
    let mut current = ThreadCurrent::new(thread_id.into(), epoch);
    current.state.context.records = vec![ContextRecord {
        id: "confirmed-context".into(),
        turn_id: None,
        source: ContextSource::User,
        content: vec![ContextContent::Text {
            text: format!("完整上下文🙂\n{}", "c".repeat(mib * 1024 * 1024 / 2)).into(),
        }],
        tool_calls: Vec::new(),
    }]
    .into();
    current.state.private_context = Some(OpaquePayload::new("sample.native", 1, "签名字节\0")?);
    let stream = ModelStreamCurrent {
        attempt_id: "partial-attempt".into(),
        generation: 0,
        previous_generations: Vec::new(),
        state: ModelStreamCurrentState::Open,
        response_id: None,
        model_observation: None,
        reported_model_is_terminal: false,
        content_parts: Vec::new(),
        blocks: Vec::new(),
        reasoning_summary_parts: vec!["reasoning 保留".into()],
        raw_reasoning_parts: vec![format!("原始思考λ\0{}", "r".repeat(mib * 1024 * 1024 / 2))],
        tool_inputs: vec![ModelStreamToolInput {
            stream_id: None,
            item_id: "item".into(),
            provider_call_id: None,
            call_id: "partial-call".into(),
            name: "read_file".into(),
            kind: pl_model::completion::ToolCallKind::Function,
            input: "{\"path\":\"src/ma".into(),
            phase: ModelStreamToolInputPhase::Streaming,
            stream_aliases: Vec::new(),
            item_aliases: Vec::new(),
            call_aliases: Vec::new(),
        }],
        tool_calls: Vec::new(),
        tool_call_callers: Default::default(),
        call_bindings: Vec::new(),
        responses_context_items: Vec::new(),
        replay: ModelStreamReplay::default(),
        presentation_items: Vec::new(),
        members: Vec::new(),
        presentation_states: Default::default(),
        final_usage: None,
        usage_is_terminal: false,
    };
    current.model_call = Some(CurrentModelCall {
        source_run_id: epoch,
        source_execution_id: "execution".into(),
        source_turn_id: "turn".into(),
        source_attempt_id: stream.attempt_id.clone(),
        tools: Arc::from([]),
        tool_call_mode: ToolCallMode::Sequential,
        solo_tool_ids: Arc::from([]),
        prepared_parameters: None,
        phase: SavedModelPhase::Streaming {
            stream: stream.encode()?,
        },
    });
    drop(stream);
    let mut expected = current.clone();
    let handle = ThreadHandle::restore_current(current, None)?;
    let runtime_epoch = handle.runtime_epoch();
    let mut store = StateStore::new(directory.path().into(), thread_id);
    let sample = async {
        ensure!(matches!(
            handle.snapshot().input_execution,
            InputExecution::Paused
        ));
        store
            .attach_current(
                ThreadPersistenceCoordinator::default(),
                None,
                runtime_epoch,
                CurrentSource::from_thread(handle.clone()),
            )
            .await?;
        let receipt = store.flush_current(runtime_epoch).await?;
        let persisted = store.current_save_state()?.persistence_snapshot();
        let restored = store
            .load_current()
            .await?
            .context("saved sample is missing")?;
        let operation_memory = if cfg!(target_os = "linux") {
            Some(
                std::fs::read_to_string("/proc/self/status")?
                    .lines()
                    .filter(|line| line.starts_with("VmHWM:") || line.starts_with("VmRSS:"))
                    .map(str::to_owned)
                    .collect::<Vec<_>>(),
            )
        } else {
            None
        };
        Ok::<_, anyhow::Error>((receipt, persisted, restored, operation_memory))
    }
    .await;
    // Join the real owner even when the sample fails. The fixture directory is disposable.
    let closed = store
        .close_current(runtime_epoch, ClosePurpose::Delete)
        .await;
    if handle.snapshot().lifecycle != ThreadLifecycle::Closed {
        handle.close().await?;
    }
    let (receipt, persisted, restored, operation_memory) = sample?;
    closed?;
    ensure!(runtime_epoch != epoch && restored.saved_runtime_epoch == runtime_epoch);
    ensure!(receipt.snapshot_revision == restored.snapshot_revision);
    ensure!(persisted.last_successful_capture_at == Some(restored.saved_at));
    let age = persisted
        .snapshot_age_millis
        .context("missing saved snapshot age")?;
    // The live owner stamps the new epoch, revision and actual capture time.
    expected.saved_runtime_epoch = runtime_epoch;
    expected.snapshot_revision = receipt.snapshot_revision;
    expected.saved_at = restored.saved_at;
    let expected = serde_json::to_vec(&expected)?;
    ensure!(
        serde_json::to_vec(&restored)? == expected,
        "Current sample changed on disk"
    );
    ensure!(std::fs::read(directory.path().join("history.sqlite"))? == b"unreadable history");
    println!(
        "current_size_sample {}",
        serde_json::json!({
            "sampleMiB": mib, "currentJsonBytes": expected.len(),
            "snapshotAgeAfterFlushMs": age,
            "operationMemory": operation_memory,
            "memoryScope": "process including fixture, owner capture, save and load with original retained; before round-trip comparison",
            "captureScope": "paused Core owner with complete retained producer observation",
            "writeGuarantee": "direct overwrite plus Tokio flush; no fsync or atomic replacement",
            "roundTrip": "all serialized logical fields equal", "history": "unreadable and unchanged"
        })
    );
    Ok(())
}
