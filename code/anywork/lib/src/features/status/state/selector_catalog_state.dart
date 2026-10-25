import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'selector_catalog_state.freezed.dart';

enum SelectorRead { accounts, models, modes, delegation }

/// Borrowed canonical snapshots only. Selection and policy remain domain-owned.
@Freezed(toStringOverride: false)
abstract class SelectorCatalogState with _$SelectorCatalogState {
  const factory SelectorCatalogState({
    required ConfigurationState configuration,
    required ModelsState models,
    required ModesState modes,
    @Default({}) Set<SelectorRead> reading,
    @Default({}) Map<SelectorRead, StudioFailure> errors,
  }) = _SelectorCatalogState;
}
