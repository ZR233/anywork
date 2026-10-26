// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_header_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A visible root's read-only demands. Neither this family key nor the agent
/// page creates a selection, opens execution, or owns a Conversation Session.

@ProviderFor(WorkspaceHeaderViewModel)
final workspaceHeaderViewModelProvider = WorkspaceHeaderViewModelFamily._();

/// A visible root's read-only demands. Neither this family key nor the agent
/// page creates a selection, opens execution, or owns a Conversation Session.
final class WorkspaceHeaderViewModelProvider
    extends
        $AsyncNotifierProvider<WorkspaceHeaderViewModel, WorkspaceHeaderState> {
  /// A visible root's read-only demands. Neither this family key nor the agent
  /// page creates a selection, opens execution, or owns a Conversation Session.
  WorkspaceHeaderViewModelProvider._({
    required WorkspaceHeaderViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceHeaderViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceHeaderViewModelHash();

  @override
  String toString() {
    return r'workspaceHeaderViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  WorkspaceHeaderViewModel create() => WorkspaceHeaderViewModel();

  @override
  bool operator ==(Object other) {
    return other is WorkspaceHeaderViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceHeaderViewModelHash() =>
    r'135bcb61d779000d1f2772baa16ba0381873716f';

/// A visible root's read-only demands. Neither this family key nor the agent
/// page creates a selection, opens execution, or owns a Conversation Session.

final class WorkspaceHeaderViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          WorkspaceHeaderViewModel,
          AsyncValue<WorkspaceHeaderState>,
          WorkspaceHeaderState,
          FutureOr<WorkspaceHeaderState>,
          String
        > {
  WorkspaceHeaderViewModelFamily._()
    : super(
        retry: null,
        name: r'workspaceHeaderViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A visible root's read-only demands. Neither this family key nor the agent
  /// page creates a selection, opens execution, or owns a Conversation Session.

  WorkspaceHeaderViewModelProvider call(String rootThreadId) =>
      WorkspaceHeaderViewModelProvider._(argument: rootThreadId, from: this);

  @override
  String toString() => r'workspaceHeaderViewModelProvider';
}

/// A visible root's read-only demands. Neither this family key nor the agent
/// page creates a selection, opens execution, or owns a Conversation Session.

abstract class _$WorkspaceHeaderViewModel
    extends $AsyncNotifier<WorkspaceHeaderState> {
  late final _$args = ref.$arg as String;
  String get rootThreadId => _$args;

  FutureOr<WorkspaceHeaderState> build(String rootThreadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<WorkspaceHeaderState>, WorkspaceHeaderState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<WorkspaceHeaderState>,
                WorkspaceHeaderState
              >,
              AsyncValue<WorkspaceHeaderState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
