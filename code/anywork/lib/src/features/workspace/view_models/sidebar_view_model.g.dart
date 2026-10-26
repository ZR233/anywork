// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sidebar_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Presentation/query owner, not a directory reducer. Each borrowed query has
/// its own canonical window/cursor; the VM never merges rows or guesses EOF.

@ProviderFor(SidebarViewModel)
final sidebarViewModelProvider = SidebarViewModelProvider._();

/// Presentation/query owner, not a directory reducer. Each borrowed query has
/// its own canonical window/cursor; the VM never merges rows or guesses EOF.
final class SidebarViewModelProvider
    extends $AsyncNotifierProvider<SidebarViewModel, SidebarViewState> {
  /// Presentation/query owner, not a directory reducer. Each borrowed query has
  /// its own canonical window/cursor; the VM never merges rows or guesses EOF.
  SidebarViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sidebarViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sidebarViewModelHash();

  @$internal
  @override
  SidebarViewModel create() => SidebarViewModel();
}

String _$sidebarViewModelHash() => r'a954f1b67ea6e9865f40814e3b9c66a7bc9f671a';

/// Presentation/query owner, not a directory reducer. Each borrowed query has
/// its own canonical window/cursor; the VM never merges rows or guesses EOF.

abstract class _$SidebarViewModel extends $AsyncNotifier<SidebarViewState> {
  FutureOr<SidebarViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<SidebarViewState>, SidebarViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SidebarViewState>, SidebarViewState>,
              AsyncValue<SidebarViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
