import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_presentations.freezed.dart';

/// Presentation identity only. SDK identities are adapted by the Connector/VM.
enum AccountKind { native, acp }

enum AccountBilling { unknown, metered, subscription, noCharge }

enum AccountQueryPhase {
  idle,
  loading,
  ready,
  unsupported,
  missingCredential,
  failed,
}

enum AccountBalanceHealth { unknown, sufficient, insufficient }

enum AccountListPhase { loading, ready, failed }

enum AccountRowAction { refresh, setDefault, edit, delete }

enum AccountModelOrigin { online, bundled, manual }

enum AccountModelTab { specifications, pricing, evaluations }

enum AccountModelAction {
  edit,
  delete,
  loadReadout,
  retryReadout,
  resetCompact,
  retryCompact,
  saveCompact,
}

enum AccountItemLayout { columns, stacked }

enum AccountMetricDensity { summary, detailed }

enum AccountEvaluationOutcome { passed, failed, notRated }

enum AccountEvaluationSort { newest, highestQuality, lowestQuality }

enum AccountEvaluationCategory {
  reasoning,
  coding,
  tooling,
  longContext,
  multimodal,
  general,
}

enum AccountConnection { automatic, http, webSocket }

enum AccountAuthenticationMethod { apiKey, chatGpt }

enum ChatGptLoginPhase {
  preparing,
  awaitingBrowser,
  exchangingCode,
  succeeded,
  cancelled,
  failed,
}

enum ChatGptLoginFailureCode {
  authorizationDenied,
  missingPlanPermission,
  expired,
  other,
}

enum NativeAccountField { name, endpoint, credential }

enum ManualModelField { id, name, contextWindow, maxOutputTokens }

enum AccountWireApi { chatCompletions, responses }

enum AcpAccountAction {
  prepare,
  cancelPreparation,
  usePrepared,
  check,
  login,
  verify,
  cancelAuthentication,
  retry,
  openGuide,
  openTerms,
}

enum AcpPresentationPhase {
  idle,
  preparing,
  ready,
  checking,
  needsLogin,
  authenticating,
  verifying,
  connected,
  cancelling,
  closing,
  failed,
}

enum AccountLeaveChoice { save, discard, cancel }

final class ChatGptAccountInfo {
  const ChatGptAccountInfo({this.email, required this.planUsageEnabled});
  final String? email;
  final bool planUsageEnabled;

  @override
  bool operator ==(Object other) =>
      other is ChatGptAccountInfo &&
      email == other.email &&
      planUsageEnabled == other.planUsageEnabled;

  @override
  int get hashCode => Object.hash(email, planUsageEnabled);
}

final class ChatGptLoginSnapshot {
  const ChatGptLoginSnapshot({required this.phase, this.account, this.failure});
  final ChatGptLoginPhase phase;
  final ChatGptAccountInfo? account;
  final ChatGptLoginFailureCode? failure;

  @override
  bool operator ==(Object other) =>
      other is ChatGptLoginSnapshot &&
      phase == other.phase &&
      account == other.account &&
      failure == other.failure;

  @override
  int get hashCode => Object.hash(phase, account, failure);
}

@freezed
abstract class AccountDisplayKey with _$AccountDisplayKey {
  const factory AccountDisplayKey({
    required AccountKind kind,
    required String id,
  }) = _AccountDisplayKey;
}

@freezed
abstract class AccountModelKey with _$AccountModelKey {
  const factory AccountModelKey({
    required AccountDisplayKey account,
    required String modelId,
  }) = _AccountModelKey;
}

@freezed
abstract class AccountTemplateKey with _$AccountTemplateKey {
  const factory AccountTemplateKey({
    required AccountKind kind,
    required String id,
  }) = _AccountTemplateKey;
}

@freezed
sealed class AccountTemplateContent with _$AccountTemplateContent {
  const factory AccountTemplateContent.native({
    required AccountBilling defaultBilling,
    required String protocolLabel,
    required String defaultEndpoint,
    required bool supportsModelDiscovery,
    required bool? supportsUsageQuery,
  }) = NativeAccountTemplateContent;
  const factory AccountTemplateContent.acp() = AcpAccountTemplateContent;
}

@freezed
abstract class AccountTemplatePresentation with _$AccountTemplatePresentation {
  const factory AccountTemplatePresentation({
    required AccountTemplateKey key,
    required String name,
    required AccountTemplateContent content,
    String? iconKey,
    String? description,
  }) = _AccountTemplatePresentation;
}

/// Decimal strings retain provider precision. Missing values remain absent.
@freezed
abstract class AccountCurrencyBalance with _$AccountCurrencyBalance {
  const factory AccountCurrencyBalance({
    required String currency,
    String? total,
    String? granted,
    String? toppedUp,
  }) = _AccountCurrencyBalance;
}

/// The owner supplies the true remaining fraction and localized values.
@freezed
abstract class AccountQuotaPresentation with _$AccountQuotaPresentation {
  const factory AccountQuotaPresentation({
    required String label,
    required String remaining,
    double? remainingFraction,
    String? resetLabel,
    @Default(false) bool low,
  }) = _AccountQuotaPresentation;
}

@freezed
abstract class AccountUsagePresentation with _$AccountUsagePresentation {
  const factory AccountUsagePresentation({
    @Default(AccountQueryPhase.idle) AccountQueryPhase phase,
    @Default(AccountBalanceHealth.unknown) AccountBalanceHealth balanceHealth,
    @Default(<AccountCurrencyBalance>[]) List<AccountCurrencyBalance> balances,
    @Default(<AccountQuotaPresentation>[])
    List<AccountQuotaPresentation> quotas,
    String? updatedLabel,
    String? error,

    /// The owner confirms that retained values belong to a successful query.
    @Default(false) bool hasLastGood,
    @Default(false) bool canRefresh,
    @Default(false) bool canRetry,
  }) = _AccountUsagePresentation;
}

@freezed
sealed class AccountRowContent with _$AccountRowContent {
  const factory AccountRowContent.native({
    required AccountBilling billing,
    required AccountUsagePresentation usage,
    String? displayEndpoint,
  }) = NativeAccountRowContent;
  const factory AccountRowContent.acp({required String status}) =
      AcpAccountRowContent;
}

@freezed
abstract class AccountRowPresentation with _$AccountRowPresentation {
  const factory AccountRowPresentation({
    required AccountDisplayKey key,
    required String name,
    required AccountRowContent content,
    String? iconKey,
    @Default(false) bool isDefault,
    String? operationError,
    @Default(<AccountRowAction>[]) List<AccountRowAction> actions,
  }) = _AccountRowPresentation;
}

@freezed
abstract class AccountsListPresentation with _$AccountsListPresentation {
  const factory AccountsListPresentation({
    @Default(AccountListPhase.ready) AccountListPhase phase,
    @Default(<AccountRowPresentation>[]) List<AccountRowPresentation> rows,
    @Default('') String search,
    @Default(false) bool searchHasNoResults,
    @Default(false) bool refreshing,
    @Default(true) bool canAdd,
    @Default(false) bool canRefresh,
    String? error,
  }) = _AccountsListPresentation;
}

@freezed
abstract class AccountDisplayFact with _$AccountDisplayFact {
  const factory AccountDisplayFact({
    required String label,
    required String value,
  }) = _AccountDisplayFact;
}

@freezed
abstract class AccountModelSpecificationFacts
    with _$AccountModelSpecificationFacts {
  const factory AccountModelSpecificationFacts({
    @Default(<AccountDisplayFact>[])
    List<AccountDisplayFact> modalityCapabilities,
    @Default(<AccountDisplayFact>[]) List<AccountDisplayFact> context,
    @Default(<AccountDisplayFact>[]) List<AccountDisplayFact> connection,
  }) = _AccountModelSpecificationFacts;
}

@freezed
abstract class AccountBillingPresentation with _$AccountBillingPresentation {
  const factory AccountBillingPresentation({
    required AccountBilling effective,
    AccountBilling? billingKindOverride,
    @Default(<AccountBilling>[]) List<AccountBilling> allowedOverrides,
    @Default(false) bool saving,
    String? error,
  }) = _AccountBillingPresentation;
}

@freezed
abstract class AccountCompactPresentation with _$AccountCompactPresentation {
  const factory AccountCompactPresentation({
    @Default('') String raw,
    @Default(false) bool overridden,
    String? effective,
    String? automatic,
    String? error,
    @Default(false) bool saving,
    @Default(false) bool canEdit,
    @Default(false) bool canReset,
    @Default(false) bool canRetry,
    @Default(false) bool dirty,
    @Default(false) bool canSave,
    int? contextWindow,
    @Default(false) bool adjusted,
  }) = _AccountCompactPresentation;
}

@freezed
abstract class AccountModelEvaluation with _$AccountModelEvaluation {
  const factory AccountModelEvaluation({
    required AccountEvaluationCategory category,
    required String categoryLabel,
    required AccountEvaluationOutcome outcome,
    required String outcomeLabel,
    required String updatedLabel,
    required int updatedAt,
    required String comment,
    int? quality,
    int? instructionFollowing,
  }) = _AccountModelEvaluation;
}

@freezed
abstract class AccountModelPriceTier with _$AccountModelPriceTier {
  const factory AccountModelPriceTier({
    required String label,
    required double input,
    required double output,
    double? cacheRead,
    double? cacheWrite,
  }) = _AccountModelPriceTier;
}

@freezed
abstract class AccountEvaluationFilter with _$AccountEvaluationFilter {
  const factory AccountEvaluationFilter({
    AccountEvaluationOutcome? outcome,
    AccountEvaluationCategory? category,
    int? minimumQuality,
    @Default(AccountEvaluationSort.newest) AccountEvaluationSort sort,
  }) = _AccountEvaluationFilter;
}

@freezed
abstract class AccountEvaluationSummary with _$AccountEvaluationSummary {
  const factory AccountEvaluationSummary({
    @Default(0) int count,
    double? quality,
    double? instructionFollowing,
    @Default(<int, int>{}) Map<int, int> qualityDistribution,
    @Default(<AccountModelEvaluation>[]) List<AccountModelEvaluation> visible,
    @Default(AccountEvaluationFilter()) AccountEvaluationFilter filter,
  }) = _AccountEvaluationSummary;
}

@freezed
abstract class AccountPerformancePresentation
    with _$AccountPerformancePresentation {
  const factory AccountPerformancePresentation({
    required int sampleCount,
    required int ttftSampleCount,
    double? tokensPerSecond,
    double? averageTtftMillis,
    String? updatedLabel,
  }) = _AccountPerformancePresentation;
}

@freezed
abstract class AccountModelPresentation with _$AccountModelPresentation {
  const factory AccountModelPresentation({
    required AccountModelKey key,
    required String name,
    required AccountModelOrigin origin,
    @Default(true) bool enabled,
    @Default(false) bool canToggle,
    @Default(false) bool saving,
    String? error,
    String? summary,
    @Default(AccountModelSpecificationFacts())
    AccountModelSpecificationFacts specificationFacts,
    @Default(<AccountModelPriceTier>[]) List<AccountModelPriceTier> priceTiers,
    String? currency,
    String? priceSource,
    String? priceVerifiedLabel,
    AccountPerformancePresentation? performance,
    @Default(<AccountDisplayFact>[]) List<AccountDisplayFact> guidance,
    @Default(<AccountModelEvaluation>[])
    List<AccountModelEvaluation> evaluations,
    @Default(AccountEvaluationSummary())
    AccountEvaluationSummary evaluationSummary,
    @Default(false) bool readoutLoading,
    String? readoutError,
    @Default(false) bool canLoadReadout,
    AccountConnection? connection,
    @Default(<AccountConnection>[]) List<AccountConnection> allowedConnections,
    AccountCompactPresentation? compact,
    @Default(false) bool canEdit,
    @Default(false) bool canDelete,
  }) = _AccountModelPresentation;
}

@freezed
abstract class AccountCatalogPresentation with _$AccountCatalogPresentation {
  const factory AccountCatalogPresentation({
    @Default(<AccountModelPresentation>[])
    List<AccountModelPresentation> models,
    @Default(false) bool canSync,
    @Default(false) bool syncing,
    @Default(false) bool canRetry,
    String? checkedLabel,
    String? sourceLabel,
    String? error,
  }) = _AccountCatalogPresentation;
}

@freezed
abstract class NativeAccountDetailsPresentation
    with _$NativeAccountDetailsPresentation {
  const factory NativeAccountDetailsPresentation({
    required AccountAuthenticationMethod authentication,
    required bool credentialReady,
    required AccountBillingPresentation billing,
    required AccountCatalogPresentation catalog,
    required AccountUsagePresentation usage,
    @Default(<AccountDisplayFact>[]) List<AccountDisplayFact> advanced,
  }) = _NativeAccountDetailsPresentation;
}

@freezed
abstract class AcpLoginMethodPresentation with _$AcpLoginMethodPresentation {
  const factory AcpLoginMethodPresentation({
    required String id,
    required String label,
  }) = _AcpLoginMethodPresentation;
}

/// Describes existing ACP owner state; this is not an ACP state machine.
@freezed
abstract class AcpAccountPresentation with _$AcpAccountPresentation {
  const AcpAccountPresentation._();

  const factory AcpAccountPresentation({
    required AcpPresentationPhase phase,
    required String status,
    String? message,
    String? error,
    double? progress,
    String? progressLabel,
    @Default(<AccountDisplayFact>[]) List<AccountDisplayFact> facts,
    @Default(<AcpAccountAction>[]) List<AcpAccountAction> availableActions,

    /// Optional emphasis chosen by the VM, never inferred from [phase].
    /// Must be an available operation, not cancellation or a documentation link.
    AcpAccountAction? primaryAction,
    @Default(<AcpLoginMethodPresentation>[])
    List<AcpLoginMethodPresentation> loginMethods,
    String? selectedLoginMethod,
    @Default(false) bool canSelectLoginMethod,
  }) = _AcpAccountPresentation;

  /// Shared visual precedence for panel and footer, independent of ACP phase.
  bool get hasPrimaryAction =>
      availableActions.contains(primaryAction) &&
      switch (primaryAction) {
        AcpAccountAction.prepare ||
        AcpAccountAction.usePrepared ||
        AcpAccountAction.check ||
        AcpAccountAction.login ||
        AcpAccountAction.verify ||
        AcpAccountAction.retry => true,
        _ => false,
      };
}

@freezed
sealed class AccountDetailsContent with _$AccountDetailsContent {
  const factory AccountDetailsContent.native(
    NativeAccountDetailsPresentation value,
  ) = NativeAccountDetailsContent;
  const factory AccountDetailsContent.acp(AcpAccountPresentation value) =
      AcpAccountDetailsContent;
}

@freezed
abstract class AccountDetailsPresentation with _$AccountDetailsPresentation {
  const factory AccountDetailsPresentation({
    required AccountDisplayKey key,
    required String name,
    required AccountDetailsContent content,
    String? iconKey,
    String? endpoint,
    @Default(false) bool canEdit,
    @Default(false) bool canDelete,
    @Default(false) bool canSetDefault,
    @Default(false) bool loading,
    String? error,
  }) = _AccountDetailsPresentation;
}

@freezed
abstract class AccountTextPresentation with _$AccountTextPresentation {
  const factory AccountTextPresentation({
    @Default('') String raw,
    String? error,
    String? helper,
  }) = _AccountTextPresentation;
}

@freezed
abstract class ManualAccountModelPresentation
    with _$ManualAccountModelPresentation {
  const factory ManualAccountModelPresentation({
    required String editorKey,
    required AccountTextPresentation id,
    required AccountTextPresentation name,
    required AccountTextPresentation contextWindow,
    required AccountTextPresentation maxOutputTokens,
    required AccountWireApi wireApi,
    @Default(<AccountWireApi>[]) List<AccountWireApi> allowedWireApis,
    required AccountConnection connection,
    @Default(<AccountConnection>[]) List<AccountConnection> allowedConnections,
    @Default(false) bool canRemove,
    @Default(false) bool canEditId,
    String? error,
  }) = _ManualAccountModelPresentation;
}

/// Raw inputs, dirty/validation and save eligibility belong exclusively to VM.
@freezed
abstract class NativeAccountEditorPresentation
    with _$NativeAccountEditorPresentation {
  const factory NativeAccountEditorPresentation({
    required String editorId,
    AccountDisplayKey? accountKey,
    required AccountTemplateKey templateKey,
    @Default(<AccountTemplatePresentation>[])
    List<AccountTemplatePresentation> templates,
    required AccountTextPresentation name,
    required AccountTextPresentation endpoint,
    required AccountTextPresentation credential,
    @Default(AccountAuthenticationMethod.apiKey)
    AccountAuthenticationMethod authentication,
    @Default(false) bool isOpenAiTemplate,
    ChatGptLoginSnapshot? chatGptLogin,
    ChatGptAccountInfo? savedChatGptAccount,
    required String protocolLabel,
    @Default(false) bool canChangeTemplate,
    @Default(false) bool hasStoredCredential,
    @Default(true) bool credentialRequired,
    @Default(false) bool dirty,
    @Default(false) bool saving,
    @Default(false) bool canSave,
    @Default(false) bool canAddModel,
    @Default(false) bool setDefaultOnCreate,
    @Default(false) bool showSetDefaultOnCreate,
    @Default(<ManualAccountModelPresentation>[])
    List<ManualAccountModelPresentation> manualModels,
    @Default(<AccountModelPresentation>[])
    List<AccountModelPresentation> declaredModels,
    required AccountBillingPresentation billing,
    String? error,
  }) = _NativeAccountEditorPresentation;
}

@freezed
abstract class AcpAccountEditorPresentation
    with _$AcpAccountEditorPresentation {
  const factory AcpAccountEditorPresentation({
    required String editorId,
    AccountDisplayKey? accountKey,
    required String templateName,
    String? iconKey,
    required AccountTextPresentation name,
    required AcpAccountPresentation preparation,
    @Default(false) bool dirty,
    @Default(false) bool saving,
    @Default(false) bool canSave,
    @Default(false) bool saveAndConnect,
    String? error,
  }) = _AcpAccountEditorPresentation;
}
