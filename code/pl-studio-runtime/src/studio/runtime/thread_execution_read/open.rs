use super::*;
use crate::studio::runtime::thread_observation::facets::execution::{
    InteractionIdentity, InteractionReceiptKind, Material,
};
use crate::studio::runtime::thread_reads::{
    activity::ActivityMaterial, index::InteractionIndexMaterial, interaction::InteractionMaterial,
    scalar::StorageMaterial, turn::TurnMaterial,
};
use anyhow::Context;
use pl_protocol::studio::StudioErrorCode;

impl StudioRuntime {
    pub fn open_turn_read(
        &self,
        thread_id: String,
        reference: TurnReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioTurnRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.execution_read_lease(&thread_id, &origin)?;
            let material = lease.source().execution.material_at(
                reference.entry,
                reference.revision,
                &origin,
            )?;
            let Material::Turn(value) = &*material else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, reference.revision, material, |identity| {
                TurnMaterial::new(identity, value)
            })?;
            Ok(StudioTurnRead { scope })
        })
    }
    pub fn open_interaction_index_read(
        &self,
        thread_id: String,
        reference: InteractionIndexRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioInteractionIndexRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.execution_read_lease(&thread_id, &origin)?;
            let material = lease.source().execution.material_at(
                reference.entry,
                reference.revision,
                &origin,
            )?;
            let Material::Index(value) = &*material else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, reference.revision, material, |identity| {
                InteractionIndexMaterial::new(identity, value)
            })?;
            Ok(StudioInteractionIndexRead { scope })
        })
    }
    pub fn open_activity_read(
        &self,
        thread_id: String,
        reference: ActivityReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioActivityRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.execution_read_lease(&thread_id, &origin)?;
            let material = lease.source().execution.material_at(
                reference.entry,
                reference.revision,
                &origin,
            )?;
            let Material::Activity(value) = &*material else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, reference.revision, material, |identity| {
                ActivityMaterial::new(identity, value)
            })?;
            Ok(StudioActivityRead { scope })
        })
    }
    pub fn open_storage_read(
        &self,
        thread_id: String,
        reference: StorageReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioStorageRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.execution_read_lease(&thread_id, &origin)?;
            let material = lease.source().execution.material_at(
                reference.entry,
                reference.revision,
                &origin,
            )?;
            let Material::Storage(value) = &*material else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, reference.revision, material, |identity| {
                Ok(StorageMaterial::new(identity, value))
            })?;
            Ok(StudioStorageRead { scope })
        })
    }
    pub fn open_interaction_read(
        &self,
        thread_id: String,
        reference: InteractionReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioInteractionRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.execution_read_lease(&thread_id, &origin)?;
            let material = match lease.source().execution.interaction_at(
                reference.entry,
                reference.revision,
                &origin,
            )? {
                Ok(value) => value,
                Err(identity) => {
                    let value = Arc::new(
                        runtime
                            .read_exact_execution_interaction(
                                &thread_id,
                                &identity.wire_id,
                                reference.revision,
                                Some(&identity),
                            )
                            .await?,
                    );
                    lease.source().execution.bind_durable_interaction(
                        reference.entry,
                        reference.revision,
                        value,
                        &origin,
                    )?
                }
            };
            let Material::Interaction(value) = &*material else {
                return Err(wrong().into());
            };
            let value = value.clone();
            lease.source().execution.ensure_open()?;
            let scope = Scope::open(&runtime, lease, reference.revision, material, |identity| {
                InteractionMaterial::new(identity, value)
            })?;
            Ok(StudioInteractionRead { scope })
        })
    }
    pub fn resolve_interaction_read_ref(
        &self,
        thread_id: String,
        interaction_id: String,
        revision: u64,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<InteractionReadRef>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.execution_read_lease(&thread_id, &origin)?;
            let source = &lease.source().execution;
            if let Some(reference) =
                source.resolve_resident_interaction(&interaction_id, revision, &origin)?
            {
                return Ok(reference);
            }
            let identity = source.known_interaction(&interaction_id, &origin)?;
            let value = runtime
                .read_exact_execution_interaction(
                    &thread_id,
                    &interaction_id,
                    revision,
                    identity.as_ref(),
                )
                .await?;
            Ok(source.register_durable_interaction(Arc::new(value), &origin)?)
        })
    }

    fn execution_read_lease(
        &self,
        thread_id: &str,
        origin: &ThreadFacetStamp,
    ) -> Result<ThreadFacetLease> {
        if self.shutdown_committed() {
            return Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "Execution reads are closed",
                false,
            )
            .into());
        }
        self.thread_observations
            .execution_sources_at(thread_id, origin)?
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Superseded,
                    "The original execution incarnation is no longer registered",
                    false,
                )
                .into()
            })
    }

    async fn read_exact_execution_interaction(
        &self,
        thread_id: &str,
        id: &str,
        revision: u64,
        expected: Option<&InteractionIdentity>,
    ) -> Result<pl_protocol::InteractionRequest> {
        let (owner, local) = crate::thread_assembler::decode_interaction_key(id)
            .map_err(|_| StudioError::invalid_argument("Interaction identity is malformed"))?;
        if owner != thread_id {
            let host = self.read_owned_thread(thread_id).await?;
            let target = self.read_owned_thread(owner).await?;
            if host.parent_thread_id.is_some()
                || target.parent_thread_id.as_deref() != Some(thread_id)
            {
            return Err(StudioError::invalid_argument(
                    "Interaction is not owned by the original host or its direct child",
                ).into());
            }
        }
        if expected.is_some_and(|identity| identity.wire_id != id || identity.local_id != local) {
            return Err(wrong().into());
        }
        let history = self.store.history(owner).await?;
        let mut exact = None;
        let mut known = expected.is_some();
        let mut source_kind = None;
        for kind in [
            InteractionReceiptKind::Interaction,
            InteractionReceiptKind::Permission,
        ] {
            if expected.is_some_and(|identity| identity.kind != kind) {
                continue;
            }
            let key = crate::studio::thread_projection::order::receipt_id(kind.as_str(), local);
            let receipt = history.fact_receipt_at(&key, revision).await?;
            let has_exact = receipt.is_some();
            if let Some(receipt) = receipt {
                if receipt.kind != kind.as_str() {
                    return Err(StudioError::new(
                        StudioErrorCode::Protocol,
                        "Exact interaction receipt kind mismatch",
                        false,
                    )
                    .into());
                }
                let value = Self::project_interaction_receipt(owner, local, receipt)
                    .context(crate::studio::storage::history::HistoryReadFailure::Protocol)?;
                if value.interaction_id != id || value.revision != revision {
                    return Err(StudioError::new(
                        StudioErrorCode::Protocol,
                        "Exact interaction receipt identity mismatch",
                        false,
                    )
                    .into());
                }
                if owner != thread_id
                    && !matches!(value.scope.purpose, pl_protocol::InteractionPurpose::General)
                {
                    return Err(StudioError::invalid_argument(
                        "Child Plan confirmations are diagnostics, not hosted decisions",
                    ).into());
                }
                if exact.replace(value).is_some() {
                    return Err(StudioError::new(
                        StudioErrorCode::Protocol,
                        "Historical interaction identity has ambiguous source kinds",
                        false,
                    )
                    .into());
                }
            }
            let latest = history.latest_fact_receipt(&key).await?;
            if latest
                .as_ref()
                .is_some_and(|receipt| receipt.kind != kind.as_str())
            {
                return Err(StudioError::new(
                    StudioErrorCode::Protocol,
                    "Historical interaction receipt kind mismatch",
                    false,
                )
                .into());
            }
            if has_exact || latest.is_some() {
                if source_kind.replace(kind).is_some() {
                    return Err(StudioError::new(
                        StudioErrorCode::Protocol,
                        "Historical interaction identity has ambiguous source kinds",
                        false,
                    )
                    .into());
                }
                known = true;
            }
        }
        if let Some(value) = exact {
            return Ok(value);
        }
        if known {
            return Err(wrong().into());
        }
        Err(StudioError::not_found("Interaction receipt").into())
    }
}

fn wrong() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The exact requested execution fact is not available",
        false,
    )
}
