use super::*;
use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::{StudioHostKind, StudioRuntimeOptions};
use pl_protocol::studio::StudioUiLanguage;

#[tokio::test]
async fn ui_language_commands_publish_persist_and_survive_restart() -> Result<()> {
    let home = tempfile::tempdir()?;
    let store = ConfigStore::new(ConfigPaths::from_config_dir(home.path()));
    let mut config = StudioConfig::default_config()?;
    config.ui.compact_timeline = true;
    config.ui.sidebar_width = Some(400);
    config.instructions.user = "Keep the user's language preference out of prompts".into();
    store.save(&config)?;
    let options = || StudioRuntimeOptions {
        studio_home: Some(home.path().to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    };
    let runtime = StudioRuntime::initialize(options()).await?;
    let mut before = runtime.read_settings()?.config;
    assert_eq!(before.settings.general.language, StudioUiLanguage::System);
    for (index, language) in [
        StudioUiLanguage::Zh,
        StudioUiLanguage::En,
        StudioUiLanguage::System,
        StudioUiLanguage::Zh,
    ]
    .into_iter()
    .enumerate()
    {
        let reply = runtime
            .apply_settings_field(UpdateSettingsFieldRequest {
                operation_id: format!("language-{index}"),
                expected_revision: before.revision,
                update: SettingsFieldUpdate::GeneralLanguage { value: language },
            })
            .await?;
        assert_eq!(reply.receipt.effect, CommandEffectPoint::Immediate);
        assert!(reply.receipt.durable);
        assert!(reply.snapshot.config.revision > before.revision);
        let mut expected = before.settings;
        expected.general.language = language;
        assert_eq!(reply.snapshot.config.settings, expected);
        config.ui.language = language;
        assert_eq!(store.load()?, config);
        before = reply.snapshot.config;
    }
    assert!(
        runtime
            .apply_settings_field(UpdateSettingsFieldRequest {
                operation_id: "stale-language".into(),
                expected_revision: before.revision - 1,
                update: SettingsFieldUpdate::GeneralLanguage {
                    value: StudioUiLanguage::En,
                },
            })
            .await
            .is_err()
    );
    assert_eq!(runtime.read_settings()?.config, before);
    runtime.shutdown_runtime().await?;
    let runtime = StudioRuntime::initialize(options()).await?;
    assert_eq!(runtime.read_settings()?.config.settings, before.settings);
    runtime.shutdown_runtime().await?;
    Ok(())
}
