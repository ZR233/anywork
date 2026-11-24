import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_canonical_payload_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_current_projection.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_projection.dart';
import 'package:anywork/src/features/conversation/timeline/state/work_group_event_folder.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestHistoryReader;

const _cut = HistoryCut('folder-cut-1');

HistoryEventRecord _toolEvent({
  required int seq,
  required String eventId,
  required String kind,
  required String callId,
  required String toolName,
  required Map<String, Object?> stateMeta,
  required Map<String, Object?> stateData,
  String? presentationContract,
  Map<String, Object?>? extraInvocation,
  List<Map<String, Object?>> bodies = const [],
  String? runId = 'run-1',
  int? startedAt,
  int? finishedAt,
}) {
  final entityId = 'tool:${callId.length}:$callId';
  return HistoryEventRecord(
    seq: seq,
    eventId: eventId,
    kind: kind,
    timelineRole: HistoryTimelineRole.work,
    occurredAt: finishedAt ?? startedAt ?? seq * 1000,
    recordedAt: seq * 1000,
    runId: runId,
    turnId: 'turn-1',
    callId: callId,
    entityId: entityId,
    toolName: toolName,
    source: const ForegroundTurnChatSource(turnId: 'turn-1'),
    payloadSchema: 'anywork.event/1',
    payloadJson: jsonEncode({
      'contract': 'anywork.event/1',
      'type': 'tool',
      'meta': {
        'entityId': entityId,
        'entityKind': 'toolCall',
        'delivery': 'foreground',
        'state': stateMeta,
        'startedAt': ?startedAt,
        'finishedAt': ?finishedAt,
        'contentPresent': bodies.isNotEmpty,
        'presentationContract': ?presentationContract,
        'tool': {'callId': callId, 'name': toolName},
      },
      'data': {
        'invocation': {
          'toolCallId': callId,
          'name': toolName,
          'presentationContract': ?presentationContract,
          ...?extraInvocation,
        },
        'state': stateData,
      },
      'bodies': bodies,
    }),
  );
}

HistoryEventRecord _textEvent({
  required int seq,
  required String eventId,
  required String text,
  HistoryTimelineRole role = HistoryTimelineRole.divider,
  HistoryEventBodyRef? reference,
  String channel = 'final',
}) {
  return HistoryEventRecord(
    seq: seq,
    eventId: eventId,
    kind: 'text_completed',
    timelineRole: role,
    occurredAt: seq * 1000,
    recordedAt: seq * 1000,
    turnId: 'turn-1',
    entityId: eventId,
    rowKey: 'row:$eventId',
    source: const ForegroundTurnChatSource(turnId: 'turn-1'),
    payloadSchema: 'anywork.event/1',
    payloadJson: jsonEncode({
      'contract': 'anywork.event/1',
      'type': 'text',
      'meta': {
        'entityId': eventId,
        'entityKind': 'text',
        'delivery': 'foreground',
        'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
        'textChannel': channel == 'final' ? 'finalAnswer' : channel,
        'contentPresent': true,
      },
      'data': {'channel': channel},
      'bodies': [
        {
          'key': 'body',
          'role': 'body',
          'byteLength': utf8.encode(text).length,
          if (reference == null) 'inlineText': text,
          if (reference != null)
            'reference': {
              'databaseId': reference.databaseId,
              'ownerEventId': reference.ownerEventId,
              'bodyKey': reference.bodyKey,
              'bodyId': reference.bodyId,
              'byteStart': reference.byteStart,
              'byteLength': reference.byteLength,
            },
        },
      ],
    }),
  );
}

Widget _appHost(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

final class _SpyHistoryReader extends TestHistoryReader {
  _SpyHistoryReader({HistoryCut? cut})
    : super(threadId: 'thread-1', cut: cut ?? _cut);

  int readEventCalls = 0;
  int readBodyCalls = 0;
  int eventsPageCalls = 0;
  int workRangeCalls = 0;
  final Map<String, HistoryBodyWindow> bodyWindows = {};

  @override
  Future<HistoryWorkRangePage> workRangePage({
    int? afterSeq,
    int? beforeSeq,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    workRangeCalls++;
    return super.workRangePage(
      afterSeq: afterSeq,
      beforeSeq: beforeSeq,
      cut: cut,
      cursor: cursor,
      demand: demand,
    );
  }

  @override
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) {
    eventsPageCalls++;
    return super.eventsPage(
      query: query,
      cut: cut,
      cursor: cursor,
      demand: demand,
    );
  }

  @override
  Future<HistoryEventRecord> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) {
    readEventCalls++;
    return Future.error(StateError('Unexpected readEvent call for $eventId'));
  }

  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) async {
    readBodyCalls++;
    return bodyWindows[reference.bodyId] ??
        (throw StateError('Missing spy body window for ${reference.bodyId}'));
  }
}

void main() {
  test('4-stage call_id folds into one row at firstSeq and retires Current upon terminal event', () {
    const callId = 'call_4_stage';
    final called = _toolEvent(
      seq: 1,
      eventId: 'ev-1',
      kind: 'tool_called',
      callId: callId,
      toolName: 'exec',
      presentationContract: 'builtin.exec@2',
      startedAt: 1_785_000_000_000,
      stateMeta: const {'kind': 'knownActive', 'status': 'running'},
      stateData: const {'kind': 'running'},
      bodies: const [
        {
          'key': 'tool.arguments',
          'role': 'toolArguments',
          'byteLength': 20,
          'inlineText': '{"command":"echo hi"}',
        },
      ],
    );
    final waiting = _toolEvent(
      seq: 2,
      eventId: 'ev-2',
      kind: 'tool_waiting_approval',
      callId: callId,
      toolName: 'exec',
      presentationContract: 'builtin.exec@2',
      stateMeta: const {'kind': 'knownActive', 'status': 'waiting'},
      stateData: const {'kind': 'waitingApproval'},
    );
    final backgrounded = _toolEvent(
      seq: 3,
      eventId: 'ev-3',
      kind: 'tool_backgrounded',
      callId: callId,
      toolName: 'exec',
      presentationContract: 'builtin.exec@2',
      stateMeta: const {'kind': 'knownTerminal', 'outcome': 'transferred'},
      stateData: const {'kind': 'backgroundStarted'},
    );
    final completed = _toolEvent(
      seq: 4,
      eventId: 'ev-4',
      kind: 'tool_completed',
      callId: callId,
      toolName: 'exec',
      presentationContract: 'builtin.exec@2',
      finishedAt: 1_785_000_005_000,
      stateMeta: const {'kind': 'knownTerminal', 'outcome': 'completed'},
      stateData: const {
        'kind': 'succeeded',
        'completedAt': 1_785_000_005,
        'output': {'exitCode': 0},
      },
      bodies: const [
        {
          'key': 'tool.result',
          'role': 'toolOutput',
          'byteLength': 3,
          'inlineText': 'hi\n',
        },
      ],
    );

    final liveAtom = CurrentAtom(
      id: 'tool:12:$callId',
      source: const ForegroundTurnChatSource(turnId: 'turn-1'),
      sourceOrder: 1,
      kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      tool: const ChatToolIdentity(callId: callId, name: 'exec'),
      contents: const [
        CurrentAtomContent(
          role: ChatContentRole.toolOutput,
          reference: CurrentContentRef(
            ownerId: 'run-1',
            domain: 'tool',
            entityId: 'tool:12:$callId',
            contentKey: 'tool.result',
            generation: '1',
          ),
        ),
      ],
    );

    // Before terminal event arrives, active row accepts Current overlay.
    final activeFold = WorkGroupEventFolder.fold(
      rangeEvents: [called, waiting],
    );
    DisplayRecord overlay(DisplayRecord record) =>
        TimelineCurrentProjection.overlayRecord(
          record,
          current: {liveAtom.id: liveAtom},
          currentByCall: {callId: liveAtom},
          ownerId: 'run-1',
          fallbackRunId: 'run-1',
        );
    expect(activeFold.missingCallIds, isEmpty);
    expect(activeFold.entries, hasLength(1));
    expect(activeFold.entries.single.memberKey, 'call:$callId');
    expect(activeFold.entries.single.memberOrder, 1);
    expect(
      overlay(activeFold.entries.single.record).contentSource,
      isA<CurrentAtomSource>(),
    );
    expect(activeFold.entries.single.record.isTerminalHistory, isFalse);

    // Once terminal event is folded, Current overlay immediately retires even on an open tail.
    final terminalFold = WorkGroupEventFolder.fold(
      rangeEvents: [called, waiting, backgrounded, completed],
    );
    expect(terminalFold.missingCallIds, isEmpty);
    expect(terminalFold.entries, hasLength(1));
    final entry = terminalFold.entries.single;
    expect(entry.memberKey, 'call:$callId');
    expect(entry.memberOrder, 1);
    expect(entry.record.isTerminalHistory, isTrue);
    expect(overlay(entry.record), same(entry.record));
    expect(entry.record.contentSource, isA<CompletedOriginal>());
    expect(entry.record.currentContents, isEmpty);

    final presentation = ChatItemPresentation.forRecord(
      entry.record,
      id: entry.memberKey,
    );
    final toolCard = presentation.toolCard;
    expect(toolCard, isA<DecodedToolCard>());
    final decoded = (toolCard as DecodedToolCard).value;
    expect(decoded.presentationContract, 'builtin.exec@2');
    expect(decoded.statusString, 'succeeded');
    expect(decoded.arguments, '{"command":"echo hi"}');
    expect(decoded.output, 'hi\n');
    expect(decoded.exitCode, 0);
  });

  test('cross-divider missing tool_called triggers CallHistoryEvents backfill at in-range firstSeq', () async {
    const callId = 'cross_divider_call';
    final reader = _SpyHistoryReader()
      ..onWorkRange = (afterSeq, beforeSeq, cut, cursor, demand) async {
        expect(afterSeq, 5);
        expect(beforeSeq, isNull);
        return HistoryWorkRangePage(
          cut: _cut,
          afterSeq: afterSeq,
          beforeSeq: beforeSeq,
          events: [
            _toolEvent(
              seq: 10,
              eventId: 'ev-10',
              kind: 'tool_completed',
              callId: callId,
              toolName: 'exec',
              stateMeta: const {
                'kind': 'knownTerminal',
                'outcome': 'completed',
              },
              stateData: const {
                'kind': 'succeeded',
                'output': {'exitCode': 0},
              },
              bodies: const [
                {
                  'key': 'tool.result',
                  'role': 'toolOutput',
                  'byteLength': 4,
                  'inlineText': 'done',
                },
              ],
            ),
          ],
        );
      }
      ..onEvents = (query, cut, cursor, demand) async {
        expect(query, isA<CallHistoryEvents>());
        expect((query as CallHistoryEvents).callId, callId);
        return HistoryEventsPage(
          cut: _cut,
          entries: [
            _toolEvent(
              seq: 3,
              eventId: 'ev-3',
              kind: 'tool_called',
              callId: callId,
              toolName: 'exec',
              presentationContract: 'builtin.exec@2',
              startedAt: 1_785_000_000_000,
              stateMeta: const {'kind': 'knownActive', 'status': 'running'},
              stateData: const {'kind': 'running'},
              bodies: const [
                {
                  'key': 'tool.arguments',
                  'role': 'toolArguments',
                  'byteLength': 17,
                  'inlineText': '{"command":"pwd"}',
                },
              ],
            ),
          ],
        );
      };

    final scope = HistoryReadScope(
      threadId: 'thread-1',
      generation: 1,
      reader: reader,
      isEligible: () => true,
    );
    final members = await HistoryWorkRangeMembers.open(
      scope,
      reference: const DisplayBlockRef(
        blockId: 'work:10',
        cut: _cut,
        anchorSeq: 10,
        headSeq: 10,
        afterSeq: 5,
        beforeSeq: null,
      ),
      demand: const ReadDemand(maxItems: 16, maxBytes: 64 * 1024),
    );

    final batch = await members.next();
    expect(batch, isNotNull);
    expect(batch!.complete, isTrue);
    expect(batch.entries, hasLength(1));
    final entry = batch.entries.single;
    expect(entry.memberKey, 'call:$callId');
    expect(entry.memberOrder, 10);
    expect(reader.workRangeCalls, 1);
    expect(reader.eventsPageCalls, 1);

    final presentation = ChatItemPresentation.forRecord(
      entry.record,
      id: entry.memberKey,
    );
    final decoded = (presentation.toolCard as DecodedToolCard).value;
    expect(decoded.presentationContract, 'builtin.exec@2');
    expect(decoded.arguments, '{"command":"pwd"}');
    expect(decoded.output, 'done');

    await members.close();
    await scope.close();
  });

  testWidgets(
    'single unknown payload_schema or malformed payload_json degrades per-row without affecting siblings',
    (tester) async {
      final goodDivider = DividerTimelineItem(
        _textEvent(seq: 1, eventId: 'ev-good', text: 'healthy sibling row'),
      );
      final unknownSchemaDivider = DividerTimelineItem(
        HistoryEventRecord(
          seq: 2,
          eventId: 'ev-unknown-schema',
          kind: 'future_event',
          timelineRole: HistoryTimelineRole.divider,
          recordedAt: 2000,
          payloadSchema: 'anywork.future/99',
          payloadJson: '{"future":true}',
        ),
      );
      final malformedJsonDivider = DividerTimelineItem(
        HistoryEventRecord(
          seq: 3,
          eventId: 'ev-malformed',
          kind: 'text_completed',
          timelineRole: HistoryTimelineRole.divider,
          recordedAt: 3000,
          payloadSchema: 'anywork.event/1',
          payloadJson: '{broken json',
        ),
      );

      final blocks = TimelineHistoryProjection.blocks([
        goodDivider,
        unknownSchemaDivider,
        malformedJsonDivider,
      ], cut: _cut);
      expect(blocks, hasLength(3));

      final foldResult = WorkGroupEventFolder.fold(
        rangeEvents: [
          _textEvent(
            seq: 10,
            eventId: 'w-good',
            text: 'healthy work member',
            role: HistoryTimelineRole.work,
          ),
          unknownSchemaDivider.event,
        ],
      );
      expect(foldResult.entries, hasLength(2));

      final items = [
        for (final block in blocks)
          ChatItemPresentation.forRecord(
            (block.body as SingleDisplayBlock).record,
            id: block.id,
          ),
      ];
      expect(items[0].compatibility, ChatItemCompatibility.current);
      expect(items[1].compatibility, ChatItemCompatibility.unknown);
      expect(items[2].compatibility, ChatItemCompatibility.malformed);

      await tester.pumpWidget(
        _appHost(
          Column(
            children: [
              for (final item in items)
                ChatItemView(item: item, isDisplayActive: () => true),
            ],
          ),
        ),
      );

      expect(find.text('healthy sibling row'), findsOneWidget);
      expect(find.text('未知内容格式'), findsOneWidget);
      expect(find.text('内容格式错误'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('unregistered future presentationContract falls back to generic@1 tool display', () {
    final event = _toolEvent(
      seq: 1,
      eventId: 'ev-future-tool',
      kind: 'tool_completed',
      callId: 'call_future',
      toolName: 'my_future_tool',
      presentationContract: 'future.unknown_tool@9',
      finishedAt: 1_785_000_002_000,
      stateMeta: const {'kind': 'knownTerminal', 'outcome': 'completed'},
      stateData: const {'kind': 'succeeded', 'output': <String, Object?>{}},
      bodies: const [
        {
          'key': 'tool.arguments',
          'role': 'toolArguments',
          'byteLength': 7,
          'inlineText': '{"x":1}',
        },
        {
          'key': 'tool.result',
          'role': 'toolOutput',
          'byteLength': 13,
          'inlineText': 'future result',
        },
      ],
    );
    final presentation = ChatItemPresentation.decodeEventRecord(event);
    final card = presentation.toolCard;
    expect(card, isA<DecodedToolCard>());
    final tool = (card as DecodedToolCard).value;
    expect(tool.presentationContract, 'generic@1');
    expect(tool.name, 'my_future_tool');
    expect(tool.arguments, '{"x":1}');
    expect(tool.output, 'future result');
  });

  testWidgets(
    '<=16 KiB inline body renders synchronously with 0 readEvent/readBody RPCs; >16 KiB body loads via readBody',
    (tester) async {
      final reader = _SpyHistoryReader();
      final largeText = 'L' * 20000;
      final largeBytes = utf8.encode(largeText);
      const largeRef = HistoryEventBodyRef(
        databaseId: 'db-1',
        ownerEventId: 'ev-large',
        bodyKey: 'body',
        bodyId: 'body-large-1',
        byteStart: 0,
        byteLength: 20000,
      );
      reader.bodyWindows['body-large-1'] = HistoryBodyWindow(
        offset: 0,
        bytes: largeBytes,
        totalLength: largeBytes.length,
        mediaType: 'text/plain; charset=utf-8',
      );
      final scope = HistoryReadScope(
        threadId: 'thread-1',
        generation: 1,
        reader: reader,
        isEligible: () => true,
      );

      final inlineBlock = TimelineHistoryProjection.block(
        DividerTimelineItem(
          _textEvent(seq: 1, eventId: 'ev-inline', text: 'hello <= 16k'),
        ),
        cut: _cut,
      );
      final inlineItem = ChatItemPresentation.forRecord(
        (inlineBlock.body as SingleDisplayBlock).record,
        id: inlineBlock.id,
      );
      expect(inlineItem.needsHistoryBodyLoad, isFalse);

      await tester.pumpWidget(
        _appHost(
          TimelineCanonicalPayloadConnector(
            item: inlineItem,
            threadId: 'thread-1',
            isActive: () => true,
            openHistory: () => scope,
            render: (resolved) =>
                ChatItemView(item: resolved, isDisplayActive: () => true),
          ),
        ),
      );
      expect(find.text('hello <= 16k'), findsOneWidget);
      expect(reader.readEventCalls, 0);
      expect(reader.readBodyCalls, 0);

      final largeBlock = TimelineHistoryProjection.block(
        DividerTimelineItem(
          _textEvent(
            seq: 2,
            eventId: 'ev-large',
            text: largeText,
            reference: largeRef,
          ),
        ),
        cut: _cut,
      );
      final largeUnit = TimelineDisplayUnit(block: largeBlock);
      largeUnit.expansion.current = largeUnit;
      largeUnit.expansion.setBodyVisible(largeUnit, true);
      addTearDown(largeUnit.expansion.dispose);
      final largeItem = ChatItemPresentation.forRecord(
        (largeBlock.body as SingleDisplayBlock).record,
        id: largeBlock.id,
      );
      expect(largeItem.needsHistoryBodyLoad, isTrue);

      await tester.pumpWidget(
        _appHost(
          TimelineGroupBodyIntent(
            intent: largeUnit.expansion,
            child: TimelineCanonicalPayloadConnector(
              item: largeItem,
              threadId: 'thread-1',
              isActive: () => true,
              openHistory: () => scope,
              render: (resolved) =>
                  ChatItemView(item: resolved, isDisplayActive: () => true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(reader.readEventCalls, 0);
      expect(reader.readBodyCalls, 1);
      expect(find.textContaining('LLLLLLLLLL'), findsOneWidget);
      await scope.close();
    },
  );
}
