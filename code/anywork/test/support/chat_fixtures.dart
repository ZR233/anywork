import 'dart:convert';

import 'package:anywork_client/models.dart';

const chatDemand = ReadDemand(maxItems: 20, maxBytes: 65536);

/// A producer-side fixture row. It is deliberately not a public protocol type:
/// display identity remains the stable History row key and block order.
final class FixtureCompletion {
  const FixtureCompletion({
    required this.recordId,
    required this.completionSeq,
    required this.atom,
  });

  final String recordId;
  final int completionSeq;
  final ChatAtom atom;
}

ChatAtom fixtureAtom({required String id, required PayloadData payload}) =>
    ChatAtom(
      id: id,
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

ChatAtom chatAtomMessage(
  String id, {
  String body = '中文 🐱',
  bool? contentPresent,
}) => ChatAtom(
  id: id,
  source: ReceiptChatSource(receiptId: id),
  sourceOrder: null,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.independent,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contentPresent: contentPresent,
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

FixtureCompletion chatMessage(
  String id, {
  String body = '中文 🐱',
  int completionSeq = 1,
}) => FixtureCompletion(
  recordId: id,
  completionSeq: completionSeq,
  atom: chatAtomMessage(id, body: body),
);

FixtureCompletion statusItem(ChatAtom atom, {int completionSeq = 1}) =>
    FixtureCompletion(
      recordId: atom.id,
      completionSeq: completionSeq,
      atom: atom,
    );

FixtureCompletion workItem(String id, {int count = 3, int? completionSeq}) {
  final seq = completionSeq ?? count;
  return FixtureCompletion(
    recordId: id,
    completionSeq: seq,
    atom: ChatAtom(
      id: id,
      source: const ForegroundTurnChatSource(turnId: 'T'),
      sourceOrder: null,
      kind: ChatAtomKind.toolCall,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const TerminalChatAtom(
        started: null,
        ended: null,
        outcome: ChatTerminalOutcome.completed,
      ),
      contents: const [],
      payload: DeferredPayload(
        reference: ContentRef(
          databaseId: 'database',
          target: ItemPayloadTarget(itemId: id),
        ),
        byteLength: 100,
      ),
    ),
  );
}

ThreadWorkspace chatWorkspace(String threadId) {
  final thread = StudioThread(
    id: threadId,
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  );
  return ThreadWorkspace(
    businessRefs: const ThreadBusinessRefs(plan: null, interactions: null),
    thread: thread,
    revision: 1,
    interactions: const [],
    runtime: const ThreadRuntimeView(
      modelId: 'model',
      contextTokens: 0,
      contextWindow: 1,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
    ),
  );
}
