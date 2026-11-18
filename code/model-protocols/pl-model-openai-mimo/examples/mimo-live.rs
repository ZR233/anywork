use clap::Parser;
use pl_model_runtime::live_example::{self, CommonCommand, ExampleResult, Profile, Target, Wire};
use pl_model_types::protocol::{ProtocolEndpoint, ProtocolKind, WireApi};

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
    let endpoint = args.target.endpoint(|url| {
        ProtocolEndpoint::compatible("MiMo", url).with_protocol(ProtocolKind::MiMo)
    })?;
    live_example::run(endpoint, async move |endpoint| {
        args.command
            .execute(
                endpoint,
                Profile {
                    default_wire: Wire::Chat,
                    supported: &[WireApi::ChatCompletions],
                    defaults: pl_model_openai_mimo::models::models(),
                    parse: pl_model_openai_mimo::generic_catalog::records,
                    allow_tool_stream: false,
                    upload: None,
                },
            )
            .await
    })
    .await
}
