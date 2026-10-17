import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';

/// 持续输出期间的呈现稳定性：断言的是「尚未 settle 的那些帧」。
///
/// 缺陷恰恰发生在动画进行中，等到 `pumpAndSettle` 之后截图完全可能正常，因此这里
/// 按帧推进并在动画周期中途取样。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('摘要连续更新期间不存在正在退场的旧文本', (tester) async {
    final row = _reasoningRow(const ['第一步：读取配置']);
    await tester.pumpWidget(_harness(_timeline([row])));
    await tester.pump();

    expect(_summaryTexts(row.id), hasLength(1));

    // 33 ms 一次追加，快于任何 140 ms 级别的交叉淡化：若仍以 label 作为
    // Widget 身份，动画周期内会同时存在当前 child 与多个 outgoing child。
    for (final label in const [
      '第一步：读取配置',
      '第一步：读取配置 · 第二步',
      '第一步：读取配置 · 第二步 · 第三步',
    ]) {
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 33));
        expect(
          _summaryTexts(row.id),
          hasLength(1),
          reason: '摘要 "$label" 在动画未结束时出现了退场中的旧文本',
        );
      }
      await tester.pumpWidget(
        _harness(
          _timeline([
            _reasoningRow([label]),
          ]),
        ),
      );
    }

    // 动画若确实存在，settle 之后会回到单文本；这里要求全程都只有一份。
    await tester.pump(const Duration(milliseconds: 300));
    expect(_summaryTexts(row.id), hasLength(1));
  });

  testWidgets('工具分组摘要逐步追加也不产生退场文本', (tester) async {
    const commands = ['cargo fmt --check', 'cargo clippy', 'cargo test'];
    final row = _toolGroupRow(commands.take(1).toList());
    await tester.pumpWidget(_harness(_timeline([row])));
    await tester.pump();

    for (final count in const [2, 3]) {
      await tester.pumpWidget(
        _harness(_timeline([_toolGroupRow(commands.take(count).toList())])),
      );
      await tester.pump(const Duration(milliseconds: 33));
      expect(
        _summaryTexts(row.id),
        hasLength(1),
        reason: '工具分组摘要追加到 $count 项时出现了退场中的旧文本',
      );
    }
  });

  testWidgets('仅 saved 变化不改变正文几何', (tester) async {
    final pending = _textRow('item-1', '已经写入的正文', saved: false);
    await tester.pumpWidget(_harness(_timeline([pending])));
    await tester.pump();

    final before = tester.getRect(
      find.byKey(StudioDriverKeys.timelineRow(pending.id)),
    );
    expect(_pendingSaveIconCount(pending.id), 1);

    final saved = _textRow('item-1', '已经写入的正文');
    await tester.pumpWidget(_harness(_timeline([saved])));
    await tester.pump();

    final after = tester.getRect(
      find.byKey(StudioDriverKeys.timelineRow(saved.id)),
    );
    expect(_pendingSaveIconCount(saved.id), 0);
    expect(after, before, reason: '保存确认改变了行几何，会触发额外的滚动补偿');
  });

  testWidgets('切换会话后第一帧不保留旧会话行', (tester) async {
    tester.view.physicalSize = const Size(800, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rowsByThread = <String, List<TimelineRow>>{
      'thread-a': _threadRows('thread-a', 0),
      'thread-b': _threadRows('thread-b', 0),
    };

    Widget view(String threadId, int revision) {
      final rows = revision == 0
          ? rowsByThread[threadId]!
          : _threadRows(threadId, revision);
      return _harness(
        TimelineView(
          threadId: threadId,
          viewId: 'view-$threadId',
          rows: rows,
          body: const ThreadHistoryWindow(),
          turn: null,
          onCommand: (_) {},
        ),
      );
    }

    Future<void> show(String threadId, int revision) async {
      await tester.pumpWidget(view(threadId, revision));
      final otherThread = threadId == 'thread-a' ? 'thread-b' : 'thread-a';
      final screen = Offset.zero & tester.view.physicalSize;
      for (var frame = 0; frame < 2; frame++) {
        expect(
          tester.takeException(),
          isNull,
          reason: 'thread=$threadId revision=$revision frame=$frame',
        );
        for (final row in rowsByThread[otherThread]!) {
          final finder = find.byKey(StudioDriverKeys.timelineRow(row.id));
          if (finder.evaluate().isEmpty) continue;
          expect(
            tester.getRect(finder).overlaps(screen),
            isFalse,
            reason: '旧会话行 ${row.id} 在新会话首帧仍可见',
          );
        }
        expect(
          rowsByThread[threadId]!.any(
            (row) => find
                .byKey(StudioDriverKeys.timelineRow(row.id))
                .evaluate()
                .isNotEmpty,
          ),
          isTrue,
          reason: '新会话在首帧没有挂载任何行',
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await show('thread-a', 0);
    await tester.drag(
      find.byKey(StudioDriverKeys.timeline),
      const Offset(0, 280),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull, reason: 'initial scroll');

    await show('thread-b', 1);
    await show('thread-b', 2);
    await show('thread-a', 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'dispose');
  });
}

/// 该行内可见的摘要文本数量（推理摘要 + 工具摘要共用同一层）。
List<Text> _summaryTexts(String rowId) {
  return find
      .descendant(
        of: find.byKey(StudioDriverKeys.timelineRow(rowId)),
        matching: find.byType(Text),
      )
      .evaluate()
      .map((element) => element.widget as Text)
      .toList(growable: false);
}

int _pendingSaveIconCount(String rowId) {
  // Visibility 保留占位时图标仍在树里，但不可命中；提示只在真正可见时算存在。
  return find
      .descendant(
        of: find.byKey(StudioDriverKeys.timelineRow(rowId)),
        matching: find.byIcon(Icons.cloud_upload_outlined).hitTestable(),
      )
      .evaluate()
      .length;
}

Widget _timeline(List<TimelineRow> rows) {
  return TimelineView(
    threadId: 'thread-main',
    rows: rows,
    body: const ThreadHistoryWindow(),
    turn: null,
    onCommand: (_) {},
    hasOlder: false,
    hasNewer: false,
    canExtendLatest: false,
  );
}

Widget _harness(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(height: 640, child: child)),
    ),
  );
}

TimelineRow _reasoningRow(List<String> summaries) {
  final now = DateTime.utc(2026);
  return TimelineRowProjector().project([
    for (final entry in summaries.indexed)
      ThreadItemView(
        id: 'reasoning-${entry.$1}',
        threadId: 'thread-main',
        turnId: 'turn-1',
        ordinal: entry.$1,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        state: ThreadThinkingItemStateView(
          summary: [entry.$2],
          content: const [],
          lifecycle: const StreamingThreadContentView(),
        ),
      ),
  ]).single;
}

TimelineRow _toolGroupRow(List<String> commands) {
  final now = DateTime.utc(2026);
  return TimelineRowProjector().project([
    for (final entry in commands.indexed)
      ThreadItemView(
        id: 'tool-${entry.$1}',
        threadId: 'thread-main',
        turnId: 'turn-1',
        ordinal: entry.$1,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        state: ThreadToolItemStateView(
          invocation: ThreadToolInvocationView(
            toolCallId: 'call-${entry.$1}',
            name: 'exec_command',
            arguments: jsonEncode({'command': entry.$2}),
          ),
          lifecycle: const RunningThreadToolView(''),
        ),
      ),
  ]).single;
}

TimelineRow _textRow(
  String id,
  String text, {
  bool saved = true,
  String threadId = 'thread-main',
}) {
  final now = DateTime.utc(2026, 1, 1);
  final item = ThreadItemView(
    id: id,
    threadId: threadId,
    turnId: 'turn-1',
    ordinal: 0,
    revision: 1,
    createdAt: now,
    updatedAt: now,
    saved: saved,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.finalAnswer,
      text: text,
      attachments: const [],
      lifecycle: CompletedThreadContentView(now),
    ),
  );
  return TimelineTextRow(
    item: item,
    part: TimelineEntry(
      id: id,
      groupId: 'turn-1',
      type: TimelineEntryType.text,
      text: text,
      threadId: threadId,
      turnId: 'turn-1',
      textChannel: TimelineTextChannel.finalAnswer,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

List<TimelineRow> _threadRows(String threadId, int revision) {
  return [
    for (var index = 0; index < 32; index += 1)
      _textRow(
        '$threadId/item-$index',
        '$threadId row $index revision $revision\n\n'
            '正文包含中文、`code` 和多段文本。',
        threadId: threadId,
      ),
  ];
}
