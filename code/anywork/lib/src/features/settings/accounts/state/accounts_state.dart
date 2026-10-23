import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';

part 'accounts_state.freezed.dart';

enum AccountsReadField { accounts, models, templates, defaultAccount, usage,
  configurationSource, modelSource, usageSource }
enum AccountRowAction { setDefault, remove }

@freezed
abstract class AccountUsageCheckPresentation with _$AccountUsageCheckPresentation {
  const factory AccountUsageCheckPresentation({required AccountUsageQueryIdentity? identity,
    required OperationState operation, required bool preparing,
    StudioFailure? observationError}) = _AccountUsageCheckPresentation;
}

@freezed
abstract class AccountsViewState with _$AccountsViewState {
  const factory AccountsViewState({
    required ConfigurationState source,
    required ModelsState modelSource,
    required TemplatesState templateSource,
    required AccountUsageState usageSource,
    AccountTemplatesValue? templates,
    @Default('') String query,
    @Default([]) List<String> matchingAccountIds,
    String? selectedAccountId,
    @Default(false) bool showDetails,
    AccountEditorKey? editor,
    String? editorAccountId,
    @Default(0) int navigationIntent,
    @Default(0) int latestIntent,
    @Default({}) Map<(String, AccountRowAction), SettingsAction> rowActions,
    @Default({}) Set<String> preparingRemovalIds,
    @Default({}) Map<(String, String), SettingsAction> modelActions,
    @Default({}) Map<String, SettingsAction> usageActions,
    @Default({}) Map<String, OperationId> usageActionIds,
    @Default({}) Map<String, AccountUsageCheckPresentation> usageChecks,
    @Default(false) bool refreshingAll,
    @Default({}) Map<AccountsReadField, StudioFailure> readIssues,
    @Default({}) Set<AccountsReadField> reading,
    StudioFailure? editorError,
  }) = _AccountsViewState;
}
