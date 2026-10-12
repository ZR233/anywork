// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_usage_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 服务商用量。协议水位 [ProviderUsageStateSnapshot.revision] 就是查询代次，
/// 不另造 generation 计数器。

@ProviderFor(ProviderUsageStore)
final providerUsageStoreProvider = ProviderUsageStoreProvider._();

/// 服务商用量。协议水位 [ProviderUsageStateSnapshot.revision] 就是查询代次，
/// 不另造 generation 计数器。
final class ProviderUsageStoreProvider
    extends
        $NotifierProvider<
          ProviderUsageStore,
          CanonicalClockState<ProviderUsageStateSnapshot>
        > {
  /// 服务商用量。协议水位 [ProviderUsageStateSnapshot.revision] 就是查询代次，
  /// 不另造 generation 计数器。
  ProviderUsageStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'providerUsageStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$providerUsageStoreHash();

  @$internal
  @override
  ProviderUsageStore create() => ProviderUsageStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    CanonicalClockState<ProviderUsageStateSnapshot> value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<ProviderUsageStateSnapshot>>(
            value,
          ),
    );
  }
}

String _$providerUsageStoreHash() =>
    r'c57ceb5a90fa6fc5e8b7ae4101773b491dd5d3b0';

/// 服务商用量。协议水位 [ProviderUsageStateSnapshot.revision] 就是查询代次，
/// 不另造 generation 计数器。

abstract class _$ProviderUsageStore
    extends $Notifier<CanonicalClockState<ProviderUsageStateSnapshot>> {
  CanonicalClockState<ProviderUsageStateSnapshot> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<ProviderUsageStateSnapshot>,
              CanonicalClockState<ProviderUsageStateSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<ProviderUsageStateSnapshot>,
                CanonicalClockState<ProviderUsageStateSnapshot>
              >,
              CanonicalClockState<ProviderUsageStateSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
