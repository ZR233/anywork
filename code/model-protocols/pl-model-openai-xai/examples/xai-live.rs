use clap::Parser;
use pl_model_runtime::live_example::{self, CommonCommand, ExampleResult, Profile, Target, Wire};
use pl_model_wire::protocol::WireApi;

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
        .endpoint(|url| pl_model_openai_xai::endpoint::endpoint(Some(url)))?;
    live_example::run(endpoint, async move |endpoint| {
        args.command
            .execute(
                endpoint,
                Profile {
                    default_wire: Wire::Responses,
                    supported: &[WireApi::Responses, WireApi::ChatCompletions],
                    defaults: pl_model_openai_xai::bundled_definition()?.models,
                    adapter: &pl_model_openai_xai::adapter::ADAPTER,
                    allow_tool_stream: false,
                },
            )
            .await
    })
    .await
}
