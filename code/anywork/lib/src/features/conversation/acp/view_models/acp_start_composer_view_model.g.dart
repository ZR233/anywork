// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_start_composer_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AcpStartComposerViewModel)
final acpStartComposerViewModelProvider = AcpStartComposerViewModelFamily._();

final class AcpStartComposerViewModelProvider
    extends
        $NotifierProvider<
          AcpStartComposerViewModel,
          AcpStartComposerViewState
        > {
  AcpStartComposerViewModelProvider._({
    required AcpStartComposerViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpStartComposerViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpStartComposerViewModelHash();

  @override
  String toString() {
    return r'acpStartComposerViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpStartComposerViewModel create() => AcpStartComposerViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpStartComposerViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpStartComposerViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpStartComposerViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpStartComposerViewModelHash() =>
    r'a855db9ee27925cfa6b5589fa9b69632584bdbd0';

final class AcpStartComposerViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpStartComposerViewModel,
          AcpStartComposerViewState,
          AcpStartComposerViewState,
          AcpStartComposerViewState,
          String
        > {
  AcpStartComposerViewModelFamily._()
    : super(
        retry: null,
        name: r'acpStartComposerViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpStartComposerViewModelProvider call(String workspaceId) =>
      AcpStartComposerViewModelProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'acpStartComposerViewModelProvider';
}

abstract class _$AcpStartComposerViewModel
    extends $Notifier<AcpStartComposerViewState> {
  late final _$args = ref.$arg as String;
  String get workspaceId => _$args;

  AcpStartComposerViewState build(String workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AcpStartComposerViewState, AcpStartComposerViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AcpStartComposerViewState, AcpStartComposerViewState>,
              AcpStartComposerViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
