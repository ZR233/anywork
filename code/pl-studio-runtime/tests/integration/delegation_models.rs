use anyhow::Result;

use crate::support;

#[tokio::test]
async fn profile_tool_reports_frozen_mode_without_automatic_preset_routes() -> Result<()> {
    use pl_studio_runtime::{
        CreateThreadRequest, DelegationMode, NewThreadModelRoute, StudioPromptInput,
        ThreadWorkspaceMode,
    };
    use serde_json::json;
    use support::{Environment, completed_prompt, prompt_step, receipt, text_reply, tool_reply};
    let cases = [
        ("automatic", DelegationMode::Automatic),
        ("profile", DelegationMode::Profile),
    ];
    for (label, mode) in cases {
        let env = Environment::new(
            vec![
                prompt_step(
                    label,
                    0,
                    tool_reply("list_agent_profiles", label, json!({})),
                ),
                prompt_step(
                    label,
                    1,
                    text_reply("catalog received", &format!("done-{label}")),
                ),
            ],
            vec![],
        )
        .await?;
        let result = async {
            let started = env
                .runtime
                .create_thread_command(
                    env.project.id.clone(),
                    CreateThreadRequest {
                        title: Some(label.into()),
                        input: StudioPromptInput {
                            input_id: format!("input-{label}"),
                            text: label.into(),
                            attachment_draft_ids: vec![],
                        },
                        mode: "mode.auto".into(),
                        route: NewThreadModelRoute {
                            account_id: "root-fixture".into(),
                            model_id: support::MODEL.into(),
                            effort: None,
                        },
                        service_tier: None,
                        delegation_mode: Some(mode),
                        delegation_preference: None,
                        workspace_mode: ThreadWorkspaceMode::Local,
                    },
                    None,
                )
                .await?;
            completed_prompt(&env.runtime, &started.thread.id, label).await?;
            let catalog = receipt(&env.root_provider, label)?;
            assert_eq!(catalog["delegationMode"], label);
            let profiles = catalog["profiles"].as_array().unwrap();
            assert!(!profiles.is_empty());
            for profile in profiles {
                if profile["binding"]["kind"] == "native" {
                    assert_eq!(
                        profile["binding"].get("route").is_none(),
                        mode == DelegationMode::Automatic
                    );
                }
            }
            Ok(())
        }
        .await;
        env.finish(result).await?;
    }
    Ok(())
}
