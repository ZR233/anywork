// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mode_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ModeEditorViewModel)
final modeEditorViewModelProvider = ModeEditorViewModelProvider._();

final class ModeEditorViewModelProvider
    extends $AsyncNotifierProvider<ModeEditorViewModel, ModeEditorViewState> {
  ModeEditorViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modeEditorViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modeEditorViewModelHash();

  @$internal
  @override
  ModeEditorViewModel create() => ModeEditorViewModel();
}

String _$modeEditorViewModelHash() =>
    r'9cb9214bd8503a7826e6f484d584d31e0b318d39';

abstract class _$ModeEditorViewModel
    extends $AsyncNotifier<ModeEditorViewState> {
  FutureOr<ModeEditorViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ModeEditorViewState>, ModeEditorViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ModeEditorViewState>, ModeEditorViewState>,
              AsyncValue<ModeEditorViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
