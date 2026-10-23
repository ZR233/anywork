import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'model_limits_state.freezed.dart';

enum ModelLimitValidation { positiveAsciiInteger }
enum ModelLimitsReadField { configuration, catalog }

@freezed
abstract class ModelLimitDraft with _$ModelLimitDraft {
  const factory ModelLimitDraft({
    required String raw,
    required int intent,
    @Default(false) bool restoreDefault,
    @Default(false) bool dirty,
    @Default(false) bool composing,
    ModelLimitValidation? validation,
    SettingsAction? action,
  }) = _ModelLimitDraft;
}

@freezed
abstract class AccountModelLimitsViewState with _$AccountModelLimitsViewState {
  const factory AccountModelLimitsViewState({
    required String accountId,
    required ConfigurationState source,
    required ModelsState modelSource,
    required AccountConfiguration canonical,
    required AccountCatalogEntry catalog,
    @Default({}) Map<String, ModelLimitDraft> drafts,
    @Default({}) Map<ModelLimitsReadField, StudioFailure> readIssues,
    @Default(false) bool readPending,
  }) = _AccountModelLimitsViewState;
}
