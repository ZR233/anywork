import 'package:anywork_client/models.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'account_model_details_state.freezed.dart';

/// A fresh, immutable display intent per explicit open. Identity equality keeps
/// two dialogs for the same model from sharing an in-flight read or lifetime.
@Freezed(equal: false)
abstract class AccountModelDetailsEntry with _$AccountModelDetailsEntry {
  const factory AccountModelDetailsEntry({
    required AccountModelKey model,
    required DelegationModelReadTarget? target,
    required bool billingOverrideKnown,
    required BillingKind? billingOverride,
  }) = _AccountModelDetailsEntry;
}

@freezed
abstract class AccountModelDetailsViewState
    with _$AccountModelDetailsViewState {
  const factory AccountModelDetailsViewState({
    required AccountModelDetailsEntry entry,
    required DelegationModelReadTarget? target,
    required bool billingOverrideKnown,
    required BillingKind? billingOverride,
    DelegationModelDetail? detail,
    @Default(0) int latestIntent,
    @Default(false) bool reading,
    @Default(false) bool stale,
    StudioFailure? error,
    @Default([]) List<StudioFailure> observationErrors,
    StudioFailure? configurationError,
    StudioFailure? catalogError,
  }) = _AccountModelDetailsViewState;
}
