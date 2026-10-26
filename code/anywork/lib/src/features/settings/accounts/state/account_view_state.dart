import 'package:freezed_annotation/freezed_annotation.dart';

import 'account_presentations.dart';

part 'account_view_state.freezed.dart';

/// A form instance, not an account identity. Reopening the same account creates
/// a new editor and cannot inherit an earlier asynchronous completion.
@freezed
abstract class AccountEditorKey with _$AccountEditorKey {
  const factory AccountEditorKey({
    required String editorId,
    required AccountDisplayKey target,
    required bool creating,
    AccountTemplateKey? template,
  }) = _AccountEditorKey;
}

/// Read-only projection of the existing action owner's current attempt. It is
/// independent of list filtering and carries no operation handle or reducer.
@freezed
abstract class AccountActionPresentation with _$AccountActionPresentation {
  const factory AccountActionPresentation({
    required String ownerEpoch,
    int? acpConnectionRevision,
    @Default(false) bool pending,
    String? message,
  }) = _AccountActionPresentation;
}

@freezed
abstract class AccountsViewState with _$AccountsViewState {
  const factory AccountsViewState({
    required AccountsListPresentation list,
    AccountDisplayKey? selected,
    AccountEditorKey? editor,
    @Default(false) bool choosingTemplate,
    @Default(false) bool templatesLoading,
    @Default([]) List<AccountTemplatePresentation> templates,
    String? templateError,
    @Default({}) Map<AccountDisplayKey, AccountActionPresentation> actions,
  }) = _AccountsViewState;
}

@freezed
abstract class AccountDetailsViewState with _$AccountDetailsViewState {
  const factory AccountDetailsViewState({
    required AccountDetailsPresentation details,
    AccountAcpKey? acpKey,
    @Default(false) bool observed,
    @Default(false) bool stale,
  }) = _AccountDetailsViewState;
}

enum AccountReadoutPhase { unknown, loading, ready, failed }

@freezed
abstract class AccountAcpKey with _$AccountAcpKey {
  const factory AccountAcpKey({
    required AccountDisplayKey target,
    required String providerId,
    required int connectionRevision,
    String? editorId,
    @Default(false) bool creating,
  }) = _AccountAcpKey;
}

@freezed
abstract class AccountReadoutState with _$AccountReadoutState {
  const factory AccountReadoutState({
    required AccountReadoutPhase phase,
    @Default([]) List<AccountDisplayFact> performance,
    @Default([]) List<AccountModelEvaluation> evaluations,
    String? error,
  }) = _AccountReadoutState;
}

@freezed
abstract class AccountModelsViewState with _$AccountModelsViewState {
  const factory AccountModelsViewState({
    required AccountCatalogPresentation catalog,
    @Default({}) Map<String, AccountReadoutState> readouts,
    @Default(false) bool stale,
  }) = _AccountModelsViewState;
}

@freezed
abstract class AccountEditorViewState with _$AccountEditorViewState {
  const factory AccountEditorViewState({
    required AccountEditorKey key,
    NativeAccountEditorPresentation? native,
    AcpAccountEditorPresentation? acp,
    AccountAcpKey? acpKey,
    @Default(false) bool loading,
    @Default(false) bool dirty,
    @Default(false) bool saving,
    @Default(false) bool canSave,
    @Default(0) int draftRevision,
    @Default(false) bool stale,
    String? error,
  }) = _AccountEditorViewState;
}

@freezed
abstract class AccountAcpViewState with _$AccountAcpViewState {
  const factory AccountAcpViewState({
    required AcpAccountPresentation panel,
    @Default(false) bool preparedForEditor,
    String? claimedOperationId,
    @Default(0) int preparationGeneration,
  }) = _AccountAcpViewState;
}
