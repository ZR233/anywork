// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_plan_card_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Selects ONLY `state.value?.plan` so streaming message chunks never notify
/// plan listeners while the canonical `AcpPlanView` reference is unchanged.

@ProviderFor(acpPlanCardViewModel)
final acpPlanCardViewModelProvider = AcpPlanCardViewModelFamily._();

/// Selects ONLY `state.value?.plan` so streaming message chunks never notify
/// plan listeners while the canonical `AcpPlanView` reference is unchanged.

final class AcpPlanCardViewModelProvider
    extends
        $FunctionalProvider<
          AcpPlanCardViewState?,
          AcpPlanCardViewState?,
          AcpPlanCardViewState?
        >
    with $Provider<AcpPlanCardViewState?> {
  /// Selects ONLY `state.value?.plan` so streaming message chunks never notify
  /// plan listeners while the canonical `AcpPlanView` reference is unchanged.
  AcpPlanCardViewModelProvider._({
    required AcpPlanCardViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpPlanCardViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpPlanCardViewModelHash();

  @override
  String toString() {
    return r'acpPlanCardViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpPlanCardViewState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpPlanCardViewState? create(Ref ref) {
    final argument = this.argument as String;
    return acpPlanCardViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpPlanCardViewState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpPlanCardViewState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpPlanCardViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpPlanCardViewModelHash() =>
    r'75d267b70dd03512f220a985cbcf1554f8fbf03a';

/// Selects ONLY `state.value?.plan` so streaming message chunks never notify
/// plan listeners while the canonical `AcpPlanView` reference is unchanged.

final class AcpPlanCardViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpPlanCardViewState?, String> {
  AcpPlanCardViewModelFamily._()
    : super(
        retry: null,
        name: r'acpPlanCardViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Selects ONLY `state.value?.plan` so streaming message chunks never notify
  /// plan listeners while the canonical `AcpPlanView` reference is unchanged.

  AcpPlanCardViewModelProvider call(String threadId) =>
      AcpPlanCardViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpPlanCardViewModelProvider';
}
