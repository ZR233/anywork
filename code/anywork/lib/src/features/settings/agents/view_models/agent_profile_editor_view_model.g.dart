// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_profile_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AgentProfileEditorViewModel)
final agentProfileEditorViewModelProvider =
    AgentProfileEditorViewModelFamily._();

final class AgentProfileEditorViewModelProvider
    extends
        $AsyncNotifierProvider<
          AgentProfileEditorViewModel,
          ProfileEditorViewState
        > {
  AgentProfileEditorViewModelProvider._({
    required AgentProfileEditorViewModelFamily super.from,
    required ProfileEditorKey super.argument,
  }) : super(
         retry: null,
         name: r'agentProfileEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProfileEditorViewModelHash();

  @override
  String toString() {
    return r'agentProfileEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentProfileEditorViewModel create() => AgentProfileEditorViewModel();

  @override
  bool operator ==(Object other) {
    return other is AgentProfileEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProfileEditorViewModelHash() =>
    r'0ab918c0be1fe884e11abdf495b6d4113878bdc1';

final class AgentProfileEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentProfileEditorViewModel,
          AsyncValue<ProfileEditorViewState>,
          ProfileEditorViewState,
          FutureOr<ProfileEditorViewState>,
          ProfileEditorKey
        > {
  AgentProfileEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'agentProfileEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentProfileEditorViewModelProvider call(ProfileEditorKey key) =>
      AgentProfileEditorViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'agentProfileEditorViewModelProvider';
}

abstract class _$AgentProfileEditorViewModel
    extends $AsyncNotifier<ProfileEditorViewState> {
  late final _$args = ref.$arg as ProfileEditorKey;
  ProfileEditorKey get key => _$args;

  FutureOr<ProfileEditorViewState> build(ProfileEditorKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ProfileEditorViewState>, ProfileEditorViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ProfileEditorViewState>,
                ProfileEditorViewState
              >,
              AsyncValue<ProfileEditorViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
