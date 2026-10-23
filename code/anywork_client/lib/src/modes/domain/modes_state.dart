import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'mode_documents.dart';
import 'mode_values.dart';

part 'modes_state.freezed.dart';

@freezed
abstract class ModeCatalogReadRef with _$ModeCatalogReadRef {
  const factory ModeCatalogReadRef({required int entry, required int revision}) = _ModeCatalogReadRef;
}

@freezed
abstract class ModeCatalogReadTarget with _$ModeCatalogReadTarget {
  const factory ModeCatalogReadTarget({required ProductReadOrigin origin, required ModeCatalogReadRef reference}) = _ModeCatalogReadTarget;
}

@freezed
abstract class ModeCatalogHeader with _$ModeCatalogHeader {
  const factory ModeCatalogHeader({required int revision, required ModeCatalogReadRef reference}) = _ModeCatalogHeader;
}

@Freezed(toStringOverride: false)
abstract class ModesState with _$ModesState {
  const factory ModesState({required ProductProjection<ModeCatalogHeader> projection, required CollectionMirror<ThreadModeDescriptor> modes}) = _ModesState;
}

@Freezed(toStringOverride: false)
abstract class ModeDefinitionResult with _$ModeDefinitionResult {
  const factory ModeDefinitionResult({required ModeCatalogReadTarget catalog, required ModeDefinitionSnapshot? definition}) = _ModeDefinitionResult;
}
