// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_external_history_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(acpExternalHistoryOperations)
final acpExternalHistoryOperationsProvider =
    AcpExternalHistoryOperationsProvider._();

final class AcpExternalHistoryOperationsProvider
    extends
        $FunctionalProvider<
          AcpExternalHistoryOperations,
          AcpExternalHistoryOperations,
          AcpExternalHistoryOperations
        >
    with $Provider<AcpExternalHistoryOperations> {
  AcpExternalHistoryOperationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'acpExternalHistoryOperationsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$acpExternalHistoryOperationsHash();

  @$internal
  @override
  $ProviderElement<AcpExternalHistoryOperations> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpExternalHistoryOperations create(Ref ref) {
    return acpExternalHistoryOperations(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpExternalHistoryOperations value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpExternalHistoryOperations>(value),
    );
  }
}

String _$acpExternalHistoryOperationsHash() =>
    r'85da56d5a134e028151de50721685d899c329697';

/// Observes ONLY the fields required by the status-bar button so streaming
/// message chunks never rebuild the external-sessions trigger.

@ProviderFor(acpExternalHistoryButtonViewModel)
final acpExternalHistoryButtonViewModelProvider =
    AcpExternalHistoryButtonViewModelFamily._();

/// Observes ONLY the fields required by the status-bar button so streaming
/// message chunks never rebuild the external-sessions trigger.

final class AcpExternalHistoryButtonViewModelProvider
    extends
        $FunctionalProvider<
          AcpExternalHistoryButtonState,
          AcpExternalHistoryButtonState,
          AcpExternalHistoryButtonState
        >
    with $Provider<AcpExternalHistoryButtonState> {
  /// Observes ONLY the fields required by the status-bar button so streaming
  /// message chunks never rebuild the external-sessions trigger.
  AcpExternalHistoryButtonViewModelProvider._({
    required AcpExternalHistoryButtonViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpExternalHistoryButtonViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() =>
      _$acpExternalHistoryButtonViewModelHash();

  @override
  String toString() {
    return r'acpExternalHistoryButtonViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpExternalHistoryButtonState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpExternalHistoryButtonState create(Ref ref) {
    final argument = this.argument as String;
    return acpExternalHistoryButtonViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpExternalHistoryButtonState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpExternalHistoryButtonState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpExternalHistoryButtonViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpExternalHistoryButtonViewModelHash() =>
    r'8c9baad0fe0974d3e28d7c77940ea804ad0bd44f';

/// Observes ONLY the fields required by the status-bar button so streaming
/// message chunks never rebuild the external-sessions trigger.

final class AcpExternalHistoryButtonViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpExternalHistoryButtonState, String> {
  AcpExternalHistoryButtonViewModelFamily._()
    : super(
        retry: null,
        name: r'acpExternalHistoryButtonViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Observes ONLY the fields required by the status-bar button so streaming
  /// message chunks never rebuild the external-sessions trigger.

  AcpExternalHistoryButtonViewModelProvider call(String threadId) =>
      AcpExternalHistoryButtonViewModelProvider._(
        argument: threadId,
        from: this,
      );

  @override
  String toString() => r'acpExternalHistoryButtonViewModelProvider';
}

/// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
/// never cross widget constructor boundaries. Internally verifies that async
/// responses still match the current session owner of [threadId].

@ProviderFor(AcpExternalHistoryViewModel)
final acpExternalHistoryViewModelProvider =
    AcpExternalHistoryViewModelFamily._();

/// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
/// never cross widget constructor boundaries. Internally verifies that async
/// responses still match the current session owner of [threadId].
final class AcpExternalHistoryViewModelProvider
    extends
        $NotifierProvider<
          AcpExternalHistoryViewModel,
          AcpExternalHistoryDialogState
        > {
  /// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
  /// never cross widget constructor boundaries. Internally verifies that async
  /// responses still match the current session owner of [threadId].
  AcpExternalHistoryViewModelProvider._({
    required AcpExternalHistoryViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpExternalHistoryViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpExternalHistoryViewModelHash();

  @override
  String toString() {
    return r'acpExternalHistoryViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpExternalHistoryViewModel create() => AcpExternalHistoryViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpExternalHistoryDialogState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpExternalHistoryDialogState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpExternalHistoryViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpExternalHistoryViewModelHash() =>
    r'bc414d67d03380bace2a6b680992d5b6136bc41a';

/// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
/// never cross widget constructor boundaries. Internally verifies that async
/// responses still match the current session owner of [threadId].

final class AcpExternalHistoryViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpExternalHistoryViewModel,
          AcpExternalHistoryDialogState,
          AcpExternalHistoryDialogState,
          AcpExternalHistoryDialogState,
          String
        > {
  AcpExternalHistoryViewModelFamily._()
    : super(
        retry: null,
        name: r'acpExternalHistoryViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
  /// never cross widget constructor boundaries. Internally verifies that async
  /// responses still match the current session owner of [threadId].

  AcpExternalHistoryViewModelProvider call(String threadId) =>
      AcpExternalHistoryViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpExternalHistoryViewModelProvider';
}

/// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
/// never cross widget constructor boundaries. Internally verifies that async
/// responses still match the current session owner of [threadId].

abstract class _$AcpExternalHistoryViewModel
    extends $Notifier<AcpExternalHistoryDialogState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  AcpExternalHistoryDialogState build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AcpExternalHistoryDialogState,
              AcpExternalHistoryDialogState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AcpExternalHistoryDialogState,
                AcpExternalHistoryDialogState
              >,
              AcpExternalHistoryDialogState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
