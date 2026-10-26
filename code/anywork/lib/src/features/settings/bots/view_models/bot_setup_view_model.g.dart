// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bot_setup_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One bot create/edit session. It freezes the command inputs before waiting,
/// keeps pending/rejected/unknown presentation for its own intent, and never
/// turns a receipt into a configuration fact: the canonical snapshot is the
/// only source for what actually got saved.

@ProviderFor(BotSetupViewModel)
final botSetupViewModelProvider = BotSetupViewModelFamily._();

/// One bot create/edit session. It freezes the command inputs before waiting,
/// keeps pending/rejected/unknown presentation for its own intent, and never
/// turns a receipt into a configuration fact: the canonical snapshot is the
/// only source for what actually got saved.
final class BotSetupViewModelProvider
    extends $AsyncNotifierProvider<BotSetupViewModel, BotSetupViewState> {
  /// One bot create/edit session. It freezes the command inputs before waiting,
  /// keeps pending/rejected/unknown presentation for its own intent, and never
  /// turns a receipt into a configuration fact: the canonical snapshot is the
  /// only source for what actually got saved.
  BotSetupViewModelProvider._({
    required BotSetupViewModelFamily super.from,
    required BotSetupKey super.argument,
  }) : super(
         retry: null,
         name: r'botSetupViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$botSetupViewModelHash();

  @override
  String toString() {
    return r'botSetupViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BotSetupViewModel create() => BotSetupViewModel();

  @override
  bool operator ==(Object other) {
    return other is BotSetupViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$botSetupViewModelHash() => r'b7d167a78f97327ea20d840dfcf2460b6d49c123';

/// One bot create/edit session. It freezes the command inputs before waiting,
/// keeps pending/rejected/unknown presentation for its own intent, and never
/// turns a receipt into a configuration fact: the canonical snapshot is the
/// only source for what actually got saved.

final class BotSetupViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          BotSetupViewModel,
          AsyncValue<BotSetupViewState>,
          BotSetupViewState,
          FutureOr<BotSetupViewState>,
          BotSetupKey
        > {
  BotSetupViewModelFamily._()
    : super(
        retry: null,
        name: r'botSetupViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One bot create/edit session. It freezes the command inputs before waiting,
  /// keeps pending/rejected/unknown presentation for its own intent, and never
  /// turns a receipt into a configuration fact: the canonical snapshot is the
  /// only source for what actually got saved.

  BotSetupViewModelProvider call(BotSetupKey key) =>
      BotSetupViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'botSetupViewModelProvider';
}

/// One bot create/edit session. It freezes the command inputs before waiting,
/// keeps pending/rejected/unknown presentation for its own intent, and never
/// turns a receipt into a configuration fact: the canonical snapshot is the
/// only source for what actually got saved.

abstract class _$BotSetupViewModel extends $AsyncNotifier<BotSetupViewState> {
  late final _$args = ref.$arg as BotSetupKey;
  BotSetupKey get key => _$args;

  FutureOr<BotSetupViewState> build(BotSetupKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<BotSetupViewState>, BotSetupViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BotSetupViewState>, BotSetupViewState>,
              AsyncValue<BotSetupViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
