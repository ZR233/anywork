// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_costs_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。

@ProviderFor(SessionCostsStore)
final sessionCostsStoreProvider = SessionCostsStoreFamily._();

/// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。
final class SessionCostsStoreProvider
    extends
        $NotifierProvider<
          SessionCostsStore,
          CanonicalClockState<SessionCostsStateView>
        > {
  /// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。
  SessionCostsStoreProvider._({
    required SessionCostsStoreFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sessionCostsStoreProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sessionCostsStoreHash();

  @override
  String toString() {
    return r'sessionCostsStoreProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SessionCostsStore create() => SessionCostsStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<SessionCostsStateView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<SessionCostsStateView>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionCostsStoreProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sessionCostsStoreHash() => r'38fb456283837092f9a343567dc5e332c474ec59';

/// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。

final class SessionCostsStoreFamily extends $Family
    with
        $ClassFamilyOverride<
          SessionCostsStore,
          CanonicalClockState<SessionCostsStateView>,
          CanonicalClockState<SessionCostsStateView>,
          CanonicalClockState<SessionCostsStateView>,
          String
        > {
  SessionCostsStoreFamily._()
    : super(
        retry: null,
        name: r'sessionCostsStoreProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。

  SessionCostsStoreProvider call(String rootThreadId) =>
      SessionCostsStoreProvider._(argument: rootThreadId, from: this);

  @override
  String toString() => r'sessionCostsStoreProvider';
}

/// 根会话费用。`cost == null` 是显式清除，仍按 revision 保留条目。

abstract class _$SessionCostsStore
    extends $Notifier<CanonicalClockState<SessionCostsStateView>> {
  late final _$args = ref.$arg as String;
  String get rootThreadId => _$args;

  CanonicalClockState<SessionCostsStateView> build(String rootThreadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<SessionCostsStateView>,
              CanonicalClockState<SessionCostsStateView>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<SessionCostsStateView>,
                CanonicalClockState<SessionCostsStateView>
              >,
              CanonicalClockState<SessionCostsStateView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
