//! Immutable discovery capabilities, separate from any one observation's winners.
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::Ordering;

use futures::future::join_all;
use pl_core::tool::opaque::ToolAuthorization;
use pl_protocol::{PureError, Result};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::{
    FrozenSkillCatalog, FrozenSkillEntry, SkillProvider, SkillProviderObservation,
    SkillProviderRequest, SkillRegistryInner, cancelled_error, validate_provider_candidate,
};
use crate::skill::{SkillCatalog, SkillMetadata, SkillsConfig};

/// A fixed workspace/configuration and the complete set of Providers captured for tool assembly.
///
/// Clones share one capability, including Providers that returned no candidates. Later registry
/// registrations cannot expand it. A discovery never retains the preparation Turn's cancellation
/// token, and does not publish a Studio catalog or alter earlier results.
#[derive(Debug, Clone)]
pub struct SkillDiscoverySources {
    scope: Arc<DiscoveryScope>,
}

#[derive(Debug)]
struct DiscoveryScope {
    workspace_root: PathBuf,
    config: SkillsConfig,
    system_dir: Option<PathBuf>,
    providers: Vec<Arc<dyn SkillProvider>>,
    registry: Arc<SkillRegistryInner>,
    authorization: ToolAuthorization,
}

impl SkillDiscoverySources {
    pub(super) fn capture(
        registry: Arc<SkillRegistryInner>,
        request: &SkillProviderRequest,
    ) -> Result<Self> {
        let providers: Vec<Arc<dyn SkillProvider>> = registry
            .providers
            .read()
            .map_err(|_| {
                PureError::ConfigError("skill provider registry lock poisoned".to_string())
            })?
            .iter()
            .map(|registered| registered.provider.clone())
            .collect();
        let authorization = source_authorization(request, &providers)?;
        Ok(Self {
            scope: Arc::new(DiscoveryScope {
                workspace_root: request.workspace_root.clone(),
                config: request.config.clone(),
                system_dir: request.system_dir.clone(),
                providers,
                registry,
                authorization,
            }),
        })
    }

    pub(crate) fn authorization(&self) -> ToolAuthorization {
        self.scope.authorization.clone()
    }

    /// Scans only these fixed sources and returns a complete, immutable call-local catalog.
    ///
    /// Generation changes retry once with the same Providers, not the current registry rows.
    /// Individual invalid documents remain warnings; incomplete observations fail without a
    /// partial catalog or a last-good fallback. All Provider operations use this call's token.
    ///
    /// # Errors
    /// Returns an error for cancellation, invalid configuration, Provider/I/O failure, or an
    /// observation that remains incomplete after the bounded generation retry.
    pub async fn discover(&self, cancellation: CancellationToken) -> Result<FrozenSkillCatalog> {
        let (generation, mut catalog) = self.discover_generation(cancellation.clone()).await?;
        if generation != self.generation() {
            let (generation, retry) = self.discover_generation(cancellation).await?;
            catalog = retry;
            if generation != self.generation() {
                catalog.snapshot.complete = false;
                catalog.snapshot.warnings.push(
                    "skill provider registry changed repeatedly during discovery".to_string(),
                );
            }
        }
        if !catalog.snapshot.complete {
            let warnings = catalog.snapshot.warnings.join("; ");
            return Err(PureError::ConfigError(format!(
                "Skill directory discovery is incomplete{}",
                if warnings.is_empty() {
                    ": provider reported an incomplete observation".to_string()
                } else {
                    format!(": {warnings}")
                }
            )));
        }
        Ok(catalog)
    }

    pub(super) fn generation(&self) -> u64 {
        self.scope.registry.generation.load(Ordering::Acquire)
    }

    pub(super) async fn discover_generation(
        &self,
        cancellation: CancellationToken,
    ) -> Result<(u64, FrozenSkillCatalog)> {
        if cancellation.is_cancelled() {
            return Err(cancelled_error());
        }
        let generation = self.generation();
        let request = SkillProviderRequest {
            workspace_root: self.scope.workspace_root.clone(),
            config: self.scope.config.clone(),
            system_dir: self.scope.system_dir.clone(),
            cancellation: cancellation.clone(),
        };
        let project_dir =
            super::super::project_skills_dir(&request.workspace_root, &request.config)?;
        let observations = join_all(self.scope.providers.iter().map(|provider| {
            let request = request.clone();
            async move { (provider.clone(), provider.list(request).await) }
        }));
        // Providers consume this call's token cooperatively. Await their terminal results even
        // after cancellation, retaining every blocking worker's join owner until it has stopped.
        let observations = observations.await;
        if cancellation.is_cancelled() {
            return Err(cancelled_error());
        }
        let mut warnings = Vec::new();
        let mut complete = true;
        let mut winners: BTreeMap<String, FrozenSkillEntry> = BTreeMap::new();
        for (provider_order, (provider, observation)) in observations.into_iter().enumerate() {
            let observation = match observation {
                Ok(observation) => observation,
                Err(error) => {
                    complete = false;
                    warnings.push(format!(
                        "skill provider {} failed: {error}",
                        provider.id().as_str()
                    ));
                    SkillProviderObservation::empty()
                }
            };
            complete &= observation.complete;
            warnings.extend(observation.warnings);
            for candidate in observation.candidates {
                if let Err(error) = validate_provider_candidate(provider.id(), &candidate) {
                    warnings.push(format!(
                        "skill provider {} returned an invalid candidate: {error}",
                        provider.id().as_str()
                    ));
                    continue;
                }
                let key = candidate.summary.name.to_ascii_lowercase();
                let ordering = (candidate.rank, provider_order, candidate.local_order);
                if winners
                    .get(&key)
                    .is_none_or(|existing| ordering < existing.ordering)
                {
                    winners.insert(
                        key,
                        FrozenSkillEntry {
                            ordering,
                            candidate,
                            provider: provider.clone(),
                        },
                    );
                }
            }
        }
        let skills = winners
            .values()
            .map(|entry| SkillMetadata::from(entry.candidate.summary.clone()))
            .collect();
        Ok((
            generation,
            FrozenSkillCatalog {
                snapshot: SkillCatalog {
                    project_dir,
                    skills,
                    warnings,
                    complete,
                },
                entries: winners,
                sources: self.clone(),
            },
        ))
    }

    pub(super) fn invalidate(&self) {
        self.scope
            .registry
            .generation
            .fetch_add(1, Ordering::AcqRel);
    }
}

fn source_authorization(
    request: &SkillProviderRequest,
    providers: &[Arc<dyn SkillProvider>],
) -> Result<ToolAuthorization> {
    let mut digest = Sha256::new();
    let mut part = |bytes: &[u8]| {
        digest.update((bytes.len() as u64).to_le_bytes());
        digest.update(bytes);
    };
    part(b"pl-tool/skill-discovery-authority/v1");
    part(request.workspace_root.as_os_str().as_encoded_bytes());
    part(&serde_json::to_vec(&request.config)?);
    match &request.system_dir {
        None => part(b"no-system-source"),
        Some(path) => {
            part(b"system-source");
            part(path.as_os_str().as_encoded_bytes());
        }
    }
    for provider in providers {
        let identity = provider.discovery_identity();
        if identity.trim().is_empty() {
            return Err(PureError::ConfigError(format!(
                "skill provider {} has an empty discovery capability identity",
                provider.id().as_str()
            )));
        }
        part(provider.id().as_str().as_bytes());
        part(identity.as_bytes());
    }
    Ok(ToolAuthorization::new(format!(
        "pl.skills-sources:{}",
        hex::encode(digest.finalize())
    )))
}
