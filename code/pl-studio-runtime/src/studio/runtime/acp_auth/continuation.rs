//! 在原登录流程与原连接上受理认证方法，不派生新进程。

use anyhow::Result;
use pl_protocol::studio::{
    AcpAuthMethodKind, AcpAuthState, ContinueAcpAuthRequest, StudioErrorCode,
};

use super::admission::{AcpAuthAcceptance, AcpAuthRuntime, MAX_ACCEPTED_STARTS};
use super::mapping::{acp_error, ensure_operation_id};
use super::registry::{AcceptedAction, AcceptedIntent};

impl AcpAuthRuntime {
    pub(crate) fn continue_auth(
        &self,
        request: ContinueAcpAuthRequest,
    ) -> Result<AcpAuthAcceptance> {
        ensure_operation_id(&request.operation_id)?;
        ensure_operation_id(&request.target_operation_id)?;
        let inner = self.inner.clone();
        self.inner
            .config
            .with_acp_snapshot(move |revision, config| {
                let mut registry = inner.lock();
                if registry.closed {
                    return Err(acp_error(
                        StudioErrorCode::RuntimeStopped,
                        "运行时正在关闭，不能继续 ACP 登录",
                        false,
                    ));
                }
                if registry.settings_revision != revision {
                    return Err(acp_error(
                        StudioErrorCode::StaleRevision,
                        "设置已变化，请重新读取认证状态",
                        false,
                    ));
                }
                if !config.definitions.contains_key(&request.account_id) {
                    return Err(acp_error(
                        StudioErrorCode::NotFound,
                        "ACP 接入不存在",
                        false,
                    ));
                }
                let intent = AcceptedIntent {
                    account_id: request.account_id.clone(),
                    connection_revision: request.expected_connection_revision,
                    action: AcceptedAction::Continue {
                        target_operation_id: request.target_operation_id.clone(),
                        method_id: request.method_id.clone(),
                    },
                };
                let Some(slot) = registry.slots.get(&request.account_id) else {
                    return Err(acp_error(
                        StudioErrorCode::NotFound,
                        "ACP 接入不存在",
                        false,
                    ));
                };
                if slot.retired || slot.revision != request.expected_connection_revision {
                    return Err(acp_error(
                        StudioErrorCode::StaleRevision,
                        "ACP 接入的连接身份已变化，请重新检查",
                        false,
                    ));
                }
                if let Some(recorded) = registry.accepted.get(&request.operation_id) {
                    if recorded != &intent {
                        return Err(acp_error(
                            StudioErrorCode::Conflict,
                            "该 operationId 已绑定另一个 ACP 认证意图",
                            false,
                        ));
                    }
                    return Ok(AcpAuthAcceptance {
                        snapshot: registry.snapshot(),
                        changed: false,
                    });
                }
                if registry.accepted.len() >= MAX_ACCEPTED_STARTS {
                    return Err(acp_error(
                        StudioErrorCode::Overloaded,
                        "已受理的 ACP 认证操作身份过多，请重启运行时后重试",
                        true,
                    ));
                }
                let Some(operation) = slot.operation.as_ref() else {
                    return Err(acp_error(
                        StudioErrorCode::Conflict,
                        "该接入没有等待登录的认证流程，请重新检查连接",
                        false,
                    ));
                };
                if operation.operation_id != request.target_operation_id
                    || operation.cancel.is_cancelled()
                {
                    return Err(acp_error(
                        StudioErrorCode::Conflict,
                        "目标登录流程已失效",
                        false,
                    ));
                }
                let AcpAuthState::Required { methods, .. } = &slot.state else {
                    return Err(acp_error(
                        StudioErrorCode::Busy,
                        "当前认证流程没有等待选择登录方法",
                        true,
                    ));
                };
                if !methods.iter().any(|method| {
                    method.id == request.method_id && method.kind == AcpAuthMethodKind::Agent
                }) {
                    return Err(acp_error(
                        StudioErrorCode::InvalidArgument,
                        "当前连接未声明该登录方法或不支持该方法类型",
                        false,
                    ));
                }
                // 队列容量为一。锁内准入、发送与状态提交串行，重复命令不会产生第二次 authenticate。
                operation
                    .authentication
                    .try_send(pl_acp::auth::AuthCommand::Authenticate {
                        method_id: request.method_id.clone(),
                    })
                    .map_err(|_| {
                        acp_error(
                            StudioErrorCode::Conflict,
                            "登录连接已经关闭或已有待处理的认证命令",
                            false,
                        )
                    })?;
                registry
                    .slots
                    .get_mut(&request.account_id)
                    .expect("validated slot")
                    .state = AcpAuthState::Authenticating {
                    operation_id: request.target_operation_id,
                    method_id: request.method_id,
                };
                registry.accepted.insert(request.operation_id, intent);
                registry.bump();
                let snapshot = registry.snapshot();
                drop(registry);
                inner.emit(snapshot.clone());
                Ok(AcpAuthAcceptance {
                    snapshot,
                    changed: true,
                })
            })?
    }
}

#[cfg(test)]
mod tests {
    use super::super::registry::Operation;
    use super::*;
    use crate::config::{
        AcpProvider, AcpServiceDefinition, ConfigPaths, ConfigStore, StudioConfig,
    };
    use crate::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
    use std::sync::Arc;
    use tokio_util::sync::CancellationToken;

    #[cfg(target_os = "linux")]
    #[tokio::test]
    async fn generic_auth_accepts_missing_agent_info_without_template_version_or_usage()
    -> Result<()> {
        let home = tempfile::tempdir()?;
        let requests = home.path().join("requests.jsonl");
        let script = home.path().join("synthetic_acp.py");
        std::fs::write(
            &script,
            r#"import json, sys
with open(sys.argv[1], 'a', buffering=1) as log:
    for line in sys.stdin:
        request = json.loads(line)
        log.write(json.dumps(request) + '\n')
        method = request.get('method')
        if method == 'initialize':
            result = {'protocolVersion': 1, 'agentCapabilities': {}, 'authMethods': []}
        elif method == 'session/new':
            result = {'sessionId': 'synthetic-auth-session'}
        else:
            raise RuntimeError('unexpected method')
        print(json.dumps({'jsonrpc':'2.0', 'id':request['id'], 'result':result}), flush=True)
"#,
        )?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.path().join("isolated-home")),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        let definition = crate::config::AcpServiceDefinition {
            id: "generic".into(),
            display_name: "Generic".into(),
            enabled: true,
            launch: crate::config::AcpLaunch::Command {
                command: "/usr/bin/python3".into(),
                args: vec![
                    script.to_string_lossy().into_owned(),
                    requests.to_string_lossy().into_owned(),
                ],
            },
            env: Default::default(),
        };
        let crate::config::AcpLaunch::Command { command, args } = definition.launch else {
            unreachable!("generic fixture")
        };
        runtime.save_acp_account(pl_protocol::studio::UpdateAcpAccountRequest {
            operation_id: "save-generic".into(),
            expected_revision: runtime.config_runtime.read()?.revision,
            expected_document_revision: None,
            account: pl_protocol::studio::AcpAccountUpdate {
                account_id: definition.id,
                name: definition.display_name,
                template: None,
                command: Some(command),
                args: Some(args),
                env: definition.env,
                enabled: true,
            },
        })?;
        let saved = runtime.config_runtime.read()?;
        let revision = saved.acp.definitions["generic"].connection_revision;
        let error = runtime
            .acp_auth
            .start(pl_protocol::studio::StartAcpAuthRequest {
                operation_id: "no-generic-usage".into(),
                account_id: "generic".into(),
                expected_connection_revision: revision,
                action: pl_protocol::studio::AcpAuthAction::QueryUsage,
            })
            .err()
            .expect("generic usage is not inferred");
        assert_eq!(
            crate::error_mapping::studio_error_from_anyhow(error).code,
            StudioErrorCode::InvalidArgument
        );
        assert!(!requests.exists(), "rejected usage must not spawn");
        runtime
            .acp_auth
            .start(pl_protocol::studio::StartAcpAuthRequest {
                operation_id: "generic-check".into(),
                account_id: "generic".into(),
                expected_connection_revision: revision,
                action: pl_protocol::studio::AcpAuthAction::Check,
            })?;
        let operation = runtime.acp_auth.inner.lock().slots["generic"]
            .operation
            .clone()
            .expect("admitted operation");
        let joined = tokio::time::timeout(std::time::Duration::from_secs(15), async {
            let mut join = operation.join.lock().await;
            join.as_mut().expect("supervisor").await
        })
        .await;
        let state = runtime.acp_auth.read_state();
        let verified = matches!(
            state.accounts[0].state,
            pl_protocol::studio::AcpAuthState::Verified { server: None, .. }
        );
        let shutdown = runtime.shutdown_runtime().await;
        joined??;
        shutdown?;
        assert!(
            verified,
            "generic server without agentInfo must verify: {state:?}"
        );
        let logged: Vec<serde_json::Value> = std::fs::read_to_string(requests)?
            .lines()
            .map(serde_json::from_str)
            .collect::<std::result::Result<_, _>>()?;
        assert_eq!(
            logged
                .iter()
                .map(|entry| entry["method"].as_str().unwrap())
                .collect::<Vec<_>>(),
            ["initialize", "session/new"]
        );
        Ok(())
    }

    #[tokio::test]
    async fn continuation_is_bound_to_live_connection_and_idempotent_command_identity() -> Result<()>
    {
        let home = tempfile::tempdir()?;
        let config = StudioConfig::default_config()?;
        let paths = ConfigPaths::from_config_dir(home.path());
        ConfigStore::new(paths.clone()).save(&config)?;
        std::fs::create_dir_all(paths.acp_dir())?;
        std::fs::write(
            paths.acp_dir().join("account.toml"),
            AcpServiceDefinition::template(
                "account".into(),
                "Antigravity".into(),
                AcpProvider::Antigravity,
            )
            .encode()?,
        )?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.path().to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        // Only the external protocol endpoint is controlled. Admission, config
        // serialization, deduplication, cancellation and publication are real.
        let (sender, mut commands) = tokio::sync::mpsc::channel(1);
        let operation = {
            let mut registry = runtime.acp_auth.inner.lock();
            let slot = registry
                .slots
                .get_mut("account")
                .expect("configured account");
            let operation = Arc::new(Operation {
                operation_id: "flow".into(),
                account_id: "account".into(),
                connection_revision: slot.revision,
                generation: 1,
                action: pl_protocol::studio::AcpAuthAction::Check,
                cancel: CancellationToken::new(),
                authentication: sender,
                cleanup_retry: tokio::sync::Notify::new(),
                join: tokio::sync::Mutex::new(None),
            });
            slot.operation = Some(operation.clone());
            slot.state = AcpAuthState::Required {
                operation_id: "flow".into(),
                server: None,
                methods: vec![pl_protocol::studio::AcpAuthMethod {
                    id: "browser".into(),
                    name: "Browser".into(),
                    description: None,
                    kind: AcpAuthMethodKind::Agent,
                }],
            };
            operation
        };
        let request = ContinueAcpAuthRequest {
            operation_id: "continue".into(),
            account_id: "account".into(),
            expected_connection_revision: operation.connection_revision,
            target_operation_id: "flow".into(),
            method_id: "browser".into(),
        };
        for invalid in [
            ContinueAcpAuthRequest {
                target_operation_id: "stale".into(),
                ..request.clone()
            },
            ContinueAcpAuthRequest {
                expected_connection_revision: operation.connection_revision + 1,
                ..request.clone()
            },
            ContinueAcpAuthRequest {
                method_id: "undeclared".into(),
                ..request.clone()
            },
        ] {
            assert!(runtime.acp_auth.continue_auth(invalid).is_err());
            assert!(commands.try_recv().is_err());
        }
        let accepted = runtime.acp_auth.continue_auth(request.clone())?;
        assert!(accepted.changed);
        assert!(matches!(&accepted.snapshot.accounts[0].state,
            AcpAuthState::Authenticating { operation_id, .. } if operation_id == "flow"));
        // busy 状态与活动操作投影来自同一操作槽位：ID、修订与启动动作一致。
        assert_eq!(
            accepted.snapshot.accounts[0].active_operation,
            Some(pl_protocol::studio::AcpAuthActiveOperation {
                operation_id: "flow".into(),
                connection_revision: operation.connection_revision,
                action: pl_protocol::studio::AcpAuthAction::Check,
            })
        );
        assert!(
            matches!(commands.try_recv(), Ok(pl_acp::auth::AuthCommand::Authenticate { method_id }) if method_id == "browser")
        );
        assert!(!runtime.acp_auth.continue_auth(request.clone())?.changed);
        assert!(commands.try_recv().is_err());
        assert!(
            runtime
                .acp_auth
                .continue_auth(ContinueAcpAuthRequest {
                    operation_id: "other-click".into(),
                    ..request
                })
                .is_err()
        );
        runtime
            .acp_auth
            .cancel(pl_protocol::studio::CancelAcpAuthRequest {
                operation_id: "cancel".into(),
                account_id: "account".into(),
                target_operation_id: "flow".into(),
            })?;
        assert!(operation.cancel.is_cancelled());
        runtime.acp_auth.inner.complete_operation(
            "account",
            1,
            operation.connection_revision,
            AcpAuthState::Verified {
                checked_at: 1,
                server: None,
            },
            None,
        );
        assert!(matches!(
            runtime.acp_auth.inner.lock().slots["account"].state,
            AcpAuthState::Cancelled
        ));
        // 终态与释放槽位同事务提交：活动操作投影随之清空。
        assert_eq!(
            runtime
                .acp_auth
                .inner
                .lock()
                .snapshot()
                .accounts
                .first()
                .and_then(|account| account.active_operation.clone()),
            None
        );
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn interrupted_shutdown_retains_the_task_and_rejects_late_success() -> Result<()> {
        let home = tempfile::tempdir()?;
        let config = StudioConfig::default_config()?;
        let paths = ConfigPaths::from_config_dir(home.path());
        ConfigStore::new(paths.clone()).save(&config)?;
        std::fs::create_dir_all(paths.acp_dir())?;
        std::fs::write(
            paths.acp_dir().join("account.toml"),
            AcpServiceDefinition::template(
                "account".into(),
                "Antigravity".into(),
                AcpProvider::Antigravity,
            )
            .encode()?,
        )?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.path().to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        let (sender, _commands) = tokio::sync::mpsc::channel(1);
        let operation = {
            let mut registry = runtime.acp_auth.inner.lock();
            let slot = registry
                .slots
                .get_mut("account")
                .expect("configured account");
            let operation = Arc::new(Operation {
                operation_id: "flow".into(),
                account_id: "account".into(),
                connection_revision: slot.revision,
                generation: 1,
                action: pl_protocol::studio::AcpAuthAction::Check,
                cancel: CancellationToken::new(),
                authentication: sender,
                cleanup_retry: tokio::sync::Notify::new(),
                join: tokio::sync::Mutex::new(None),
            });
            slot.operation = Some(operation.clone());
            operation
        };
        let (cancel_seen, cancellation) = tokio::sync::oneshot::channel();
        let (finish, finishing) = tokio::sync::oneshot::channel();
        let token = operation.cancel.clone();
        *operation.join.lock().await = Some(tokio::spawn(async move {
            token.cancelled().await;
            let _ = cancel_seen.send(());
            let _ = finishing.await;
        }));
        let mut first_wait = Box::pin(runtime.acp_auth.cancel_and_join());
        tokio::select! {
            biased;
            result = &mut first_wait => panic!("unfinished task joined: {result:?}"),
            result = cancellation => result?,
        }
        // Model the outer shutdown coordinator exhausting its budget. Cancelling
        // the wait must retain ownership, so a later shutdown can still join it.
        drop(first_wait);
        assert!(operation.join.try_lock()?.is_some());
        finish.send(()).expect("owned task is still waiting");
        runtime.acp_auth.cancel_and_join().await?;
        assert!(operation.join.lock().await.is_none());
        runtime.acp_auth.inner.complete_operation(
            "account",
            1,
            operation.connection_revision,
            AcpAuthState::Verified {
                checked_at: 1,
                server: None,
            },
            None,
        );
        assert!(matches!(
            runtime.acp_auth.read_state().accounts[0].state,
            AcpAuthState::Cancelled
        ));
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
