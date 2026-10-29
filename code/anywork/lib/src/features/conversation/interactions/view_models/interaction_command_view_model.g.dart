// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction_command_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// SDK status is the durable fact; this notifier only derives a presentation projection
/// and holds a synchronous gate while an SDK call is being entered.

@ProviderFor(InteractionCommandViewModel)
final interactionCommandViewModelProvider =
    InteractionCommandViewModelFamily._();

/// SDK status is the durable fact; this notifier only derives a presentation projection
/// and holds a synchronous gate while an SDK call is being entered.
final class InteractionCommandViewModelProvider
    extends
        $AsyncNotifierProvider<
          InteractionCommandViewModel,
          InteractionCommandViewState
        > {
  /// SDK status is the durable fact; this notifier only derives a presentation projection
  /// and holds a synchronous gate while an SDK call is being entered.
  InteractionCommandViewModelProvider._({
    required InteractionCommandViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'interactionCommandViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$interactionCommandViewModelHash();

  @override
  String toString() {
    return r'interactionCommandViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  InteractionCommandViewModel create() => InteractionCommandViewModel();

  @override
  bool operator ==(Object other) {
    return other is InteractionCommandViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$interactionCommandViewModelHash() =>
    r'550e9be78b302b62abe6d66342adbc21bdd45a0a';

/// SDK status is the durable fact; this notifier only derives a presentation projection
/// and holds a synchronous gate while an SDK call is being entered.

final class InteractionCommandViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          InteractionCommandViewModel,
          AsyncValue<InteractionCommandViewState>,
          InteractionCommandViewState,
          FutureOr<InteractionCommandViewState>,
          String
        > {
  InteractionCommandViewModelFamily._()
    : super(
        retry: null,
        name: r'interactionCommandViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// SDK status is the durable fact; this notifier only derives a presentation projection
  /// and holds a synchronous gate while an SDK call is being entered.

  InteractionCommandViewModelProvider call(String hostThreadId) =>
      InteractionCommandViewModelProvider._(argument: hostThreadId, from: this);

  @override
  String toString() => r'interactionCommandViewModelProvider';
}

/// SDK status is the durable fact; this notifier only derives a presentation projection
/// and holds a synchronous gate while an SDK call is being entered.

abstract class _$InteractionCommandViewModel
    extends $AsyncNotifier<InteractionCommandViewState> {
  late final _$args = ref.$arg as String;
  String get hostThreadId => _$args;

  FutureOr<InteractionCommandViewState> build(String hostThreadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<InteractionCommandViewState>,
              InteractionCommandViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<InteractionCommandViewState>,
                InteractionCommandViewState
              >,
              AsyncValue<InteractionCommandViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
