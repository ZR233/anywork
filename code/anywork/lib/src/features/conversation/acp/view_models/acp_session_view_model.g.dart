// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_session_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Admits through the application's exact directory identity. Re-entering a
/// page borrows the existing Client owner; Ref never closes business membership.

@ProviderFor(acpConversationOwner)
final acpConversationOwnerProvider = AcpConversationOwnerFamily._();

/// Admits through the application's exact directory identity. Re-entering a
/// page borrows the existing Client owner; Ref never closes business membership.

final class AcpConversationOwnerProvider
    extends
        $FunctionalProvider<
          AsyncValue<AcpConversationSession>,
          AcpConversationSession,
          FutureOr<AcpConversationSession>
        >
    with
        $FutureModifier<AcpConversationSession>,
        $FutureProvider<AcpConversationSession> {
  /// Admits through the application's exact directory identity. Re-entering a
  /// page borrows the existing Client owner; Ref never closes business membership.
  AcpConversationOwnerProvider._({
    required AcpConversationOwnerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpConversationOwnerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpConversationOwnerHash();

  @override
  String toString() {
    return r'acpConversationOwnerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AcpConversationSession> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AcpConversationSession> create(Ref ref) {
    final argument = this.argument as String;
    return acpConversationOwner(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AcpConversationOwnerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpConversationOwnerHash() =>
    r'ba17fce025785b872026e6d26ad8ded742c2a8f0';

/// Admits through the application's exact directory identity. Re-entering a
/// page borrows the existing Client owner; Ref never closes business membership.

final class AcpConversationOwnerFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AcpConversationSession>, String> {
  AcpConversationOwnerFamily._()
    : super(
        retry: null,
        name: r'acpConversationOwnerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Admits through the application's exact directory identity. Re-entering a
  /// page borrows the existing Client owner; Ref never closes business membership.

  AcpConversationOwnerProvider call(String threadId) =>
      AcpConversationOwnerProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpConversationOwnerProvider';
}

/// Shared single-subscription observation of [AcpConversationState] for one
/// [threadId]. Downstream component ViewModels use `.select(...)` so streaming
/// message chunks only notify the active item rather than configuration, plan,
/// or composer controls.

@ProviderFor(acpConversationState)
final acpConversationStateProvider = AcpConversationStateFamily._();

/// Shared single-subscription observation of [AcpConversationState] for one
/// [threadId]. Downstream component ViewModels use `.select(...)` so streaming
/// message chunks only notify the active item rather than configuration, plan,
/// or composer controls.

final class AcpConversationStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<AcpConversationState>,
          AsyncValue<AcpConversationState>,
          AsyncValue<AcpConversationState>
        >
    with $Provider<AsyncValue<AcpConversationState>> {
  /// Shared single-subscription observation of [AcpConversationState] for one
  /// [threadId]. Downstream component ViewModels use `.select(...)` so streaming
  /// message chunks only notify the active item rather than configuration, plan,
  /// or composer controls.
  AcpConversationStateProvider._({
    required AcpConversationStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpConversationStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpConversationStateHash();

  @override
  String toString() {
    return r'acpConversationStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AsyncValue<AcpConversationState>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<AcpConversationState> create(Ref ref) {
    final argument = this.argument as String;
    return acpConversationState(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<AcpConversationState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<AcpConversationState>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpConversationStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpConversationStateHash() =>
    r'c709f9c72265d662b0ea53f4a2de0184f868c306';

/// Shared single-subscription observation of [AcpConversationState] for one
/// [threadId]. Downstream component ViewModels use `.select(...)` so streaming
/// message chunks only notify the active item rather than configuration, plan,
/// or composer controls.

final class AcpConversationStateFamily extends $Family
    with $FunctionalFamilyOverride<AsyncValue<AcpConversationState>, String> {
  AcpConversationStateFamily._()
    : super(
        retry: null,
        name: r'acpConversationStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Shared single-subscription observation of [AcpConversationState] for one
  /// [threadId]. Downstream component ViewModels use `.select(...)` so streaming
  /// message chunks only notify the active item rather than configuration, plan,
  /// or composer controls.

  AcpConversationStateProvider call(String threadId) =>
      AcpConversationStateProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpConversationStateProvider';
}
