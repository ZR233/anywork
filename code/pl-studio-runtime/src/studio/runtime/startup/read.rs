use super::{
    super::{
        StudioRuntime,
        read_budget::{FieldTable, bounded_header, count, require_budget, text_chunk},
    },
    scope::StartupReadScope,
    source::StartupSnapshot,
};
use anyhow::Result;
use pl_protocol::products::{identity::*, read::startup::*, source::SourceStateErrorRead};
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::{future::Future, sync::Arc};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    Backup,
    Reason,
    Code,
    Message,
    Thread(usize),
    Turn(usize),
}
struct StartupMaterial {
    source: Arc<StartupSnapshot>,
    texts: FieldTable<Field>,
}
pub struct StudioStartupRead {
    scope: StartupReadScope<StartupMaterial>,
}
impl StudioRuntime {
    /// Freezes the original ready result once. Idempotent start returns this same detail reference.
    pub fn runtime_ready(
        &self,
        attempt_id: u64,
    ) -> impl Future<Output = Result<RuntimeReady>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let snapshot = runtime.runtime_snapshot().await?;
            Ok(runtime.startup_source.ready(attempt_id, snapshot)?)
        })
    }
    pub fn open_startup_read(
        &self,
        reference: RuntimeStartupReadRef,
    ) -> impl Future<Output = Result<StudioStartupRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.startup_source.pin(reference)?;
            Ok(StudioStartupRead {
                scope: StartupReadScope::open(
                    &runtime,
                    runtime.startup_source.origin(),
                    ProductReadVersion::Value {
                        entry: reference.entry,
                        revision: reference.revision,
                    },
                    StartupMaterial {
                        source,
                        texts: FieldTable::default(),
                    },
                )?,
            })
        })
    }
}
impl StudioStartupRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<RuntimeStartupReadHeader>> + Send + 'static + use<> {
        let identity = self.scope.identity();
        self.scope.query(move |m| {
            bounded_header(|inline| {
                let value = &m.source.value;
                let at = value.state.updated_at();
                let state = match &value.state {
                    crate::StudioRuntimeLifecycleState::Uninitialized(_) => {
                        RuntimeStateRead::Uninitialized { at }
                    }
                    crate::StudioRuntimeLifecycleState::Initializing(_) => {
                        RuntimeStateRead::Initializing { at }
                    }
                    crate::StudioRuntimeLifecycleState::Ready(_) => RuntimeStateRead::Ready { at },
                    crate::StudioRuntimeLifecycleState::ShuttingDown(_) => {
                        RuntimeStateRead::ShuttingDown { at }
                    }
                    crate::StudioRuntimeLifecycleState::Stopped(_) => {
                        RuntimeStateRead::Stopped { at }
                    }
                    crate::StudioRuntimeLifecycleState::Failed(s) => RuntimeStateRead::Failed {
                        failed_at: s.failed_at(),
                        error: SourceStateErrorRead {
                            code: m.read(Field::Code, inline)?,
                            message: m.read(Field::Message, inline)?,
                            retryable: s.error().retryable,
                        },
                    },
                };
                let startup_recovery = value
                    .startup_recovery
                    .as_ref()
                    .map(|recovery| -> Result<_, StudioError> {
                        Ok(StartupRecoveryRead {
                            backup_path: m.read(Field::Backup, inline)?,
                            reason: m.read(Field::Reason, inline)?,
                            created_at: recovery.created_at,
                        })
                    })
                    .transpose()?;
                Ok(RuntimeStartupReadHeader {
                    scope: RuntimeStartupScopeIdentity {
                        scope_id: identity.scope_id.clone(),
                        owner_epoch: identity.owner_epoch.clone(),
                        attempt_id: m.source.attempt_id,
                        revision: value.revision,
                    },
                    reference: m.source.reference,
                    revision: value.revision,
                    state,
                    startup_recovery,
                    active_turn_count: count(value.active_turns.len())?,
                })
            })
        })
    }
    pub fn active_turns(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<StartupActiveTurnReadPage>> + Send + 'static + use<> {
        self.scope.query(move |m| {
            if !(1..=100).contains(&limit) {
                return Err(StudioError::invalid_argument(
                    "Page limit must be in 1..=100",
                ));
            }
            let total = m.source.value.active_turns.len();
            let start = usize::try_from(offset)
                .ok()
                .filter(|start| *start <= total)
                .ok_or_else(wrong)?;
            let end = start.saturating_add(limit as usize).min(total);
            let mut page = StartupActiveTurnReadPage {
                offset,
                total: count(total)?,
                items: Vec::new(),
                next_offset: None,
            };
            for index in start..end {
                page.items.push(StartupActiveTurnRead {
                    thread_id: m.read(Field::Thread(index), 0)?,
                    turn_id: m.read(Field::Turn(index), 0)?,
                });
                page.next_offset = if index + 1 < total {
                    Some(count(index + 1)?)
                } else {
                    None
                };
                if let Err(error) = require_budget(&page) {
                    page.items.pop();
                    if page.items.is_empty() {
                        return Err(error);
                    }
                    page.next_offset = Some(count(index)?);
                    break;
                }
            }
            Ok(page)
        })
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope.query(move |m| {
            text_chunk(
                field_id,
                m.source(m.texts.field(field_id)?)?,
                offset,
                max_bytes,
            )
        })
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}
impl StartupMaterial {
    fn read(
        &self,
        field: Field,
        inline: usize,
    ) -> Result<pl_protocol::studio::ReadText, StudioError> {
        self.texts.read(field, self.source(field)?, inline)
    }
    fn source(&self, field: Field) -> Result<&str, StudioError> {
        let value = &self.source.value;
        match field {
            Field::Backup => Ok(&value
                .startup_recovery
                .as_ref()
                .ok_or_else(wrong)?
                .backup_path),
            Field::Reason => Ok(&value.startup_recovery.as_ref().ok_or_else(wrong)?.reason),
            Field::Code | Field::Message => {
                let crate::StudioRuntimeLifecycleState::Failed(s) = &value.state else {
                    return Err(wrong());
                };
                match field {
                    Field::Code => Ok(&s.error().code),
                    Field::Message => Ok(&s.error().message),
                    _ => Err(wrong()),
                }
            }
            Field::Thread(index) => Ok(&value.active_turns.get(index).ok_or_else(wrong)?.thread_id),
            Field::Turn(index) => Ok(&value.active_turns.get(index).ok_or_else(wrong)?.turn_id),
        }
    }
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("Unknown startup field, member or offset in this original scope")
}
