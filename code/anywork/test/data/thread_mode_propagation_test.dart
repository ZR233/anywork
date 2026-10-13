import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/data/frb/studio_api.dart';
import 'package:anywork/src/domain/models/studio_models.dart';

/// 回归证据：会话快照携带的 thread 身份必须能在目录水位不前进时修正窗口行，
/// 更旧快照不得覆盖窗口里更新的事实。design/18 §18.11.1。
///
/// 这条合并由 [ThreadDirectoryWindow.replaceIdentity] 承载。目录基线/增量仍是
/// 严格 revision 门，不能代替它：不推进水位的 mode 变更会被基线原样拒绝。
///
/// 阅读面可见性竞态用例随 visibility 机制一并移除：订阅生命周期由 Riverpod watcher 承担，design/25 §25.8。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const threadId = 'thread-main';

  group('thread 身份单调合并', () {
    test('会话快照能在目录水位不前进时修正 mode', () async {
      final window = await _directoryWindow(revision: 7);
      final directoryRow = _row(window, threadId);
      expect(directoryRow, isNotNull, reason: 'demo fixture 应包含目录行');
      expect(directoryRow!.mode, ThreadModeId.simple);

      final corrected = directoryRow.copyWith(mode: ThreadModeId.task);
      final baselineRejected = window.applyBaselinePage(
        ThreadDirectoryPage(
          threads: [
            for (final thread in window.threads)
              if (thread.id == threadId) corrected else thread,
          ],
          nextCursor: window.nextCursor,
          revision: window.revision,
        ),
        revision: window.revision,
      );
      expect(baselineRejected, same(window), reason: '同水位基线不是身份修正，不得改写 mode');

      final next = window.replaceIdentity(corrected);

      expect(
        _row(next, threadId)?.mode,
        ThreadModeId.task,
        reason: '会话自身的 canonical 快照必须能修正 mode（selector 文案与选中态同源）',
      );
      expect(next.revision, window.revision, reason: '快照不是目录基线，不得推进目录水位');
      expect(next.threads.length, window.threads.length);
    });

    test('更旧的会话快照不得覆盖目录里更新的事实', () async {
      final base = await _directoryWindow();
      final directoryRow = _row(base, threadId)!;
      final newest = directoryRow.copyWith(
        mode: ThreadModeId.task,
        updatedAt: directoryRow.updatedAt.add(const Duration(minutes: 5)),
      );
      final window = base.copyWith(
        threads: [
          for (final thread in base.threads)
            if (thread.id == threadId) newest else thread,
        ],
      );

      final next = window.replaceIdentity(
        directoryRow.copyWith(
          mode: ThreadModeId.simple,
          updatedAt: directoryRow.updatedAt,
        ),
      );

      final row = _row(next, threadId);
      expect(row?.mode, ThreadModeId.task);
      expect(row?.updatedAt, newest.updatedAt);
      expect(next.revision, window.revision);
    });
  });
}

Future<ThreadDirectoryWindow> _directoryWindow({int? revision}) async {
  final api = DemoStudioBridgeDataSource(lspActivityLoop: false);
  final snapshot = await api.readStudioState();
  final window = snapshot.threadDirectory;
  if (revision == null) return window;
  return window.copyWith(revision: revision);
}

StudioThread? _row(ThreadDirectoryWindow window, String id) {
  for (final thread in window.threads) {
    if (thread.id == id) return thread;
  }
  return null;
}
