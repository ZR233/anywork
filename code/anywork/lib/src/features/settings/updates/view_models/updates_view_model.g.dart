// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'updates_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(UpdatesViewModel)
final updatesViewModelProvider = UpdatesViewModelProvider._();

final class UpdatesViewModelProvider
    extends $AsyncNotifierProvider<UpdatesViewModel, UpdatesViewState> {
  UpdatesViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updatesViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updatesViewModelHash();

  @$internal
  @override
  UpdatesViewModel create() => UpdatesViewModel();
}

String _$updatesViewModelHash() => r'1cf6028fb8d3dd80a85fcac4b07e543a2596030e';

abstract class _$UpdatesViewModel extends $AsyncNotifier<UpdatesViewState> {
  FutureOr<UpdatesViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<UpdatesViewState>, UpdatesViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<UpdatesViewState>, UpdatesViewState>,
              AsyncValue<UpdatesViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
