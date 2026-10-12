// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recovery_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 恢复问题。时钟是 [RecoveryStateSnapshot.revision]。

@ProviderFor(RecoveryStore)
final recoveryStoreProvider = RecoveryStoreProvider._();

/// 恢复问题。时钟是 [RecoveryStateSnapshot.revision]。
final class RecoveryStoreProvider
    extends
        $NotifierProvider<
          RecoveryStore,
          CanonicalClockState<RecoveryStateSnapshot>
        > {
  /// 恢复问题。时钟是 [RecoveryStateSnapshot.revision]。
  RecoveryStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recoveryStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recoveryStoreHash();

  @$internal
  @override
  RecoveryStore create() => RecoveryStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<RecoveryStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<RecoveryStateSnapshot>>(value),
    );
  }
}

String _$recoveryStoreHash() => r'ba594eddf32ccdcabaa290d803411ea7bad8424a';

/// 恢复问题。时钟是 [RecoveryStateSnapshot.revision]。

abstract class _$RecoveryStore
    extends $Notifier<CanonicalClockState<RecoveryStateSnapshot>> {
  CanonicalClockState<RecoveryStateSnapshot> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<RecoveryStateSnapshot>,
              CanonicalClockState<RecoveryStateSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<RecoveryStateSnapshot>,
                CanonicalClockState<RecoveryStateSnapshot>
              >,
              CanonicalClockState<RecoveryStateSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
