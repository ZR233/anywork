// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ConversationViewModel)
final conversationViewModelProvider = ConversationViewModelFamily._();

final class ConversationViewModelProvider
    extends
        $AsyncNotifierProvider<ConversationViewModel, ConversationViewState> {
  ConversationViewModelProvider._({
    required ConversationViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'conversationViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$conversationViewModelHash();

  @override
  String toString() {
    return r'conversationViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ConversationViewModel create() => ConversationViewModel();

  @override
  bool operator ==(Object other) {
    return other is ConversationViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$conversationViewModelHash() =>
    r'257e0e0f857b9256b8419ca5040180c285d4c756';

final class ConversationViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ConversationViewModel,
          AsyncValue<ConversationViewState>,
          ConversationViewState,
          FutureOr<ConversationViewState>,
          String
        > {
  ConversationViewModelFamily._()
    : super(
        retry: null,
        name: r'conversationViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ConversationViewModelProvider call(String threadId) =>
      ConversationViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'conversationViewModelProvider';
}

abstract class _$ConversationViewModel
    extends $AsyncNotifier<ConversationViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<ConversationViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ConversationViewState>, ConversationViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ConversationViewState>,
                ConversationViewState
              >,
              AsyncValue<ConversationViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
