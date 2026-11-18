use std::path::PathBuf;

use clap::{Parser, Subcommand};
use pl_model_openai::{images, search};
use pl_model_openai_wire::protocol::{ImageGenerationCapabilities, WireApi};
use pl_model_runtime::live_example::{self, CommonCommand, ExampleResult, Profile, Target, Wire};
use pl_tool_search::tools::web_search::{SearchCommands, SearchQuery};

#[derive(Parser)]
struct Args {
    #[command(flatten)]
    target: Target,
    /// Use the conservative capability defaults of a generic compatible endpoint.
    #[arg(long)]
    compatible: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    #[command(flatten)]
    Common(CommonCommand),
    /// Call an endpoint that supports the OpenAI Images API.
    Image {
        #[arg(long)]
        model: String,
        #[arg(long)]
        prompt: String,
        #[arg(long)]
        output: PathBuf,
    },
    /// Call an endpoint that explicitly supports the compatible /alpha/search API.
    Search {
        #[arg(long)]
        model: String,
        #[arg(long)]
        query: String,
    },
}

#[tokio::main]
async fn main() -> ExampleResult {
    let args = Args::parse();
    let endpoint = args.target.endpoint(|url| {
        if args.compatible {
            pl_model_openai::endpoint::compatible_endpoint("manual compatible endpoint", url)
        } else {
            pl_model_openai::endpoint::endpoint(Some(url))
        }
    })?;
    live_example::run(endpoint, async move |mut endpoint| {
        match args.command {
            Command::Common(command) => {
                command
                    .execute(
                        endpoint,
                        Profile {
                            default_wire: if args.compatible {
                                Wire::Chat
                            } else {
                                Wire::Responses
                            },
                            supported: &[WireApi::ChatCompletions, WireApi::Responses],
                            defaults: if args.compatible {
                                vec![]
                            } else {
                                pl_model_openai::bundled_definition()?.models
                            },
                            adapter: if args.compatible {
                                &pl_model_openai::adapter::COMPATIBLE_ADAPTER
                            } else {
                                &pl_model_openai::adapter::ADAPTER
                            },
                            allow_tool_stream: false,
                        },
                    )
                    .await?;
            }
            Command::Image {
                model,
                prompt,
                output,
            } => {
                if output.try_exists()? {
                    return Err("image output already exists".into());
                }
                endpoint.service_capabilities.image_generation =
                    Some(ImageGenerationCapabilities::openai_images());
                let image = images::ImagesClient::new(endpoint)?
                    .generate(images::ImageGenerationRequest {
                        model,
                        prompt,
                        background: images::ImageGenerationBackground::Opaque,
                    })
                    .await?;
                use std::io::Write;
                std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&output)?
                    .write_all(&image.bytes)?;
                println!("Wrote {} bytes ({})", image.bytes.len(), image.media_type);
            }
            Command::Search { model, query } => {
                let client = search::WebSearchClient::new(&search::SearchEndpoint {
                    base_url: endpoint.base_url.clone(),
                    bearer_token: endpoint.bearer_token.clone(),
                    http_headers: endpoint.http_headers.clone(),
                })?;
                let result = client
                    .search(&search::SearchRequest {
                        id: format!("manual-{}", uuid::Uuid::new_v4()),
                        model,
                        input: None,
                        commands: SearchCommands {
                            search_query: Some(vec![SearchQuery {
                                q: query,
                                recency: None,
                                domains: None,
                            }]),
                            ..Default::default()
                        },
                        settings: search::SearchSettings {
                            user_location: None,
                            search_context_size: None,
                            filters: None,
                            allowed_callers: vec![search::SearchAllowedCaller::Direct],
                            external_web_access: search::ExternalWebAccess::Boolean(true),
                        },
                        max_output_tokens: None,
                    })
                    .await?;
                live_example::print(&endpoint, &serde_json::to_string_pretty(&result)?);
            }
        }
        Ok(())
    })
    .await
}
