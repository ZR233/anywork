import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import 'mcp_values.dart';

part 'mcp_state.freezed.dart';

@freezed
abstract class McpReadRef with _$McpReadRef {
  const factory McpReadRef({required int entry, required int revision}) =
      _McpReadRef;
}

@freezed
abstract class McpReadTarget with _$McpReadTarget {
  const factory McpReadTarget({
    required ProductReadOrigin origin,
    required McpReadRef reference,
  }) = _McpReadTarget;
}

@freezed
abstract class McpHeader with _$McpHeader {
  const factory McpHeader({
    required ObservedHeader source,
    required McpReadRef? reference,
  }) = _McpHeader;
}

@Freezed(toStringOverride: false)
abstract class McpState with _$McpState {
  const factory McpState({
    required ProductProjection<McpHeader> projection,
    required ReadValue<ProductSourceStatus, ProductSourceStatusRef>?
    sourceStatus,
    required CollectionMirror<McpServer> servers,
    required ReadValue<List<String>, McpReadRef>? activeServerIds,
    required ReadValue<String, McpReadRef>? desiredConfigFingerprint,
    required ReadValue<String, McpReadRef>? appliedConfigFingerprint,
  }) = _McpState;
}
