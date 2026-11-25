use crate::studio::StudioRuntime;

async fn exercise(fail_watcher: bool) -> anyhow::Result<()> {
    let home = tempfile::tempdir()?;
    let runtime = Box::pin(StudioRuntime::initialize(crate::StudioRuntimeOptions {
        studio_home: Some(home.path().to_owned()),
        host: crate::StudioHostKind::Test,
        ..crate::StudioRuntimeOptions::desktop()
    }))
    .await?;
    // Use the existing storage fixture without the product-observation installer: its
    // member has a real ColdStore but deliberately has no saved product association.
    let session = crate::session::SessionRuntime::default();
    session.set_agent_services(
        runtime.config_runtime.clone(),
        runtime.store.clone(),
        runtime.agent_facility.product_events.clone(),
        runtime.thread_factory.clone(),
        runtime.model_performance.clone(),
        runtime.recovery.clone(),
    )?;
    let result = crate::studio::thread_factory::mcp::tests::exercise_member_mcp_exit_fence(
        &runtime,
        &runtime.thread_factory,
        &session,
        home.path(),
        fail_watcher,
    )
    .await;
    let shutdown = runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn member_mcp_exit_fence_stops_while_terminal_flush_is_blocked_and_joins_once()
-> anyhow::Result<()> {
    exercise(false).await
}

#[tokio::test]
async fn member_mcp_exit_fence_retains_real_failure_for_final_join_and_retry() -> anyhow::Result<()>
{
    exercise(true).await
}
