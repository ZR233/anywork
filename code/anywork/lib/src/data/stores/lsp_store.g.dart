// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lsp_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// LSP 服务状态。时钟是 [LspStateSnapshot.revision]。

@ProviderFor(LspStore)
final lspStoreProvider = LspStoreProvider._();

/// LSP 服务状态。时钟是 [LspStateSnapshot.revision]。
final class LspStoreProvider
    extends $NotifierProvider<LspStore, CanonicalClockState<LspStateSnapshot>> {
  /// LSP 服务状态。时钟是 [LspStateSnapshot.revision]。
  LspStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lspStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lspStoreHash();

  @$internal
  @override
  LspStore create() => LspStore();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanonicalClockState<LspStateSnapshot> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<CanonicalClockState<LspStateSnapshot>>(value),
    );
  }
}

String _$lspStoreHash() => r'a77427a260f05dc4b8a8be217e2f7bce6cd35ff2';

/// LSP 服务状态。时钟是 [LspStateSnapshot.revision]。

abstract class _$LspStore
    extends $Notifier<CanonicalClockState<LspStateSnapshot>> {
  CanonicalClockState<LspStateSnapshot> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              CanonicalClockState<LspStateSnapshot>,
              CanonicalClockState<LspStateSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                CanonicalClockState<LspStateSnapshot>,
                CanonicalClockState<LspStateSnapshot>
              >,
              CanonicalClockState<LspStateSnapshot>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
