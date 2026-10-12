// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// MCP 服务状态。时钟是 [McpStateSnapshot.revision]。

@ProviderFor(McpStore)
final mcpStoreProvider = McpStoreProvider._();

/// MCP 服务状态。时钟是 [McpStateSnapshot.revision]。
final class McpStoreProvider
    extends $NotifierProvider<McpStore, CanonicalClockState<McpStateSnapshot>> {
  /// MCP 服务状态。时钟是 [McpStateSnapshot.revision]。
  McpStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpStoreHash();

  @$internal
  @override
  McpStore create() => McpStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<McpStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<McpStateSnapshot>>(value),
    );
  }
}

String _$mcpStoreHash() => r'de52626a30adbf2d16b2c33b03d46ee2d2163b29';

/// MCP 服务状态。时钟是 [McpStateSnapshot.revision]。

abstract class _$McpStore
    extends $Notifier<CanonicalClockState<McpStateSnapshot>> {
  CanonicalClockState<McpStateSnapshot> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<McpStateSnapshot>,
              CanonicalClockState<McpStateSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<McpStateSnapshot>,
                CanonicalClockState<McpStateSnapshot>
              >,
              CanonicalClockState<McpStateSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
