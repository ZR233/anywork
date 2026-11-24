use clap::Parser;
use pl_model_wire::protocol::WireApi;
use pl_model_runtime::live_example::{self, CommonCommand, ExampleResult, Profile, Target, Wire};

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
        .endpoint(|url| pl_model_openai_glm::endpoint::endpoint(Some(url)))?;
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
                    adapter: &pl_model_openai_glm::adapter::ADAPTER,
                    allow_tool_stream: true,
                },
            )
            .await
    })
    .await
}
