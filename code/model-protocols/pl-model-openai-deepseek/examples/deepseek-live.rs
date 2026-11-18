use std::{
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use clap::{Parser, Subcommand};
use pl_model_openai_deepseek::{UPLOAD, deepseek_catalog, tools, upload};
use pl_model_runtime::live_example::{self, CommonCommand, ExampleResult, Profile, Target, Wire};
use pl_model_types::{
    completion::{AttachmentInput, AttachmentModality, AttachmentSource},
    files::FileUploadRequest,
    protocol::{ProtocolEndpoint, StandaloneWebSearchDialect, WireApi},
};

#[derive(Parser)]
struct Args {
    #[command(flatten)]
    target: Target,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    #[command(flatten)]
    Common(CommonCommand),
    /// Upload an explicit local file through DeepSeek's Files API.
    Upload {
        #[arg(long)]
        file: PathBuf,
        #[arg(long, default_value = "application/octet-stream")]
        media_type: String,
    },
    /// Search using an endpoint that implements DeepSeek Search & Fetch.
    Search {
        #[arg(long)]
        query: String,
    },
    /// Fetch a public page using an endpoint that implements DeepSeek Search & Fetch.
    Fetch {
        #[arg(long)]
        url: String,
    },
}

#[tokio::main]
async fn main() -> ExampleResult {
    let args = Args::parse();
    let endpoint = args
        .target
        .endpoint(|url| ProtocolEndpoint::deepseek(Some(url)))?;
    live_example::run(endpoint, async move |mut endpoint| {
        match args.command {
            Command::Common(command) => {
                command
                    .execute(
                        endpoint,
                        Profile {
                            default_wire: Wire::Chat,
                            supported: &[WireApi::ChatCompletions, WireApi::Responses],
                            defaults: pl_model_openai_deepseek::bundled_definition()?.models,
                            parse: deepseek_catalog::records,
                            allow_tool_stream: false,
                            upload: Some(UPLOAD),
                        },
                    )
                    .await?;
            }
            Command::Upload { file, media_type } => {
                let bytes = std::sync::Arc::<[u8]>::from(std::fs::read(&file)?);
                let input = AttachmentInput {
                    attachment_id: "manual-upload".into(),
                    modality: AttachmentModality::File,
                    media_type,
                    filename: file
                        .file_name()
                        .map(|name| name.to_string_lossy().into_owned()),
                    source: AttachmentSource::Bytes {
                        bytes: bytes.clone(),
                    },
                };
                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .retry(reqwest::retry::never())
                    .build()?;
                let result = upload::upload_file(FileUploadRequest {
                    client: &client,
                    endpoint: &endpoint,
                    model_headers: &Default::default(),
                    input: &input,
                    bytes: &bytes,
                    now: SystemTime::now()
                        .duration_since(UNIX_EPOCH)?
                        .as_secs()
                        .try_into()?,
                })
                .await?
                .ok_or("endpoint does not support DeepSeek Files")?;
                live_example::print(&endpoint, &result.id);
            }
            command @ (Command::Search { .. } | Command::Fetch { .. }) => {
                endpoint.service_capabilities.web_search.standalone =
                    Some(StandaloneWebSearchDialect::DeepSeekToolsApi);
                let client = tools::ToolsClient::new(&endpoint, tools::ToolsOptions::default())?;
                let output = match command {
                    Command::Search { query } => serde_json::to_string_pretty(
                        &client
                            .search(&tools::SearchRequest { query }, Default::default())
                            .await?,
                    )?,
                    Command::Fetch { url } => serde_json::to_string_pretty(
                        &client
                            .fetch(&tools::FetchRequest { url }, Default::default())
                            .await?,
                    )?,
                    _ => unreachable!(),
                };
                live_example::print(&endpoint, &output);
            }
        }
        Ok(())
    })
    .await
}
