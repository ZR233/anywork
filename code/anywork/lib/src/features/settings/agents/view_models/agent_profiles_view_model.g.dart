// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_profiles_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AgentProfilesViewModel)
final agentProfilesViewModelProvider = AgentProfilesViewModelProvider._();

final class AgentProfilesViewModelProvider
    extends
        $AsyncNotifierProvider<AgentProfilesViewModel, AgentProfilesViewState> {
  AgentProfilesViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'agentProfilesViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$agentProfilesViewModelHash();

  @$internal
  @override
  AgentProfilesViewModel create() => AgentProfilesViewModel();
}

String _$agentProfilesViewModelHash() =>
    r'20fd0386517687935b022c054709431fca4ea900';

abstract class _$AgentProfilesViewModel
    extends $AsyncNotifier<AgentProfilesViewState> {
  FutureOr<AgentProfilesViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AgentProfilesViewState>, AgentProfilesViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AgentProfilesViewState>,
                AgentProfilesViewState
              >,
              AsyncValue<AgentProfilesViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
