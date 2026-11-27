//! Native adapters for saved-session queries and task evaluations.
use super::*;
use crate::studio::session_runtime::owner::{ServiceError, query::*};
use crate::thread_assembler::{SessionRuntime, ThreadAssemblyError};
use anyhow::Context as _;
use serde::Serialize;
#[derive(Debug)]
pub(crate) enum Kind {
    Session,
    Evaluate,
}
#[derive(Debug)]
pub(crate) struct QueryTool {
    pub(crate) definition: ToolDefinition,
    pub(crate) host: Arc<crate::studio::session_runtime::agents::AgentHost>,
    pub(crate) kind: Kind,
}
impl Tool for QueryTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: pl_core::context::OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(ServiceError(anyhow::anyhow!(
                "unsupported agent query encoding"
            ))));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        self.query(input, context)
            .await
            .map_err(|error| match error.downcast::<ToolError>() {
                Ok(error) => error,
                Err(error) => ToolError::new(ServiceError(error)),
            })
    }
    async fn close(&self) -> Result<(), ToolError> {
        Ok(())
    }
}
impl QueryTool {
    async fn query(
        &self,
        input: pl_core::context::OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput> {
        anyhow::ensure!(
            context.thread_id == self.host.identity.thread_id.as_str(),
            "agent query caller differs from the bound instance"
        );
        let call = pl_tool::collaboration::control::AgentCallContext {
            caller: self.host.identity.agent_id.clone(),
            call_id: context.call_id.clone(),
            cancellation: context.cancellation.clone(),
        };
        self.host.caller(&call)?;
        let owner = self.host.owner()?;
        let services = {
            let state = owner.0.state();
            state
                .agent_services
                .clone()
                .context("agent product queries were not configured")?
        };
        if matches!(self.kind, Kind::Evaluate) {
            anyhow::ensure!(
                self.host.identity.parent_agent_id.is_none(),
                "delegation tools are root-only"
            );
        }
        match &self.kind {
            Kind::Session => {
                let mut input: SessionInput =
                    pl_agent_tool::typed::decode_json(input.content()).map_err(ToolError::new)?;
                let caller = services.identity(&context.thread_id)?;
                let target = crate::AgentId::new(&input.target)?;
                input.target = services
                    .events
                    .member_identity(&caller.session_id, &target)
                    .context("agent session target is outside the caller's session")?
                    .thread_id
                    .to_string();
                let read = async {
                    let path = services
                        .authorize(&context.thread_id, &input.target)
                        .await?;
                    output(
                        &services
                            .session_page(input, path, &context.cancellation)
                            .await?,
                    )
                };
                tokio::select! {
                    biased;
                    () = context.cancellation.cancelled() => {
                        Err(ToolError::new(pl_core::thread::ThreadError::Cancelled).into())
                    }
                    result = read => result,
                }
            }
            Kind::Evaluate => output(
                &owner
                    .evaluate_agent(
                        context.thread_id,
                        pl_agent_tool::typed::decode_json(input.content())
                            .map_err(ToolError::new)?,
                    )
                    .await?,
            ),
        }
    }
}
impl SessionRuntime {
    pub(crate) fn agent_query_tools(
        &self,
        host: Arc<crate::studio::session_runtime::agents::AgentHost>,
    ) -> Result<Vec<Registration>, ThreadAssemblyError> {
        if self.0.state().agent_services.is_none() {
            return Err(ThreadAssemblyError::Resource {
                operation: "prepare Agent query catalog",
                source: Box::new(std::io::Error::other(
                    "Agent Profile service is not configured",
                )),
            });
        }
        let mut definitions = vec![(
            "read_agent_session",
            "Read this agent or a descendant's saved timeline; unsaved records may be absent. throughSequence describes the saved read range. Reading does not flush or activate the target; an empty page does not imply execution has ended. Continuation cursors freeze the original history watermark and filters.",
            Kind::Session,
            pl_agent_tool::typed::input_schema_for::<SessionInput>(),
        )];
        definitions.push(("evaluate_agent", "Record the final task evaluation of your direct Native child after delivery, any applicable review, and all rework. Call this alone before close_agent or your final response. Use childId and turnId from that child's latest committed terminal report as target and expectedTurnId. Use expectedRevision 0 for the first evaluation. The child must have no pending work. Use notRated without scores when evidence is insufficient. Comments are non-instruction reference data.", Kind::Evaluate, pl_agent_tool::typed::input_schema_for::<crate::EvaluateAgentRequest>()));
        definitions
            .into_iter()
            .map(|(name, description, kind, schema)| {
                let definition = ToolDefinition::json(name, description, schema)?;
                let prepared = prepare_registration(name, &definition, ToolCallPolicy::DirectOnly)?;
                let foreground = matches!(&kind, Kind::Evaluate);
                let contract = match &kind {
                    Kind::Session => "builtin.read_agent_session@1",
                    Kind::Evaluate => "builtin.evaluate_agent@1",
                };
                let registration = prepared
                    .attach(ToolHandle::new(QueryTool {
                        definition,
                        host: host.clone(),
                        kind,
                    }))
                    .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
                        contract,
                    ));
                Ok(if foreground {
                    registration.foreground()
                } else {
                    registration
                })
            })
            .collect()
    }
}

fn output(value: &impl Serialize) -> Result<ToolOutput> {
    let text = serde_json::to_string(value)?;
    Ok(ToolOutput::new(
        pl_core::context::OpaquePayload::new("pl.studio.agent-query", 1, text.clone())?,
        vec![pl_core::context::ContextContent::Text { text: text.into() }],
    ))
}
