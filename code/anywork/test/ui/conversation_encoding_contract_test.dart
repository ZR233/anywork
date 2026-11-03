import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = ForegroundTurnChatSource(turnId: '轮次🐱');
  const reference = ContentRef(
    databaseId: '库',
    target: ItemPayloadTarget(itemId: '实际载荷'),
  );
  ChatAtom atom(PayloadData payload, {ChatSourceState? state}) => ChatAtom(
    id: '成员',
    completionItemId: '实际载荷',
    completionSeq: 7,
    source: source,
    sourceState: state,
    sourceOrder: 30,
    kind: ChatAtomKind.reasoning,
    delivery: ChatDeliveryKind.foreground,
    lifecycle: const TerminalChatAtom(
      started: null,
      ended: ChatFactPosition(effectSeq: 4, suborder: 1),
      outcome: ChatTerminalOutcome.completed,
    ),
    contents: const [],
    payload: payload,
  );
  // Independent wire-contract example, not a second encoder or a reflection of
  // the implementation's list of fields. FrozenNone is omission, not JSON null.
  const inlineEntry = {
    'kind': 'atom',
    'value': {
      'id': '成员',
      'completionItemId': '实际载荷',
      'completionSeq': 7,
      'source': {'kind': 'foregroundTurn', 'turnId': '轮次🐱'},
      'sourceOrder': 30,
      'kind': 'reasoning',
      'delivery': 'foreground',
      'lifecycle': {
        'kind': 'terminal',
        'started': null,
        'ended': {'effectSeq': 4, 'suborder': 1},
        'outcome': 'completed',
      },
      'turnId': null,
      'attemptId': null,
      'tool': null,
      'textChannel': null,
      'startedAt': null,
      'finishedAt': null,
      'contents': [],
      'payload': {
        'kind': 'inline',
        'bytes': [0, 34, 255],
      },
    },
  };
  test('canonical entry preserves Unicode, distinct payload identity and FrozenNone', () {
    final value = atom(InlinePayload(bytes: [0, 34, 255]));
    expect(chatEntryToJson(ChatAtomEntry(value)), inlineEntry);
    expect(chatAtomToJson(value).containsKey('sourceState'), isFalse);
    final encoded = jsonEncode(inlineEntry);
    expect(chatAtomEntryEncodedLength(value), utf8.encode(encoded).length);
    expect(chatAtomEntryEncodedLength(value), greaterThan(encoded.length));
  });
  test(
    'same-cut source annotation and Deferred retain the original capability',
    () {
      final value = atom(
        const DeferredPayload(reference: reference, byteLength: 4096),
        state: const ChatSourceState(
          source: source,
          lifecycle: EndedChatSource(outcome: ChatTerminalOutcome.failed),
          started: null,
          ended: ChatFactPosition(effectSeq: 9, suborder: 0),
        ),
      );
      final expected = {
        'kind': 'atom',
        'value': {
          ...(inlineEntry['value']! as Map<String, Object?>),
          'sourceState': {
            'source': {'kind': 'foregroundTurn', 'turnId': '轮次🐱'},
            'lifecycle': {'kind': 'ended', 'outcome': 'failed'},
            'started': null,
            'ended': {'effectSeq': 9, 'suborder': 0},
          },
          'payload': {
            'kind': 'deferred',
            'reference': {
              'databaseId': '库',
              'target': {'kind': 'itemPayload', 'itemId': '实际载荷'},
            },
            'byteLength': 4096,
          },
        },
      };
      expect(chatEntryToJson(ChatAtomEntry(value)), expected);
      expect(
        chatAtomEntryEncodedLength(value),
        utf8.encode(jsonEncode(expected)).length,
      );
    },
  );
}
