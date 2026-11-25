use super::super::settings_api::validated_route;
use crate::{CommandEffectPoint, SetThreadModelRouteRequest, ThreadModelRouteCommandReply};
use anyhow::{Context, Result};

use super::super::StudioRuntime;

impl StudioRuntime {
    pub async fn save_thread_model_route(
        &self,
        thread_id: &str,
        request: SetThreadModelRouteRequest,
    ) -> Result<ThreadModelRouteCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let _guard = self.lifecycle_lock.lock().await;
        let record = self.read_owned_thread(thread_id).await?;
        anyhow::ensure!(
            self.bots.config_for_thread(thread_id).await?.is_none(),
            "该会话的模型由机器人统一管理，请打开机器人设置修改"
        );
        anyhow::ensure!(
            record.parent_thread_id.is_none(),
            "child Thread model routes are frozen by their Agent Profile"
        );
        let thread = self.ensure_thread_owner(thread_id).await?;
        let state = thread.snapshot();
        let settings = self.config_runtime.read()?;
        let route_extension_id = crate::studio::model_route::MODEL_ROUTE_EXTENSION;
        let previous = state
            .extensions
            .get(route_extension_id)
            .context("Thread has no saved model route")?;
        if previous.revision != request.expected_model_route_revision {
            return Err(crate::ConfigRuntimeError::StaleRevision {
                expected: request.expected_model_route_revision,
                actual: previous.revision,
            }
            .into());
        }
        let directory_mode = record
            .mode
            .clone()
            .context("Native root has no workflow mode")?;
        let mode = crate::studio::thread_projection::saved_mode(&state)?.unwrap_or(directory_mode);
        crate::mode::saved_registered_mode(&state)?
            .or_else(|| self.thread_modes.snapshot().mode(&mode))
            .context("current Thread Mode is unavailable")?;
        let model = validated_route(
            &settings.config,
            &format!("Thread {thread_id}"),
            &request.account_id,
            &request.model_id,
            request.effort.as_deref(),
        )?;
        let selector = crate::studio::model_route::ThreadModelSelection {
            model,
            service_tier: request.service_tier,
        };
        // The session owns speed. Preserve the existing preference write only
        // when the user changes the model or effort, not on speed-only edits.
        let update_mode_default =
            crate::studio::model_route::decode(&previous.payload)?.model != selector.model;
        let route = selector.resolve(&settings.config)?;
        crate::studio::delegation::validate_credential(&route)?;
        let committed = match thread
            .mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
                id: route_extension_id.into(),
                expected_revision: Some(request.expected_model_route_revision),
                payload: crate::studio::model_route::encode(&selector)?,
            }])
            .await
        {
            Ok(committed) => committed,
            Err(pl_core::thread::ThreadError::ExtensionConflict {
                id,
                expected: Some(expected),
                actual: Some(actual),
            }) if id == route_extension_id => {
                return Err(crate::ConfigRuntimeError::StaleRevision { expected, actual }.into());
            }
            Err(error) => return Err(error.into()),
        };
        let route_changed = previous.payload
            != committed
                .get(route_extension_id)
                .context("committed route missing")?
                .payload;
        let route_revision = committed
            .get(route_extension_id)
            .context("committed route missing")?
            .revision;
        self.tool_catalog_updates.notify_one();

        let mut confirmed_settings = settings.clone();
        let mut default_changed = false;
        let mut mode_default_saved = false;
        let mut warning = None;
        if update_mode_default {
            match self
                .config_runtime
                .update_with_effective(None, |desired, effective| {
                    let candidate = validated_route(
                        effective,
                        &format!("Thread Mode {mode}"),
                        &request.account_id,
                        &request.model_id,
                        request.effort.as_deref(),
                    )
                    .map_err(|error| crate::PureError::ConfigError(error.to_string()))?;
                    let mut config = desired.clone();
                    default_changed = config.mode_model_routes.get(&mode) != Some(&candidate);
                    config.mode_model_routes.insert(mode.clone(), candidate);
                    Ok(config)
                }) {
                Ok(updated) => {
                    confirmed_settings = updated;
                    mode_default_saved = true;
                    if let Err(error) = self.publish_settings_state() {
                        warning = Some(format!(
                            "current Thread and Mode default were saved, but the Settings event was not published: {error}"
                        ));
                    }
                }
                Err(error) => {
                    default_changed = false;
                    warning = Some(format!(
                        "current Thread was updated, but its Mode default was not saved: {error}"
                    ));
                }
            }
        }
        let snapshot = self.thread_snapshot(thread_id).await?;
        let runtime = snapshot
            .runtime
            .context("Thread runtime snapshot is unavailable")?;
        let mut targets =
            vec![self.resource_stamp(format!("thread-route:{thread_id}"), route_revision)];
        if mode_default_saved {
            targets.push(self.resource_stamp("settings", confirmed_settings.revision));
        }
        Ok(ThreadModelRouteCommandReply {
            runtime,
            receipt: self.command_receipt(
                request.operation_id,
                route_changed || default_changed,
                targets,
                CommandEffectPoint::NextTurn,
                false,
            ),
            settings: self.read_settings()?,
            mode_default_saved,
            warning,
        })
    }
}
