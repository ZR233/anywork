import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

const chatDemand = ReadDemand(maxItems: 20, maxBytes: 65536);

/// An explicit independent synthetic completion, not a grouping fixture.
ChatAtom fixtureAtom({required String id, required PayloadData payload}) =>
    ChatAtom(
      id: id,
      completionItemId: id,
      source: ReceiptChatSource(receiptId: id),
      sourceOrder: null,
      kind: ChatAtomKind.receipt,
      delivery: ChatDeliveryKind.independent,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.completed,
      ),
      contents: const [],
      payload: payload,
    );

ChatAtom chatMessage(String id, {String body = '中文 🐱', int? completionSeq}) =>
    ChatAtom(
      id: id,
      source: ReceiptChatSource(receiptId: id),
      sourceOrder: null,
      completionSeq: completionSeq,
      completionItemId: id,
      kind: ChatAtomKind.text,
      delivery: ChatDeliveryKind.independent,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.completed,
      ),
      contents: const [],
      payload: InlinePayload(
        bytes: utf8.encode(
          jsonEncode({
            'contract': 'anywork.chat/1',
            'type': 'text',
            'turnId': 'turn',
            'data': {
              'channel': 'final',
              'attachments': <Object?>[],
              'outcome': {
                'kind': 'completed',
                'data': {'completedAt': 0},
              },
            },
            'bodies': [
              {
                'key': 'body',
                'byteLength': utf8.encode(body).length,
                'inline': utf8.encode(body),
              },
            ],
          }),
        ),
      ),
    );

CurrentProjection chatCurrent({int sequence = 0}) => CurrentProjection(
  sourceEffectSeq: sequence,
  logicalStatus: ThreadStatusView.idle,
  executionPresent: false,
  sources: const [],
  atoms: const [],
  previews: const [],
  collections: const [],
);

ChatAtom chatEnvelope(
  String id, {
  required String type,
  required Map<String, Object?> data,
  List<Map<String, Object?>> bodies = const [],
  int? sealedAt,
  String contract = 'anywork.chat/1',
}) => ChatAtom(
  id: id,
  source: ReceiptChatSource(receiptId: id),
  sourceOrder: null,
  completionItemId: id,
  kind: ChatAtomKind.receipt,
  delivery: ChatDeliveryKind.independent,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [],
  payload: InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': contract,
        'type': type,
        'data': data,
        'bodies': bodies,
        'sealedAt': ?sealedAt,
      }),
    ),
  ),
);

Map<String, Object?> inlineBody(String key, String text) => {
  'key': key,
  'byteLength': utf8.encode(text).length,
  'inline': utf8.encode(text),
};

ChatBatch chatBatch(
  List<ChatAtom> messages, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
  CurrentProjection? current,
}) => ChatBatch(
  placement: placement,
  entries: messages.map(ChatAtomEntry.new).toList(),
  before: before,
  current: current,
);
