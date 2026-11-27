use super::FeishuErrorKind;
use crate::bots::test_support::Fixture;
use crate::protocol::*;
use anyhow::Result;
use std::sync::Arc;

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
struct PrivateBotBackendCause(&'static str);

#[test]
fn bot_tool_error_preserves_the_typed_backend_cause_only_for_trusted_callers() {
    use super::{BotToolError, FeishuError};
    use std::error::Error;
    const MARKER: &str = "PRIVATE_BACKEND_SENTINEL";
    let original = FeishuError::new(
        FeishuErrorKind::Transport,
        "safe outer bot failure",
        true,
        None,
    )
    .with_source(PrivateBotBackendCause(MARKER));
    let safe = BotToolError::from(original);
    assert!(safe.to_string().contains("safe outer bot failure"));
    assert!(!safe.to_string().contains(MARKER));
    assert!(!format!("{safe:?}").contains(MARKER));
    assert!(safe.source().is_none());
    assert_eq!(safe.original().kind(), FeishuErrorKind::Transport);
    assert_eq!(
        safe.original()
            .source()
            .unwrap()
            .downcast_ref::<PrivateBotBackendCause>()
            .unwrap()
            .0,
        MARKER
    );
}

#[tokio::test]
async fn independent_bot_tools_use_studio_authorization_and_reject_cross_project_access()
-> Result<()> {
    use pl_agent_tool::Tool;
    use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
    use pl_tool::bots::{BotToolKind, ThreadBotTool};
    let fixture = Fixture::new().await?;
    let host = Arc::new(crate::bots::StudioBotSessionHost {
        runtime: fixture.bots.clone(),
    });
    let context = || CallContext {
        thread_id: "bot-tools".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    };
    let result = async {
        let kind = BotToolKind::ListBots;
        let list = ThreadBotTool::new(
            host.clone(),
            kind,
            fixture.workspace_id.clone(),
            kind.declaration(),
        );
        let output = list
            .execute(OpaquePayload::new("application/json", 1, "{}")?, context())
            .await?;
        assert_eq!(output.data(), Some(&serde_json::json!([])));
        let config = fixture.managed.config.lock().await.clone();
        fixture
            .host
            .runtime
            .save_bot(SaveBotRequest {
                operation_id: "allow-domain-tools".into(),
                bot_id: Some(config.id.clone()),
                expected_config_revision: config.config_revision,
                name: config.name,
                workspace_id: config.workspace_id,
                app_id: "cli_archive_fixture".into(),
                secret: BotSecretUpdate::Preserve,
                enabled: false,
                tools_enabled: true,
                model_route: None,
            })
            .await?;
        let output = list
            .execute(OpaquePayload::new("application/json", 1, "{}")?, context())
            .await?;
        let bots = output.data().expect("bot list data");
        assert_eq!(bots[0]["id"], config.id);
        assert_eq!(bots[0]["toolsEnabled"], true);
        assert!(bots[0].get("appId").is_none());
        for (kind, arguments) in [
            (
                BotToolKind::ListConversations,
                serde_json::json!({"botId":config.id}),
            ),
            (
                BotToolKind::ReadMessages,
                serde_json::json!({"botId":config.id,"chatId":"chat"}),
            ),
            (
                BotToolKind::SendMessage,
                serde_json::json!({"botId":config.id,"chatId":"chat","text":"do not send"}),
            ),
        ] {
            let tool = ThreadBotTool::new(
                host.clone(),
                kind,
                "other-project".into(),
                kind.declaration(),
            );
            let error = tool
                .execute(
                    OpaquePayload::new("application/json", 1, arguments.to_string())?,
                    context(),
                )
                .await
                .unwrap_err();
            assert_eq!(
                error
                    .source
                    .downcast_ref::<crate::bots::host::BotToolError>()
                    .expect("safe Studio authorization error")
                    .original()
                    .kind(),
                FeishuErrorKind::Permission
            );
        }
        Ok::<(), anyhow::Error>(())
    }
    .await;
    let shutdown = fixture.host.runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    Ok(())
}
