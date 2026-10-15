// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Mode 选择器只订阅目录本身。Shell 租约由 shell 持有；这里不另开 topic。

@ProviderFor(statusModeCatalog)
final statusModeCatalogProvider = StatusModeCatalogProvider._();

/// Mode 选择器只订阅目录本身。Shell 租约由 shell 持有；这里不另开 topic。

final class StatusModeCatalogProvider
    extends
        $FunctionalProvider<
          List<ThreadModeDescriptorView>,
          List<ThreadModeDescriptorView>,
          List<ThreadModeDescriptorView>
        >
    with $Provider<List<ThreadModeDescriptorView>> {
  /// Mode 选择器只订阅目录本身。Shell 租约由 shell 持有；这里不另开 topic。
  StatusModeCatalogProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusModeCatalogProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusModeCatalogHash();

  @$internal
  @override
  $ProviderElement<List<ThreadModeDescriptorView>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<ThreadModeDescriptorView> create(Ref ref) {
    return statusModeCatalog(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ThreadModeDescriptorView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ThreadModeDescriptorView>>(
        value,
      ),
    );
  }
}

String _$statusModeCatalogHash() => r'cfd28e1941c49630644f5ddd71c4b98ec2a98bcd';

/// LSP 活动只读 store。Shell bundle 不含 LspTopic，无人租用时列表为空。

@ProviderFor(statusLspServers)
final statusLspServersProvider = StatusLspServersProvider._();

/// LSP 活动只读 store。Shell bundle 不含 LspTopic，无人租用时列表为空。

final class StatusLspServersProvider
    extends
        $FunctionalProvider<
          List<LspServerStateView>,
          List<LspServerStateView>,
          List<LspServerStateView>
        >
    with $Provider<List<LspServerStateView>> {
  /// LSP 活动只读 store。Shell bundle 不含 LspTopic，无人租用时列表为空。
  StatusLspServersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusLspServersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusLspServersHash();

  @$internal
  @override
  $ProviderElement<List<LspServerStateView>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<LspServerStateView> create(Ref ref) {
    return statusLspServers(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LspServerStateView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LspServerStateView>>(value),
    );
  }
}

String _$statusLspServersHash() => r'd636fc36cb4cc890efe9f1427cbdb9554f75b235';

@ProviderFor(statusRuntimeProjection)
final statusRuntimeProjectionProvider = StatusRuntimeProjectionProvider._();

final class StatusRuntimeProjectionProvider
    extends
        $FunctionalProvider<
          StudioRuntimeProjection?,
          StudioRuntimeProjection?,
          StudioRuntimeProjection?
        >
    with $Provider<StudioRuntimeProjection?> {
  StatusRuntimeProjectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusRuntimeProjectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusRuntimeProjectionHash();

  @$internal
  @override
  $ProviderElement<StudioRuntimeProjection?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudioRuntimeProjection? create(Ref ref) {
    return statusRuntimeProjection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioRuntimeProjection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioRuntimeProjection?>(value),
    );
  }
}

String _$statusRuntimeProjectionHash() =>
    r'c4e131163b4e632664c8b59c4dfe740643c4e254';

@ProviderFor(statusContextProjection)
final statusContextProjectionProvider = StatusContextProjectionProvider._();

final class StatusContextProjectionProvider
    extends
        $FunctionalProvider<
          StudioContextProjection?,
          StudioContextProjection?,
          StudioContextProjection?
        >
    with $Provider<StudioContextProjection?> {
  StatusContextProjectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusContextProjectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusContextProjectionHash();

  @$internal
  @override
  $ProviderElement<StudioContextProjection?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudioContextProjection? create(Ref ref) {
    return statusContextProjection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioContextProjection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioContextProjection?>(value),
    );
  }
}

String _$statusContextProjectionHash() =>
    r'cdd7786967916d4e4dc7754d41c8f1b74923265e';

@ProviderFor(statusThroughputProjection)
final statusThroughputProjectionProvider =
    StatusThroughputProjectionProvider._();

final class StatusThroughputProjectionProvider
    extends
        $FunctionalProvider<
          StudioThroughputProjection?,
          StudioThroughputProjection?,
          StudioThroughputProjection?
        >
    with $Provider<StudioThroughputProjection?> {
  StatusThroughputProjectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusThroughputProjectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusThroughputProjectionHash();

  @$internal
  @override
  $ProviderElement<StudioThroughputProjection?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudioThroughputProjection? create(Ref ref) {
    return statusThroughputProjection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioThroughputProjection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioThroughputProjection?>(value),
    );
  }
}

String _$statusThroughputProjectionHash() =>
    r'48a028c2d03c2a0c7e8d57008c66e07afb1c2528';

@ProviderFor(statusBarView)
final statusBarViewProvider = StatusBarViewProvider._();

final class StatusBarViewProvider
    extends $FunctionalProvider<StatusBarView?, StatusBarView?, StatusBarView?>
    with $Provider<StatusBarView?> {
  StatusBarViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusBarViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusBarViewHash();

  @$internal
  @override
  $ProviderElement<StatusBarView?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StatusBarView? create(Ref ref) {
    return statusBarView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StatusBarView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StatusBarView?>(value),
    );
  }
}

String _$statusBarViewHash() => r'49921666fec1a9d2259c75f20b7427d6b3d83746';
