use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};

use crate::PureError;
use crate::studio::store::object::{PersistedStudioObject, load_object, put_object};
use crate::studio::{StudioStore, unix_seconds};

use super::recent::RecentIdentities;

const MODEL_PERFORMANCE_OWNER_ID: &str = "global";
const CACHE_VERSION: u32 = 4;
const LEGACY_CACHE_VERSION: u32 = 2;

/// 模型性能领域的固定上限缓存。
///
/// 只保存版本、单调 revision 和更新时间。调用库拥有历史、汇总与持久幂等。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ModelPerformanceState {
    version: u32,
    revision: u64,
    updated_at: i64,
}

/// 仅在 persistence worker 内存在的 object 编码 DTO。
#[derive(Serialize, Deserialize)]
#[serde(transparent)]
pub(super) struct ModelPerformanceDto(ModelPerformanceState);

impl Default for ModelPerformanceState {
    fn default() -> Self {
        Self {
            version: CACHE_VERSION,
            revision: 0,
            updated_at: 0,
        }
    }
}

impl PersistedStudioObject for ModelPerformanceState {
    type PersistenceDto = ModelPerformanceDto;

    const OWNER_KIND: &'static str = "studio";
    const OBJECT_KIND: &'static str = "modelPerformance";
    const SCHEMA_VERSION: i64 = 1;

    fn revision(&self) -> u64 {
        self.revision
    }

    fn to_persistence_dto(&self) -> Self::PersistenceDto {
        ModelPerformanceDto(self.clone())
    }

    fn from_persistence_dto(dto: Self::PersistenceDto) -> anyhow::Result<Self> {
        Ok(dto.0)
    }
}

#[derive(Default)]
pub(super) struct PerformanceCache {
    memory: Mutex<CacheMemory>,
    persisted_revision: AtomicU64,
    persist_lock: tokio::sync::Mutex<()>,
}

#[derive(Default)]
struct CacheMemory {
    metadata: ModelPerformanceState,
    recent: RecentIdentities,
}

impl PerformanceCache {
    pub(super) fn fingerprint_matches(
        &self,
        thread: &str,
        inference: &str,
        fingerprint: &str,
    ) -> Option<bool> {
        let memory = self
            .memory
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        memory
            .recent
            .get(thread, inference)
            .map(|previous| previous == fingerprint)
    }

    pub(super) fn record(&self, identity: Option<(&str, &str, &str, String)>) {
        let mut memory = self
            .memory
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some((root, thread, inference, fingerprint)) = identity {
            memory.recent.insert(root, thread, inference, fingerprint);
        }
        Self::advance(&mut memory.metadata);
    }

    pub(super) fn remove(&self, root: &str) {
        let mut memory = self
            .memory
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        memory.recent.remove_root(root);
        Self::advance(&mut memory.metadata);
    }

    fn advance(metadata: &mut ModelPerformanceState) {
        metadata.revision = metadata.revision.saturating_add(1);
        metadata.updated_at = unix_seconds();
    }

    pub(super) async fn load(&self, store: &StudioStore) -> anyhow::Result<Option<u64>> {
        let Some(restored) =
            load_object::<ModelPerformanceState>(store.database(), MODEL_PERFORMANCE_OWNER_ID)
                .await?
        else {
            return Ok(None);
        };
        if restored.version < LEGACY_CACHE_VERSION || restored.version > CACHE_VERSION {
            return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                "unsupported model performance cache version {}",
                restored.version
            )));
        }
        {
            let mut state = self
                .memory
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            *state = CacheMemory {
                metadata: ModelPerformanceState {
                    version: CACHE_VERSION,
                    revision: restored.revision,
                    updated_at: restored.updated_at,
                },
                recent: RecentIdentities::default(),
            };
        }
        self.persisted_revision
            .store(restored.revision, Ordering::Release);
        Ok(Some(restored.revision))
    }

    /// 把进程内有界缓存（revision/更新时间）前移写盘；同 revision 幂等，旧 revision 不回写。
    pub(super) async fn persist(&self, store: &StudioStore) -> Result<(), PureError> {
        let _guard = self.persist_lock.lock().await;
        let (revision, updated_at, snapshot) = {
            let state = self
                .memory
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            (
                state.metadata.revision,
                state.metadata.updated_at,
                state.metadata.clone(),
            )
        };
        if revision == 0 || revision <= self.persisted_revision.load(Ordering::Acquire) {
            return Ok(());
        }
        put_object(
            store.database(),
            MODEL_PERFORMANCE_OWNER_ID,
            &snapshot,
            updated_at,
        )
        .await
        .map_err(|error| PureError::MemoryError(error.to_string()))?;
        self.persisted_revision.store(revision, Ordering::Release);
        Ok(())
    }
}
