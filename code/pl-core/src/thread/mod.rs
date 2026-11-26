//! Serial Thread ownership over protocol-independent model context and committed private material.

use std::sync::Arc;
use tokio::sync::{mpsc, oneshot, watch};
mod background;
mod cancellation;
pub mod cold;
pub mod context_preparation;
mod continuation;
pub use continuation::{
    ContinuationDisposition, ContinuationNotExecuted, ContinuationOperation, ContinuationRead,
    ResumeRequest,
};
pub mod current;
pub mod events;
mod execution;
pub mod extensions;
mod facts;
pub mod history_sink;
pub mod inbox;
pub mod input;
pub mod interactions;
pub mod journal;
mod owner;
pub mod permissions;
mod runtime_bundle;
pub use runtime_bundle::{
    RuntimeApplication, RuntimeBinding, RuntimeBindingReader, RuntimeBundle, RuntimeBundleBase,
    RuntimeBundleReceipt, RuntimeBundleState, RuntimeModel, RuntimeTools,
};
mod subscription;
pub mod task;
mod task_access;
pub use task_access::{NestedToolDeclaration, TaskAccess, TaskWaitSnapshot};
mod nested;
mod turn;
pub(crate) mod usage;
pub use events::{CoreCommitEvent, CoreEvent, CoreEventSink, CoreLiveEvent};
pub use journal::{
    ContextCompactionEvent, ContextCompactionOutcome, PreparedAccountingSlot, ThreadEffectBatch,
};
use owner::{Owner, PendingCall};
pub use subscription::ThreadSubscription;
use tokio_util::sync::CancellationToken;

use crate::context::{
    ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
};
use crate::model::{
    DynModelSession, ModelError, ModelRequest, ModelStepOutput, ModelToolDeclaration,
};

mod handle;
pub use handle::ThreadHandle;
use handle::{LoopEvent, UserCommand};
mod model_members;
mod model_settlement;
mod model_step;
mod reconfiguration;
mod replacement;
mod tool_execution;
mod types;
pub use model_settlement::ModelSettlementPort;
pub use types::*;
