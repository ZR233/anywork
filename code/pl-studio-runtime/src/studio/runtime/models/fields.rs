//! Closed locators over the original immutable Models/Templates values, never JSON paths.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) struct ModelPath {
    pub(super) group: usize,
    pub(super) model: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum AccountText {
    Id,
    CapabilitySource,
    HostedDialect,
    Standalone,
    PromptCache,
    DefaultModel,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum SearchText {
    Mode,
    Availability,
    Account,
    Model,
    DeepSeekAvailability,
    DeepSeekAccount,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum TemplateText {
    Id,
    DisplayName,
    Description,
    BaseUrl,
    CredentialLabel,
    CredentialEnv,
    CatalogId,
    Protocol,
    SuggestedModel,
    Icon,
    HostedDialect,
    Standalone,
    PromptCache,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum DescriptorText {
    Id,
    DisplayName,
    Description,
    Protocol,
    DefaultConnection,
    NativeContext,
    ReasoningParameter,
    ReasoningLabel,
    ReasoningDefault,
    PricingCurrency,
    PricingSource,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum SelectionSourceText {
    Url,
    Model,
    Effort,
    Metric,
    MetricVersion,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum EvaluationText {
    Agent,
    Parent,
    Account,
    Model,
    Effort,
    Profile,
    Turn,
    Comment,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum DelegationText {
    AccountName,
    UnavailableReason,
    GuideSummary,
    Source(usize, SelectionSourceText),
    Evaluation(usize, EvaluationText),
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum StringList {
    Candidates(ModelPath),
    MediaTypes(ModelPath, usize),
    GuideLimitations,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum TextField {
    Delegation(DelegationText),
    Account(usize, AccountText),
    Search(SearchText),
    Template(usize, TemplateText),
    TemplateRevision,
    CatalogKey(usize),
    CatalogId(usize),
    Model(ModelPath, DescriptorText),
    ConnectionId(ModelPath, usize),
    ConnectionName(ModelPath, usize),
    TierLabel(ModelPath, usize),
    String(StringList, usize),
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ListField {
    SelectionSources,
    Evaluations,
    Accounts,
    Templates,
    Catalogs,
    Models(usize),
    TypeSupport(ModelPath),
    Exclusions(ModelPath, usize),
    ConnectionModes(ModelPath),
    Inputs(ModelPath),
    InputSources(ModelPath, usize),
    Modalities(ModelPath),
    Tiers(ModelPath),
    Strings(StringList),
}
