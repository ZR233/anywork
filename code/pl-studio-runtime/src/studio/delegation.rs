//! Immutable dispatch provenance. The selected child route belongs only to its saved Profile.
use crate::{DelegationMode, DelegationPreference, DelegationSettings};
use anyhow::{Result, ensure};
use pl_core::{
    context::OpaquePayload,
    thread::{ThreadSnapshot, extensions::ExtensionRecord},
};

pub(crate) const EXTENSION: &str = "studio.delegation";
const FORMAT: &str = "pl.studio.delegation";

pub(crate) fn encode(selection: DelegationSettings) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        FORMAT,
        1,
        serde_json::to_string(&selection)?,
    )?)
}

pub(crate) fn saved(state: &ThreadSnapshot) -> Result<Option<DelegationSettings>> {
    state
        .extensions
        .get(EXTENSION)
        .map(|record| decode(&record.payload))
        .transpose()
}

pub(crate) fn decode(payload: &OpaquePayload) -> Result<DelegationSettings> {
    ensure!(
        payload.format() == FORMAT && payload.version() == 1,
        "unsupported saved delegation encoding"
    );
    Ok(serde_json::from_str(payload.content())?)
}

/// Invoked only by the versioned history recovery writer, never by default inheritance.
pub(crate) fn migrate(state: &mut ThreadSnapshot) -> Result<()> {
    if saved(state)?.is_none() {
        state.extension_sequence = state
            .extension_sequence
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("delegation extension sequence overflow"))?;
        state.extensions.insert(
            EXTENSION.into(),
            ExtensionRecord {
                revision: state.extension_sequence,
                payload: encode(DelegationSettings::default())?,
            },
        );
    }
    Ok(())
}

pub(crate) fn profile_model(profile: &crate::AgentProfileSnapshot) -> crate::NewThreadModelRoute {
    crate::NewThreadModelRoute {
        account_id: profile.account_id.clone(),
        model_id: profile.model_id.clone(),
        effort: profile.effort.clone(),
    }
}

/// Product admission uses the model owner's canonical selection, effort and connection rules.
/// Credentials are checked without a network probe; OpenAI-compatible accounts explicitly allow
/// credential-free local endpoints. All child query/spawn/continuation paths use this result.
pub(crate) fn resolve_child_route(
    config: &crate::StudioConfig,
    profile: &crate::AgentProfileSnapshot,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    resolve_child_selection(
        config,
        pl_model::config::AgentRoleId::new(profile.profile_id.clone())?,
        &crate::studio::model_route::profile_route(profile)
            .map_err(|error| crate::PureError::ConfigError(error.to_string()))?,
    )
}

pub(crate) fn resolve_current_child_route(
    config: &crate::StudioConfig,
    profile: &crate::AgentProfile,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    let crate::AgentBinding::Native(native) = &profile.binding else {
        return Err(crate::PureError::ConfigError(
            "ACP execution is not supported before S4".into(),
        ));
    };
    let route = native.route.as_ref().ok_or_else(|| {
        crate::PureError::ConfigError("child Native Profile has no model route".into())
    })?;
    resolve_child_selection(
        config,
        pl_model::config::AgentRoleId::new(profile.definition.definition_id.clone())?,
        &pl_model::config::ModelRouteConfig {
            account_id: pl_model::config::AccountId::new(route.account_id.clone())?,
            model_id: route.model_id.clone(),
            effort: route
                .effort
                .clone()
                .map(pl_model::config::ReasoningEffort::new),
        },
    )
}

pub(crate) fn resolve_child_selection(
    config: &crate::StudioConfig,
    role: pl_model::config::AgentRoleId,
    selector: &pl_model::config::ModelRouteConfig,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    let route = config.models.resolve_route(role, selector)?;
    validate_credential(&route)?;
    if !route.model.capabilities.tools.function_calling {
        return Err(crate::PureError::ConfigError(
            "child model requires tool calling".into(),
        ));
    }
    Ok(route)
}

pub(crate) fn validate_credential(
    route: &pl_model::config::ResolvedModelRoute,
) -> crate::Result<()> {
    if route.endpoint.protocol != pl_model::protocol::providers::openai::COMPATIBLE_ID
        && route.endpoint.authorization.is_none()
        && route
            .endpoint
            .bearer_token
            .as_deref()
            .is_none_or(|token| token.trim().is_empty())
    {
        return Err(crate::PureError::ConfigError(
            "model account credential is unavailable".into(),
        ));
    }
    Ok(())
}

pub(crate) fn preference_prompt(selection: DelegationSettings) -> Option<&'static str> {
    if selection.mode == DelegationMode::Profile {
        return None;
    }
    Some(match selection.preference {
        DelegationPreference::Economy => {
            "自动分发偏好：经济。先满足任务难度、必需能力、上下文与交付质量。当前会话是自动模式，Profile 只提供职责与工作区，其预设路由不决定选模。先发现 delegation_model 工具，用 list_delegation_models 读取完整候选目录，再用 get_delegation_models 查询详情与评价；主动批量比较相关型号的近期评价，候选充足时至少比较两个；优先看同类任务的指令遵循、失败原因与返修风险。满足要求时优先不计费与订阅账号，同类仍比较已知参考价及预计输入、输出、缓存和返修成本。简单任务便宜够用，困难任务确需更强能力时再用更贵且适配的模型，不因不另收费默认最贵。未知价格不是免费，不比不同币种裸数值，不编造套餐额度或倍率。同次决策复用资料，相关事实变化后重查；显式选择合法 modelSelection，不改变主模型、冻结身份、权限、预算或验收要求。"
        }
        DelegationPreference::Balanced => {
            "自动分发偏好：平衡。先满足必需能力、上下文与交付质量。当前会话是自动模式，Profile 只提供职责与工作区，其预设路由不决定选模。先发现 delegation_model 工具，用 list_delegation_models 读取完整候选目录，再用 get_delegation_models 查询详情与评价；主动批量比较相关型号的近期评价，候选充足时至少比较两个；优先看同类任务的具体评语、质量、指令遵循和失败原因，再综合适配、返修风险、成本与总交付时间。经济性上合适时优先不计费与订阅，同类仍比较已知参考价及预计输入、输出、缓存和返修成本，不因不另收费默认最贵。空评价、少样本、异类评价与未知速度如实保留不确定性，不按最高均分或价格直接排名，不编造额度或跨币种换算。同次决策复用资料，相关事实变化后重查；显式选择合法 modelSelection，不改变主模型、冻结身份、权限、预算或验收要求。"
        }
        DelegationPreference::Fast => {
            "自动分发偏好：快速。先满足必需能力、上下文与交付质量。当前会话是自动模式，Profile 只提供职责与工作区，其预设路由不决定选模。先发现 delegation_model 工具，用 list_delegation_models 读取完整候选目录，再用 get_delegation_models 查询详情与评价；主动批量比较相关型号的近期评价，候选充足时至少比较两个；结合相近任务的失败原因、指令遵循、首字延迟 TTFT、吞吐 TPS 及样本量，以整项任务完成时间和返修风险为主，不只看最高吞吐。能力和交付时间相近时优先合适的不计费与订阅账号，同类仍比较已知参考价及预计总成本，不因不另收费默认最贵。无样本速度不是零延迟，价格不证明质量，不编造额度、倍率或跨币种换算。同次决策复用资料，相关事实变化后重查；显式选择合法 modelSelection，不改变主模型、冻结身份、权限、预算或验收要求。"
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{AccountAuthenticationMethod, ChatGptAccountInfo};
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig, ReasoningEffort};
    use pl_model_auth::chatgpt::{
        ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
    };
    use std::sync::Arc;

    struct NoCredentialIo;

    impl ChatGptCredentialStorage for NoCredentialIo {
        fn load(&self) -> std::result::Result<ChatGptCredentialRecord, ChatGptAuthError> {
            panic!("route admission must not load ChatGPT credentials");
        }

        fn persist(
            &self,
            _: &str,
            _: &ChatGptCredentialRecord,
        ) -> std::result::Result<(), ChatGptAuthError> {
            panic!("route admission must not persist ChatGPT credentials");
        }
    }

    fn native_selection() -> Result<(crate::StudioConfig, ModelRouteConfig)> {
        let mut config = crate::StudioConfig::default_config()?;
        let account = pl_model::config::builtin_account_catalog()?
            .templates
            .into_iter()
            .find(|template| template.id.as_str() == "openai")
            .expect("bundled OpenAI account")
            .account;
        let selector = ModelRouteConfig {
            account_id: AccountId::new("credential-admission")?,
            model_id: "gpt-5.5".into(),
            effort: Some(ReasoningEffort::new("low")),
        };
        config.models.accounts.clear();
        config
            .models
            .accounts
            .insert(selector.account_id.clone(), account);
        Ok((config, selector))
    }

    fn resolve(
        config: &crate::StudioConfig,
        selector: &ModelRouteConfig,
    ) -> crate::Result<pl_model::config::ResolvedModelRoute> {
        resolve_child_selection(config, crate::config::root_agent_route_id(), selector)
    }

    #[test]
    fn shared_route_admission_accepts_chatgpt_without_reading_credentials() -> Result<()> {
        let (mut config, selector) = native_selection()?;
        let record = ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: "admission-registration".into(),
            account: ChatGptAccountInfo {
                issuer: "https://auth.openai.com".into(),
                subject: "admission-subject".into(),
                client_id: "admission-issued-client".into(),
                email: None,
                plan_usage_enabled: true,
                codex: None,
            },
            ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            access_token: "synthetic-access".into(),
            refresh_token: "synthetic-refresh".into(),
            id_token: "synthetic-id".into(),
            scopes: vec!["chatgpt.tokens.use.direct".into()],
            expires_at: 1,
            earliest_refresh_at: None,
            refresh_in_flight: true,
        };
        let temp = tempfile::tempdir()?;
        let session = ChatGptSession::new(
            &record,
            Arc::new(NoCredentialIo),
            temp.path().join("must-not-lock"),
        )?;
        let account = config
            .models
            .accounts
            .get_mut(&selector.account_id)
            .unwrap();
        account.authentication = AccountAuthenticationMethod::ChatGpt;
        account.chatgpt_account = Some(record.account);
        account.chatgpt_session = Some(session.clone());
        account.bearer_token = None;
        account.bearer_token_env = None;

        let route = resolve(&config, &selector)?;
        assert!(route.endpoint.bearer_token.is_none());
        assert_eq!(
            route
                .endpoint
                .authorization
                .as_ref()
                .map(|auth| auth.registration_id()),
            Some(session.registration_id()),
        );
        assert!(!temp.path().join("must-not-lock").exists());
        // Admission recognizes the capability; only request preparation decides whether this
        // deliberately expired/in-flight session can produce a token. Even revocation is not
        // resolved by this synchronous gate.
        session.revoke();
        resolve(&config, &selector)?;
        Ok(())
    }

    #[test]
    fn shared_route_admission_preserves_api_credential_requirements() -> Result<()> {
        let (mut config, selector) = native_selection()?;
        for token in [None, Some(""), Some(" \t"), Some("synthetic-api-key")] {
            let account = config
                .models
                .accounts
                .get_mut(&selector.account_id)
                .unwrap();
            account.bearer_token_env = None;
            account.bearer_token = token.map(str::to_owned);
            let result = resolve(&config, &selector);
            if token.is_some_and(|token| !token.trim().is_empty()) {
                result?;
            } else {
                assert!(matches!(result, Err(crate::PureError::ConfigError(_))));
            }
        }
        Ok(())
    }

    #[test]
    fn shared_route_admission_keeps_local_compatible_accounts_credential_free() -> Result<()> {
        let (mut config, mut selector) = native_selection()?;
        selector.model_id = "local-model".into();
        selector.effort = None;
        config.models.accounts.insert(
            selector.account_id.clone(),
            AccountConfig::from_explicit_models(
                pl_model::protocol::providers::openai::compatible_endpoint(
                    "Local admission fixture",
                    "http://127.0.0.1:1",
                ),
                vec![pl_model::model::ModelInfo::compatible(&selector.model_id)],
            ),
        );
        let route = resolve(&config, &selector)?;
        assert!(route.endpoint.bearer_token.is_none());
        assert!(route.endpoint.authorization.is_none());
        Ok(())
    }
}
