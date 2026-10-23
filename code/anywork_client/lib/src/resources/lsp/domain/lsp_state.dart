import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'lsp_values.dart';

part 'lsp_state.freezed.dart';

@freezed
abstract class LspReadRef with _$LspReadRef {
  const factory LspReadRef({required int entry, required int revision}) = _LspReadRef;
}

@freezed
abstract class LspReadTarget with _$LspReadTarget {
  const factory LspReadTarget({
    required ProductReadOrigin origin,
    required LspReadRef reference,
  }) = _LspReadTarget;
}

@freezed
abstract class LspHeader with _$LspHeader {
  const factory LspHeader({
    required ObservedHeader source,
    required LspReadRef? reference,
  }) = _LspHeader;
}

@Freezed(toStringOverride: false)
abstract class LspState with _$LspState {
  const factory LspState({
    required ProductProjection<LspHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,
    required CollectionMirror<LspServer> servers,
    required ReadValue<List<String>, LspReadRef>? activeServerIds,
  }) = _LspState;
}
