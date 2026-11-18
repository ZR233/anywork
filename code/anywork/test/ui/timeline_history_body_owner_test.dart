import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_item_content.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_canonical_payload_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_content_range_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('historical tool reads semantic input and disclosed output', (
    tester,
  ) async {
    final bodies = {
      'tool.arguments': utf8.encode('{"taskIds":["task"],"timeoutMs":60000}'),
      'tool.result': utf8.encode(
        '{"tasks":[{"taskId":"task","status":"succeeded"}],"timedOut":false}',
      ),
    };
    final member = DisplayRecord(
      historyEventId: 'event',
      contentSource: const CompletedOriginal(completionId: 'event'),
      atom: ChatAtom(
        id: 'tool',
        sourceOrder: null,
        source: const ForegroundTurnChatSource(turnId: 'turn'),
        kind: ChatAtomKind.toolCall,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        ),
        tool: const ChatToolIdentity(callId: 'call', name: 'wait'),
        contents: const [],
      ),
    );
    final unit = TimelineDisplayUnit(
      block: const DisplayBlock(
        id: 'work-row',
        blockOrder: 1,
        body: WorkDisplayBlock(
          timing: WorkTiming(startedAt: null),
          members: DisplayBlockRef(
            blockId: 'work',
            cut: HistoryCut('fixed-cut'),
            anchorSeq: 1,
            headSeq: 1,
          ),
          executionPresent: false,
          memberCount: 1,
          unfinishedCount: 0,
          groupClosed: true,
        ),
      ),
    );
    unit.expansion.current = unit;
    final reads = <String>[];
    unit.expansion.readHistoryBody = (generation, reference, range) async {
      expect(identical(generation, unit.expansion.bodyGeneration), isTrue);
      expect(reference.ownerEventId, 'event');
      expect(range.offset, 0);
      reads.add(reference.bodyKey);
      final bytes = bodies[reference.bodyKey]!;
      return ContentWindow(
        offset: 0,
        bytes: bytes,
        generation: reference.bodyId,
        availableThrough: bytes.length,
        sealed: true,
      );
    };
    final item = ChatItemPresentation.forRecord(member, id: 'wait-row')
        .resolvePayload(
          InlinePayload(
            bytes: utf8.encode(
              jsonEncode({
                'contract': 'anywork.chat/1',
                'type': 'tool',
                'data': {
                  'invocation': {
                    'toolCallId': 'call',
                    'name': 'wait',
                    'presentationContract': 'builtin.wait@1',
                  },
                  'state': {
                    'kind': 'succeeded',
                    'output': {'attachments': []},
                  },
                  'wait': {
                    'state': 'ready',
                    'messagesReady': true,
                    'intent': {
                      'kind': 'events',
                      'data': {
                        'targets': [
                          {
                            'taskId': 'task',
                            'toolName': 'exec',
                            'status': 'succeeded',
                          },
                        ],
                        'timeoutMs': 60000,
                      },
                    },
                  },
                },
                'bodies': [
                  for (final entry in bodies.entries)
                    {
                      'key': entry.key,
                      'byteLength': entry.value.length,
                      'reference': {
                        'databaseId': 'db',
                        'ownerEventId': 'event',
                        'bodyKey': entry.key,
                        'bodyId': entry.key,
                        'byteStart': 0,
                        'byteLength': entry.value.length,
                      },
                    },
                ],
              }),
            ),
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimelineDisplayUnitView(
              unit: unit,
              childBuilder: (_) => ChatItemView(item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('completion-run-header:work-row')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimelineWaitPanel), findsOneWidget);
    expect(reads, ['tool.arguments']);
    await tester.tap(find.byKey(StudioDriverKeys.waitingCard('wait-row')));
    await tester.pumpAndSettle();
    expect(reads, ['tool.arguments']);
    await tester.tap(
      find.byKey(StudioDriverKeys.waitingDiagnostics('wait-row')),
    );
    await tester.pumpAndSettle();
    expect(reads, ['tool.arguments', 'tool.result']);
    final output = tester
        .widgetList<TimelineContentRangeView>(
          find.byType(TimelineContentRangeView),
        )
        .singleWhere((view) => view.contentKey == 'tool.result');
    expect(output.window?.bytes, bodies['tool.result']);
    expect(find.textContaining('"timedOut"'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('completion-run-header:work-row')),
    );
    expect(unit.expansion.bodyActive, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(TimelineWaitPanel), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(unit.expansion.bodyActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final (source, failed) in <(ChatSourceId, bool)>[
    (const ForegroundTurnChatSource(turnId: 'turn'), false),
    (const InputChatSource(inputId: 'input'), false),
    (const InputChatSource(inputId: 'input'), true),
  ]) {
    testWidgets(
      'resolved historical ${source.runtimeType} keeps its body read owner (failed=$failed)',
      (tester) async {
        const text = '独立历史正文🙂';
        final bytes = utf8.encode(text);
        final transferred = source is InputChatSource;
        final prefix = utf8.encode('独立历史');
        final unit = TimelineDisplayUnit(
          block: DisplayBlock(
            id: 'row',
            blockOrder: 1,
            body: SingleDisplayBlock(
              visibility: HistorySingleVisibility.content,
              record: DisplayRecord(
                historyEventId: 'event',
                contentSource: const CompletedOriginal(completionId: 'event'),
                atom: ChatAtom(
                  id: 'entity',
                  sourceOrder: null,
                  source: source,
                  kind: source is InputChatSource
                      ? ChatAtomKind.input
                      : ChatAtomKind.text,
                  delivery: ChatDeliveryKind.independent,
                  lifecycle: const TerminalChatAtom(
                    started: null,
                    ended: null,
                    outcome: ChatTerminalOutcome.completed,
                  ),
                  contentPresent: true,
                  contents: const [],
                ),
              ),
            ),
          ),
        );
        unit.expansion.current = unit;
        var reads = 0;
        unit.expansion.readHistoryBody = (generation, reference, range) async {
          expect(identical(generation, unit.expansion.bodyGeneration), isTrue);
          expect(reference.ownerEventId, 'event');
          expect(range.offset, transferred ? prefix.length : 0);
          reads++;
          return ContentWindow(
            offset: range.offset,
            bytes: bytes.sublist(range.offset),
            generation: reference.bodyId,
            availableThrough: bytes.length,
            sealed: true,
          );
        };
        final item = ChatItemPresentation.forUnit(unit).resolvePayload(
          InlinePayload(
            bytes: utf8.encode(
              jsonEncode({
                'contract': 'anywork.chat/1',
                'type': 'text',
                'data': {
                  'channel': source is InputChatSource ? 'user' : 'final',
                  'attachments': <Object?>[],
                },
                'bodies': [
                  {
                    'key': 'body',
                    'byteLength': bytes.length,
                    'reference': {
                      'databaseId': 'db',
                      'ownerEventId': 'event',
                      'bodyKey': 'body',
                      'bodyId': 'body-id',
                      'byteStart': 0,
                      'byteLength': bytes.length,
                    },
                  },
                ],
              }),
            ),
          ),
        );
        final original = ChatItemPresentation.forUnit(unit);
        final prototype = ChatItemPresentation.forRecord(
          (unit.body as SingleDisplayBlock).record,
          id: unit.id,
        ).resolvePresentation(item);
        final body = transferred
            ? TimelineInitialHistoryContent(
                content: (
                  identity: timelineHistoryItemIdentity(prototype),
                  result: AsyncSnapshot.withData(
                    ConnectionState.done,
                    TimelineHistoryItemContent(
                      item: prototype,
                      bodyReads: {
                        historyBodyIdentity(
                          item.bodies.single.historyReference!,
                        ): failed
                            ? AsyncSnapshot.withError(
                                ConnectionState.done,
                                StateError('history body unavailable'),
                              )
                            : AsyncSnapshot.withData(
                                ConnectionState.done,
                                ContentWindow(
                                  offset: 0,
                                  bytes: prefix,
                                  generation: 'original-window',
                                  availableThrough: bytes.length,
                                  sealed: true,
                                ),
                              ),
                      },
                    ),
                  ),
                ),
                child: TimelineCanonicalPayloadConnector(
                  item: original,
                  threadId: 'thread',
                  isActive: () => true,
                  openHistory: () =>
                      throw StateError('unexpected second query'),
                  render: (resolved) => ChatItemView(
                    item: resolved,
                    bodyBuilder: (_, text) => Text(text),
                  ),
                ),
              )
            : ChatItemView(item: item, bodyBuilder: (_, text) => Text(text));
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: body),
          ),
        );
        await tester.pumpAndSettle();
        if (failed) {
          expect(
            find.textContaining('history body unavailable'),
            findsOneWidget,
          );
          expect(find.text(text), findsNothing);
        } else if (transferred) {
          expect(find.text('独立历史'), findsOneWidget);
          expect(reads, 0);
          await tester.tap(
            find.byKey(
              StudioDriverKeys.timelineContentNextWindow(item.id, 'body'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('正文🙂'), findsOneWidget);
        } else {
          expect(find.text(text), findsOneWidget);
        }
        expect(reads, failed ? 0 : 1);
        await tester.pumpWidget(const SizedBox());
        expect(unit.expansion.bodyActive, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
