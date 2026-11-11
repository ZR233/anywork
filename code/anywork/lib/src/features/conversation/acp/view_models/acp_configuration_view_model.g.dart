// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_configuration_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AcpConfigurationViewModel)
final acpConfigurationViewModelProvider = AcpConfigurationViewModelFamily._();

final class AcpConfigurationViewModelProvider
    extends
        $NotifierProvider<
          AcpConfigurationViewModel,
          AcpConfigurationViewState
        > {
  AcpConfigurationViewModelProvider._({
    required AcpConfigurationViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpConfigurationViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpConfigurationViewModelHash();

  @override
  String toString() {
    return r'acpConfigurationViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpConfigurationViewModel create() => AcpConfigurationViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpConfigurationViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpConfigurationViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpConfigurationViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpConfigurationViewModelHash() =>
    r'091713effd4e05427139bc3bc1e70ae9ba69934b';

final class AcpConfigurationViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpConfigurationViewModel,
          AcpConfigurationViewState,
          AcpConfigurationViewState,
          AcpConfigurationViewState,
          String
        > {
  AcpConfigurationViewModelFamily._()
    : super(
        retry: null,
        name: r'acpConfigurationViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpConfigurationViewModelProvider call(String threadId) =>
      AcpConfigurationViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpConfigurationViewModelProvider';
}

abstract class _$AcpConfigurationViewModel
    extends $Notifier<AcpConfigurationViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  AcpConfigurationViewState build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AcpConfigurationViewState, AcpConfigurationViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AcpConfigurationViewState, AcpConfigurationViewState>,
              AcpConfigurationViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
