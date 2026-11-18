use clap::Parser;
use pl_model_runtime::live_example::{self, CommonCommand, ExampleResult, Profile, Target, Wire};
use pl_model_types::protocol::{ProtocolEndpoint, WireApi};

#[derive(Parser)]
struct Args {
    #[command(flatten)]
    target: Target,
    #[command(subcommand)]
    command: CommonCommand,
}

#[tokio::main]
async fn main() -> ExampleResult {
    let args = Args::parse();
    let endpoint = args
        .target
        .endpoint(|url| ProtocolEndpoint::zhipu(Some(url)))?;
    live_example::run(endpoint, async move |endpoint| {
        args.command
            .execute(
                endpoint,
                Profile {
                    default_wire: Wire::Chat,
                    supported: &[WireApi::ChatCompletions, WireApi::Responses],
                    defaults: {
                        let mut models = pl_model_openai_glm::models::models();
                        models.extend(pl_model_openai_glm::models::responses_models());
                        models
                    },
                    parse: pl_model_openai_glm::generic_catalog::records,
                    allow_tool_stream: true,
                    upload: None,
                },
            )
            .await
    })
    .await
}
