import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/editor_keys.dart';
import '../../state/settings_action.dart';

part 'account_editor_state.freezed.dart';

enum AccountEditorField { template, name, baseUrl, pricing, secret }

enum AccountSecretIntent { preserve, replace, clear }

enum CustomModelField { modelId, displayName, wireApi, contextWindow, maxOutputTokens }

enum AccountValidation { required, integer, duplicateModel, onlineModelConflict }

@Freezed(toStringOverride: false)
abstract class CustomModelDraft with _$CustomModelDraft {
  const factory CustomModelDraft({
    required int rowId,
    required String? originalModelId,
    required String modelId,
    required String displayName,
    required String wireApi,
    required String contextWindowRaw,
    required String maxOutputTokensRaw,
    @Default(false) bool dirty,
    @Default({}) Set<CustomModelField> dirtyFields,
    @Default({}) Map<CustomModelField, AccountValidation> validation,
  }) = _CustomModelDraft;
}

/// Secret text has no generated diagnostic/JSON representation. hasBearerToken
/// comes exclusively from canonical account data, not the text or its intent.
@Freezed(toStringOverride: false)
abstract class AccountEditorViewState with _$AccountEditorViewState {
  const AccountEditorViewState._();

  const factory AccountEditorViewState({
    required AccountEditorKey key,
    required String accountId,
    required ConfigurationState source,
    required ModelsState modelSource,
    required TemplatesState templateSource,
    required AccountTemplatesValue templates,
    AccountConfiguration? canonical,
    AccountCatalogEntry? catalog,
    @Default(false) bool templatePreview,
    @Default(false) bool rebuildModelConfiguration,
    String? templateId,
    required String protocol,
    required String name,
    required String baseUrl,
    required bool pricingEnabled,
    @Default(AccountSecretIntent.preserve) AccountSecretIntent secretIntent,
    @Default('') String secretRaw,
    @Default([]) List<CustomModelDraft> customModels,
    @Default([]) List<String> removedCustomModelIds,
    @Default({}) Map<String, String> connectionEdits,
    @Default({}) Set<AccountEditorField> dirtyFields,
    @Default({}) Map<AccountEditorField, AccountValidation> validation,
    @Default(0) int draftRevision,
    @Default(0) int formGeneration,
    @Default(false) bool saved,
    @Default(false) bool verifying,
    SettingsAction? saveAction,
    SettingsAction? defaultAction,
    StudioFailure? sourceError,
  }) = _AccountEditorViewState;

  bool get create => key.accountId == null && !saved;

  bool get hasBearerToken => canonical?.hasBearerToken ?? false;

  bool get dirty => rebuildModelConfiguration || dirtyFields.isNotEmpty ||
      customModels.any((model) => model.dirty) ||
      removedCustomModelIds.isNotEmpty || connectionEdits.isNotEmpty;

  bool get saving => (saveAction?.pending ?? false) ||
      (defaultAction?.pending ?? false) || verifying;
}
