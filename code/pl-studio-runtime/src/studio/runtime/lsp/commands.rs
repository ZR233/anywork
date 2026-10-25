use super::{super::StudioRuntime, LspReadTarget};
use anyhow::Result;
use pl_protocol::studio::LspResetRequest;
use std::future::Future;

impl StudioRuntime {
    pub fn lsp_probe(
        &self,
        project_id: String,
    ) -> impl Future<Output = Result<LspReadTarget>> + Send + 'static + use<> {
        let runtime = self.clone();
        let pending = self.read_calls.run(async move {
            runtime.lsp_source.ensure_open()?;
            let captured = runtime.probe_lsp_server(&project_id).await?;
            let target = runtime.lsp_source.expose_committed(&captured)?;
            Ok((target, captured))
        });
        async move {
            let (target, _capture) = pending.await?;
            Ok(target)
        }
    }
    pub fn lsp_repair(
        &self,
        project_id: String,
        server_id: String,
    ) -> impl Future<Output = Result<LspReadTarget>> + Send + 'static + use<> {
        let runtime = self.clone();
        let pending = self.read_calls.run(async move {
            runtime.lsp_source.ensure_open()?;
            let captured = runtime.repair_lsp_server(&project_id, &server_id).await?;
            let target = runtime.lsp_source.expose_committed(&captured)?;
            Ok((target, captured))
        });
        async move {
            let (target, _capture) = pending.await?;
            Ok(target)
        }
    }
    pub fn lsp_reset_server(
        &self,
        project_id: String,
        server_id: String,
    ) -> impl Future<Output = Result<LspReadTarget>> + Send + 'static + use<> {
        self.lsp_reset_product(LspResetRequest::Server {
            project_id,
            server_id,
        })
    }
    pub fn lsp_reset_workspace(
        &self,
        project_id: String,
    ) -> impl Future<Output = Result<LspReadTarget>> + Send + 'static + use<> {
        self.lsp_reset_product(LspResetRequest::Workspace { project_id })
    }
    fn lsp_reset_product(
        &self,
        request: LspResetRequest,
    ) -> impl Future<Output = Result<LspReadTarget>> + Send + 'static + use<> {
        let runtime = self.clone();
        let pending = self.read_calls.run(async move {
            runtime.lsp_source.ensure_open()?;
            let captured = runtime.reset_lsp_request(request).await?;
            let target = runtime.lsp_source.expose_committed(&captured)?;
            Ok((target, captured))
        });
        async move {
            let (target, _capture) = pending.await?;
            Ok(target)
        }
    }
}
