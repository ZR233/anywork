// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_composer_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AcpComposerViewModel)
final acpComposerViewModelProvider = AcpComposerViewModelFamily._();

final class AcpComposerViewModelProvider
    extends $NotifierProvider<AcpComposerViewModel, AcpComposerViewState> {
  AcpComposerViewModelProvider._({
    required AcpComposerViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpComposerViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpComposerViewModelHash();

  @override
  String toString() {
    return r'acpComposerViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpComposerViewModel create() => AcpComposerViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpComposerViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpComposerViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpComposerViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpComposerViewModelHash() =>
    r'a5d08db12705b92c7e7bdb8c1135e73306b5471d';

final class AcpComposerViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpComposerViewModel,
          AcpComposerViewState,
          AcpComposerViewState,
          AcpComposerViewState,
          String
        > {
  AcpComposerViewModelFamily._()
    : super(
        retry: null,
        name: r'acpComposerViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpComposerViewModelProvider call(String threadId) =>
      AcpComposerViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpComposerViewModelProvider';
}

abstract class _$AcpComposerViewModel extends $Notifier<AcpComposerViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  AcpComposerViewState build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AcpComposerViewState, AcpComposerViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AcpComposerViewState, AcpComposerViewState>,
              AcpComposerViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
