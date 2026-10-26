use super::super::read_budget::require_budget;
use super::{
    super::StudioRuntime, SkillSearchInvocationPolicy, SkillSearchResourceBase, SkillSearchSummary,
    SkillSource, SkillsReadTarget, SkillsSearchResult,
};
use anyhow::Result;
use pl_protocol::ObservedResource;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::future::Future;

impl StudioRuntime {
    pub fn skills_discover(
        &self,
        project_id: String,
    ) -> impl Future<Output = Result<SkillsReadTarget>> + Send + 'static + use<> {
        let runtime = self.clone();
        let pending = self.read_calls.run(async move {
            runtime.project_record(&project_id).await?;
            let source = runtime.skills_source.source(&project_id)?;
            let captured = runtime.discover_skills(&project_id).await?;
            let publication = captured.publication.ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Unavailable,
                    "Studio Skills discovery has no original product capture",
                    false,
                )
            })?;
            let target = source.expose_committed(&publication)?;
            Ok((target, publication))
        });
        async move {
            let (target, _capture) = pending.await?;
            Ok(target)
        }
    }
    /// Uses only a current Ready catalog with the current configuration fingerprint. The legacy
    /// selector supplies matching/ranking, not authorization; both sides of the await recheck the
    /// original publication and never cache the result as a future execution capability.
    pub fn skills_search(
        &self,
        project_id: String,
        query: String,
        limit: u32,
    ) -> impl Future<Output = Result<SkillsSearchResult>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if query.trim().is_empty() || !(1..=50).contains(&limit) {
                return Err(StudioError::invalid_argument(
                    "Skill search requires a nonempty query and a limit in 1..=50",
                )
                .into());
            }
            runtime.project_record(&project_id).await?;
            let source = runtime.skills_source.source(&project_id)?;
            let original = source.current()?;
            if !matches!(
                original.source_status.metadata(),
                ObservedResource::Ready(_)
            ) {
                return Err(unavailable().into());
            }
            let material = original.material.as_ref().ok_or_else(unavailable)?;
            let settings = runtime.config_runtime.read()?;
            let fingerprint =
                super::super::skill_catalog::skills_fingerprint(&settings.config.skills)?;
            if material.value.config_fingerprint != fingerprint {
                return Err(unavailable().into());
            }
            let result = runtime
                .search_skills(&project_id, &query, limit as usize)
                .await?;
            let current = source.current()?;
            if current.revision != original.revision
                || result.catalog_revision != material.value.catalog_revision
                || !matches!(current.source_status.metadata(), ObservedResource::Ready(_))
                || runtime.config_runtime.read()?.revision != settings.revision
            {
                return Err(StudioError::new(
                    StudioErrorCode::Superseded,
                    "Skills catalog changed during the original search",
                    true,
                )
                .into());
            }
            let result = search_result(result)?;
            require_budget(&result)?;
            Ok(result)
        })
    }
}
/// Keeps the exact discovery publication alive through command result delivery. Existing Turn
/// discovery consumers use `snapshot`; product commands expose only `publication`'s target.
pub struct SkillsDiscovery {
    pub(crate) snapshot: crate::SkillsStateSnapshot,
    pub(crate) publication: Option<std::sync::Arc<super::source::SkillsSnapshot>>,
}
impl From<SkillsDiscovery> for crate::StudioSkillsStateSnapshot {
    fn from(discovery: SkillsDiscovery) -> Self {
        Self::from(discovery.snapshot)
    }
}
impl From<SkillsDiscovery> for crate::SkillsStateSnapshot {
    fn from(discovery: SkillsDiscovery) -> Self {
        discovery.snapshot
    }
}
fn search_result(result: crate::SkillSearchResult) -> Result<SkillsSearchResult> {
    use pl_tool::skill::{SkillResourceBase, SkillSourceKind};
    let matches = result
        .matches
        .into_iter()
        .map(|value| {
            let resource_base = match value.resource_base {
                SkillResourceBase::Directory { path } => SkillSearchResourceBase::Directory {
                    path: path
                        .to_str()
                        .ok_or_else(|| {
                            StudioError::new(
                                StudioErrorCode::Protocol,
                                "Skill path is not representable as UTF-8",
                                false,
                            )
                        })?
                        .to_owned(),
                },
                SkillResourceBase::Url { url } => SkillSearchResourceBase::Url { url },
                SkillResourceBase::Opaque { description } => {
                    SkillSearchResourceBase::Opaque { description }
                }
            };
            Ok(SkillSearchSummary {
                name: value.name,
                description: value.description,
                category: value.category,
                platforms: value.platforms,
                source: match value.source {
                    SkillSourceKind::Project => SkillSource::Project,
                    SkillSourceKind::User => SkillSource::User,
                    SkillSourceKind::System => SkillSource::System,
                    SkillSourceKind::External => SkillSource::External,
                },
                provider_id: value.provider_id.as_str().to_owned(),
                invocation: SkillSearchInvocationPolicy {
                    model_invocable: value.invocation.model_invocable,
                    user_invocable: value.invocation.user_invocable,
                },
                resource_base,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(SkillsSearchResult {
        project_id: result.project_id,
        catalog_revision: result.catalog_revision,
        matches,
        truncated: result.truncated,
    })
}
fn unavailable() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "Skills catalog is not currently Ready for this configuration; discover it explicitly",
        true,
    )
}
