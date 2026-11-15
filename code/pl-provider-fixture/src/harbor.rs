//! Offline Harbor task environment, using the same strict provider fixture as runtime tests.

use anyhow::Result;

use crate::{FixtureOptions, FixtureServer, Protocol, RealtimeToolCall, Reply, Step};

pub const PROMPT: &str = "Create harbor-result.txt containing ANYWK_HARBOR_OK\n";
pub const MODEL: &str = "vendor/harbor-fixture";

pub async fn serve(cancel: bool) -> Result<()> {
    let call = RealtimeToolCall {
        item_id: "harbor-write",
        call_id: "harbor-write",
        name: "exec_command",
        arguments: serde_json::json!({
            "command": if cancel {
                "while :; do printf 'ANYWK_HARBOR_OK\\n' >> harbor-result.txt; sleep 0.05; done"
            } else {
                "printf 'ANYWK_HARBOR_OK\\n' > harbor-result.txt"
            }
        })
        .to_string(),
    }
    .program("exec_command");
    let steps = vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            0,
            Reply::Sse(crate::responses_tool_calls("harbor-write", MODEL, &[call])),
        ),
        Step::tool_output(
            Protocol::ResponsesHttp,
            "harbor-write",
            "",
            1,
            if cancel {
                Reply::HangingSse(vec![])
            } else {
                Reply::Sse(crate::responses_text(
                    "Harbor fixture completed",
                    "harbor-done",
                    MODEL,
                ))
            },
        ),
    ];
    let server = FixtureServer::start_with_options(
        steps,
        FixtureOptions {
            bind_port: Some(19321),
            ..Default::default()
        },
    )
    .await?;
    println!("harbor_fixture_ready={}", server.base_url());
    tokio::signal::ctrl_c().await?;
    server.finish().await?;
    Ok(())
}
