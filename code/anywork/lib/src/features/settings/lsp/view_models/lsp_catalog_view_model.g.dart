// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lsp_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The source is global even with no selected project. Project actions have
/// their own non-null keyed VM, not a fabricated per-project LSP feed.

@ProviderFor(LspCatalogViewModel)
final lspCatalogViewModelProvider = LspCatalogViewModelProvider._();

/// The source is global even with no selected project. Project actions have
/// their own non-null keyed VM, not a fabricated per-project LSP feed.
final class LspCatalogViewModelProvider
    extends $AsyncNotifierProvider<LspCatalogViewModel, LspCatalogViewState> {
  /// The source is global even with no selected project. Project actions have
  /// their own non-null keyed VM, not a fabricated per-project LSP feed.
  LspCatalogViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lspCatalogViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lspCatalogViewModelHash();

  @$internal
  @override
  LspCatalogViewModel create() => LspCatalogViewModel();
}

String _$lspCatalogViewModelHash() =>
    r'fc1a533c59640f6025dae8bef9c642727cd7f7b5';

/// The source is global even with no selected project. Project actions have
/// their own non-null keyed VM, not a fabricated per-project LSP feed.

abstract class _$LspCatalogViewModel
    extends $AsyncNotifier<LspCatalogViewState> {
  FutureOr<LspCatalogViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<LspCatalogViewState>, LspCatalogViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<LspCatalogViewState>, LspCatalogViewState>,
              AsyncValue<LspCatalogViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
