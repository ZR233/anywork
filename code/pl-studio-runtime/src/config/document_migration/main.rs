use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::{VERSION_KEY, identity, optional_identity, wire};
use crate::toml_schema::{self, LoadedDocument};

const ENTITY: &str = "studio-config";

/// All root fields and nested values are frozen here, including the unchanged ones.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
#[serde(bound(
    serialize = "M: Serialize, R: Serialize, A: Serialize + Default + PartialEq, S: Serialize + Default + PartialEq",
    deserialize = "M: Deserialize<'de>, R: Deserialize<'de>, A: Deserialize<'de> + Default, S: Deserialize<'de> + Default"
))]
struct Document<M, R, A, S = wire::SkillsConfig> {
    models: M,
    #[serde(default)]
    delegation: wire::DelegationSettings,
    #[serde(default)]
    mode_model_routes: BTreeMap<String, R>,
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    disabled_system_agents: BTreeSet<String>,
    #[serde(default)]
    web_search: wire::WebSearchConfig,
    #[serde(default)]
    deepseek_web_search: wire::DeepSeekWebSearchConfig,
    #[serde(default, skip_serializing_if = "wire::is_default")]
    runtime: wire::RuntimeConfig,
    #[serde(default, skip_serializing_if = "wire::is_default")]
    instructions: wire::InstructionsConfig,
    #[serde(default, skip_serializing_if = "wire::is_default")]
    skills: S,
    #[serde(default)]
    mcp: wire::StudioMcpConfig,
    #[serde(default, skip_serializing_if = "wire::is_default")]
    lsp: wire::StudioLspConfig,
    #[serde(default, skip_serializing_if = "wire::is_default")]
    ui: wire::StudioUiConfig,
    #[serde(default, skip_serializing_if = "wire::is_default")]
    acp: A,
}

impl<M, R, A, S> Document<M, R, A, S> {
    fn map<N, T, B>(
        self,
        models: impl FnOnce(M) -> N,
        route: impl Fn(R) -> T,
        acp: impl FnOnce(A) -> B,
    ) -> Document<N, T, B, S> {
        Document {
            models: models(self.models),
            delegation: self.delegation,
            mode_model_routes: self
                .mode_model_routes
                .into_iter()
                .map(|(k, v)| (k, route(v)))
                .collect(),
            disabled_system_agents: self.disabled_system_agents,
            web_search: self.web_search,
            deepseek_web_search: self.deepseek_web_search,
            runtime: self.runtime,
            instructions: self.instructions,
            skills: self.skills,
            mcp: self.mcp,
            lsp: self.lsp,
            ui: self.ui,
            acp: acp(self.acp),
        }
    }

    fn map_skills<K>(self, skills: impl FnOnce(S) -> K) -> Document<M, R, A, K> {
        Document {
            models: self.models,
            delegation: self.delegation,
            mode_model_routes: self.mode_model_routes,
            disabled_system_agents: self.disabled_system_agents,
            web_search: self.web_search,
            deepseek_web_search: self.deepseek_web_search,
            runtime: self.runtime,
            instructions: self.instructions,
            skills: skills(self.skills),
            mcp: self.mcp,
            lsp: self.lsp,
            ui: self.ui,
            acp: self.acp,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Route {
    account_id: String,
    model_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    effort: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "LegacyRouteWire")]
struct LegacyRoute(Route);

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyRouteWire {
    provider: Option<String>,
    account_id: Option<String>,
    model: Option<String>,
    model_id: Option<String>,
    effort: Option<String>,
}

impl TryFrom<LegacyRouteWire> for LegacyRoute {
    type Error = anyhow::Error;

    fn try_from(value: LegacyRouteWire) -> Result<Self> {
        Ok(Self(Route {
            account_id: identity(value.provider, value.account_id, "account")?,
            model_id: identity(value.model, value.model_id, "model")?,
            effort: value.effort,
        }))
    }
}

// The required planner field is checked by Serde, so 19→20 cannot fail or invent a route.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct PlannerRoutes {
    planner: LegacyRoute,
    #[serde(flatten)]
    children: BTreeMap<String, LegacyRoute>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(bound(deserialize = "A: Deserialize<'de> + PartialEq, R: Deserialize<'de>"))]
#[serde(try_from = "LegacyModelsWire<A, R>")]
struct LegacyModels<A, R> {
    providers: BTreeMap<String, A>,
    routes: R,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
#[serde(bound(deserialize = "A: Deserialize<'de>, R: Deserialize<'de>"))]
struct LegacyModelsWire<A, R> {
    providers: Option<BTreeMap<String, A>>,
    accounts: Option<BTreeMap<String, A>>,
    routes: R,
}

impl<A: PartialEq, R> TryFrom<LegacyModelsWire<A, R>> for LegacyModels<A, R> {
    type Error = anyhow::Error;

    fn try_from(value: LegacyModelsWire<A, R>) -> Result<Self> {
        Ok(Self {
            providers: identity(value.providers, value.accounts, "account collection")?,
            routes: value.routes,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
#[serde(bound(deserialize = "A: Deserialize<'de>"))]
struct Models<A> {
    accounts: BTreeMap<String, A>,
    #[serde(default)]
    routes: BTreeMap<String, Route>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "source", rename_all = "snake_case", deny_unknown_fields)]
#[serde(bound(deserialize = "M: Deserialize<'de>"))]
enum Catalog<M> {
    Bundled {
        catalog: String,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        additional_models: Vec<M>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        connection_overrides: BTreeMap<String, wire::ConnectionMode>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        auto_compact_overrides: BTreeMap<String, u64>,
    },
    Explicit {
        models: Vec<M>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        connection_overrides: BTreeMap<String, wire::ConnectionMode>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        auto_compact_overrides: BTreeMap<String, u64>,
    },
}

impl<M> Catalog<M> {
    fn map<N>(self, convert: impl Fn(M) -> N) -> Catalog<N> {
        match self {
            Self::Bundled {
                catalog,
                additional_models,
                connection_overrides,
                auto_compact_overrides,
            } => Catalog::Bundled {
                catalog,
                additional_models: additional_models.into_iter().map(convert).collect(),
                connection_overrides,
                auto_compact_overrides,
            },
            Self::Explicit {
                models,
                connection_overrides,
                auto_compact_overrides,
            } => Catalog::Explicit {
                models: models.into_iter().map(convert).collect(),
                connection_overrides,
                auto_compact_overrides,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(tag = "source", rename_all = "snake_case", deny_unknown_fields)]
enum Capabilities {
    PresetDefaults,
    #[default]
    TemplateDefaults,
    Explicit(wire::ProtocolServiceCapabilities),
}

/// Field generation only; the official Migrator below owns path registration and execution.
macro_rules! account {
    ($(#[$attribute:meta])* $name:ident, $($extras:tt)*) => {
        #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
        #[serde(deny_unknown_fields)]
        #[serde(bound(deserialize = "M: Deserialize<'de>"))]
        $(#[$attribute])*
        struct $name<M> {
            #[serde(default)]
            protocol: wire::ProtocolKind,
            #[serde(default, skip_serializing_if = "Option::is_none")]
            template: Option<String>,
            name: String,
            base_url: String,
            #[serde(default, skip_serializing_if = "Option::is_none")]
            bearer_token: Option<String>,
            #[serde(default, skip_serializing_if = "Option::is_none")]
            bearer_token_env: Option<String>,
            #[serde(default, skip_serializing_if = "Option::is_none")]
            http_headers: Option<BTreeMap<String, String>>,
            #[serde(default)]
            tool_wire_policy: wire::ToolWirePolicy,
            #[serde(default, skip_serializing_if = "Option::is_none")]
            apply_patch_tool_type: Option<wire::ApplyPatchToolType>,
            #[serde(default)]
            capabilities: Capabilities,
            catalog: Catalog<M>,
            #[serde(default, skip_serializing_if = "Option::is_none")]
            billing_kind: Option<wire::BillingKind>,
            $($extras)*
        }
    };
}

account!(Account23,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pricing_mode: Option<wire::PricingMode>,
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    disabled_models: BTreeSet<String>,
);
account!(#[serde(try_from = "Account26Wire<M>")] Account26,
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    disabled_models: BTreeSet<String>,
);
account!(Account26Wire,
    disabled_models: Option<BTreeSet<String>>,
    model_enabled_overrides: Option<BTreeMap<String, bool>>,
);
account!(Account27,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    model_enabled_overrides: BTreeMap<String, bool>,
);

impl<M> TryFrom<Account26Wire<M>> for Account26<M> {
    type Error = anyhow::Error;

    fn try_from(value: Account26Wire<M>) -> Result<Self> {
        let disabled = value
            .disabled_models
            .map(|models| models.into_iter().map(|model| (model, false)).collect());
        let overrides =
            optional_identity(disabled, value.model_enabled_overrides, "model enablement")?
                .unwrap_or_default();
        ensure!(
            overrides.values().all(|enabled| !enabled),
            "schema 26 cannot represent explicit model enablement"
        );
        Ok(Self {
            protocol: value.protocol,
            template: value.template,
            name: value.name,
            base_url: value.base_url,
            bearer_token: value.bearer_token,
            bearer_token_env: value.bearer_token_env,
            http_headers: value.http_headers,
            tool_wire_policy: value.tool_wire_policy,
            apply_patch_tool_type: value.apply_patch_tool_type,
            capabilities: value.capabilities,
            catalog: value.catalog,
            billing_kind: value.billing_kind,
            disabled_models: overrides.into_keys().collect(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(bound(deserialize = "M: Deserialize<'de>"))]
#[serde(try_from = "LegacyAccountWire<M>")]
struct LegacyAccount<M>(Account23<M>);

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
#[serde(bound(deserialize = "M: Deserialize<'de>"))]
struct LegacyAccountWire<M> {
    adapter: Option<Adapter>,
    protocol: Option<wire::ProtocolKind>,
    preset: Option<String>,
    template: Option<String>,
    name: String,
    base_url: String,
    bearer_token: Option<String>,
    bearer_token_env: Option<String>,
    http_headers: Option<BTreeMap<String, String>>,
    #[serde(default)]
    tool_wire_policy: wire::ToolWirePolicy,
    apply_patch_tool_type: Option<wire::ApplyPatchToolType>,
    capabilities: Option<Capabilities>,
    service_capabilities: Option<wire::ProtocolServiceCapabilities>,
    catalog: Catalog<M>,
    billing_kind: Option<wire::BillingKind>,
    pricing_mode: Option<wire::PricingMode>,
    #[serde(default)]
    disabled_models: BTreeSet<String>,
}

#[derive(Deserialize)]
enum Adapter {
    #[serde(rename = "openAi", alias = "open_ai")]
    OpenAi,
    #[serde(rename = "deepSeek", alias = "deep_seek")]
    DeepSeek,
    #[serde(rename = "zhipu")]
    Zhipu,
    #[serde(rename = "miMo", alias = "mi_mo")]
    MiMo,
    #[serde(rename = "xai")]
    Xai,
    #[serde(rename = "openAiCompatible", alias = "open_ai_compatible")]
    OpenAiCompatible,
}

impl Adapter {
    fn protocol(self) -> wire::ProtocolKind {
        match self {
            Self::OpenAi => wire::ProtocolKind::OpenAi,
            Self::DeepSeek => wire::ProtocolKind::DeepSeek,
            Self::Zhipu => wire::ProtocolKind::Zhipu,
            Self::MiMo => wire::ProtocolKind::MiMo,
            Self::Xai => wire::ProtocolKind::Xai,
            Self::OpenAiCompatible => wire::ProtocolKind::OpenAiCompatible,
        }
    }
}

impl<M> TryFrom<LegacyAccountWire<M>> for LegacyAccount<M> {
    type Error = anyhow::Error;

    fn try_from(value: LegacyAccountWire<M>) -> Result<Self> {
        let capabilities = match (value.capabilities, value.service_capabilities) {
            (None, None) => Capabilities::default(),
            (Some(value), None) => value,
            (None, Some(value)) => Capabilities::Explicit(value),
            // This retired design-only table was never the persisted capability selection.
            // Decode its frozen shape while retaining the authoritative selection.
            (Some(selection), Some(_)) => selection,
        };
        Ok(Self(Account23 {
            protocol: optional_identity(
                value.adapter.map(Adapter::protocol),
                value.protocol,
                "protocol",
            )?
            .unwrap_or_default(),
            template: optional_identity(value.preset, value.template, "template")?,
            name: value.name,
            base_url: value.base_url,
            bearer_token: value.bearer_token,
            bearer_token_env: value.bearer_token_env,
            http_headers: value.http_headers,
            tool_wire_policy: value.tool_wire_policy,
            apply_patch_tool_type: value.apply_patch_tool_type,
            capabilities,
            catalog: value.catalog,
            billing_kind: value.billing_kind,
            pricing_mode: value.pricing_mode,
            disabled_models: value.disabled_models,
        }))
    }
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyAcp {
    #[serde(default)]
    accounts: BTreeMap<String, LegacyAcpAccount>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyAcpAccount {
    name: String,
    provider: wire::AcpProvider,
    program: Option<String>,
    #[serde(default)]
    args: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "LegacyModelWire")]
struct LegacyModel(wire::ModelInfo);

// Kept as an explicit historical DTO; neither the slug nor nested model wire imports domain types.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LegacyModelWire {
    slug: Option<String>,
    model_id: Option<String>,
    observation: Option<wire::ModelObservation>,
    display_name: String,
    description: Option<String>,
    context_window: Option<u64>,
    max_context_window: Option<u64>,
    auto_compact_token_limit: Option<u64>,
    default_temperature: Option<f32>,
    max_output_tokens: Option<u64>,
    pricing: wire::ModelPricing,
    #[serde(default)]
    parameters: Vec<wire::ModelParameter>,
    binding: wire::ModelBinding,
    #[serde(default)]
    capabilities: wire::ModelCapabilities,
    #[serde(default)]
    truncation_policy: wire::TruncationPolicy,
    #[serde(default)]
    base_instructions: String,
}

impl TryFrom<LegacyModelWire> for LegacyModel {
    type Error = anyhow::Error;

    fn try_from(value: LegacyModelWire) -> Result<Self> {
        Ok(Self(wire::ModelInfo {
            model_id: identity(value.slug, value.model_id, "model declaration")?,
            observation: value.observation,
            display_name: value.display_name,
            description: value.description,
            context_window: value.context_window,
            max_context_window: value.max_context_window,
            auto_compact_token_limit: value.auto_compact_token_limit,
            default_temperature: value.default_temperature,
            max_output_tokens: value.max_output_tokens,
            pricing: value.pricing,
            parameters: value.parameters,
            binding: value.binding,
            capabilities: value.capabilities,
            truncation_policy: value.truncation_policy,
            base_instructions: value.base_instructions,
        }))
    }
}

type PreModes =
    Document<LegacyModels<LegacyAccount<LegacyModel>, PlannerRoutes>, LegacyRoute, LegacyAcp>;
type BeforeSlug = Document<
    LegacyModels<LegacyAccount<LegacyModel>, BTreeMap<String, LegacyRoute>>,
    LegacyRoute,
    LegacyAcp,
>;
type BeforeAccounts = Document<
    LegacyModels<LegacyAccount<wire::ModelInfo>, BTreeMap<String, LegacyRoute>>,
    LegacyRoute,
    LegacyAcp,
>;
type BeforeAcp = Document<Models<Account23<wire::ModelInfo>>, Route, LegacyAcp>;
type BeforePricing = Document<Models<Account23<wire::ModelInfo>>, Route, wire::AcpConfig>;
type BeforeEnablement = Document<Models<Account26<wire::ModelInfo>>, Route, wire::AcpConfig>;
type BeforeAuthentication = Document<Models<Account27<wire::ModelInfo>>, Route, wire::AcpConfig>;
type BeforeSkillDirectoryRemoval =
    Document<Models<Account28<wire::ModelInfo>>, Route, wire::AcpConfig>;
type Current =
    Document<Models<Account28<wire::ModelInfo>>, Route, wire::AcpConfig, wire::SkillsConfigCurrent>;

account!(Account28,
    authentication: wire::AuthenticationMethod,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    chatgpt_account: Option<wire::ChatGptAccountInfo>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    model_enabled_overrides: BTreeMap<String, bool>,
);

macro_rules! version {
    ($name:ident, $version:literal, $body:ty, $input:literal) => {
        #[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Versioned)]
        #[versioned(version = $version)]
        #[serde(try_from = $input)]
        pub(crate) struct $name($body);
    };
    ($name:ident, $version:literal, $body:ty) => {
        #[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Versioned)]
        #[versioned(version = $version)]
        #[serde(transparent)]
        pub(crate) struct $name($body);
    };
}

version!(MainV18, "18.0.0", PreModes, "PreModes");
version!(MainV19, "19.0.0", PreModes, "PreModes");
version!(MainV20, "20.0.0", BeforeSlug);
version!(MainV21, "21.0.0", BeforeSlug);
version!(MainV22, "22.0.0", BeforeAccounts);
version!(MainV23, "23.0.0", BeforeAcp);
version!(MainV24, "24.0.0", BeforeAcp);
version!(MainV25, "25.0.0", BeforePricing);
version!(MainV26, "26.0.0", BeforeEnablement);
version!(MainV27, "27.0.0", BeforeAuthentication);
version!(MainV28, "28.0.0", BeforeSkillDirectoryRemoval);
version!(MainV29, "29.0.0", Current);

fn validate_pre_mode_routes(document: &PreModes) -> Result<()> {
    for (mode, route) in &document.mode_model_routes {
        ensure!(
            matches!(mode.as_str(), "mode.simple" | "mode.task"),
            "unexpected Mode route before schema 20"
        );
        ensure!(
            route == &document.models.routes.planner,
            "conflicting planner and Mode model routes"
        );
    }
    Ok(())
}

impl TryFrom<PreModes> for MainV18 {
    type Error = anyhow::Error;

    fn try_from(document: PreModes) -> Result<Self> {
        validate_pre_mode_routes(&document)?;
        Ok(Self(document))
    }
}

impl TryFrom<PreModes> for MainV19 {
    type Error = anyhow::Error;

    fn try_from(document: PreModes) -> Result<Self> {
        validate_pre_mode_routes(&document)?;
        Ok(Self(document))
    }
}

impl MigratesTo<MainV19> for MainV18 {
    fn migrate(mut self) -> MainV19 {
        self.0.disabled_system_agents.remove("planner");
        MainV19(self.0)
    }
}

impl MigratesTo<MainV20> for MainV19 {
    fn migrate(self) -> MainV20 {
        let planner = self.0.models.routes.planner.clone();
        let mut document = self.0.map(
            |models| LegacyModels {
                providers: models.providers,
                routes: models.routes.children,
            },
            std::convert::identity,
            std::convert::identity,
        );
        document.mode_model_routes = BTreeMap::from([
            ("mode.simple".into(), planner.clone()),
            ("mode.task".into(), planner),
        ]);
        MainV20(document)
    }
}

impl MigratesTo<MainV21> for MainV20 {
    fn migrate(mut self) -> MainV21 {
        for account in self.0.models.providers.values_mut() {
            if let Capabilities::Explicit(capabilities) = &mut account.0.capabilities
                && capabilities.web_search.standalone
                    == Some(wire::StandaloneWebSearchDialect::DeepSeekAnthropicMessages)
            {
                capabilities.web_search.standalone =
                    Some(wire::StandaloneWebSearchDialect::DeepSeekToolsApi);
            }
        }
        MainV21(self.0)
    }
}

impl MigratesTo<MainV22> for MainV21 {
    fn migrate(self) -> MainV22 {
        MainV22(self.0.map(
            |models| {
                LegacyModels {
                    providers: models
                        .providers
                        .into_iter()
                        .map(|(k, v)| (k, LegacyAccount(v.0.map_models(|m| m.0))))
                        .collect(),
                    routes: models.routes,
                }
            },
            std::convert::identity,
            std::convert::identity,
        ))
    }
}

impl<M> Account23<M> {
    fn map_models<N>(self, convert: impl Fn(M) -> N) -> Account23<N> {
        Account23 {
            protocol: self.protocol,
            template: self.template,
            name: self.name,
            base_url: self.base_url,
            bearer_token: self.bearer_token,
            bearer_token_env: self.bearer_token_env,
            http_headers: self.http_headers,
            tool_wire_policy: self.tool_wire_policy,
            apply_patch_tool_type: self.apply_patch_tool_type,
            capabilities: self.capabilities,
            catalog: self.catalog.map(convert),
            billing_kind: self.billing_kind,
            pricing_mode: self.pricing_mode,
            disabled_models: self.disabled_models,
        }
    }
}

impl MigratesTo<MainV23> for MainV22 {
    fn migrate(self) -> MainV23 {
        MainV23(self.0.map(
            |models| {
                Models {
                    accounts: models
                        .providers
                        .into_iter()
                        .map(|(k, v)| {
                            let mut account = v.0;
                            account.bearer_token = None;
                            if account.capabilities == Capabilities::PresetDefaults {
                                account.capabilities = Capabilities::TemplateDefaults;
                            }
                            (k, account)
                        })
                        .collect(),
                    routes: models.routes.into_iter().map(|(k, v)| (k, v.0)).collect(),
                }
            },
            |route| route.0,
            std::convert::identity,
        ))
    }
}

impl MigratesTo<MainV24> for MainV23 {
    fn migrate(self) -> MainV24 {
        MainV24(self.0)
    }
}

impl MigratesTo<MainV25> for MainV24 {
    fn migrate(self) -> MainV25 {
        MainV25(
            self.0
                .map(std::convert::identity, std::convert::identity, |acp| {
                    wire::AcpConfig {
                        accounts: acp
                            .accounts
                            .into_iter()
                            .map(|(k, v)| {
                                (
                                    k,
                                    wire::AcpAccountConfig {
                                        name: v.name,
                                        provider: v.provider,
                                    },
                                )
                            })
                            .collect(),
                    }
                }),
        )
    }
}

impl MigratesTo<MainV26> for MainV25 {
    fn migrate(self) -> MainV26 {
        MainV26(self.0.map(
            |models| {
                Models {
                    accounts: models
                        .accounts
                        .into_iter()
                        .map(|(k, v)| {
                            (
                                k,
                                Account26 {
                                    protocol: v.protocol,
                                    template: v.template,
                                    name: v.name,
                                    base_url: v.base_url,
                                    bearer_token: v.bearer_token,
                                    bearer_token_env: v.bearer_token_env,
                                    http_headers: v.http_headers,
                                    tool_wire_policy: v.tool_wire_policy,
                                    apply_patch_tool_type: v.apply_patch_tool_type,
                                    capabilities: v.capabilities,
                                    catalog: v.catalog,
                                    billing_kind: v.billing_kind,
                                    disabled_models: v.disabled_models,
                                },
                            )
                        })
                        .collect(),
                    routes: models.routes,
                }
            },
            std::convert::identity,
            std::convert::identity,
        ))
    }
}

impl MigratesTo<MainV27> for MainV26 {
    fn migrate(self) -> MainV27 {
        MainV27(self.0.map(
            |models| {
                Models {
                    accounts: models
                        .accounts
                        .into_iter()
                        .map(|(k, v)| {
                            (
                                k,
                                Account27 {
                                    protocol: v.protocol,
                                    template: v.template,
                                    name: v.name,
                                    base_url: v.base_url,
                                    bearer_token: v.bearer_token,
                                    bearer_token_env: v.bearer_token_env,
                                    http_headers: v.http_headers,
                                    tool_wire_policy: v.tool_wire_policy,
                                    apply_patch_tool_type: v.apply_patch_tool_type,
                                    capabilities: v.capabilities,
                                    catalog: v.catalog,
                                    billing_kind: v.billing_kind,
                                    model_enabled_overrides: v
                                        .disabled_models
                                        .into_iter()
                                        .map(|id| (id, false))
                                        .collect(),
                                },
                            )
                        })
                        .collect(),
                    routes: models.routes,
                }
            },
            std::convert::identity,
            std::convert::identity,
        ))
    }
}

impl MigratesTo<MainV28> for MainV27 {
    fn migrate(self) -> MainV28 {
        MainV28(self.0.map(
            |models| {
                Models {
                    accounts: models
                        .accounts
                        .into_iter()
                        .map(|(id, account)| {
                            (
                                id,
                                Account28 {
                                    protocol: account.protocol,
                                    template: account.template,
                                    name: account.name,
                                    base_url: account.base_url,
                                    bearer_token: account.bearer_token,
                                    bearer_token_env: account.bearer_token_env,
                                    http_headers: account.http_headers,
                                    tool_wire_policy: account.tool_wire_policy,
                                    apply_patch_tool_type: account.apply_patch_tool_type,
                                    capabilities: account.capabilities,
                                    catalog: account.catalog,
                                    billing_kind: account.billing_kind,
                                    model_enabled_overrides: account.model_enabled_overrides,
                                    authentication: wire::AuthenticationMethod::ApiKey,
                                    chatgpt_account: None,
                                },
                            )
                        })
                        .collect(),
                    routes: models.routes,
                }
            },
            std::convert::identity,
            std::convert::identity,
        ))
    }
}

impl MigratesTo<MainV29> for MainV28 {
    fn migrate(self) -> MainV29 {
        MainV29(self.0.map_skills(wire::SkillsConfigCurrent::from))
    }
}

impl IntoDomain<MainV27> for MainV27 {
    fn into_domain(self) -> Self {
        self
    }
}

impl IntoDomain<MainV28> for MainV28 {
    fn into_domain(self) -> Self {
        self
    }
}

#[cfg(test)]
impl MainV27 {
    pub(crate) fn from_config(config: &super::super::StudioConfig) -> Result<Self> {
        let mut value = toml::Value::try_from(config)?;
        value
            .as_table_mut()
            .ok_or_else(|| anyhow::anyhow!("config is not a table"))?
            .remove(VERSION_KEY);
        if let Some(accounts) = value
            .get_mut("models")
            .and_then(|models| models.get_mut("accounts"))
            .and_then(toml::Value::as_table_mut)
        {
            for (_, account) in accounts.iter_mut() {
                let account = account
                    .as_table_mut()
                    .ok_or_else(|| anyhow::anyhow!("account is not a table"))?;
                account.remove("authentication");
                account.remove("chatgpt_account");
            }
        }
        value.try_into().map_err(Into::into)
    }

    pub(crate) fn encode(&self) -> Result<String> {
        toml_schema::encode(self, VERSION_KEY)
    }
}

impl IntoDomain<MainV29> for MainV29 {
    fn into_domain(self) -> Self {
        self
    }
}

impl MainV29 {
    pub(crate) fn into_config(self) -> Result<super::super::StudioConfig> {
        let mut value = toml::Value::try_from(self)?;
        value
            .as_table_mut()
            .ok_or_else(|| anyhow::anyhow!("config DTO is not a table"))?
            .insert(VERSION_KEY.into(), 29.into());
        let config: super::super::StudioConfig = value.try_into()?;
        ensure!(
            config
                .models
                .accounts
                .values()
                .all(|account| account.bearer_token.is_none()),
            "current config forbids inline credentials"
        );
        config.validate_declarations()?;
        Ok(config)
    }

    pub(crate) fn from_config(config: &super::super::StudioConfig) -> Result<Self> {
        let mut value = toml::Value::try_from(config)?;
        value
            .as_table_mut()
            .ok_or_else(|| anyhow::anyhow!("config is not a table"))?
            .remove(VERSION_KEY);
        value.try_into().map_err(Into::into)
    }

    pub(crate) fn encode(&self) -> Result<String> {
        toml_schema::encode(self, VERSION_KEY)
    }
}

fn migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(ENTITY)
                .with_keys(VERSION_KEY, "data")
                .from::<MainV18>()
                .step::<MainV19>()
                .step::<MainV20>()
                .step::<MainV21>()
                .step::<MainV22>()
                .step::<MainV23>()
                .step::<MainV24>()
                .step::<MainV25>()
                .step::<MainV26>()
                .step::<MainV27>()
                .step::<MainV28>()
                .step::<MainV29>()
                .into::<MainV29>(),
        )
        .map_err(|error| toml_schema::chain_error(ENTITY, error))?;
    Ok(migrator)
}

pub(crate) fn load_main(path: &Path, content: &str) -> Result<LoadedDocument<MainV29>> {
    toml_schema::load::<MainV18, MainV29>(path, content, &migrator()?, ENTITY, VERSION_KEY)
}

pub(crate) fn load_current_main(path: &Path, content: &str) -> Result<MainV29> {
    toml_schema::load::<MainV29, MainV29>(path, content, &migrator()?, ENTITY, VERSION_KEY)
        .map(|loaded| loaded.document)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::de::DeserializeOwned;

    // Schema 18 predates Mode routes and still owns the planner among five role routes.
    const V18: &str = r#"
schema_version = 18
disabled_system_agents = ["planner", "reviewer"]

[models.routes.planner]
provider = "saved"
model = "deepseek-flash"
effort = "high"
[models.routes.explorer]
provider = "saved"
model = "deepseek-flash"
[models.routes.executor]
provider = "saved"
model = "deepseek-flash"
[models.routes.worktree_executor]
provider = "saved"
model = "deepseek-flash"
[models.routes.reviewer]
provider = "saved"
model = "deepseek-reasoner"

[models.providers.saved]
name = "Saved account"
base_url = "https://api.deepseek.com"
preset = "deepseek"
adapter = "deepSeek"
bearer_token_env = "SAVED_KEY"
[models.providers.saved.capabilities]
source = "explicit"
[models.providers.saved.capabilities.web_search]
standalone = "deep_seek_anthropic_messages"
[models.providers.saved.catalog]
source = "bundled"
catalog = "deepseek"
[models.providers.saved.catalog.auto_compact_overrides]
deepseek-flash = 410000

[instructions]
user = "Keep deep_seek_anthropic_messages in user text"
[deepseek_web_search]
enabled = false
"#;

    fn decode_v18() -> MainV18 {
        let mut value: toml::Table = toml::from_str(V18).unwrap();
        value.remove(VERSION_KEY);
        toml::Value::Table(value).try_into().unwrap()
    }

    fn round_trip<T>(document: &T)
    where
        T: Versioned + Serialize + DeserializeOwned + PartialEq + std::fmt::Debug,
    {
        let encoded = toml::to_string(document).expect("historical TOML");
        let decoded: T = toml::from_str(&encoded).expect("same frozen wire");
        assert_eq!(&decoded, document);
        let version = toml_schema::integer_version(T::VERSION).unwrap();
        let integer = toml_schema::encode(document, VERSION_KEY).unwrap();
        let loaded = load_main(Path::new("historical.toml"), &integer).expect("official path");
        assert_eq!(loaded.source_version, version);
        assert_eq!(loaded.migrated, version != 29);
        assert_eq!(loaded.document.into_config().unwrap().schema_version, 29);
    }

    #[test]
    fn every_registered_integer_node_round_trips_its_frozen_nested_wire() {
        let v18 = decode_v18();
        round_trip(&v18);
        let v19: MainV19 = v18.migrate();
        round_trip(&v19);
        let v20: MainV20 = v19.migrate();
        round_trip(&v20);
        let v21: MainV21 = v20.migrate();
        round_trip(&v21);
        let v22: MainV22 = v21.migrate();
        round_trip(&v22);
        let v23: MainV23 = v22.migrate();
        round_trip(&v23);
        let v24: MainV24 = v23.migrate();
        round_trip(&v24);
        let v25: MainV25 = v24.migrate();
        round_trip(&v25);
        let v26: MainV26 = v25.migrate();
        round_trip(&v26);
        let v27: MainV27 = v26.migrate();
        round_trip(&v27);
        let v28: MainV28 = v27.migrate();
        round_trip(&v28);
        let v29: MainV29 = v28.migrate();
        round_trip(&v29);
    }

    #[test]
    fn planner_and_provider_dialect_steps_preserve_user_choices() {
        let v18 = decode_v18();
        let planner = v18.0.models.routes.planner.clone();
        let v19: MainV19 = v18.migrate();
        assert!(!v19.0.disabled_system_agents.contains("planner"));
        assert_eq!(v19.0.models.routes.planner, planner);
        assert_eq!(v19.0.models.routes.children.len(), 4);
        let historical19 = toml_schema::encode(&v19, VERSION_KEY).unwrap();
        for raw in [V18, historical19.as_str()] {
            let loaded = load_main(Path::new("saved.toml"), raw).unwrap();
            let config = loaded.document.into_config().unwrap();
            assert_eq!(config.models.routes.len(), 4);
            assert_eq!(config.mode_model_routes.len(), 2);
            assert!(config.disabled_system_agents.contains("reviewer"));
            assert!(!config.deepseek_web_search.enabled);
            assert!(config.deepseek_web_search.fetch_enabled);
            assert_eq!(
                config.instructions.user,
                "Keep deep_seek_anthropic_messages in user text"
            );
            let encoded = MainV29::from_config(&config).unwrap().encode().unwrap();
            let table: toml::Table = toml::from_str(&encoded).unwrap();
            assert_eq!(
                table["models"]["accounts"]["saved"]["capabilities"]["web_search"]["standalone"]
                    .as_str(),
                Some("deep_seek_tools_api")
            );
            assert_eq!(table["models"]["accounts"]["saved"]["catalog"]["auto_compact_overrides"]["deepseek-flash"].as_integer(), Some(410000));
        }
    }

    #[test]
    fn rejects_invalid_headers_and_missing_historical_planner_with_sources() {
        for header in [
            "",
            "schema_version=0\n",
            "schema_version=17\n",
            "schema_version=30\n",
            "schema_version=-1\n",
            "schema_version=4294967296\n",
            "schema_version='27'\n",
            "schema_version=27.0\n",
        ] {
            let raw = V18.replacen("schema_version = 18", header, 1);
            let error = load_main(Path::new("saved.toml"), &raw).err().unwrap();
            assert!(error.is::<toml_schema::DocumentMigrationFailed>());
        }
        let missing = V18.replace("[models.routes.planner]", "[models.routes.other]");
        assert!(load_main(Path::new("saved.toml"), &missing).is_err());
        assert!(load_current_main(Path::new("saved.toml"), V18).is_err());
    }

    #[test]
    fn planner_and_mode_aliases_require_the_same_saved_route() {
        let v19: MainV19 = decode_v18().migrate();
        let raw = toml_schema::encode(&v19, VERSION_KEY).unwrap();
        let mut value: toml::Value = toml::from_str(&raw).unwrap();
        let planner = value["models"]["routes"]["planner"].clone();
        value["mode_model_routes"] = toml::Value::Table(
            [
                ("mode.simple".into(), planner.clone()),
                ("mode.task".into(), planner),
            ]
            .into_iter()
            .collect(),
        );
        load_main(Path::new("saved.toml"), &toml::to_string(&value).unwrap())
            .expect("equal transitional keys are canonicalized");
        value["mode_model_routes"]["mode.task"]["model_id"] = "different".into();
        assert!(load_main(Path::new("saved.toml"), &toml::to_string(&value).unwrap()).is_err());
    }

    #[test]
    fn disabled_models_only_create_false_overrides() {
        let v18 = decode_v18();
        let v19: MainV19 = v18.migrate();
        let v20: MainV20 = v19.migrate();
        let v21: MainV21 = v20.migrate();
        let v22: MainV22 = v21.migrate();
        let v23: MainV23 = v22.migrate();
        let v24: MainV24 = v23.migrate();
        let v25: MainV25 = v24.migrate();
        let mut v26: MainV26 = v25.migrate();
        v26.0
            .models
            .accounts
            .get_mut("saved")
            .unwrap()
            .disabled_models
            .insert("withdrawn".into());
        let v27: MainV27 = v26.migrate();
        assert_eq!(
            v27.0.models.accounts["saved"].model_enabled_overrides,
            BTreeMap::from([("withdrawn".into(), false)])
        );
    }

    #[test]
    fn schema_26_aliases_normalize_equal_enablement_and_reject_conflicts_before_steps() {
        let v19: MainV19 = decode_v18().migrate();
        let v20: MainV20 = v19.migrate();
        let v21: MainV21 = v20.migrate();
        let v22: MainV22 = v21.migrate();
        let v23: MainV23 = v22.migrate();
        let v24: MainV24 = v23.migrate();
        let v25: MainV25 = v24.migrate();
        let mut v26: MainV26 = v25.migrate();
        v26.0
            .models
            .accounts
            .get_mut("saved")
            .unwrap()
            .disabled_models
            .insert("withdrawn".into());
        let source = toml_schema::encode(&v26, VERSION_KEY).unwrap();
        let mut equal: toml::Value = toml::from_str(&source).unwrap();
        equal["models"]["accounts"]["saved"]
            .as_table_mut()
            .unwrap()
            .insert(
                "model_enabled_overrides".into(),
                toml::Value::Table(
                    BTreeMap::from([("withdrawn".into(), false.into())])
                        .into_iter()
                        .collect(),
                ),
            );
        let raw = toml::to_string(&equal).unwrap();
        let loaded = load_main(Path::new("saved.toml"), &raw).unwrap();
        assert_eq!(loaded.source_version, 26);
        assert_eq!(
            loaded.document.0.models.accounts["saved"].model_enabled_overrides,
            BTreeMap::from([("withdrawn".into(), false)])
        );

        for changed in [
            toml::Value::Table([("withdrawn".into(), true.into())].into_iter().collect()),
            toml::Value::Table([("different".into(), false.into())].into_iter().collect()),
        ] {
            let mut invalid = equal.clone();
            invalid["models"]["accounts"]["saved"]["model_enabled_overrides"] = changed;
            let error = load_main(Path::new("saved.toml"), &toml::to_string(&invalid).unwrap())
                .err()
                .expect("conflicting aliases are not overwritten");
            assert!(error.is::<toml_schema::DocumentMigrationFailed>());
        }
        // The retired array is accepted only in the migration boundary.
        equal[VERSION_KEY] = 27.into();
        assert!(load_main(Path::new("saved.toml"), &toml::to_string(&equal).unwrap()).is_err());
    }

    #[test]
    fn schema_27_skill_user_directory_is_dropped_without_changing_other_settings() {
        let mut config = crate::config::StudioConfig::default_config().unwrap();
        config.skills.enabled = false;
        config.skills.auto_learn = false;
        config.skills.system.enabled = false;
        config.skills.project_dir = ".workspace/skills".into();
        config.skills.external_dirs = vec!["/readonly/skills".into()];
        config.skills.disabled = vec!["paused-skill".into()];
        config.skills.auto_learn_min_tool_calls = 9;
        config.ui.language = pl_protocol::studio::StudioUiLanguage::En;
        let old_models = config.models.clone();
        let old_routes = config.mode_model_routes.clone();
        let old_ui = config.ui.clone();

        let mut old = toml::Value::try_from(MainV27::from_config(&config).unwrap()).unwrap();
        old.as_table_mut()
            .unwrap()
            .entry("skills")
            .or_insert_with(|| toml::Value::Table(toml::Table::new()));
        old["skills"]["user_dir"] = "~/.anywork/skills".into();
        let old: MainV27 = old.try_into().unwrap();
        let loaded = load_main(Path::new("v27.toml"), &old.encode().unwrap()).unwrap();

        assert_eq!(loaded.source_version, 27);
        let current = loaded.document.encode().unwrap();
        assert!(!current.contains("user_dir"));
        let mut invalid_current: toml::Value = toml::from_str(&current).unwrap();
        invalid_current
            .as_table_mut()
            .unwrap()
            .entry("skills")
            .or_insert_with(|| toml::Value::Table(toml::Table::new()));
        invalid_current["skills"]
            .as_table_mut()
            .unwrap()
            .insert("user_dir".into(), "/custom/skills".into());
        assert!(
            load_current_main(
                Path::new("v29.toml"),
                &toml::to_string(&invalid_current).unwrap()
            )
            .is_err()
        );
        let migrated = loaded.document.into_config().unwrap();
        assert_eq!(migrated.schema_version, 29);
        assert_eq!(migrated.models, old_models);
        assert_eq!(migrated.mode_model_routes, old_routes);
        assert_eq!(migrated.ui, old_ui);
        assert!(!migrated.skills.enabled);
        assert!(!migrated.skills.auto_learn);
        assert!(!migrated.skills.system.enabled);
        assert_eq!(migrated.skills.project_dir, ".workspace/skills");
        assert_eq!(migrated.skills.external_dirs, ["/readonly/skills"]);
        assert_eq!(migrated.skills.disabled, ["paused-skill"]);
        assert_eq!(migrated.skills.auto_learn_min_tool_calls, 9);
    }
}
