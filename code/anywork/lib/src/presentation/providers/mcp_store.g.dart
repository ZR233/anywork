// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod owns this display observation; the Client owns the resource.

@ProviderFor(mcpStore)
final mcpStoreProvider = McpStoreProvider._();

/// Riverpod owns this display observation; the Client owns the resource.

final class McpStoreProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<McpCatalogSnapshot>,
          CanonicalClockState<McpCatalogSnapshot>,
          CanonicalClockState<McpCatalogSnapshot>
        >
    with $Provider<CanonicalClockState<McpCatalogSnapshot>> {
  /// Riverpod owns this display observation; the Client owns the resource.
  McpStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpStoreHash();

  @$internal
  @override
  $ProviderElement<CanonicalClockState<McpCatalogSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<McpCatalogSnapshot> create(Ref ref) {
    return mcpStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<McpCatalogSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<McpCatalogSnapshot>>(value),
    );
  }
}

String _$mcpStoreHash() => r'1585bd20342309d0dc53749987802e131569cf4d';

@ProviderFor(mcpCatalogByScope)
final mcpCatalogByScopeProvider = McpCatalogByScopeFamily._();

final class McpCatalogByScopeProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<McpCatalogSnapshot>,
          CanonicalClockState<McpCatalogSnapshot>,
          CanonicalClockState<McpCatalogSnapshot>
        >
    with $Provider<CanonicalClockState<McpCatalogSnapshot>> {
  McpCatalogByScopeProvider._({
    required McpCatalogByScopeFamily super.from,
    required McpScope super.argument,
  }) : super(
         retry: null,
         name: r'mcpCatalogByScopeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mcpCatalogByScopeHash();

  @override
  String toString() {
    return r'mcpCatalogByScopeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CanonicalClockState<McpCatalogSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<McpCatalogSnapshot> create(Ref ref) {
    final argument = this.argument as McpScope;
    return mcpCatalogByScope(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<McpCatalogSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<McpCatalogSnapshot>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is McpCatalogByScopeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mcpCatalogByScopeHash() => r'f314d063b410064081cc0ae7127c01c57c413eb0';

final class McpCatalogByScopeFamily extends $Family
    with
        $FunctionalFamilyOverride<
          CanonicalClockState<McpCatalogSnapshot>,
          McpScope
        > {
  McpCatalogByScopeFamily._()
    : super(
        retry: null,
        name: r'mcpCatalogByScopeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  McpCatalogByScopeProvider call(McpScope scope) =>
      McpCatalogByScopeProvider._(argument: scope, from: this);

  @override
  String toString() => r'mcpCatalogByScopeProvider';
}

@ProviderFor(threadMcp)
final threadMcpProvider = ThreadMcpFamily._();

final class ThreadMcpProvider
    extends
        $FunctionalProvider<
          CanonicalClockState<ThreadMcpStateSnapshot>,
          CanonicalClockState<ThreadMcpStateSnapshot>,
          CanonicalClockState<ThreadMcpStateSnapshot>
        >
    with $Provider<CanonicalClockState<ThreadMcpStateSnapshot>> {
  ThreadMcpProvider._({
    required ThreadMcpFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadMcpProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadMcpHash();

  @override
  String toString() {
    return r'threadMcpProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CanonicalClockState<ThreadMcpStateSnapshot>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CanonicalClockState<ThreadMcpStateSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return threadMcp(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    CanonicalClockState<ThreadMcpStateSnapshot> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<ThreadMcpStateSnapshot>>(
            value,
          ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThreadMcpProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadMcpHash() => r'ef100c27fb1f900c908e6cf8a363a9021fddfd78';

final class ThreadMcpFamily extends $Family
    with
        $FunctionalFamilyOverride<
          CanonicalClockState<ThreadMcpStateSnapshot>,
          String
        > {
  ThreadMcpFamily._()
    : super(
        retry: null,
        name: r'threadMcpProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThreadMcpProvider call(String threadId) =>
      ThreadMcpProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadMcpProvider';
}
