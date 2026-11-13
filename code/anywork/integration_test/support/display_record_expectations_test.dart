import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'display_record_expectations.dart';
import 'display_record_observation.dart' show expectFrozenObservationPayload;

void main() {
  test(
    'available frozen public payload is current after inline or resolve',
    () {
      const text = '这段推理在正文开始后继续保持活动。';
      final body = utf8.encode(text);
      final variants = [
        (
          compatibility: ChatItemCompatibility.current,
          bytes: utf8.encode(
            jsonEncode({
              'contract': 'anywork.chat/1',
              'type': 'thinking',
              'data': <String, Object?>{},
              'bodies': [
                {'key': 'summary', 'byteLength': body.length, 'inline': body},
              ],
            }),
          ),
        ),
        (
          compatibility: ChatItemCompatibility.unknown,
          bytes: utf8.encode(
            jsonEncode({'kind': 'reasoning', 'summary': text}),
          ),
        ),
        (
          compatibility: ChatItemCompatibility.malformed,
          bytes: utf8.encode('{invalid JSON'),
        ),
      ];
      for (final variant in variants) {
        for (final deferred in [false, true]) {
          final record = _frozen(
            payload: variant.bytes,
            displayPayload: deferred
                ? DeferredPayload(
                    reference: _reference('member-a'),
                    byteLength: variant.bytes.length,
                  )
                : null,
          );
          var value = ChatItemPresentation.decode(
            record.atom,
            record: record,
            displayId: 'frozen-row',
          );
          if (deferred) {
            expect(value.compatibility, ChatItemCompatibility.deferred);
            value = value.resolvePayload(InlinePayload(bytes: variant.bytes));
          }
          expect(value.displayRecord, same(record));
          expect(value.compatibility, variant.compatibility);
          if (variant.compatibility == ChatItemCompatibility.current) {
            expectFrozenObservationPayload(value);
            expect(value.inlineText('summary'), text);
            expect(value.bodies.single.inline, orderedEquals(body));
          } else {
            expect(
              () => expectFrozenObservationPayload(value),
              throwsA(
                isA<TestFailure>().having(
                  (failure) => failure.message,
                  'frozen payload diagnostic',
                  allOf(
                    contains('frozen-row'),
                    contains(variant.compatibility.name),
                  ),
                ),
              ),
            );
          }
        }
      }
    },
  );

  test('image originals require the real completed or failed terminal', () {
    for (final failed in [false, true]) {
      final expected = failed
          ? ChatTerminalOutcome.failed
          : ChatTerminalOutcome.completed;
      expectImageOriginalOutcome(_atom(_terminal(expected)), failed: failed);
      for (final outcome in ChatTerminalOutcome.values.where(
        (outcome) => outcome != expected,
      )) {
        expect(
          () => expectImageOriginalOutcome(
            _atom(_terminal(outcome)),
            failed: failed,
          ),
          throwsA(isA<TestFailure>()),
          reason: 'Payload status cannot replace the real $outcome outcome',
        );
      }
      expect(
        () => expectImageOriginalOutcome(
          _atom(
            const ActiveChatAtom(
              started: null,
              status: ChatActiveStatus.running,
            ),
          ),
          failed: failed,
        ),
        throwsA(isA<TestFailure>()),
      );
    }
  });

  test(
    'frozen member rejects status, facts, metadata, time and payload drift',
    () {
      final baseline = displayRecordEvidence(_frozen());
      final saved = jsonDecode(jsonEncode(baseline));
      expect(displayRecordEvidence(_frozen()), saved);
      for (final changed in [
        _frozen(status: ChatActiveStatus.waiting),
        _frozen(startEffect: 7),
        _frozen(startedAt: 101),
        _frozen(attemptId: 'another-attempt'),
        _frozen(contentMemberKey: 'another-member'),
        _frozen(payload: [9]),
      ]) {
        expect(
          () => expect(displayRecordEvidence(changed), saved),
          throwsA(isA<TestFailure>()),
        );
      }
    },
  );

  test('frozen Work timing rejects either timestamp drifting', () {
    final saved = jsonDecode(jsonEncode(workTimingEvidence(_summary())));
    expect(workTimingEvidence(_summary()), saved);
    for (final changed in [
      _summary(startedAt: 99),
      _summary(finishedAt: 103),
      _summary(finishedAt: 104),
    ]) {
      expect(
        () => expect(workTimingEvidence(changed), saved),
        throwsA(isA<TestFailure>()),
      );
    }
  });
}

TerminalChatAtom _terminal(ChatTerminalOutcome outcome) => TerminalChatAtom(
  started: const ChatFactPosition(effectSeq: 1, suborder: 0),
  ended: const ChatFactPosition(effectSeq: 2, suborder: 0),
  outcome: outcome,
);

ChatAtom _atom(
  ChatAtomLifecycle lifecycle, {
  int startedAt = 100,
  String attemptId = 'attempt',
  String contentMemberKey = 'member-a',
  List<int> payload = const [1, 2],
  PayloadData? displayPayload,
}) => ChatAtom(
  id: 'atom-a',
  source: const ForegroundTurnChatSource(turnId: 'turn'),
  sourceOrder: 1,
  kind: ChatAtomKind.reasoning,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: lifecycle,
  turnId: 'turn',
  attemptId: attemptId,
  contentPresent: true,
  startedAt: startedAt,
  contents: [
    ChatAtomContent(
      role: ChatContentRole.reasoningSummary,
      reference: _reference(contentMemberKey),
    ),
  ],
  payload: displayPayload ?? InlinePayload(bytes: payload),
);

DisplayRecord _frozen({
  ChatActiveStatus status = ChatActiveStatus.running,
  int startEffect = 1,
  int startedAt = 100,
  String attemptId = 'attempt',
  String contentMemberKey = 'member-a',
  List<int> payload = const [1, 2],
  PayloadData? displayPayload,
}) => DisplayRecord(
  atom: _atom(
    ActiveChatAtom(
      started: ChatFactPosition(effectSeq: startEffect, suborder: 0),
      status: status,
    ),
    startedAt: startedAt,
    attemptId: attemptId,
    contentMemberKey: contentMemberKey,
    payload: payload,
    displayPayload: displayPayload,
  ),
  startFact: const ChatFactPosition(effectSeq: 1, suborder: 0),
  endFact: null,
  contentSource: const FrozenObservation(capturedAt: 102, available: true),
);

ContentRef _reference(String memberKey) => ContentRef(
  databaseId: 'db',
  target: BodyContentTarget(
    owner: DisplayObservationContentOwner(
      blockId: 'work',
      memberKey: memberKey,
    ),
    key: 'reasoningSummary',
  ),
);

WorkTiming _summary({int startedAt = 100, int finishedAt = 102}) =>
    WorkTiming(startedAt: startedAt, finishedAt: finishedAt);
