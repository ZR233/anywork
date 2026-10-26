// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_password_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SshPasswordViewModel)
final sshPasswordViewModelProvider = SshPasswordViewModelFamily._();

final class SshPasswordViewModelProvider
    extends $AsyncNotifierProvider<SshPasswordViewModel, SshPasswordViewState> {
  SshPasswordViewModelProvider._({
    required SshPasswordViewModelFamily super.from,
    required (String, int, int) super.argument,
  }) : super(
         retry: null,
         name: r'sshPasswordViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sshPasswordViewModelHash();

  @override
  String toString() {
    return r'sshPasswordViewModelProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SshPasswordViewModel create() => SshPasswordViewModel();

  @override
  bool operator ==(Object other) {
    return other is SshPasswordViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sshPasswordViewModelHash() =>
    r'65d157befcd26b377edc9859247184429dbae59d';

final class SshPasswordViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          SshPasswordViewModel,
          AsyncValue<SshPasswordViewState>,
          SshPasswordViewState,
          FutureOr<SshPasswordViewState>,
          (String, int, int)
        > {
  SshPasswordViewModelFamily._()
    : super(
        retry: null,
        name: r'sshPasswordViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SshPasswordViewModelProvider call(String alias, int scopeId, int promptId) =>
      SshPasswordViewModelProvider._(
        argument: (alias, scopeId, promptId),
        from: this,
      );

  @override
  String toString() => r'sshPasswordViewModelProvider';
}

abstract class _$SshPasswordViewModel
    extends $AsyncNotifier<SshPasswordViewState> {
  late final _$args = ref.$arg as (String, int, int);
  String get alias => _$args.$1;
  int get scopeId => _$args.$2;
  int get promptId => _$args.$3;

  FutureOr<SshPasswordViewState> build(String alias, int scopeId, int promptId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<SshPasswordViewState>, SshPasswordViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SshPasswordViewState>,
                SshPasswordViewState
              >,
              AsyncValue<SshPasswordViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}
