// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lsp_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LspViewModel)
final lspViewModelProvider = LspViewModelFamily._();

final class LspViewModelProvider
    extends $AsyncNotifierProvider<LspViewModel, LspActionsViewState> {
  LspViewModelProvider._({
    required LspViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lspViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lspViewModelHash();

  @override
  String toString() {
    return r'lspViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LspViewModel create() => LspViewModel();

  @override
  bool operator ==(Object other) {
    return other is LspViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lspViewModelHash() => r'53c27b721cf8566ae925f88c12ceff5ce0d000b6';

final class LspViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          LspViewModel,
          AsyncValue<LspActionsViewState>,
          LspActionsViewState,
          FutureOr<LspActionsViewState>,
          String
        > {
  LspViewModelFamily._()
    : super(
        retry: null,
        name: r'lspViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LspViewModelProvider call(String projectId) =>
      LspViewModelProvider._(argument: projectId, from: this);

  @override
  String toString() => r'lspViewModelProvider';
}

abstract class _$LspViewModel extends $AsyncNotifier<LspActionsViewState> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<LspActionsViewState> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<LspActionsViewState>, LspActionsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<LspActionsViewState>, LspActionsViewState>,
              AsyncValue<LspActionsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
