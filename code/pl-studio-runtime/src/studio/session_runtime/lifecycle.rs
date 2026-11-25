//! Studio resource handoff, preservation and publication around Core transactions.
use super::*;

impl SessionRuntime {
    pub(crate) async fn close_prepared_resources(
        &self,
        id: &str,
        resources: &crate::session::PreparedResources,
    ) -> Result<(), ThreadAssemblyError> {
        let scope = match resources {
            crate::session::PreparedResources::Native(native) => native,
            crate::session::PreparedResources::Acp(acp) => {
                let events = self
                    .0
                    .state()
                    .agent_services
                    .as_ref()
                    .map(|services| services.events.clone());
                let settlement = if let Some(events) = events {
                    acp.settle_association(&events).await.map_err(|source| {
                        ThreadAssemblyError::Resource {
                            operation: "settle successful ACP session association",
                            source: source.into_boxed_dyn_error(),
                        }
                    })
                } else {
                    Ok(())
                };
                let outcome = acp.close().await;
                settlement?;
                return if outcome.local_complete {
                    Ok(())
                } else {
                    Err(ThreadAssemblyError::Unpublished(id.into()))
                };
            }
        };
        scope
            .candidates
            .retry(None)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "close preparation candidates",
                source: source.into_boxed_dyn_error(),
            })?;
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services
                .factory
                .close_scope_tools(id, scope)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "close preparation binding and MCP",
                    source: source.into_boxed_dyn_error(),
                })?;
        }
        if scope.has_obligations() {
            return Err(ThreadAssemblyError::Unpublished(id.into()));
        }
        Ok(())
    }

    pub(crate) fn finish_native_binding_installation(
        &self,
        resources: &Arc<crate::session::NativeResources>,
        thread: &ThreadHandle,
    ) {
        if resources.binding().is_some() {
            resources.observe_binding(thread.runtime_binding());
            if let Some(services) = self.0.state().agent_services.as_ref() {
                services.factory.notify_lsp_binding_changed();
            }
        }
    }
    pub(crate) async fn publish_prepared_root(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let services = { self.0.state().agent_services.clone() };
        if let Some(services) = services
            && services
                .store
                .thread_preparation(id)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "read root preparation publication",
                    source: source.into_boxed_dyn_error(),
                })?
                .is_some()
        {
            services
                .store
                .publish_preparation(id)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "confirm root preparation publication",
                    source: source.into_boxed_dyn_error(),
                })?;
        }
        Ok(())
    }
    pub(crate) async fn finish_native_retirement(
        &self,
        id: &str,
        resources: &Arc<crate::session::NativeResources>,
        incarnation: &Arc<()>,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services
                .factory
                .close_scope_tools(id, resources)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "close Native tool binding and MCP",
                    source: source.into_boxed_dyn_error(),
                })?;
        }
        self.drain_observation_for_purpose(id, purpose).await?;
        self.join_close_storage_for_purpose(id, purpose).await?;
        self.close_published_resources(id, incarnation).await?;
        let retired = !self
            .0
            .state()
            .activation
            .unpublished_children
            .contains_key(id);
        self.confirm_preparation_close_for_purpose(id, retired, purpose)
            .await?;
        if resources.has_obligations() {
            return Err(ThreadAssemblyError::Unpublished(id.into()));
        }
        Ok(())
    }
}
