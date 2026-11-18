use clap::Parser;
use pl_model_openai_wire::protocol::WireApi;
use pl_model_runtime::live_example::{CommonCommand, Profile, Target, Wire};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};

#[derive(Parser)]
struct Args {
    #[command(flatten)]
    target: Target,
    #[command(subcommand)]
    command: CommonCommand,
}

#[tokio::test]
async fn example_chat_uses_the_selected_wire_and_model() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "fixture prompt",
        0,
        Reply::Sse(responses_text("fixture output", "example", "custom-model")),
    )])
    .await
    .unwrap();
    let args = Args::try_parse_from([
        "live",
        "--base-url",
        "http://fixture.invalid",
        "chat",
        "--model",
        "custom-model",
        "--prompt",
        "fixture prompt",
        "--stream",
    ])
    .unwrap();
    let mut endpoint =
        pl_model_openai::endpoint::compatible_endpoint("fixture", fixture.base_url());
    endpoint.bearer_token = Some("fixture-secret".into());
    args.command
        .execute(
            endpoint,
            Profile {
                default_wire: Wire::Responses,
                supported: &[WireApi::Responses],
                defaults: vec![],
                adapter: &pl_model_openai::adapter::COMPATIBLE_ADAPTER,
                allow_tool_stream: false,
            },
        )
        .await
        .unwrap();
    let requests = fixture.finish().await.unwrap();
    assert_eq!(requests.len(), 1);
    assert!(requests[0].accepted);
    assert!(requests[0].path.ends_with("/responses"));
    assert_eq!(requests[0].body["model"], "custom-model");
    assert_eq!(requests[0].body["stream"], true);
}

#[test]
fn example_rejects_credential_bearing_urls_before_reading_the_key() {
    let target = Target {
        base_url: "https://user:secret@example.test/v1".into(),
    };
    let error = target
        .endpoint(|url| pl_model_openai::endpoint::compatible_endpoint("fixture", url))
        .unwrap_err()
        .to_string();
    assert!(error.contains("without credentials"));
    assert!(!error.contains("secret"));
}
