//! Per-Thread reliable owner of independent immutable History exports.
//!
//! The original projection freezes each product event once. This queue retains the exact export
//! and candidate across admission, writing, cancellation and retry. The writer appends schema-26
//! events and bodies; it neither captures, saves nor acknowledges Current.

use crate::ExecutionItem;
use std::{
    collections::{BTreeMap, VecDeque},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::{Context, Result, ensure};
use pl_core::thread::{
    HistoryExport, UsageSummary,
    cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
};

use tokio::time::Instant;

use crate::history::HistoryStore;
use crate::studio::StudioStore;
use crate::studio::storage::coordinator::{
    PendingSequenceRange, ThreadPersistenceMetrics, ThreadPersistenceReport,
};
use crate::studio::storage::sqlite_util::is_retryable_write;
use crate::studio::thread_projection::PreparedEffect;

mod batch;
pub(in crate::studio) use batch::CommittedBatch;

#[cfg(feature = "benchmarks")]
pub(crate) mod benchmark;

#[cfg(feature = "benchmarks")]
use super::calls::observation::Metric as BenchMetric;

mod channel;
mod order_index;
mod sink;

use channel::*;
pub(crate) use channel::{
    HistoryChannel, PendingProjectionRetention, ProjectionRetention, ProjectionTransfer,
    ReviewDeliveryRetention,
};
use order_index::{ExecutionIndexBudgetFull, OrderIndexState};
pub(in crate::studio) use order_index::{ExecutionMaterialization, RuntimeOrderIndex};
use sink::*;
pub(crate) use sink::{ThreadStorageBinding, ThreadStorageSink};

#[cfg(test)]
#[path = "tests/batch_window.rs"]
mod batch_window_tests;
#[cfg(test)]
#[path = "tests/order_index.rs"]
mod execution_index_tests;
#[cfg(test)]
#[path = "tests/support.rs"]
pub(crate) mod storage_fault_tests;
#[cfg(test)]
#[path = "tests/watchdog.rs"]
mod watchdog_tests;
#[cfg(test)]
#[path = "tests/writer.rs"]
mod writer_tests;
