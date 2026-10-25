//! Closed locators over the original Configuration pin; no copied JSON or string-path queries.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) struct ModelPath {
    pub(super) account: usize,
    pub(super) model: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum RootText {
    DefaultAccount,
    Permission,
    BaseInstruction,
    Developer,
    User,
    SkillsProject,
    SkillsUser,
    SearchMode,
    SearchContext,
    Country,
    Region,
    City,
    Timezone,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum AccountText {
    Id,
    Template,
    Protocol,
    Name,
    BaseUrl,
    Catalog,
    BearerTokenEnv,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ModelText {
    Id,
    Name,
    BaseInstructions,
    WireApi,
    DefaultConnection,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum RouteText {
    Key,
    Account,
    Model,
    Effort,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum McpText {
    Id,
    Transport,
    Endpoint,
    Source,
    MutationPolicy,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum StringList {
    ProjectDocs,
    SkillsExternal,
    SkillsDisabled,
    PinnedThreads,
    PinnedProjects,
    SearchDomains,
    DisabledModels(usize),
    Efforts(ModelPath),
    Connections(ModelPath),
    MediaTypes(ModelPath, usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum TextField {
    Root(RootText),
    Account(usize, AccountText),
    Model(ModelPath, ModelText),
    Connection(usize, usize, bool),
    AutoCompact(usize, usize),
    Mode(usize, RouteText),
    Role(usize, RouteText),
    Mcp(usize, McpText),
    String(StringList, usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ListField {
    Accounts,
    CustomModels(usize),
    Connections(usize),
    AutoCompact(usize),
    Modes,
    Roles,
    Mcp,
    Strings(StringList),
    Inputs(ModelPath),
    InputSources(ModelPath, usize),
}
