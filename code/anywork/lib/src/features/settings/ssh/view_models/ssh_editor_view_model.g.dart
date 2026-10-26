// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SshEditorViewModel)
final sshEditorViewModelProvider = SshEditorViewModelFamily._();

final class SshEditorViewModelProvider
    extends $AsyncNotifierProvider<SshEditorViewModel, SshEditorViewState> {
  SshEditorViewModelProvider._({
    required SshEditorViewModelFamily super.from,
    required SshEditorKey super.argument,
  }) : super(
         retry: null,
         name: r'sshEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sshEditorViewModelHash();

  @override
  String toString() {
    return r'sshEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SshEditorViewModel create() => SshEditorViewModel();

  @override
  bool operator ==(Object other) {
    return other is SshEditorViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sshEditorViewModelHash() =>
    r'9112d8e16046eb9538fc75d27b650de81824040a';

final class SshEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          SshEditorViewModel,
          AsyncValue<SshEditorViewState>,
          SshEditorViewState,
          FutureOr<SshEditorViewState>,
          SshEditorKey
        > {
  SshEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'sshEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SshEditorViewModelProvider call(SshEditorKey target) =>
      SshEditorViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'sshEditorViewModelProvider';
}

abstract class _$SshEditorViewModel extends $AsyncNotifier<SshEditorViewState> {
  late final _$args = ref.$arg as SshEditorKey;
  SshEditorKey get target => _$args;

  FutureOr<SshEditorViewState> build(SshEditorKey target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<SshEditorViewState>, SshEditorViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SshEditorViewState>, SshEditorViewState>,
              AsyncValue<SshEditorViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
