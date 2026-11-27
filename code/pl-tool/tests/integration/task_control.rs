use crate::binding_host;
use pl_core::{
    model::DynModelSession,
    thread::{
        HistoryExport, ModelStepLimit, ThreadEffectBatch, ThreadError, ThreadHandle, ToolDelivery,
        ToolOutcome, UsageSummary,
        cold::{ColdStoreError, DurableToolTask, StorageIdleStatus, StoragePressure},
        current::{RuntimeEpoch, ThreadCurrent},
        history_sink::{HistorySink, HistorySinkHandle},
        task::{TaskRecord, TaskStatus},
    },
    tool::ToolOutput,
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_registration},
    task_control::{TaskControlKind, TaskControlTool, query_definition},
};
use serde_json::{Value, json};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

const THREAD_ID: &str = "task-query-after-relocation";
const TASK_ID: &str = "task:original-call";

#[derive(Debug)]
struct SavedOriginal {
    fact: Option<DurableToolTask>,
    reads: Arc<AtomicUsize>,
}

impl HistorySink for SavedOriginal {
    fn fold_usage(&self, _: &mut UsageSummary, _: &ThreadEffectBatch) {}
    fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
        Ok(())
    }
    fn reserve_operation_output(&self, _: &str, _: &str, max: u64) -> Result<u64, ColdStoreError> {
        Ok(max)
    }
    fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }
    fn release_operation_output(&self, _: &str, _: &str) {}
    fn pressure(&self, _: &str) -> StoragePressure {
        StoragePressure::default()
    }
    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        StorageIdleStatus {
            pressure: self.pressure(thread_id),
            reclaimable_thread_bytes: None,
        }
    }
    fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        None
    }
    fn admit(&self, _: &str, _: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        Ok(())
    }
    async fn read_saved_tool_task(
        &self,
        thread_id: &str,
        id: &str,
    ) -> Result<Option<DurableToolTask>, ColdStoreError> {
        assert_eq!(thread_id, THREAD_ID);
        assert_eq!(id, TASK_ID);
        self.reads.fetch_add(1, Ordering::Relaxed);
        Ok(self.fact.clone())
    }
}

fn saved_original() -> DurableToolTask {
    let task = TaskRecord {
        id: TASK_ID.into(),
        call_id: "original-call".into(),
        tool_id: "producer".into(),
        turn_id: "saved-turn".into(),
        revision: 2,
        status: TaskStatus::Succeeded,
        cancel_requested: false,
        invocation: None,
        parent_call_id: None,
        acknowledgement: None,
        started_sequence: Some(1),
    };
    let output = ToolOutput::text("保存的结果".into());
    let delivery = ToolDelivery {
        target: Default::default(),
        call_id: task.call_id.clone(),
        tool_id: task.tool_id.clone(),
        delivered_context: output.content().to_vec(),
        output,
        outcome: ToolOutcome::Succeeded,
        cancellation_cause: None,
    };
    DurableToolTask {
        task,
        delivery: Some(delivery),
    }
}

async fn query_relocated_task(
    status: TaskStatus,
    fact: Option<DurableToolTask>,
    cursors: &[Option<usize>],
) -> (Vec<ToolDelivery>, usize) {
    let mut resident = saved_original().task;
    resident.call_id = "relocated-call".into();
    resident.cancel_requested = true;
    resident.status = status;
    let mut current = ThreadCurrent::new(THREAD_ID.into(), RuntimeEpoch::new());
    current.state.start_task(resident).unwrap();
    let model = binding_host::Calls {
        calls: cursors
            .iter()
            .map(|cursor| {
                (
                    "get_tool_task".into(),
                    json!({"taskId":TASK_ID, "resultCursor":cursor}).to_string(),
                )
            })
            .collect(),
        requests: Default::default(),
    };
    let thread = ThreadHandle::restore_current(current, Some(DynModelSession::new(model))).unwrap();
    let reads = Arc::new(AtomicUsize::new(0));
    thread
        .attach_history(HistorySinkHandle::new(SavedOriginal {
            fact,
            reads: reads.clone(),
        }))
        .await
        .unwrap();
    let definition = query_definition();
    let registration =
        prepare_registration("get_tool_task", &definition, ToolCallPolicy::DirectOnly).unwrap();
    thread
        .register_tools(vec![
            TaskControlTool::new(TaskControlKind::Query, definition)
                .registration(registration)
                .foreground(),
        ])
        .await
        .unwrap();
    thread
        .resume_current(
            "query".into(),
            ModelStepLimit::Unlimited,
            Default::default(),
        )
        .await
        .unwrap();
    let deliveries = thread
        .effects()
        .await
        .unwrap()
        .iter()
        .flat_map(|effect| effect.deliveries.iter())
        .filter(|delivery| delivery.tool_id == "get_tool_task")
        .cloned()
        .collect::<Vec<_>>();
    thread.close().await.unwrap();
    assert_eq!(deliveries.len(), cursors.len());
    (deliveries, reads.load(Ordering::Relaxed))
}

#[tokio::test]
async fn task_query_pages_the_history_pair_after_current_relocates_the_call() {
    let original = saved_original();
    let expected =
        serde_json::to_string(original.delivery.as_ref().unwrap().output.result()).unwrap();
    let (deliveries, reads) =
        query_relocated_task(TaskStatus::Succeeded, Some(original), &[None, Some(0)]).await;
    assert_eq!(
        reads, 1,
        "status-only lookup uses Current, paging reads History once"
    );
    let [status, page] = deliveries.as_slice() else {
        unreachable!()
    };
    assert!(matches!(status.outcome, ToolOutcome::Succeeded));
    assert_eq!(
        status.output.data().unwrap()["task"]["cancelRequested"],
        true
    );
    assert!(status.output.data().unwrap().get("result").is_none());
    assert!(
        matches!(page.outcome, ToolOutcome::Succeeded),
        "{:?}",
        page.outcome
    );
    assert_eq!(
        page.output.data(),
        Some(&json!({
            "task": {"taskId":TASK_ID,"toolId":"producer","status":"succeeded","cancelRequested":false},
            "result": {"content":expected,"totalBytes":expected.len(),"nextCursor":Value::Null}
        }))
    );
}

#[tokio::test]
async fn task_query_rejects_mismatched_history_identity_and_outcome() {
    for corrupt in ["taskId", "callId", "toolId", "outcome"] {
        let mut original = saved_original();
        let delivery = original.delivery.as_mut().unwrap();
        match corrupt {
            "taskId" => {
                original.task.id = "task:other-call".into();
                original.task.call_id = "other-call".into();
                delivery.call_id = "other-call".into();
            }
            "callId" => delivery.call_id = "relocated-call".into(),
            "toolId" => delivery.tool_id = "other-tool".into(),
            "outcome" => delivery.outcome = ToolOutcome::Cancelled,
            _ => unreachable!(),
        }
        let (deliveries, reads) =
            query_relocated_task(TaskStatus::Succeeded, Some(original), &[Some(0)]).await;
        assert_eq!(reads, 1);
        let ToolOutcome::Failed(error) = &deliveries[0].outcome else {
            panic!("accepted mismatched {corrupt}");
        };
        assert!(
            matches!(
                error.source.downcast_ref::<ThreadError>(),
                Some(ThreadError::InvalidIdentity)
            ),
            "{corrupt}: {error:?}"
        );
        assert!(deliveries[0].output.data().is_none());
    }
}

#[tokio::test]
async fn task_query_distinguishes_running_from_missing_terminal_original() {
    let (running, reads) = query_relocated_task(TaskStatus::Running, None, &[Some(0)]).await;
    assert_eq!(reads, 0);
    assert!(matches!(running[0].outcome, ToolOutcome::Succeeded));
    let data = running[0].output.data().unwrap();
    assert_eq!(data["task"]["status"], "running");
    assert!(data.get("result").is_none());

    let (terminal, reads) = query_relocated_task(TaskStatus::Succeeded, None, &[Some(0)]).await;
    assert_eq!(reads, 1);
    let ToolOutcome::Failed(error) = &terminal[0].outcome else {
        panic!("terminal task without an original must fail paging");
    };
    assert!(
        error
            .to_string()
            .contains("Original result for terminal task")
    );
}
