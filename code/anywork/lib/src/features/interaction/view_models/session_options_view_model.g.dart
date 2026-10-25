// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_options_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Presentation for an explicit draft/default edit, not a configuration store.

@ProviderFor(SessionOptionsViewModel)
final sessionOptionsViewModelProvider = SessionOptionsViewModelFamily._();

/// Presentation for an explicit draft/default edit, not a configuration store.
final class SessionOptionsViewModelProvider
    extends
        $AsyncNotifierProvider<SessionOptionsViewModel, SessionOptionsState> {
  /// Presentation for an explicit draft/default edit, not a configuration store.
  SessionOptionsViewModelProvider._({
    required SessionOptionsViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sessionOptionsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sessionOptionsViewModelHash();

  @override
  String toString() {
    return r'sessionOptionsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SessionOptionsViewModel create() => SessionOptionsViewModel();

  @override
  bool operator ==(Object other) {
    return other is SessionOptionsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sessionOptionsViewModelHash() =>
    r'b5a0bce02d9be48d38e8261cbce10672d84d2ac5';

/// Presentation for an explicit draft/default edit, not a configuration store.

final class SessionOptionsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          SessionOptionsViewModel,
          AsyncValue<SessionOptionsState>,
          SessionOptionsState,
          FutureOr<SessionOptionsState>,
          String
        > {
  SessionOptionsViewModelFamily._()
    : super(
        retry: null,
        name: r'sessionOptionsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Presentation for an explicit draft/default edit, not a configuration store.

  SessionOptionsViewModelProvider call(String projectId) =>
      SessionOptionsViewModelProvider._(argument: projectId, from: this);

  @override
  String toString() => r'sessionOptionsViewModelProvider';
}

/// Presentation for an explicit draft/default edit, not a configuration store.

abstract class _$SessionOptionsViewModel
    extends $AsyncNotifier<SessionOptionsState> {
  late final _$args = ref.$arg as String;
  String get projectId => _$args;

  FutureOr<SessionOptionsState> build(String projectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<SessionOptionsState>, SessionOptionsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SessionOptionsState>, SessionOptionsState>,
              AsyncValue<SessionOptionsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
