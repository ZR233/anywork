use super::*;
use crate::agent::definition::VerifiedAgentIdentity;
use pl_core::thread::extensions::ExtensionRecord;

/// bot 归属必须解码校验；没有正向证明时不推断普通渠道，而是明确渠道未指定的 legacy-root。
#[test]
fn bot_ownership_is_verified_by_decoding_not_by_extension_presence() -> Result<()> {
    let owned = |payload: OpaquePayload| {
        let mut state = ThreadSnapshot::default();
        state.extensions.insert(
            BOT_OWNER_EXTENSION.into(),
            ExtensionRecord {
                revision: 1,
                payload,
            },
        );
        state
    };
    let frozen = owned(encode_bot_owner("bot-1a2b3c4d-0")?);
    assert_eq!(
        verified_bot_owner(None, Some(&frozen))?,
        Some("bot-1a2b3c4d-0".to_owned())
    );
    assert_eq!(
        verified_bot_owner(Some("bot-1a2b3c4d-0"), Some(&frozen))?,
        Some("bot-1a2b3c4d-0".to_owned())
    );
    assert_eq!(
        verified_bot_owner(Some("bot-1a2b3c4d-1"), None)?,
        Some("bot-1a2b3c4d-1".to_owned())
    );
    assert_eq!(verified_bot_owner(None, None)?, None);
    assert!(
        verified_bot_owner(Some("bot-ffffffff-9"), Some(&frozen)).is_err(),
        "运行期绑定与冻结 owner 冲突"
    );
    for damaged in [
        OpaquePayload::new("pl.studio.bot-owner", 1, "\"\"")?,
        OpaquePayload::new("pl.studio.bot-owner", 1, "\"has space\"")?,
        OpaquePayload::new("pl.studio.bot-owner", 2, "\"bot-1a2b3c4d-0\"")?,
        OpaquePayload::new("pl.studio.bot-owner.other", 1, "\"bot-1a2b3c4d-0\"")?,
        OpaquePayload::new("pl.studio.bot-owner", 1, "not json")?,
    ] {
        assert!(
            verified_bot_owner(None, Some(&owned(damaged))).is_err(),
            "损坏 owner 不能被忽略"
        );
    }
    // canonical 校验器的最小长度 8 与字符集不能被同构副本放宽。
    for short in ["bot", "bot-123", "bot 1a2b3c"] {
        assert!(
            verified_bot_owner(None, Some(&owned(encode_bot_owner(short)?))).is_err(),
            "短或非法 bot owner `{short}` 必须失败"
        );
        assert!(
            verified_bot_owner(Some(short), None).is_err(),
            "短或非法运行期绑定 `{short}` 必须失败"
        );
    }
    assert_eq!(
        VerifiedAgentIdentity::GenericRoot.migrated_identity().id,
        "root:legacy"
    );
    assert_eq!(
        VerifiedAgentIdentity::BotRoot.migrated_identity().id,
        "root:feishu"
    );
    Ok(())
}
