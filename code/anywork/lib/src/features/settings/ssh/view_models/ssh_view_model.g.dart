// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SshViewModel)
final sshViewModelProvider = SshViewModelProvider._();

final class SshViewModelProvider
    extends $AsyncNotifierProvider<SshViewModel, SshViewState> {
  SshViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sshViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sshViewModelHash();

  @$internal
  @override
  SshViewModel create() => SshViewModel();
}

String _$sshViewModelHash() => r'df5b7216da518a360c9f5935e8b90280b14d79d6';

abstract class _$SshViewModel extends $AsyncNotifier<SshViewState> {
  FutureOr<SshViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SshViewState>, SshViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SshViewState>, SshViewState>,
              AsyncValue<SshViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
