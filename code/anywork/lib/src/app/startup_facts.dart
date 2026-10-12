import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/studio_api_provider.dart';
import '../data/stores/selection_store.dart';
import '../data/stores/settings_store.dart';

/// 启动所有者：静态供应商目录与上次选择恢复。
///
/// 二者没有命令 lane，也不在 provider 初始化里写。函数幂等：目录已加载或选择已
/// 存在时不再覆盖。设置页不再重复调用，静态事实在 shell 首帧前就绪。
Future<void> ensureSettingsStaticFacts(WidgetRef ref) async {
  if (!ref.context.mounted) return;
  final api = ref.read(studioBridgeDataSourceProvider);
  if (!ref.read(settingsStoreProvider).providerCatalogLoaded) {
    try {
      final catalog = await api.loadProviderCatalog();
      if (!ref.context.mounted) return;
      ref.read(settingsStoreProvider.notifier).applyProviderCatalog(catalog);
    } catch (error, stackTrace) {
      debugPrint(
        'settings_provider_catalog_ingest_failed error=$error\n$stackTrace',
      );
    }
  }
  if (!ref.context.mounted) return;
  final selection = ref.read(selectionStoreProvider);
  if (selection.selectedProjectId != null ||
      selection.selectedThreadId != null) {
    return;
  }
  try {
    final snapshot = await api.readStudioState();
    if (!ref.context.mounted) return;
    final current = ref.read(selectionStoreProvider);
    if (current.selectedProjectId != null || current.selectedThreadId != null) {
      return;
    }
    ref
        .read(selectionStoreProvider.notifier)
        .restoreStartup(
          projectId: snapshot.selectedProjectId,
          threadId: snapshot.selectedThreadId,
          needsOpen: snapshot.selectedThreadId != null,
        );
  } catch (error, stackTrace) {
    debugPrint('settings_selection_restore_failed error=$error\n$stackTrace');
  }
}
