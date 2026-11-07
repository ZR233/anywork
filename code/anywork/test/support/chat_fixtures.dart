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

CurrentProjection chatCurrent({int sequence = 0}) => CurrentProjection(
  sourceEffectSeq: sequence,
  logicalStatus: ThreadStatusView.idle,
  executionPresent: false,
  sources: const [],
  atoms: const [],
  items: const [],
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
  List<TimelineItem> messages, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
  CurrentProjection? current,
}) => ChatBatch(
  placement: placement,
  entries: messages.map(ItemChatEntry.new).toList(),
  before: before,
  current: current,
);

/// Explicit text Main item. Atomic member fixtures use chatAtomMessage instead.
TimelineItem chatMessage(
  String id, {
  String body = '中文 🐱',
  int? completionSeq,
}) => TimelineItem(
  id: id,
  kind: TimelineItemKind.text,
  source: ReceiptChatSource(receiptId: id),
  atomKind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.independent,
  textChannel: ThreadTextChannel.finalAnswer,
  outcome: ChatTerminalOutcome.completed,
  contentItemId: id,
  contents: const [],
  payload: chatAtomMessage(id, body: body).payload,
  position: completionSeq,
  admissionClosed: true,
);

/// An explicitly independent status fixture, not an atom classification rule.
TimelineItem statusItem(ChatAtom atom) => TimelineItem(
  id: atom.id,
  kind: TimelineItemKind.status,
  source: atom.source,
  atomKind: atom.kind,
  delivery: ChatDeliveryKind.independent,
  contents: atom.contents,
  payload: atom.payload,
  admissionClosed: true,
);

/// Explicit synthetic producer capability; rebuild stories supply a different
/// opaque generation. Production code never manufactures either value.
TimelineItem workItem(
  String id, {
  bool closed = true,
  int active = 0,
  int count = 3,
  int failed = 0,
  int cancelled = 0,
  int? start,
  int? end,
  String? latestThinkingSummary,
  String projectionGeneration = 'fixture-projection-generation',
}) => TimelineItem(
  id: id,
  kind: TimelineItemKind.workGroup,
  source: const ForegroundTurnChatSource(turnId: 'T'),
  delivery: ChatDeliveryKind.foreground,
  admissionClosed: closed,
  contents: const [],
  members: TimelineMembersRef(
    databaseId: 'database',
    projectionVersion: 1,
    projectionGeneration: projectionGeneration,
    itemId: id,
  ),
  summary: TimelineGroupSummary(
    memberCount: count,
    activeCount: active,
    failedCount: failed,
    cancelledCount: cancelled,
    startedAt: start,
    finishedAt: end,
    latestThinkingSummary: latestThinkingSummary,
    categories: const [
      TimelineCategoryCount(category: TimelineCategory.thinking, count: 1),
    ],
  ),
);
