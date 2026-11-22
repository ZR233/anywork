import 'package:anywork/src/features/conversation/timeline/state/timeline_current_projection.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_canonical_payload_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentRef = CurrentContentRef(
  ownerId: 'run-1',
  domain: 'content',
  entityId: 'entity-1',
  contentKey: 'body',
  generation: '3',
);

CurrentAtom _atom() => CurrentAtom(
  id: 'entity-1',
  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
  sourceOrder: 1,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-1',
  contentPresent: true,
  contents: const [
    CurrentAtomContent(role: ChatContentRole.body, reference: _currentRef),
  ],
);

DisplayBlock _history({
  bool isTerminalHistory = false,
  bool isFrozenHistory = false,
}) => DisplayBlock(
  id: 'single:entity-1',
  blockOrder: 7,
  body: SingleDisplayBlock(
    visibility: HistorySingleVisibility.content,
    record: DisplayRecord(
      atom: ChatAtom(
        id: 'entity-1',
        source: const ForegroundTurnChatSource(turnId: 'turn-1'),
        sourceOrder: 1,
        kind: ChatAtomKind.text,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const TerminalChatAtom(
          started: null,
          ended: null,
          outcome: ChatTerminalOutcome.completed,
        ),
        turnId: 'turn-1',
        contentPresent: true,
        contents: const [],
      ),
      contentSource: const CompletedOriginal(completionId: 'event-1'),
      historyEventId: 'event-1',
      historyDetailEventId: 'detail-1',
      runId: 'run-1',
      isTerminalHistory: isTerminalHistory,
      isFrozenHistory: isFrozenHistory,
    ),
  ),
);

void main() {
  test(
    'Current enriches an existing stable History row without a parallel row',
    () {
      final history = _history();
      final result = TimelineCurrentProjection.overlayHistory(
        [history],
        atoms: [_atom()],
        ownerId: 'run-1',
      );

      expect(result, hasLength(1));
      expect(result.single.id, history.id);
      final body = result.single.body as SingleDisplayBlock;
      expect(body.record.contentSource, isA<CurrentAtomSource>());
      expect(body.record.currentContents.single.reference, _currentRef);
      expect(body.record.historyEventId, isNull);
      expect(body.record.historyDetailEventId, isNull);
      expect(body.record.immutableRecord?.historyEventId, 'event-1');

      final restored = TimelineCurrentProjection.overlayHistory(
        result,
        atoms: const [],
        ownerId: 'run-1',
      ).single;
      final restoredBody = restored.body as SingleDisplayBlock;
      expect(restoredBody.record.historyEventId, 'event-1');
      expect(restoredBody.record.currentContents, isEmpty);
      expect(restoredBody.record.contentSource, isA<CompletedOriginal>());
    },
  );

  test(
    'Current without a loaded History anchor creates no guessed timeline row',
    () {
      expect(
        TimelineCurrentProjection.overlayHistory(
          const [],
          atoms: [_atom()],
          ownerId: 'run-1',
        ),
        isEmpty,
      );
    },
  );

  test(
    'terminal and BoundaryObserved History rows never accept late Current',
    () {
      final history = _history();
      for (final protected in [
        _history(isTerminalHistory: true),
        _history(isFrozenHistory: true),
      ]) {
        final result = TimelineCurrentProjection.overlayHistory(
          [protected],
          atoms: [_atom()],
          ownerId: 'run-1',
        );
        expect(result.single, same(protected));
      }

      final olderRun = TimelineCurrentProjection.overlayHistory(
        [history],
        atoms: [_atom()],
        ownerId: 'run-2',
      );
      expect(olderRun.single, same(history));
    },
  );

  testWidgets(
    'Current raw body is rendered by its body owner, not JSON decode',
    (tester) async {
      final record = DisplayRecord(
        atom: _atomAsChatAtom(),
        contentSource: const CurrentAtomSource(),
        currentContents: const [
          CurrentAtomContent(
            role: ChatContentRole.body,
            reference: _currentRef,
          ),
        ],
      );
      final item = ChatItemPresentation.forRecord(record, id: 'entity-1');
      var rendered = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TimelineCanonicalPayloadConnector(
            item: item,
            threadId: 'thread',
            isActive: () => true,
            render: (_) {
              rendered++;
              return const Text('raw-current-body-owner');
            },
          ),
        ),
      );
      expect(rendered, 1);
      expect(find.text('raw-current-body-owner'), findsOneWidget);
      expect(find.textContaining('正在读取'), findsNothing);
    },
  );
}

ChatAtom _atomAsChatAtom() => ChatAtom(
  id: 'entity-1',
  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
  sourceOrder: 1,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-1',
  contentPresent: true,
  contents: const [],
);
