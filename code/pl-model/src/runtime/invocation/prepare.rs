//! Input validation, attachment preparation and wire-body assembly.
use crate::completion::{CompletionFailure, CompletionRequest, InferenceModelObservation};
use crate::runtime::invocation_context::InvocationPurpose;
use crate::runtime::openai::OpenAiRequestBody;
use crate::runtime::{ModelInvocationContext, ModelRuntime};
use pl_protocol::{PureError, Result};

impl ModelRuntime {
    pub(in crate::runtime) async fn prepare_attachments(
        &self,
        request: &mut CompletionRequest,
        context: &ModelInvocationContext,
    ) -> std::result::Result<(), CompletionFailure> {
        let mut candidate = request.clone();
        let prepare = async {
            crate::runtime::attachments::AttachmentBackend {
                endpoint: &self.endpoint,
                model: &self.model,
                client: &self.http_client,
                session: &context.session,
                fingerprint: self.connection_fingerprint(),
                now: self.clock.unix_seconds()?,
                cancellation: context.cancellation.clone().unwrap_or_default(),
            }
            .prepare(&mut candidate)
            .await
        };
        if let Some(token) = &context.cancellation {
            tokio::select! {
                biased;
                _ = token.cancelled() => return Err(CompletionFailure::cancelled(
                    PureError::LlmError("attachment preparation cancelled".into()), Box::default())),
                result = prepare => result?,
            }
        } else {
            prepare.await?;
        }
        *request = candidate;
        Ok(())
    }
    pub(in crate::runtime) fn prompt_cache_key(
        &self,
        context: &ModelInvocationContext,
    ) -> Result<Option<String>> {
        context
            .prompt_cache_scope
            .as_ref()
            .map(|scope| scope.resolve(&self.account_id, &self.endpoint, &self.model))
            .transpose()
            .map(Option::flatten)
    }
    pub(in crate::runtime) fn prepare_request_body(
        &self,
        request: CompletionRequest,
        prompt_cache_key: Option<&str>,
        purpose: &InvocationPurpose,
    ) -> Result<(OpenAiRequestBody, InferenceModelObservation)> {
        let prompt_cache_key = prompt_cache_key.filter(|_| {
            self.endpoint
                .effective_prompt_cache_policy(&self.model)
                .uses_prompt_cache_key()
        });
        let request = crate::runtime::context::project_request(
            &self.endpoint,
            &self.model,
            &self.account_id,
            request,
        )?;
        let mut body = crate::runtime::openai::build_request(
            self.model.binding.transport.protocol,
            self.endpoint
                .protocol
                .instruction_wire_role(self.model.binding.transport.protocol),
            &request,
            &self.model,
            prompt_cache_key,
            self.endpoint.chatgpt_session.is_some(),
        )?;
        if let InvocationPurpose::RemoteCompaction {
            body: compaction, ..
        } = purpose
        {
            body.apply_compaction_body(compaction);
        }
        body.reject_reserved_instruction_channel()?;
        body.validate_prompt_cache_key(prompt_cache_key)?;
        if matches!(purpose, InvocationPurpose::RemoteCompaction { .. }) {
            body.prepare_compaction();
        }
        let sent_model = body.sent_model()?;
        Ok((
            body,
            InferenceModelObservation {
                configured_model: self.model.model_id.clone(),
                sent_model,
                reported_model: None,
            },
        ))
    }
}
