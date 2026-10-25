// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selector_catalog_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SelectorCatalogViewModel)
final selectorCatalogViewModelProvider = SelectorCatalogViewModelProvider._();

final class SelectorCatalogViewModelProvider
    extends
        $AsyncNotifierProvider<SelectorCatalogViewModel, SelectorCatalogState> {
  SelectorCatalogViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectorCatalogViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectorCatalogViewModelHash();

  @$internal
  @override
  SelectorCatalogViewModel create() => SelectorCatalogViewModel();
}

String _$selectorCatalogViewModelHash() =>
    r'aa875a816a57823734d767591287fd905d3c6c3a';

abstract class _$SelectorCatalogViewModel
    extends $AsyncNotifier<SelectorCatalogState> {
  FutureOr<SelectorCatalogState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SelectorCatalogState>, SelectorCatalogState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SelectorCatalogState>,
                SelectorCatalogState
              >,
              AsyncValue<SelectorCatalogState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
