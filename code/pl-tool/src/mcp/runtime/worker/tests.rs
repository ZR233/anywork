use super::*;
use crate::mcp::config::{
    McpExecutionContext, McpServerConfig, McpServerMutationPolicy, McpServerSourceKind,
    McpServerStatusKind,
};
use crate::mcp::connector::tests::{FaultTransport, fault_session, retains_io_close_source};
use crate::mcp::runtime::McpRuntimeHandle;
use server::{RuntimeServer, server_descriptor};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

async fn failed_shutdown(panic_send: bool, fail_close: bool, expected: &str) {
    let closed = Arc::new(AtomicUsize::new(0));
    let session = Arc::new(
        fault_session(FaultTransport {
            panic_send,
            fail_close,
            closed: closed.clone(),
        })
        .await,
    );
    let config = EffectiveMcpServerConfig {
        id: "fault".into(),
        source_kind: McpServerSourceKind::User,
        source_label: "user".into(),
        source_detail: None,
        config: serde_json::from_value::<McpServerConfig>(serde_json::json!({
            "command": "fixture-only",
        }))
        .unwrap(),
        status_kind: McpServerStatusKind::Enabled,
        status_message: None,
        mutation_policy: McpServerMutationPolicy::UserEditable,
        bearer_token: Some("secret-close-token".into()),
        execution_context: McpExecutionContext::Host,
        tool_effect: None,
    };
    let mut server = RuntimeServer::terminal(
        &config,
        server_fingerprint(&config),
        McpAvailabilityKind::Available,
        None,
    );
    server.descriptor = server_descriptor(&config);
    server.session = Some(session.clone());
    let (commands, receiver) = mpsc::unbounded_channel();
    let (updates, _) = broadcast::channel(8);
    let completion = ShutdownCompletion::default();
    let handle = McpRuntimeHandle {
        commands: commands.clone(),
        updates: updates.clone(),
        shutdown_completion: completion.clone(),
    };
    let mut worker = RuntimeWorker::new(
        McpConnector::default(),
        receiver,
        commands,
        updates,
        completion,
    );
    worker
        .generations
        .get_mut(&worker.current)
        .unwrap()
        .servers
        .insert("fault".into(), server);
    // Own the worker future directly. Failed shutdown retains its exact session and
    // reusable close result; the second public shutdown must not report success either.
    let run = worker.run();
    tokio::pin!(run);
    for _ in 0..2 {
        let result = tokio::select! {
            result = tokio::time::timeout(Duration::from_secs(3), handle.shutdown()) => result.unwrap(),
            () = &mut run => panic!("failed shutdown must retain the worker"),
        };
        let error = result.unwrap_err().to_string();
        assert!(error.contains(expected), "{error}");
        assert!(!error.contains("secret-close-token"), "{error}");
    }
    assert_eq!(
        closed.load(Ordering::SeqCst),
        1,
        "SDK must drive transport.close exactly once"
    );
    if fail_close {
        // The original typed source is retained only in the trusted owner, not
        // reconstructed from its model-visible redacted diagnostic.
        assert!(retains_io_close_source(&session));
    }
}

#[tokio::test]
async fn sdk_send_task_join_error_is_not_successful_runtime_shutdown() {
    failed_shutdown(true, false, "send-task-failed").await;
}

#[tokio::test]
async fn sdk_transport_close_error_reaches_runtime_shutdown_with_source_and_redaction() {
    failed_shutdown(false, true, "transport-close-failed").await;
}
