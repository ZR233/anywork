//! Input validation, attachment preparation and wire-body assembly.
use crate::completion::{CompletionFailure, CompletionRequest, InferenceModelObservation};
use crate::runtime::{ModelInvocationContext, ModelRuntime};
use crate::runtime::{
    attachments::AttachmentPreparationError, invocation_context::InvocationPurpose,
};
use pl_model_wire::wire_codec::{EncodeHttpRequestInput, PreparedHttpRequest};
use pl_protocol::{PureError, Result};

impl ModelRuntime {
    pub(in crate::runtime) async fn prepare_attachments(
        &self,
        request: &mut CompletionRequest,
        context: &ModelInvocationContext,
    ) -> std::result::Result<(), (CompletionFailure, bool)> {
        let mut candidate = request.clone();
        let prepare = async {
            crate::runtime::attachments::AttachmentBackend {
                endpoint: &self.endpoint,
                upload: self.upload,
                model: &self.model,
                client: &self.http_client,
                session: &context.session,
                fingerprint: self.connection_fingerprint(),
                now: self
                    .clock
                    .unix_seconds()
                    .map_err(|source| AttachmentPreparationError {
                        source,
                        replay_safe: true,
                    })?,
                cancellation: context.cancellation.clone().unwrap_or_default(),
            }
            .prepare(&mut candidate)
            .await
        };
        let result = if let Some(token) = &context.cancellation {
            tokio::select! {
                biased;
                _ = token.cancelled() => return Err((CompletionFailure::cancelled(
                    PureError::LlmError("attachment preparation cancelled".into()), Box::default()), false)),
                result = prepare => result,
            }
        } else {
            prepare.await
        };
        result.map_err(|error| (error.source.into(), error.replay_safe))?;
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
    ) -> Result<(PreparedHttpRequest, InferenceModelObservation)> {
        if request.service_tier.is_some() && !matches!(purpose, InvocationPurpose::Completion) {
            return Err(PureError::ConfigError(
                "service_tier is only supported for completions".into(),
            ));
        }
        let prompt_cache_key = prompt_cache_key.filter(|_| {
            self.endpoint
                .effective_prompt_cache_policy(&self.model)
                .uses_prompt_cache_key()
        });
        let request = crate::runtime::context::project_request(
            &self.endpoint,
            &self.model,
            &self.account_id,
            self.codec,
            request,
        )?;
        let (compaction_body, is_compaction) = match purpose {
            InvocationPurpose::RemoteCompaction { body, .. } => (Some(body), true),
            InvocationPurpose::Completion => (None, false),
        };
        let prepared = self.codec.encode_http_request(EncodeHttpRequestInput {
            endpoint: &self.endpoint,
            model: &self.model,
            request: &request,
            prompt_cache_key,
            compaction_body,
            is_compaction,
        })?;
        let sent_model = prepared.sent_model.clone();
        Ok((
            prepared,
            InferenceModelObservation {
                configured_model: self.model.base.slug.clone(),
                sent_model,
                reported_model: None,
            },
        ))
    }
}
