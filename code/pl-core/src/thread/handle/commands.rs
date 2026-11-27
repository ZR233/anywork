//! Priority-split owner commands: Tier 1 user controls vs Tier 2 internal runtime events.
use super::*;

/// Tier 1 (priority) commands initiated directly by user/host control actions.
#[derive(Debug)]
pub(in crate::thread) enum UserCommand {
    CurrentResume {
        epoch: current::RuntimeEpoch,
        expected_stop_generation: u64,
        input: TurnInput,
        reply: oneshot::Sender<Result<TurnCompletion, current::CurrentError>>,
    },
    ContinueMessage(
        inbox::ThreadMessage,
        input::InputDriverOptions,
        Option<String>,
        oneshot::Sender<Result<u64, ThreadError>>,
    ),
    Resume(
        ResumeRequest,
        input::InputDriverOptions,
        oneshot::Sender<Result<ContinuationOperation, ThreadError>>,
    ),
    InterruptTurn {
        expected: Option<String>,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    /// Stops exactly the named execution, including one that is still preparing.
    InterruptExecution {
        expected: String,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    CancelRunningTurn {
        expected: String,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    SubmitInput(
        input::ThreadInput,
        Option<input::InputDriverOptions>,
        oneshot::Sender<Result<input::InputRecord, ThreadError>>,
    ),
    DiscardInput(
        String,
        oneshot::Sender<Result<input::InputRecord, ThreadError>>,
    ),
    DrivePending(
        input::InputDriverOptions,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    PauseExecution(oneshot::Sender<()>),
    /// Pauses queued work, stops any active execution (including Preparing), and settles once idle.
    DrainExecution(oneshot::Sender<Result<(), ThreadError>>),
    ResolveInteraction(
        interactions::InteractionResolution,
        oneshot::Sender<Result<interactions::InteractionRecord, ThreadError>>,
    ),
    CancelInteraction(
        interactions::InteractionCancellation,
        oneshot::Sender<Result<interactions::InteractionRecord, ThreadError>>,
    ),
    ResolvePermission(
        permissions::PermissionResolution,
        oneshot::Sender<Result<permissions::PermissionRecord, ThreadError>>,
    ),
    CancelTask(
        String,
        oneshot::Sender<Result<task::TaskCancellationReceipt, ThreadError>>,
    ),
    Turn(
        TurnInput,
        oneshot::Sender<Result<TurnCompletion, ThreadError>>,
    ),
    /// Makes every already-published fact durable, keeping the target fixed at request time.
    Flush(oneshot::Sender<Result<(), ThreadError>>),
    BeginIdleClose(oneshot::Sender<bool>),
    Close(
        crate::thread::owner::ClosePurpose,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
}

impl UserCommand {
    pub(in crate::thread) fn reject(self) {
        fn closed<T>(reply: oneshot::Sender<Result<T, ThreadError>>) {
            let _ = reply.send(Err(ThreadError::Closed));
        }
        match self {
            Self::CurrentResume { reply, .. } => {
                let _ = reply.send(Err(current::CurrentError::Closed));
            }
            Self::SubmitInput(_, _, reply) | Self::DiscardInput(_, reply) => closed(reply),
            Self::ContinueMessage(_, _, _, reply) => closed(reply),
            Self::Resume(_, _, reply) => closed(reply),
            Self::InterruptTurn { reply, .. }
            | Self::InterruptExecution { reply, .. }
            | Self::CancelRunningTurn { reply, .. } => closed(reply),
            Self::DrivePending(_, reply) | Self::Flush(reply) | Self::Close(_, reply) => {
                closed(reply)
            }
            Self::PauseExecution(reply) => {
                let _ = reply.send(());
            }
            Self::DrainExecution(reply) => closed(reply),
            Self::BeginIdleClose(reply) => {
                let _ = reply.send(false);
            }
            Self::ResolveInteraction(_, reply) | Self::CancelInteraction(_, reply) => closed(reply),
            Self::ResolvePermission(_, reply) => closed(reply),
            Self::CancelTask(_, reply) => closed(reply),
            Self::Turn(_, reply) => closed(reply),
        }
    }
}

/// Tier 2 general runtime/tool/context events processed after ready Tier 1 user commands.
#[derive(Debug)]
pub(in crate::thread) enum LoopEvent {
    ReadCurrent {
        captured: Option<current::CapturedStream>,
        reply: oneshot::Sender<Result<current::CurrentRead, current::CurrentError>>,
    },
    ReadResume(
        ResumeRequest,
        oneshot::Sender<Result<ContinuationRead, ThreadError>>,
    ),
    InvokeNested {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        tool_id: String,
        arguments: OpaquePayload,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<crate::tool::ToolOutput, ThreadError>>,
    },
    InstallRuntimeBundle(
        Box<RuntimeBundle>,
        crate::tool::opaque::RegistrationBatch,
        oneshot::Sender<Result<RuntimeBundleReceipt, ThreadError>>,
    ),
    RuntimeAuthorizationChanged,
    RegisterTools(
        crate::tool::opaque::RegistrationBatch,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    RetryToolCleanup(oneshot::Sender<Result<(), ThreadError>>),
    RetireTools(
        crate::tool::opaque::RegistrationBatch,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    QueueRuntimeFacts(Vec<RuntimeFact>, oneshot::Sender<Result<(), ThreadError>>),
    ToolProgress {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        update: crate::model::ToolProgressUpdate,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    ToolOutputStorageFault {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        fault: Arc<cold::OutputStorageFault>,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    RequestPermission {
        caller: String,
        authority: crate::tool::opaque::ExecutionAuthority,
        payload: OpaquePayload,
        reply: oneshot::Sender<Result<permissions::PermissionRecord, ThreadError>>,
    },
    OpenAuxiliaryModel {
        caller: Option<String>,
        turn_id: Option<String>,
        reply: oneshot::Sender<Result<ModelSettlementPort, crate::model::ModelMemberError>>,
    },
    SettleModel {
        settlement: crate::model::ModelSubAttemptSettlement,
        reply: super::model_settlement::SettlementReply,
    },
    VerifyModelSettlement {
        settlement: crate::model::ModelSubAttemptSettlement,
        reply: super::model_settlement::SettlementReply,
    },
    RecordTaskObservation {
        caller: String,
        payload: OpaquePayload,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    ValidateExecution {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    ToolCancelTask {
        caller: String,
        authorization: Option<crate::tool::opaque::ToolAuthorization>,
        target: String,
        reply: oneshot::Sender<Result<task::TaskCancellationReceipt, ThreadError>>,
    },
    RetryHistoryAdmission(oneshot::Sender<Result<(), ThreadError>>),
    ResumeStorage {
        generation: u64,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    RetryOutputStorage(oneshot::Sender<super::cold::OutputRetryReply>),
    Message(
        inbox::ThreadMessage,
        Option<input::InputDriverOptions>,
        oneshot::Sender<Result<u64, ThreadError>>,
    ),
    MessageWithExtensions {
        message: inbox::ThreadMessage,
        mutations: Vec<extensions::ExtensionMutation>,
        reply: oneshot::Sender<Result<u64, ThreadError>>,
    },
    MutateExtensions(
        Vec<extensions::ExtensionMutation>,
        oneshot::Sender<
            Result<std::collections::BTreeMap<String, extensions::ExtensionRecord>, ThreadError>,
        >,
    ),
    WakeAcceptedMessage {
        id: String,
        sequence: u64,
        options: input::InputDriverOptions,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    ContextPreparation(
        Option<context_preparation::ContextPreparer>,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Reveal(Vec<String>, oneshot::Sender<Result<(), ThreadError>>),
    RequestInteraction(
        interactions::InteractionRequest,
        oneshot::Sender<Result<interactions::InteractionRecord, ThreadError>>,
    ),
    Application(
        extensions::ApplicationUpdate,
        oneshot::Sender<Result<ThreadSnapshot, ThreadError>>,
    ),
    Resources(
        crate::context::ResourceAccess,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Retry {
        source: String,
        attempt: String,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<ModelStepOutput, ThreadError>>,
    },
    AttachHistory(
        super::super::history_sink::HistorySinkHandle,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    AttachEventSink(
        Arc<dyn super::super::events::CoreEventSink>,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Capacity(ContextCapacity, oneshot::Sender<Result<(), ThreadError>>),
    PatchRuntimeFacts(
        Vec<RuntimeFact>,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    UpdateFacts(
        Vec<RuntimeFact>,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    CompactContext(
        u64,
        CancellationToken,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    ReplaceContext(
        ReplaceContext,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    Execute(
        String,
        CancellationToken,
        oneshot::Sender<Result<ToolDispatch, ThreadError>>,
    ),
    Step(
        StepInput,
        oneshot::Sender<Result<ModelStepOutput, ThreadError>>,
    ),
}

impl LoopEvent {
    pub(in crate::thread) fn reject(self) {
        fn closed<T>(reply: oneshot::Sender<Result<T, ThreadError>>) {
            let _ = reply.send(Err(ThreadError::Closed));
        }
        match self {
            Self::ReadCurrent { reply, .. } => {
                let _ = reply.send(Err(current::CurrentError::Closed));
            }
            Self::OpenAuxiliaryModel { reply, .. } => {
                let _ = reply.send(Err(crate::model::ModelMemberError::Closed));
            }
            Self::SettleModel { reply, .. } | Self::VerifyModelSettlement { reply, .. } => {
                let _ = reply.send(Err(crate::model::ModelMemberError::Closed));
            }
            Self::RetryOutputStorage(reply) => {
                let _ = reply.send(super::cold::OutputRetryReply::Finished(Err(
                    ThreadError::Closed,
                )));
            }
            Self::RuntimeAuthorizationChanged => {}
            Self::ReadResume(_, reply) => closed(reply),
            Self::InvokeNested { reply, .. } => closed(reply),
            Self::InstallRuntimeBundle(_, _, reply) => closed(reply),
            Self::RegisterTools(_, reply)
            | Self::RetryToolCleanup(reply)
            | Self::RetireTools(_, reply)
            | Self::QueueRuntimeFacts(_, reply)
            | Self::ToolProgress { reply, .. }
            | Self::ToolOutputStorageFault { reply, .. }
            | Self::RecordTaskObservation { reply, .. }
            | Self::ValidateExecution { reply, .. }
            | Self::RetryHistoryAdmission(reply)
            | Self::ResumeStorage { reply, .. } => closed(reply),
            Self::RequestPermission { reply, .. } => closed(reply),
            Self::ToolCancelTask { reply, .. } => closed(reply),
            Self::Message(_, _, reply) | Self::MessageWithExtensions { reply, .. } => closed(reply),
            Self::MutateExtensions(_, reply) => closed(reply),
            Self::WakeAcceptedMessage { reply, .. } => closed(reply),
            Self::ContextPreparation(_, reply)
            | Self::Reveal(_, reply)
            | Self::Resources(_, reply)
            | Self::AttachHistory(_, reply)
            | Self::AttachEventSink(_, reply)
            | Self::Capacity(_, reply) => closed(reply),
            Self::RequestInteraction(_, reply) => closed(reply),
            Self::Application(_, reply) => closed(reply),
            Self::Retry { reply, .. } | Self::Step(_, reply) => closed(reply),
            Self::PatchRuntimeFacts(_, reply)
            | Self::UpdateFacts(_, reply)
            | Self::CompactContext(_, _, reply)
            | Self::ReplaceContext(_, reply) => closed(reply),
            Self::Execute(_, _, reply) => closed(reply),
        }
    }
}
