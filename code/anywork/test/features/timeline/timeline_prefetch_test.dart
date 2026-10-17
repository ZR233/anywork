import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('不足一屏且没有可加载历史时，不反复发出 extendLatest', (tester) async {
    final commands = <TimelineCommand>[];
    final row = _textRow('item-1', '短消息');

    Widget view({required bool loading}) {
      return _harness(
        TimelineView(
          threadId: 'thread-main',
          rows: [row],
          body: const ThreadHistoryWindow(),
          turn: null,
          isLoadingOlder: loading,
          hasOlder: false,
          hasNewer: false,
          canExtendLatest: false,
          onCommand: commands.add,
        ),
      );
    }

    await tester.pumpWidget(view(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(view(loading: true));
    await tester.pump();
    await tester.pumpWidget(view(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(_paging(commands), isEmpty);
  });

  testWidgets('no-op 之后边界不变，不再自动补页', (tester) async {
    final commands = <TimelineCommand>[];
    final row = _textRow('item-1', '短消息');

    Widget view({required bool loading, required bool canExtend}) {
      return _harness(
        TimelineView(
          threadId: 'thread-main',
          rows: [row],
          body: const ThreadHistoryWindow(),
          turn: null,
          isLoadingOlder: loading,
          hasOlder: canExtend,
          hasNewer: false,
          canExtendLatest: canExtend,
          onCommand: commands.add,
        ),
      );
    }

    await tester.pumpWidget(view(loading: false, canExtend: true));
    await tester.pump();
    expect(_paging(commands), const [TimelineExtendLatest()]);

    await tester.pumpWidget(view(loading: true, canExtend: true));
    await tester.pump();
    await tester.pumpWidget(view(loading: false, canExtend: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(_paging(commands), const [TimelineExtendLatest()]);
  });
}

List<TimelineCommand> _paging(List<TimelineCommand> commands) {
  return [
    for (final command in commands)
      if (command is TimelineExtendLatest ||
          command is TimelineLoadOlder ||
          command is TimelineLoadNewer)
        command,
  ];
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

TimelineRow _textRow(String id, String text) {
  final now = DateTime.utc(2026, 1, 1);
  final item = ThreadItemView(
    id: id,
    threadId: 'thread-main',
    turnId: 'turn-1',
    ordinal: 0,
    revision: 1,
    createdAt: now,
    updatedAt: now,
    state: ThreadTextItemStateView(
      channel: ThreadTextChannel.user,
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
      threadId: 'thread-main',
      turnId: 'turn-1',
      textChannel: TimelineTextChannel.user,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
