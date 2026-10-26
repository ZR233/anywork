// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_project_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Dialog editing/workflow only. Remote and Workspace remain the canonical
/// owners of commands and batches, including results after this VM is disposed.

@ProviderFor(AddProjectViewModel)
final addProjectViewModelProvider = AddProjectViewModelFamily._();

/// Dialog editing/workflow only. Remote and Workspace remain the canonical
/// owners of commands and batches, including results after this VM is disposed.
final class AddProjectViewModelProvider
    extends $AsyncNotifierProvider<AddProjectViewModel, AddProjectState> {
  /// Dialog editing/workflow only. Remote and Workspace remain the canonical
  /// owners of commands and batches, including results after this VM is disposed.
  AddProjectViewModelProvider._({
    required AddProjectViewModelFamily super.from,
    required AddProjectDialogKey super.argument,
  }) : super(
         retry: null,
         name: r'addProjectViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$addProjectViewModelHash();

  @override
  String toString() {
    return r'addProjectViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AddProjectViewModel create() => AddProjectViewModel();

  @override
  bool operator ==(Object other) {
    return other is AddProjectViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$addProjectViewModelHash() =>
    r'773372ecdabb86ca597e93dbdfed1efc29566bd1';

/// Dialog editing/workflow only. Remote and Workspace remain the canonical
/// owners of commands and batches, including results after this VM is disposed.

final class AddProjectViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AddProjectViewModel,
          AsyncValue<AddProjectState>,
          AddProjectState,
          FutureOr<AddProjectState>,
          AddProjectDialogKey
        > {
  AddProjectViewModelFamily._()
    : super(
        retry: null,
        name: r'addProjectViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Dialog editing/workflow only. Remote and Workspace remain the canonical
  /// owners of commands and batches, including results after this VM is disposed.

  AddProjectViewModelProvider call(AddProjectDialogKey target) =>
      AddProjectViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'addProjectViewModelProvider';
}

/// Dialog editing/workflow only. Remote and Workspace remain the canonical
/// owners of commands and batches, including results after this VM is disposed.

abstract class _$AddProjectViewModel extends $AsyncNotifier<AddProjectState> {
  late final _$args = ref.$arg as AddProjectDialogKey;
  AddProjectDialogKey get target => _$args;

  FutureOr<AddProjectState> build(AddProjectDialogKey target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AddProjectState>, AddProjectState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AddProjectState>, AddProjectState>,
              AsyncValue<AddProjectState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
