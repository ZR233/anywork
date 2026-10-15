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
  final now = DateTime.utc(2026, 1, 1);
  return TimelineRow.reasoningGroup(
    TimelineReasoningGroup(
      id: 'reasoning-group:turn-1',
      threadId: 'thread-main',
      groupId: 'turn-1',
      turnId: 'turn-1',
      parts: [
        for (var index = 0; index < summaries.length; index++)
          TimelineEntry(
            id: 'reasoning-$index',
            groupId: 'turn-1',
            type: TimelineEntryType.reasoning,
            text: summaries[index],
            threadId: 'thread-main',
            turnId: 'turn-1',
            order: index,
            sequence: index,
            status: 'running',
            createdAt: now,
            updatedAt: now,
          ),
      ],
    ),
  );
}

TimelineRow _toolGroupRow(List<String> commands) {
  final now = DateTime.utc(2026, 1, 1);
  return TimelineRow.toolGroup(
    TimelineToolGroup(
      id: 'tool-group:turn-1',
      threadId: 'thread-main',
      groupId: 'turn-1',
      turnId: 'turn-1',
      items: [
        for (var index = 0; index < commands.length; index++)
          TimelineToolGroupItem(
            part: TimelineEntry(
              id: 'tool-$index',
              groupId: 'turn-1',
              type: TimelineEntryType.tool,
              text: '',
              threadId: 'thread-main',
              turnId: 'turn-1',
              order: index,
              sequence: index,
              status: 'running',
              createdAt: now,
              updatedAt: now,
              tool: TimelineToolPart(
                toolCallId: 'call-$index',
                name: 'exec_command',
                arguments: jsonEncode({'command': commands[index]}),
              ),
            ),
          ),
      ],
    ),
  );
}

TimelineRow _textRow(String id, String text, {bool saved = true}) {
  final now = DateTime.utc(2026, 1, 1);
  final item = ThreadItemView(
    id: id,
    threadId: 'thread-main',
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
  return TimelineRow.item(
    item: item,
    part: TimelineEntry(
      id: id,
      groupId: 'turn-1',
      type: TimelineEntryType.text,
      text: text,
      threadId: 'thread-main',
      turnId: 'turn-1',
      textChannel: TimelineTextChannel.finalAnswer,
      createdAt: now,
      updatedAt: now,
    ),
    type: TimelineRowType.finalAnswer,
  );
}
