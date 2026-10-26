//! Immutable dispatch provenance. The selected child route belongs only to its saved Profile.
use anyhow::{Result, ensure};
use pl_core::{
    context::OpaquePayload,
    thread::{ThreadSnapshot, extensions::ExtensionRecord},
};
use pl_protocol::{DelegationMode, DelegationPreference, DelegationSettings};

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

pub(crate) fn profile_model(
    profile: &pl_protocol::AgentProfileSnapshot,
) -> pl_protocol::studio::NewThreadModelRoute {
    pl_protocol::studio::NewThreadModelRoute {
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
    profile: &pl_protocol::AgentProfileSnapshot,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    resolve_child_selection(
        config,
        pl_model::config::AgentRoleId::new(profile.profile_id.clone())?,
        &crate::studio::model_route::profile_route(profile)
            .map_err(|error| crate::PureError::ConfigError(error.to_string()))?,
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

/// Catalog queries and immutable Models capture use the same original candidate admission.
/// A captured catalog retains only its qualification outcome, never this resolved route.
pub(crate) fn resolve_catalog_selection(
    config: &crate::StudioConfig,
    account_id: &pl_model::config::AccountId,
    entry: &pl_model::config::AccountModelEntry,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    let effort = entry
        .model
        .default_effort()
        .or_else(|| entry.model.supported_efforts().first().cloned());
    resolve_child_selection(
        config,
        pl_model::config::AgentRoleId::new("executor".to_string())?,
        &pl_model::config::ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: entry.model.model_id.clone(),
            effort: effort.map(pl_model::config::ReasoningEffort::new),
        },
    )
}

pub(crate) fn validate_credential(
    route: &pl_model::config::ResolvedModelRoute,
) -> crate::Result<()> {
    if route.endpoint.protocol != pl_model::protocol::ProtocolKind::OpenAiCompatible
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
            "自动分发偏好：经济。先判断任务难度、必需能力、上下文与交付质量，再降低整项任务成本。满足要求时优先不计费与订阅账号，先分别用 billingKind=noCharge 和 subscription 查询，合适候选不足再查其他类别，单个空页不代表全局无候选。同属这两类仍按已知模型参考价及预计输入、输出、缓存和返修成本比较：简单明确任务选便宜且够用的模型，困难或高风险任务确需更强能力时才选更贵且适配的模型，不能因不另收费就默认用最贵模型。价格不证明质量；订阅高价模型通常消耗更稀缺资源，但不能据此编造额度、倍率或价格到次数的换算，已知真实套餐限制优先。未知价不是免费或最便宜；无可靠换算不比不同币种裸数值。复用未变化查询，只看少量必要详情，显式选择 modelSelection；不得改变主代理模型、child 冻结身份、权限、预算、验收或独立审查要求。"
        }
        DelegationPreference::Balanced => {
            "自动分发偏好：平衡。先满足任务能力、上下文与质量要求，综合适配、返修风险、成本与总交付时间。经济性采用同一两层规则：合适时优先不计费与订阅，分别按 billingKind=noCharge 和 subscription 查询，不足再查其他类别，一个空页不代表全局无候选；同属这两类仍比较已知模型参考价和预计输入、输出、缓存及返修成本。简单任务便宜够用，困难或高风险确需更强能力时再用更贵且适配的模型，不因不另收费默认最贵；价格不证明质量，高定价仅是订阅资源稀缺的参考，不是额度事实。优先真实套餐限制，不编造余额、倍率或价格到次数的换算；订阅不等于无限使用，未知价不是免费或最便宜，无可靠换算不比跨币种裸数值。复用未变化查询，只看少量必要详情，显式选择 modelSelection；不得改变主代理模型、child 冻结身份、权限、预算、验收或独立审查要求。"
        }
        DelegationPreference::Fast => {
            "自动分发偏好：快速。先满足必需能力、上下文和交付质量，以整项任务总完成时间为主，综合首字延迟、吞吐、任务难度及返修风险，不只看最高吞吐。能力与交付时间相近时采用同套成本取舍：合适时优先不计费与订阅，分别按 billingKind=noCharge 和 subscription 查询，不足再扩展其他类别，单个空页不代表全局无候选；同类仍比较已知模型参考价及预计输入、输出、缓存、返修成本。简单任务便宜够用，困难或高风险确需更强能力才用更贵模型，不因不另收费默认最贵；价格不证明质量。已知真实套餐限制优先，不编造额度、倍率或价格到次数换算；订阅不等于无限使用，未知价不是最便宜，无可靠换算不比跨币种裸数值。复用未变化查询，只看少量必要详情，显式选择 modelSelection；不得改变主代理模型、child 冻结身份、权限、预算、验收或独立审查要求。"
        }
    })
}
