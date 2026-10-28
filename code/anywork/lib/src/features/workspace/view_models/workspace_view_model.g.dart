// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceViewModel)
final workspaceViewModelProvider = WorkspaceViewModelProvider._();

final class WorkspaceViewModelProvider
    extends $AsyncNotifierProvider<WorkspaceViewModel, WorkspaceViewState> {
  WorkspaceViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceViewModelHash();

  @$internal
  @override
  WorkspaceViewModel create() => WorkspaceViewModel();
}

String _$workspaceViewModelHash() =>
    r'3198b53824fe5d87f596629217be1beb97b8bdec';

abstract class _$WorkspaceViewModel extends $AsyncNotifier<WorkspaceViewState> {
  FutureOr<WorkspaceViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<WorkspaceViewState>, WorkspaceViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<WorkspaceViewState>, WorkspaceViewState>,
              AsyncValue<WorkspaceViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
