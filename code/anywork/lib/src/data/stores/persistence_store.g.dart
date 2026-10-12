// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'persistence_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 持久化状态与队列诊断。协议上是两套 revision，分别比较。

@ProviderFor(PersistenceStore)
final persistenceStoreProvider = PersistenceStoreProvider._();

/// 持久化状态与队列诊断。协议上是两套 revision，分别比较。
final class PersistenceStoreProvider
    extends $NotifierProvider<PersistenceStore, PersistenceStoreState> {
  /// 持久化状态与队列诊断。协议上是两套 revision，分别比较。
  PersistenceStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'persistenceStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$persistenceStoreHash();

  @$internal
  @override
  PersistenceStore create() => PersistenceStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PersistenceStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PersistenceStoreState>(value),
    );
  }
}

String _$persistenceStoreHash() => r'2b444412342baebb9c1ffc86208b69534893f744';

/// 持久化状态与队列诊断。协议上是两套 revision，分别比较。

abstract class _$PersistenceStore extends $Notifier<PersistenceStoreState> {
  PersistenceStoreState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PersistenceStoreState, PersistenceStoreState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PersistenceStoreState, PersistenceStoreState>,
              PersistenceStoreState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
