// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A display observation only: Client remains the sole owner of topic streams.

@ProviderFor(StartedItemsViewModel)
final startedItemsViewModelProvider = StartedItemsViewModelFamily._();

/// A display observation only: Client remains the sole owner of topic streams.
final class StartedItemsViewModelProvider
    extends $AsyncNotifierProvider<StartedItemsViewModel, StartedItemsState> {
  /// A display observation only: Client remains the sole owner of topic streams.
  StartedItemsViewModelProvider._({
    required StartedItemsViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'startedItemsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$startedItemsViewModelHash();

  @override
  String toString() {
    return r'startedItemsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  StartedItemsViewModel create() => StartedItemsViewModel();

  @override
  bool operator ==(Object other) {
    return other is StartedItemsViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$startedItemsViewModelHash() =>
    r'cab2dcb58a246486726dcc909b5dc59011077436';

/// A display observation only: Client remains the sole owner of topic streams.

final class StartedItemsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          StartedItemsViewModel,
          AsyncValue<StartedItemsState>,
          StartedItemsState,
          FutureOr<StartedItemsState>,
          String
        > {
  StartedItemsViewModelFamily._()
    : super(
        retry: null,
        name: r'startedItemsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A display observation only: Client remains the sole owner of topic streams.

  StartedItemsViewModelProvider call(String threadId) =>
      StartedItemsViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'startedItemsViewModelProvider';
}

/// A display observation only: Client remains the sole owner of topic streams.

abstract class _$StartedItemsViewModel
    extends $AsyncNotifier<StartedItemsState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<StartedItemsState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<StartedItemsState>, StartedItemsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StartedItemsState>, StartedItemsState>,
              AsyncValue<StartedItemsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so response-timing updates cannot rebuild the chrome.

@ProviderFor(statusBarView)
final statusBarViewProvider = StatusBarViewFamily._();

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so response-timing updates cannot rebuild the chrome.

final class StatusBarViewProvider
    extends $FunctionalProvider<StatusBarView?, StatusBarView?, StatusBarView?>
    with $Provider<StatusBarView?> {
  /// Stable status-bar fields for one Thread. Throughput and context are not
  /// part of this value, so response-timing updates cannot rebuild the chrome.
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

String _$statusBarViewHash() => r'1438595f1bc05edefedc53f46d1ec34ab63b1fed';

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so response-timing updates cannot rebuild the chrome.

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
  /// part of this value, so response-timing updates cannot rebuild the chrome.

  StatusBarViewProvider call(String threadId) =>
      StatusBarViewProvider._(argument: threadId, from: this);

  @override
  String toString() => r'statusBarViewProvider';
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
    r'7bf387300cf3c2f00ffd56c725a5677efa6f3a2d';

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
    r'38a779c462f23a2478b5976f08cfbee9f9b3d967';

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
