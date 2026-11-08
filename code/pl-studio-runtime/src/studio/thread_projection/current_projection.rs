//! One immutable, bounded current head shared by its existing owners, never its bodies.
use pl_protocol::CurrentProjection;
use std::sync::{Arc, OnceLock};

#[derive(Debug)]
pub(in crate::studio) struct FrozenCurrentProjection {
    projection: CurrentProjection,
    json_bytes: OnceLock<u64>,
}

impl FrozenCurrentProjection {
    pub fn new(projection: CurrentProjection) -> Arc<Self> {
        Arc::new(Self {
            projection,
            json_bytes: OnceLock::new(),
        })
    }

    pub fn projection(&self) -> &CurrentProjection {
        &self.projection
    }

    /// Exact compact JSON length, without any retained-memory accounting fees.
    /// A failed measurement cannot fit any bounded publication frame.
    pub fn json_bytes(&self) -> u64 {
        *self.json_bytes.get_or_init(|| {
            serde_json::to_vec(&self.projection).map_or(u64::MAX, |bytes| {
                u64::try_from(bytes.len()).unwrap_or(u64::MAX)
            })
        })
    }

    /// Every holder still pays the original complete JSON charge. Sharing only
    /// avoids re-encoding; it does not discount another owner's responsibility.
    pub fn retained_bytes(&self) -> u64 {
        self.json_bytes()
            .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
            // Conservatively reserve a strong handle and both allocation counters.
            .saturating_add(3 * std::mem::size_of::<usize>() as u64)
    }
}
