// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_diagnostics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceDiagnosticsViewModel)
final workspaceDiagnosticsViewModelProvider =
    WorkspaceDiagnosticsViewModelProvider._();

final class WorkspaceDiagnosticsViewModelProvider
    extends
        $AsyncNotifierProvider<
          WorkspaceDiagnosticsViewModel,
          WorkspaceDiagnosticsState
        > {
  WorkspaceDiagnosticsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceDiagnosticsViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceDiagnosticsViewModelHash();

  @$internal
  @override
  WorkspaceDiagnosticsViewModel create() => WorkspaceDiagnosticsViewModel();
}

String _$workspaceDiagnosticsViewModelHash() =>
    r'52628a3770716dc0b1b6085791dee2a9d9892c00';

abstract class _$WorkspaceDiagnosticsViewModel
    extends $AsyncNotifier<WorkspaceDiagnosticsState> {
  FutureOr<WorkspaceDiagnosticsState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<WorkspaceDiagnosticsState>,
              WorkspaceDiagnosticsState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<WorkspaceDiagnosticsState>,
                WorkspaceDiagnosticsState
              >,
              AsyncValue<WorkspaceDiagnosticsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
