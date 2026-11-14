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

ChatAtom chatAtomMessage(
  String id, {
  String body = '中文 🐱',
  int? completionSeq,
  bool? contentPresent,
}) => ChatAtom(
  id: id,
  source: ReceiptChatSource(receiptId: id),
  sourceOrder: null,
  completionSeq: completionSeq,
  contentPresent: contentPresent,
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
  List<CompletedEntry> messages, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
  int? fromSeq,
  int? throughSeq,
}) => ChatBatch(
  placement: placement,
  entries: messages,
  before: before,
  fromSeq:
      fromSeq ??
      (placement == ChatPlacement.append && messages.isNotEmpty
          ? messages.first.completionSeq - 1
          : null),
  throughSeq: throughSeq ?? messages.lastOrNull?.completionSeq ?? 0,
);

CompletedEntry chatMessage(
  String id, {
  String body = '中文 🐱',
  int completionSeq = 1,
}) => CompletedEntry(
  recordId: id,
  completionSeq: completionSeq,

  atom: chatAtomMessage(id, body: body, completionSeq: completionSeq),
);

CompletedEntry statusItem(ChatAtom atom, {int completionSeq = 1}) =>
    CompletedEntry(
      recordId: atom.completionItemId ?? atom.id,
      completionSeq: completionSeq,

      atom: atom,
    );

CompletedEntry workItem(
  String id, {
  int count = 3,
  int? completionSeq,
  int startSeq = 1,
  bool isText = false,
  String databaseId = 'database',
}) {
  final seq = completionSeq ?? startSeq + count - 1;
  return CompletedEntry(
    recordId: id,
    completionSeq: seq,

    atom: ChatAtom(
      id: id,
      completionItemId: id,
      completionSeq: seq,
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
          databaseId: databaseId,
          target: ItemPayloadTarget(itemId: id),
        ),
        byteLength: 100,
      ),
    ),
  );
}

ActivitySnapshot chatActivity({
  int revision = 0,
  int through = 0,
  bool executionPresent = false,
  List<ActivityEntry> entries = const [],
}) => ActivitySnapshot(
  revision: revision,
  completedThrough: through,
  executionPresent: executionPresent,
  entries: entries,
);

/// A complete State baseline for scripted protocol tests, never a runtime.
ThreadWorkspace chatWorkspace(
  String threadId, {
  ThreadBusinessRefs businessRefs = const ThreadBusinessRefs(
    plan: null,
    interactions: null,
  ),
}) => ThreadWorkspace(
  businessRefs: businessRefs,
  thread: StudioThread(
    id: threadId,
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.simple,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  ),
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
