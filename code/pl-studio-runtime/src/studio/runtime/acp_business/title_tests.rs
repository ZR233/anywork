//! Real SDK notifications and list responses through the product directory.

use std::time::Duration;

use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use tokio::time::timeout;

use crate::acp_schema::{ContentBlock, ImageContent, ResourceLink, TextContent};
use crate::acp_transport_fixture::AcpTransportFixture as Fixture;
use crate::studio::catalog::CatalogStore;
use crate::studio::records::AcpPeerTitle;
use crate::{
    AcpBusinessFailureKind, AcpOpenIntent, AcpSessionEvent, AcpSessionOpen, ListSessionsRequest,
    OpenAcpSessionRequest, StudioProductEventKind, StudioProductFrame, StudioProductTopic,
    StudioProductTopicSubscription, ThreadWorkspaceMode,
};

const DEADLINE: Duration = Duration::from_secs(15);

fn text(value: &str) -> ContentBlock {
    ContentBlock::Text(TextContent::new(value))
}

async fn next_title(directory: &mut StudioProductTopicSubscription, id: &str) -> Result<String> {
    timeout(DEADLINE, async {
        loop {
            match directory.recv().await?.context("directory closed")? {
                StudioProductFrame::Event(event) => {
                    if let StudioProductEventKind::ThreadDirectoryChanged(delta) = event.kind
                        && let Some(row) = delta.upserted.iter().find(|row| row.thread_id == id)
                    {
                        return Ok(row.title.clone());
                    }
                }
                StudioProductFrame::Baseline(_) => {}
                StudioProductFrame::Lagged { .. } => anyhow::bail!("directory observation gap"),
            }
        }
    })
    .await?
}

async fn draft(fixture: &Fixture) -> Result<AcpSessionOpen> {
    let mut open = fixture
        .open_intent(AcpOpenIntent::Draft {
            workspace_mode: ThreadWorkspaceMode::Local,
            delegation_mode: None,
            delegation_preference: None,
            mode: None,
        })
        .await?;
    Fixture::ready(&mut open).await?;
    open.completion.wait().await?;
    Ok(open)
}

async fn peer_turn(
    fixture: &Fixture,
    open: &mut AcpSessionOpen,
    prompt: &str,
    updates: Value,
) -> Result<()> {
    tokio::fs::write(
        fixture.home.path().join("title-updates.json"),
        serde_json::to_vec(&updates)?,
    )
    .await?;
    let run = fixture
        .runtime
        .prompt_acp_session(open.target.clone(), vec![text(prompt)])
        .await?;
    let observer = open.observation.as_mut().context("original ACP observer")?;
    timeout(DEADLINE, async {
        loop {
            if let AcpSessionEvent::Completed { completed } = observer
                .recv()
                .await
                .context("ACP closed before completion")?
            {
                ensure!(completed.run == run && completed.result.is_ok());
                return Ok(());
            }
        }
    })
    .await?
}

#[tokio::test]
async fn a_later_list_title_reaches_the_directory_without_list_action() -> Result<()> {
    let fixture = Fixture::new("session-titles").await?;
    let runtime = &fixture.runtime;
    let outcome = async {
        let mut directory = runtime
            .subscribe_product_topic(StudioProductTopic::ThreadDirectory)
            .await?;
        let mut open = draft(&fixture).await?;
        let target = open.target.clone();
        let thread = &target.thread_id;
        let current = || {
            runtime
                .agent_facility
                .product_events
                .directory_facts(thread)
                .context("published root")
                .map(|(session, _)| session)
        };

        let remote_id = runtime
            .acp_session_snapshot(target.clone())
            .await?
            .acp_session_id
            .context("peer session ID")?;
        let cwd = &fixture.workspace.path;
        tokio::fs::write(
            fixture.home.path().join("listed.json"),
            serde_json::to_vec(&json!([
                {"sessionId":remote_id,"cwd":"/wrong-workspace","title":"Wrong directory"},
                {"sessionId":"unassociated","cwd":cwd,"title":"Wrong session"}
            ]))?,
        )
        .await?;
        let next_page = fixture.home.path().join("listed-next.json");
        let listed = |title| json!([{"sessionId":remote_id,"cwd":cwd,"title":title}]);
        tokio::fs::write(&next_page, serde_json::to_vec(&listed("Provider summary"))?).await?;
        runtime
            .commit_acp_draft(target.clone(), "Explain ferries")
            .await?;
        ensure!(next_title(&mut directory, thread).await? == "Explain ferries");
        peer_turn(&fixture, &mut open, "Explain ferries", json!([])).await?;
        // The preceding prompt can also emit a directory delta for the sort time.
        timeout(DEADLINE, async {
            loop {
                match next_title(&mut directory, thread).await?.as_str() {
                    "Provider summary" => return Ok::<_, anyhow::Error>(()),
                    "Explain ferries" => continue,
                    unexpected => anyhow::bail!("unexpected directory title {unexpected}"),
                }
            }
        })
        .await??;
        let before = current()?;
        tokio::fs::write(
            &next_page,
            serde_json::to_vec(&listed("Harbor Ferry Routes"))?,
        )
        .await?;
        ensure!(next_title(&mut directory, thread).await? == "Harbor Ferry Routes");
        let after = current()?;
        ensure!(after.display_title() == "Harbor Ferry Routes");
        ensure!(after.last_user_message_at == before.last_user_message_at);
        ensure!(after.updated_at == before.updated_at);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    fixture.runtime.shutdown_runtime().await?;
    outcome
}

#[tokio::test]
async fn acp_peer_titles_outrank_lists_and_survive_reopen_without_overriding_alias() -> Result<()> {
    let fixture = Fixture::new("session-titles").await?;
    let runtime = &fixture.runtime;
    let outcome = async {
        let mut directory = runtime
            .subscribe_product_topic(StudioProductTopic::ThreadDirectory)
            .await?;
        let mut open = draft(&fixture).await?;
        let target = open.target.clone();
        let thread = &target.thread_id;
        let current = || {
            runtime
                .agent_facility
                .product_events
                .directory_facts(thread)
                .context("published root")
                .map(|(session, _)| session)
        };
        runtime
            .commit_acp_draft(target.clone(), "  Fix\n the documentation  ")
            .await?;
        ensure!(next_title(&mut directory, thread).await? == "Fix the documentation");
        let snapshot = runtime.acp_session_snapshot(target.clone()).await?;
        let remote_id = snapshot.acp_session_id.context("peer session ID")?;
        let cwd = &fixture.workspace.path;
        let listing = fixture.home.path().join("listed.json");
        tokio::fs::write(
            &listing,
            serde_json::to_vec(&json!([
                {"sessionId":remote_id,"cwd":"/wrong-workspace","title":"Wrong directory"},
                {"sessionId":"unassociated","cwd":cwd,"title":"Wrong session"}
            ]))?,
        )
        .await?;
        runtime
            .list_acp_sessions(target.clone(), ListSessionsRequest::new())
            .await?;
        ensure!(current()?.display_title() == "Fix the documentation");
        ensure!(
            runtime
                .store
                .directory_members_for_project(&fixture.workspace.id)?
                .len()
                == 1
        );
        tokio::fs::write(
            &listing,
            serde_json::to_vec(&json!([
                {"sessionId":remote_id,"cwd":cwd,"title":"Listed document title"}
            ]))?,
        )
        .await?;
        ensure!(
            runtime
                .list_acp_sessions(target.clone(), ListSessionsRequest::new())
                .await?
                .sessions
                .len()
                == 1
        );
        ensure!(next_title(&mut directory, thread).await? == "Listed document title");

        peer_turn(
            &fixture,
            &mut open,
            "Fix the documentation",
            json!([
                {"sessionId":"wrong-session","fields":{"title":"Wrong push"}},
                {"fields":{"title":"Server document title"}},
                {"fields":{"updatedAt":"2026-01-01T00:00:00Z"}}
            ]),
        )
        .await?;
        ensure!(next_title(&mut directory, thread).await? == "Server document title");
        runtime
            .list_acp_sessions(target.clone(), ListSessionsRequest::new())
            .await?;
        ensure!(current()?.display_title() == "Server document title");

        peer_turn(
            &fixture,
            &mut open,
            "Follow up",
            json!([{"fields":{"title":null}}]),
        )
        .await?;
        ensure!(next_title(&mut directory, thread).await? == "Fix the documentation");
        runtime
            .list_acp_sessions(target.clone(), ListSessionsRequest::new())
            .await?;
        ensure!(current()?.display_title() == "Fix the documentation");

        // An alias to the same visible value is still an explicit user choice.
        runtime
            .rename_thread(
                "user-alias".into(),
                thread.clone(),
                "Fix the documentation".into(),
            )
            .await?;
        peer_turn(
            &fixture,
            &mut open,
            "Another follow-up",
            json!([{"fields":{"title":"Alias-hidden peer title"}}]),
        )
        .await?;
        timeout(DEADLINE, async {
            loop {
                let session = current()?;
                if session.acp_title.and_then(|state| state.peer)
                    == Some(AcpPeerTitle::Pushed {
                        title: Some("Alias-hidden peer title".into()),
                    })
                {
                    return Ok::<_, anyhow::Error>(());
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await??;
        ensure!(current()?.display_title() == "Fix the documentation");
        ensure!(
            runtime
                .close_acp_session(target.clone())
                .await?
                .local_complete
        );
        ensure!(
            current()?.acp_title.context("ACP metadata")?.peer
                == Some(AcpPeerTitle::Pushed {
                    title: Some("Alias-hidden peer title".into())
                })
        );

        tokio::fs::write(
            fixture.home.path().join("load-title"),
            "Reopened peer title",
        )
        .await?;
        let mut reopened = runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: Some(thread.clone()),
                intent: AcpOpenIntent::Load {
                    session_id: remote_id,
                },
            })
            .await?;
        Fixture::ready(&mut reopened).await?;
        ensure!(reopened.target.instance != target.instance);
        timeout(DEADLINE, async {
            loop {
                if current()?.acp_title.and_then(|state| state.peer)
                    == Some(AcpPeerTitle::Pushed {
                        title: Some("Reopened peer title".into()),
                    })
                {
                    return Ok::<_, anyhow::Error>(());
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await??;
        ensure!(current()?.display_title() == "Fix the documentation");
        ensure!(
            runtime
                .close_acp_session(reopened.target)
                .await?
                .local_complete
        );
        Ok::<_, anyhow::Error>(target.session_id)
    }
    .await;
    let shutdown = runtime.shutdown_runtime().await;
    let session_id = outcome?;
    shutdown?;
    let catalog = CatalogStore::load(runtime.store.paths().catalog_file()).await?;
    let stored = catalog
        .get_session(&session_id)
        .context("persisted title")?;
    ensure!(stored.display_title() == "Fix the documentation");
    ensure!(
        stored.acp_title.context("persisted ACP metadata")?.peer
            == Some(AcpPeerTitle::Pushed {
                title: Some("Reopened peer title".into())
            })
    );
    Ok(())
}

#[tokio::test]
async fn first_accepted_acp_input_sets_the_fallback_even_after_a_draft_publication_failure()
-> Result<()> {
    let fixture = Fixture::new("session-titles").await?;
    let runtime = &fixture.runtime;
    let outcome = async {
        let mut directory = runtime
            .subscribe_product_topic(StudioProductTopic::ThreadDirectory)
            .await?;
        let mut open = draft(&fixture).await?;
        let target = open.target.clone();
        let thread = &target.thread_id;
        let catalog = runtime.store.paths().catalog_file();
        let original = fixture.home.path().join("catalog-before-draft");
        tokio::fs::rename(&catalog, &original).await?;
        tokio::fs::create_dir(&catalog).await?;
        let frozen = format!(" \t{}\n始标题 ", "初".repeat(78));
        let failed = runtime.commit_acp_draft(target.clone(), &frozen).await;
        tokio::fs::remove_dir(&catalog).await?;
        tokio::fs::rename(&original, &catalog).await?;
        ensure!(failed.is_err(), "directory publication should have failed");
        ensure!(
            runtime
                .prompt_acp_session(target.clone(), vec![text("never sent")])
                .await
                .unwrap_err()
                .kind
                == AcpBusinessFailureKind::NotReady
        );
        runtime
            .commit_acp_draft(target.clone(), "retry must not change the first label")
            .await?;
        ensure!(next_title(&mut directory, thread).await? == format!("{} 始", "初".repeat(78)));
        ensure!(
            runtime
                .prompt_acp_session(
                    target.clone(),
                    vec![
                        text("not accepted"),
                        ContentBlock::Image(ImageContent::new("AA==", "image/png"))
                    ]
                )
                .await
                .unwrap_err()
                .kind
                == AcpBusinessFailureKind::Unsupported
        );
        peer_turn(&fixture, &mut open, "  Actual\t first input  ", json!([])).await?;
        ensure!(next_title(&mut directory, thread).await? == "Actual first input");
        peer_turn(
            &fixture,
            &mut open,
            "Must not rename the session",
            json!([]),
        )
        .await?;
        let (session, _) = runtime
            .agent_facility
            .product_events
            .directory_facts(thread)
            .context("published root")?;
        ensure!(session.display_title() == "Actual first input");
        ensure!(runtime.close_acp_session(target).await?.local_complete);

        let attachments = draft(&fixture).await?;
        let target = attachments.target;
        runtime.commit_acp_draft(target.clone(), "").await?;
        ensure!(next_title(&mut directory, &target.thread_id).await? == "New Session");
        runtime
            .prompt_acp_session(
                target.clone(),
                vec![ContentBlock::ResourceLink(ResourceLink::new(
                    "fixture",
                    "file:///fixture",
                ))],
            )
            .await?;
        let (session, _) = runtime
            .agent_facility
            .product_events
            .directory_facts(&target.thread_id)
            .context("attachment-only root")?;
        ensure!(session.display_title() == "New Session");
        ensure!(runtime.close_acp_session(target).await?.local_complete);
        Ok::<_, anyhow::Error>(())
    }
    .await;
    let shutdown = runtime.shutdown_runtime().await;
    outcome?;
    shutdown?;
    Ok(())
}
