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

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so decode updates cannot rebuild the chrome.

@ProviderFor(statusBarView)
final statusBarViewProvider = StatusBarViewFamily._();

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so decode updates cannot rebuild the chrome.

final class StatusBarViewProvider
    extends $FunctionalProvider<StatusBarView?, StatusBarView?, StatusBarView?>
    with $Provider<StatusBarView?> {
  /// Stable status-bar fields for one Thread. Throughput and context are not
  /// part of this value, so decode updates cannot rebuild the chrome.
  StatusBarViewProvider._({
    required StatusBarViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'statusBarViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$statusBarViewHash();

  @override
  String toString() {
    return r'statusBarViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<StatusBarView?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StatusBarView? create(Ref ref) {
    final argument = this.argument as String;
    return statusBarView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StatusBarView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StatusBarView?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StatusBarViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$statusBarViewHash() => r'b7e6631120bec41224595f16765fe95172dd4ead';

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so decode updates cannot rebuild the chrome.

final class StatusBarViewFamily extends $Family
    with $FunctionalFamilyOverride<StatusBarView?, String> {
  StatusBarViewFamily._()
    : super(
        retry: null,
        name: r'statusBarViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Stable status-bar fields for one Thread. Throughput and context are not
  /// part of this value, so decode updates cannot rebuild the chrome.

  StatusBarViewProvider call(String threadId) =>
      StatusBarViewProvider._(argument: threadId, from: this);

  @override
  String toString() => r'statusBarViewProvider';
}

@ProviderFor(statusCompactionCommand)
final statusCompactionCommandProvider = StatusCompactionCommandFamily._();

final class StatusCompactionCommandProvider
    extends $FunctionalProvider<CommandStatus?, CommandStatus?, CommandStatus?>
    with $Provider<CommandStatus?> {
  StatusCompactionCommandProvider._({
    required StatusCompactionCommandFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'statusCompactionCommandProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$statusCompactionCommandHash();

  @override
  String toString() {
    return r'statusCompactionCommandProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<CommandStatus?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CommandStatus? create(Ref ref) {
    final argument = this.argument as String;
    return statusCompactionCommand(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommandStatus? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommandStatus?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StatusCompactionCommandProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$statusCompactionCommandHash() =>
    r'fd660618710e688c794bee3b85281fc041014496';

final class StatusCompactionCommandFamily extends $Family
    with $FunctionalFamilyOverride<CommandStatus?, String> {
  StatusCompactionCommandFamily._()
    : super(
        retry: null,
        name: r'statusCompactionCommandProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  StatusCompactionCommandProvider call(String threadId) =>
      StatusCompactionCommandProvider._(argument: threadId, from: this);

  @override
  String toString() => r'statusCompactionCommandProvider';
}

@ProviderFor(statusContextProjection)
final statusContextProjectionProvider = StatusContextProjectionFamily._();

final class StatusContextProjectionProvider
    extends
        $FunctionalProvider<
          StudioContextProjection?,
          StudioContextProjection?,
          StudioContextProjection?
        >
    with $Provider<StudioContextProjection?> {
  StatusContextProjectionProvider._({
    required StatusContextProjectionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'statusContextProjectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$statusContextProjectionHash();

  @override
  String toString() {
    return r'statusContextProjectionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<StudioContextProjection?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudioContextProjection? create(Ref ref) {
    final argument = this.argument as String;
    return statusContextProjection(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioContextProjection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioContextProjection?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StatusContextProjectionProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$statusContextProjectionHash() =>
    r'9cb1f768f067e57bb876d86ca4dfdabb6ef6bbe4';

final class StatusContextProjectionFamily extends $Family
    with $FunctionalFamilyOverride<StudioContextProjection?, String> {
  StatusContextProjectionFamily._()
    : super(
        retry: null,
        name: r'statusContextProjectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  StatusContextProjectionProvider call(String threadId) =>
      StatusContextProjectionProvider._(argument: threadId, from: this);

  @override
  String toString() => r'statusContextProjectionProvider';
}

@ProviderFor(statusThroughputProjection)
final statusThroughputProjectionProvider = StatusThroughputProjectionFamily._();

final class StatusThroughputProjectionProvider
    extends
        $FunctionalProvider<
          StudioThroughputProjection?,
          StudioThroughputProjection?,
          StudioThroughputProjection?
        >
    with $Provider<StudioThroughputProjection?> {
  StatusThroughputProjectionProvider._({
    required StatusThroughputProjectionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'statusThroughputProjectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$statusThroughputProjectionHash();

  @override
  String toString() {
    return r'statusThroughputProjectionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<StudioThroughputProjection?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudioThroughputProjection? create(Ref ref) {
    final argument = this.argument as String;
    return statusThroughputProjection(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioThroughputProjection? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioThroughputProjection?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StatusThroughputProjectionProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$statusThroughputProjectionHash() =>
    r'ab6fa928badd2d980a621834f5cc2bb6ed5750c8';

final class StatusThroughputProjectionFamily extends $Family
    with $FunctionalFamilyOverride<StudioThroughputProjection?, String> {
  StatusThroughputProjectionFamily._()
    : super(
        retry: null,
        name: r'statusThroughputProjectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  StatusThroughputProjectionProvider call(String threadId) =>
      StatusThroughputProjectionProvider._(argument: threadId, from: this);

  @override
  String toString() => r'statusThroughputProjectionProvider';
}
