// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'instructions_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(InstructionsViewModel)
final instructionsViewModelProvider = InstructionsViewModelProvider._();

final class InstructionsViewModelProvider
    extends
        $AsyncNotifierProvider<InstructionsViewModel, InstructionsViewState> {
  InstructionsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'instructionsViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$instructionsViewModelHash();

  @$internal
  @override
  InstructionsViewModel create() => InstructionsViewModel();
}

String _$instructionsViewModelHash() =>
    r'dc97bf33e8a55199c4fa1d3c926ce014cb5bcd68';

abstract class _$InstructionsViewModel
    extends $AsyncNotifier<InstructionsViewState> {
  FutureOr<InstructionsViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<InstructionsViewState>, InstructionsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<InstructionsViewState>,
                InstructionsViewState
              >,
              AsyncValue<InstructionsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
