// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Reading only. Decisions/feedback never live in this VM.
///
/// `open`/`fullWidth`/`panelWidth` are GUI-only placement of the same published
/// document: no Session, draft or accepted command is affected by them, and no
/// second document/decision/lifecycle copy is kept here.

@ProviderFor(PlanViewModel)
final planViewModelProvider = PlanViewModelFamily._();

/// Reading only. Decisions/feedback never live in this VM.
///
/// `open`/`fullWidth`/`panelWidth` are GUI-only placement of the same published
/// document: no Session, draft or accepted command is affected by them, and no
/// second document/decision/lifecycle copy is kept here.
final class PlanViewModelProvider
    extends $AsyncNotifierProvider<PlanViewModel, PlanViewState> {
  /// Reading only. Decisions/feedback never live in this VM.
  ///
  /// `open`/`fullWidth`/`panelWidth` are GUI-only placement of the same published
  /// document: no Session, draft or accepted command is affected by them, and no
  /// second document/decision/lifecycle copy is kept here.
  PlanViewModelProvider._({
    required PlanViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'planViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$planViewModelHash();

  @override
  String toString() {
    return r'planViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PlanViewModel create() => PlanViewModel();

  @override
  bool operator ==(Object other) {
    return other is PlanViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$planViewModelHash() => r'c226e659bff86002500c12ebe0e5e32f1e8eff1b';

/// Reading only. Decisions/feedback never live in this VM.
///
/// `open`/`fullWidth`/`panelWidth` are GUI-only placement of the same published
/// document: no Session, draft or accepted command is affected by them, and no
/// second document/decision/lifecycle copy is kept here.

final class PlanViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          PlanViewModel,
          AsyncValue<PlanViewState>,
          PlanViewState,
          FutureOr<PlanViewState>,
          String
        > {
  PlanViewModelFamily._()
    : super(
        retry: null,
        name: r'planViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Reading only. Decisions/feedback never live in this VM.
  ///
  /// `open`/`fullWidth`/`panelWidth` are GUI-only placement of the same published
  /// document: no Session, draft or accepted command is affected by them, and no
  /// second document/decision/lifecycle copy is kept here.

  PlanViewModelProvider call(String threadId) =>
      PlanViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'planViewModelProvider';
}

/// Reading only. Decisions/feedback never live in this VM.
///
/// `open`/`fullWidth`/`panelWidth` are GUI-only placement of the same published
/// document: no Session, draft or accepted command is affected by them, and no
/// second document/decision/lifecycle copy is kept here.

abstract class _$PlanViewModel extends $AsyncNotifier<PlanViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<PlanViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<PlanViewState>, PlanViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PlanViewState>, PlanViewState>,
              AsyncValue<PlanViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
