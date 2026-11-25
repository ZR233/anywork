//! Per-fixture failures at the protected credential I/O boundary.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::config::credential::{BotProtectedCredentialStore, MemoryCredentialStore};

use super::{
    BotCredentialCapability, BotCredentialIoError, BotCredentialIoKind, BotProtectedPersist,
    BotProtectedRead,
};

#[derive(Default)]
pub(crate) struct FaultingBotCredentialStore {
    memory: MemoryCredentialStore,
    system_unavailable: AtomicBool,
    persist_unavailable: AtomicBool,
    fail_next_system_recycle: AtomicBool,
}

pub(crate) fn faulting_bot_capability() -> (BotCredentialCapability, Arc<FaultingBotCredentialStore>)
{
    let store = Arc::new(FaultingBotCredentialStore::default());
    (BotCredentialCapability::new(store.clone()), store)
}

impl FaultingBotCredentialStore {
    pub(crate) fn set_system_unavailable(&self, unavailable: bool) {
        self.system_unavailable
            .store(unavailable, Ordering::Relaxed);
    }

    pub(crate) fn set_persist_unavailable(&self, unavailable: bool) {
        self.persist_unavailable
            .store(unavailable, Ordering::Relaxed);
    }

    pub(crate) fn fail_next_system_recycle(&self) {
        self.fail_next_system_recycle.store(true, Ordering::Relaxed);
    }
}

const UNAVAILABLE: BotCredentialIoError = BotCredentialIoError {
    kind: BotCredentialIoKind::Unavailable,
};

impl BotProtectedCredentialStore for FaultingBotCredentialStore {
    fn read_bot_system(&self, bot_id: &str) -> Result<BotProtectedRead, BotCredentialIoError> {
        if self.system_unavailable.load(Ordering::Relaxed) {
            return Err(UNAVAILABLE);
        }
        self.memory.read_bot_system(bot_id)
    }

    fn read_bot_lease(&self, bot_id: &str) -> Result<Option<String>, BotCredentialIoError> {
        self.memory.read_bot_lease(bot_id)
    }

    fn persist_bot_protected(
        &self,
        bot_id: &str,
        payload: &str,
    ) -> Result<BotProtectedPersist, BotCredentialIoError> {
        if self.persist_unavailable.load(Ordering::Relaxed) {
            return Err(UNAVAILABLE);
        }
        self.memory.persist_bot_protected(bot_id, payload)
    }

    fn lease_bot_protected(&self, bot_id: &str, payload: &str) -> Result<(), BotCredentialIoError> {
        self.memory.lease_bot_protected(bot_id, payload)
    }

    fn recycle_bot_system(&self, bot_id: &str) -> Result<(), BotCredentialIoError> {
        if self.fail_next_system_recycle.swap(false, Ordering::Relaxed) {
            return Err(UNAVAILABLE);
        }
        self.memory.recycle_bot_system(bot_id)
    }

    fn recycle_bot_lease(&self, bot_id: &str) -> Result<(), BotCredentialIoError> {
        self.memory.recycle_bot_lease(bot_id)
    }
}
