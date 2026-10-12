// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'directory_commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 目录、选择与领域刷新命令。
///
/// 打开/归档等没有目录 revision 的响应不直接拼进目录，而是读取产品快照后走
/// [applyProductSnapshot]。模型目录刷新按 provider 去重。选择是本地事实，
/// 成功后才写入，不乐观改 canonical。

@ProviderFor(DirectoryCommands)
final directoryCommandsProvider = DirectoryCommandsProvider._();

/// 目录、选择与领域刷新命令。
///
/// 打开/归档等没有目录 revision 的响应不直接拼进目录，而是读取产品快照后走
/// [applyProductSnapshot]。模型目录刷新按 provider 去重。选择是本地事实，
/// 成功后才写入，不乐观改 canonical。
final class DirectoryCommandsProvider
    extends $NotifierProvider<DirectoryCommands, DirectoryCommandState> {
  /// 目录、选择与领域刷新命令。
  ///
  /// 打开/归档等没有目录 revision 的响应不直接拼进目录，而是读取产品快照后走
  /// [applyProductSnapshot]。模型目录刷新按 provider 去重。选择是本地事实，
  /// 成功后才写入，不乐观改 canonical。
  DirectoryCommandsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'directoryCommandsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$directoryCommandsHash();

  @$internal
  @override
  DirectoryCommands create() => DirectoryCommands();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DirectoryCommandState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DirectoryCommandState>(value),
    );
  }
}

String _$directoryCommandsHash() => r'0d11c4248b06e7bd991210f996ef64b03732a6e9';

/// 目录、选择与领域刷新命令。
///
/// 打开/归档等没有目录 revision 的响应不直接拼进目录，而是读取产品快照后走
/// [applyProductSnapshot]。模型目录刷新按 provider 去重。选择是本地事实，
/// 成功后才写入，不乐观改 canonical。

abstract class _$DirectoryCommands extends $Notifier<DirectoryCommandState> {
  DirectoryCommandState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DirectoryCommandState, DirectoryCommandState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DirectoryCommandState, DirectoryCommandState>,
              DirectoryCommandState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
