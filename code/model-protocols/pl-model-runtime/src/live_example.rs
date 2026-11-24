//! Shared CLI for the independent protocol examples.
use std::{
    error::Error,
    future::Future,
    io::Write,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use clap::{Args, Subcommand, ValueEnum};
use pl_model_wire::catalog_http::{self, CatalogResponse};
use pl_model_wire::{
    adapter::Adapter,
    completion::{
        CompletionRequest, Message, MessageContent, MessageRole, ModelTextChannel, ReasoningConfig,
        ToolSpec, completion_response_message_text,
        stream::event::{ModelBlockKind, ModelStreamEvent},
    },
    config::ModelCatalogDiscovery,
    discovery::{self, ModelCatalogQueryError},
    model::{ModelInfo, ModelProtocolOptions},
    protocol::{ConnectionMode, ProtocolEndpoint, WireApi},
};

use crate::runtime::{CancellationToken, ModelInvocationContext, ModelRuntime, PromptCacheScope};

pub type ExampleResult = Result<(), Box<dyn Error>>;

#[derive(Args)]
pub struct Target {
    /// API root including the provider's version prefix.
    #[arg(long)]
    pub base_url: String,
}

impl Target {
    pub fn endpoint(
        &self,
        build: impl FnOnce(String) -> ProtocolEndpoint,
    ) -> Result<ProtocolEndpoint, Box<dyn Error>> {
        let url = reqwest::Url::parse(&self.base_url).map_err(|_| "invalid --base-url")?;
        if !matches!(url.scheme(), "http" | "https")
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
        {
            return Err(
                "base URL must be an HTTP(S) API root without credentials, query or fragment"
                    .into(),
            );
        }
        let key = std::env::var("MODEL_API_KEY")
            .ok()
            .filter(|key| !key.trim().is_empty())
            .ok_or("set MODEL_API_KEY before running this example")?;
        let mut endpoint = build(self.base_url.clone());
        endpoint.bearer_token = Some(key);
        Ok(endpoint)
    }
}

/// Runs a single selected scenario. Provider diagnostics may contain echoed request data.
pub async fn run(
    endpoint: ProtocolEndpoint,
    operation: impl AsyncFnOnce(ProtocolEndpoint) -> ExampleResult,
) -> ExampleResult {
    let key = endpoint.bearer_token.clone().unwrap_or_default();
    match operation(endpoint).await {
        Ok(()) => Ok(()),
        Err(error) => Err(redact(&error.to_string(), &key).into()),
    }
}

fn redact(text: &str, key: &str) -> String {
    if key.is_empty() {
        text.to_owned()
    } else {
        text.replace(key, "[redacted]")
    }
}

pub fn print(endpoint: &ProtocolEndpoint, text: &str) {
    println!(
        "{}",
        redact(text, endpoint.bearer_token.as_deref().unwrap_or_default())
    );
}

#[derive(Clone, Copy, ValueEnum)]
pub enum Wire {
    Chat,
    Responses,
    ResponsesWebsocket,
    Gemini,
}

impl Wire {
    fn api(self) -> WireApi {
        match self {
            Self::Chat => WireApi::ChatCompletions,
            Self::Responses | Self::ResponsesWebsocket => WireApi::Responses,
            Self::Gemini => WireApi::GeminiGenerateContent,
        }
    }

    fn connection(self) -> ConnectionMode {
        match self {
            Self::Chat | Self::Responses | Self::Gemini => ConnectionMode::Http,
            Self::ResponsesWebsocket => ConnectionMode::WebSocket,
        }
    }
}

#[derive(Subcommand)]
pub enum CommonCommand {
    /// Send one inference request using a streaming transport.
    Chat {
        #[arg(long)]
        model: String,
        #[arg(long)]
        prompt: String,
        #[arg(long, value_enum)]
        wire: Option<Wire>,
        /// Reasoning effort from the model's declared options.
        #[arg(long)]
        effort: Option<String>,
        /// Resolve a prompt cache key for a stable manual-debug session.
        #[arg(long)]
        cache_scope: Option<String>,
        /// Enable native incremental tool arguments on a Chat endpoint that supports them.
        #[arg(long)]
        tool_stream: bool,
        /// JSON file containing a list of canonical tool declarations.
        #[arg(long)]
        tools: Option<PathBuf>,
        /// Show provisional text as it arrives, including output from failed attempts.
        #[arg(long)]
        stream: bool,
    },
    /// Query the endpoint's current model inventory.
    Models {
        #[arg(long, value_enum)]
        wire: Option<Wire>,
    },
}

/// The protocol capabilities selected by an individual example.
pub struct Profile {
    pub default_wire: Wire,
    pub supported: &'static [WireApi],
    pub defaults: Vec<ModelInfo>,
    pub adapter: &'static Adapter,
    pub allow_tool_stream: bool,
}

impl CommonCommand {
    pub async fn execute(self, mut endpoint: ProtocolEndpoint, profile: Profile) -> ExampleResult {
        let Profile {
            default_wire,
            supported,
            defaults,
            adapter,
            allow_tool_stream,
        } = profile;
        let wire = match &self {
            Self::Chat { wire, .. } | Self::Models { wire } => wire.unwrap_or(default_wire),
        };
        let api = wire.api();
        if !supported.contains(&api) {
            return Err("the selected protocol does not support this wire API".into());
        }
        match self {
            Self::Chat {
                model,
                prompt,
                effort,
                cache_scope,
                tool_stream,
                tools,
                stream,
                ..
            } => {
                let mut model = defaults
                    .into_iter()
                    .find(|entry| {
                        entry.model_id == model && entry.binding.transport.protocol == api
                    })
                    .unwrap_or_else(|| ModelInfo::compatible(&model));
                model.binding.transport.protocol = api;
                model.binding.transport.default_connection_mode = wire.connection();
                if !model
                    .binding
                    .transport
                    .supported_connection_modes
                    .contains(&wire.connection())
                {
                    model
                        .binding
                        .transport
                        .supported_connection_modes
                        .push(wire.connection());
                }
                if api == WireApi::Responses
                    && !matches!(
                        model.binding.request.protocol,
                        ModelProtocolOptions::Responses(_)
                    )
                {
                    model.binding.request.protocol =
                        ModelProtocolOptions::Responses(Default::default());
                } else if api == WireApi::GeminiGenerateContent
                    && !matches!(
                        model.binding.request.protocol,
                        ModelProtocolOptions::GeminiGenerateContent(_)
                    )
                {
                    model.binding.request.protocol =
                        ModelProtocolOptions::GeminiGenerateContent(Default::default());
                }
                let tools: Vec<ToolSpec> = tools
                    .map(|path| {
                        let bytes = std::fs::read(path)?;
                        Ok::<_, Box<dyn Error>>(serde_json::from_slice(&bytes)?)
                    })
                    .transpose()?
                    .unwrap_or_default();
                if tool_stream && tools.is_empty() {
                    return Err("--tool-stream requires a non-empty --tools file".into());
                }
                if !tools.is_empty() {
                    model.capabilities.tools.function_calling = true;
                }
                if tool_stream {
                    match &mut model.binding.request.protocol {
                        ModelProtocolOptions::ChatCompletions(options) if allow_tool_stream => {
                            options.tool_stream = true
                        }
                        _ => {
                            return Err(
                                "the selected protocol does not support native tool streaming"
                                    .into(),
                            );
                        }
                    }
                }
                if let Some(effort) = effort.as_ref()
                    && !model.supported_efforts().contains(effort)
                {
                    return Err(format!(
                        "unsupported effort; declared choices: {:?}",
                        model.supported_efforts()
                    )
                    .into());
                }
                let mut request = CompletionRequest::builder()
                    .messages(vec![Message {
                        role: MessageRole::User,
                        content: MessageContent::text(prompt),
                        presentation: Default::default(),
                        reasoning_content: None,
                        tool_calls: None,
                        tool_result: None,
                        metadata: Default::default(),
                    }])
                    .tools(tools)
                    .build();
                request.reasoning = effort.map(|effort| ReasoningConfig {
                    effort: Some(effort),
                    summary: None,
                });
                adapter.bind(&mut endpoint, &mut model);
                let upload = adapter
                    .file_upload
                    .filter(|service| service.id == endpoint.service_capabilities.files);
                let runtime = ModelRuntime::bind(
                    "manual-protocol-example",
                    endpoint.clone(),
                    model,
                    adapter.codec,
                    upload,
                )?;
                let cancellation = CancellationToken::new();
                let mut context =
                    ModelInvocationContext::default().with_cancellation(Some(cancellation.clone()));
                if let Some(scope) = cache_scope {
                    if !endpoint
                        .effective_prompt_cache_policy(runtime.model())
                        .uses_prompt_cache_key()
                    {
                        return Err(
                            "the endpoint does not support an explicit prompt-cache key".into()
                        );
                    }
                    context = context.with_prompt_cache_scope(PromptCacheScope::thread(scope));
                }
                let live_output = stream.then(|| {
                    Arc::new(Mutex::new(StreamText::new(
                        endpoint.bearer_token.clone().unwrap_or_default(),
                    )))
                });
                let context = if let Some(output) = live_output.as_ref() {
                    let output = Arc::clone(output);
                    context.with_stream_observer(move |generation, event| {
                        if let ModelStreamEvent::BlockDelta {
                            kind:
                                ModelBlockKind::Text {
                                    channel: ModelTextChannel::Final,
                                },
                            delta,
                            ..
                        } = event
                        {
                            output
                                .lock()
                                .expect("example stream output lock")
                                .write(generation, delta);
                        }
                    })
                } else {
                    context
                };
                let result = with_interrupt(runtime.complete(request, context), cancellation).await;
                let showed_live_text = match live_output {
                    Some(output) => output
                        .lock()
                        .expect("example stream output lock")
                        .finish()?,
                    None => false,
                };
                let response = result?;
                if !showed_live_text {
                    print(&endpoint, &completion_response_message_text(&response));
                }
                if !response.tool_calls.is_empty() {
                    print(
                        &endpoint,
                        &serde_json::to_string_pretty(&response.tool_calls)?,
                    );
                }
                eprintln!(
                    "usage {}",
                    serde_json::to_string(&response.accounting.usage)?
                );
            }
            Self::Models { .. } => {
                let mut url: reqwest::Url =
                    format!("{}/models", endpoint.base_url.trim_end_matches('/')).parse()?;
                if !adapter.discovery_query_params.is_empty() {
                    let mut pairs = url.query_pairs_mut();
                    for &(name, value) in adapter.discovery_query_params {
                        pairs.append_pair(name, value);
                    }
                }
                let headers = endpoint
                    .request_headers(endpoint.bearer_token.as_deref(), &Default::default())?;
                let CatalogResponse::Updated { bytes, .. } =
                    catalog_http::fetch(url, headers, None).await?
                else {
                    return Err(ModelCatalogQueryError::UnexpectedNotModified.into());
                };
                let entries = discovery::models(
                    (adapter.parse_catalog_page)(&bytes)?.records,
                    &ModelCatalogDiscovery {
                        transport: pl_model_wire::model::ModelTransportProfile {
                            protocol: api,
                            default_connection_mode: wire.connection(),
                            supported_connection_modes: vec![wire.connection()],
                        },
                    },
                    adapter.discovery,
                    None,
                    &defaults,
                )?;
                for entry in entries {
                    print(&endpoint, &entry.model_id);
                }
            }
        }
        Ok(())
    }
}

async fn with_interrupt<T>(
    operation: impl Future<Output = T>,
    cancellation: CancellationToken,
) -> T {
    tokio::pin!(operation);
    tokio::select! {
        result = &mut operation => result,
        _ = tokio::signal::ctrl_c() => {
            cancellation.cancel();
            operation.await
        }
    }
}

struct StreamText {
    secret: String,
    generation: Option<u32>,
    pending: String,
    error: Option<std::io::Error>,
}

impl StreamText {
    fn new(secret: String) -> Self {
        Self {
            secret,
            generation: None,
            pending: String::new(),
            error: None,
        }
    }

    fn write(&mut self, generation: u32, text: &str) {
        if self.error.is_some() {
            return;
        }
        let mut output = std::io::stdout().lock();
        let result = (|| {
            if self.generation != Some(generation) {
                if self.generation.is_some() {
                    writeln!(
                        output,
                        "{}",
                        redact(&std::mem::take(&mut self.pending), &self.secret)
                    )?;
                }
                self.generation = Some(generation);
                writeln!(output, "[attempt {}]", generation + 1)?;
            }
            self.pending.push_str(text);
            output
                .write_all(release_redacted_prefix(&mut self.pending, &self.secret).as_bytes())?;
            output.flush()
        })();
        self.error = result.err();
    }

    fn finish(&mut self) -> std::io::Result<bool> {
        if let Some(error) = self.error.take() {
            return Err(error);
        }
        if self.generation.is_some() {
            writeln!(
                std::io::stdout().lock(),
                "{}",
                redact(&self.pending, &self.secret)
            )?;
            return Ok(true);
        }
        Ok(false)
    }
}

/// Keep a trailing partial match until it can be disambiguated by the next delta.
fn release_redacted_prefix(pending: &mut String, secret: &str) -> String {
    if secret.is_empty() {
        return std::mem::take(pending);
    }
    let last_match_end = pending
        .match_indices(secret)
        .last()
        .map_or(0, |(start, value)| start + value.len());
    let keep = secret
        .char_indices()
        .map(|(index, _)| index)
        .rev()
        .find(|&count| pending[last_match_end..].ends_with(&secret[..count]))
        .unwrap_or(0);
    let hold = pending.split_off(pending.len() - keep);
    redact(&std::mem::replace(pending, hold), secret)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stream_keeps_split_credentials_out_of_output_and_preserves_unicode() {
        let mut pending = String::from("正文 key-");
        assert_eq!(release_redacted_prefix(&mut pending, "key-密钥"), "正文 ");
        assert_eq!(pending, "key-");
        pending.push_str("密钥! key-秘");
        assert_eq!(
            release_redacted_prefix(&mut pending, "key-密钥"),
            "[redacted]! key-秘"
        );
        assert!(pending.is_empty());
    }
}
