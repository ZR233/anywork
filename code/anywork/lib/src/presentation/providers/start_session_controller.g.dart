// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// This observer borrows the Client's logical draft across routes.

@ProviderFor(startSessionController)
final startSessionControllerProvider = StartSessionControllerProvider._();

/// This observer borrows the Client's logical draft across routes.

final class StartSessionControllerProvider
    extends
        $FunctionalProvider<
          StartSessionDraft,
          StartSessionDraft,
          StartSessionDraft
        >
    with $Provider<StartSessionDraft> {
  /// This observer borrows the Client's logical draft across routes.
  StartSessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startSessionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startSessionControllerHash();

  @$internal
  @override
  $ProviderElement<StartSessionDraft> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StartSessionDraft create(Ref ref) {
    return startSessionController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StartSessionDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StartSessionDraft>(value),
    );
  }
}

String _$startSessionControllerHash() =>
    r'e47d9b82b5de02c27b1f714ed739de49c49d4fff';
