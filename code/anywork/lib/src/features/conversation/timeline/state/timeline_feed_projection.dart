import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'chat_item_presentation.dart';
import 'timeline_display_unit.dart';

const _feedItemKey = 'timelineFeedItem';

TimelineItem? timelineFeedItemOf(Message message) =>
    message.metadata?[_feedItemKey] as TimelineItem?;

Message timelineFeedMessage(
  TimelineItem item, {
  TimelineExpansionIntent? expansion,
}) {
  final presentation = switch (item) {
    TimelineUserMessage(
      :final channel,
      :final text,
      :final attachments,
      :final occurredAtMs,
    ) =>
      _item(
        item.id,
        'text',
        occurredAtMs,
        author: switch (channel) {
          'parentAgent' => 'parentAgent',
          'user' => 'user',
          _ => 'unknown',
        },
        data: {'attachments': attachments},
        bodies: [_text('body', text)],
      ),
    TimelineAssistantText(
      :final text,
      :final bodyRef,
      :final outcome,
      :final modelRecovery,
      :final isFinalTurnDelivery,
      :final occurredAtMs,
    ) =>
      _item(
        item.id,
        'text',
        occurredAtMs,
        author: 'assistant',
        data: {
          'outcome': {'kind': outcome},
        },
        modelRecovery: modelRecovery,
        finalTurnDelivery: isFinalTurnDelivery,
        bodies: [
          if (bodyRef != null)
            _body(bodyRef, key: 'body')
          else
            _text('body', text),
        ],
      ),
    final TimelineWorkGroup group => _workGroup(group, expansion),
    TimelineCompaction(:final summary, :final outcome, :final occurredAtMs) =>
      _item(
        item.id,
        'contextCompaction',
        occurredAtMs,
        data: {
          'summary': summary,
          'outcome': {'kind': outcome},
        },
      ),
    TimelinePlanResolution(
      :final decision,
      :final document,
      :final documentRef,
      :final feedback,
      :final occurredAtMs,
    ) =>
      _item(
        item.id,
        'plan',
        occurredAtMs,
        data: {'decision': decision},
        bodies: [
          if (documentRef != null)
            _body(documentRef, key: 'plan.document')
          else if (document != null)
            _text('plan.document', document),
          if (feedback != null) _text('plan.feedback', feedback),
        ],
      ),
    TimelineConnectionNotice(
      :final scope,
      :final state,
      :final transport,
      :final fallbackTransport,
      :final attempt,
      :final maxAttempts,
      :final recoverable,
      :final reason,
      :final durationMs,
      :final occurredAtMs,
    ) =>
      _item(
        item.id,
        'connection',
        occurredAtMs,
        data: {
          'scope': scope,
          'state': state,
          'transport': transport,
          'fallbackTransport': fallbackTransport,
          'attempt': attempt,
          'maxAttempts': maxAttempts,
          'recoverable': recoverable,
          'reason': reason,
          'durationMs': durationMs,
        },
      ),
    TimelineTurnOutcome(
      :final outcome,
      :final message,
      :final turnFailure,
      :final occurredAtMs,
    ) =>
      _item(
        item.id,
        'turn',
        occurredAtMs,
        data: {
          'outcome': {
            'kind': outcome,
            'data': {
              'message': message,
              if (turnFailure != null) 'failure': turnFailure.toJson(),
            },
          },
        },
      ),
    TimelineStandaloneTool(
      :final callId,
      :final payloadJson,
      :final presentationContract,
      :final bodies,
      :final occurredAtMs,
    ) =>
      _payload(
        item.id,
        payloadJson,
        occurredAtMs,
        refs: bodies,
        contract: presentationContract,
        callId: callId,
      ),
    TimelineFallback(:final reason, :final rawPreview, :final occurredAtMs) =>
      _fallback(item.id, reason, rawPreview, occurredAtMs),
  };
  return Message.custom(
    id: item.id,
    authorId: presentation.authorId,
    createdAt: presentation.createdAt,
    metadata: {
      _feedItemKey: item,
      chatItemPresentationKey: presentation,
      timelineDisplayUnitKey: ?presentation.displayUnit,
    },
  );
}

ChatItemPresentation timelineFeedMember(WorkGroupMember member) =>
    switch (member) {
      WorkGroupReasoning(
        :final id,
        :final text,
        :final summary,
        :final bodyRef,
        :final outcome,
        :final finishedAtMs,
        :final startedAtMs,
      ) =>
        _item(
          id,
          'thinking',
          finishedAtMs ?? startedAtMs,
          data: {
            'outcome': {'kind': outcome},
            'startedAt': startedAtMs == null ? null : startedAtMs ~/ 1000,
            'finishedAt': finishedAtMs == null ? null : finishedAtMs ~/ 1000,
          },
          bodies: [
            if (summary.isNotEmpty) _text('part.summaryText.0', summary),
            if (bodyRef != null) _body(bodyRef) else _text('body', text),
          ],
        ),
      WorkGroupToolCall(
        :final id,
        :final callId,
        :final turnId,
        :final waitJson,
        :final payloadJson,
        :final bodies,
        :final presentationContract,
        :final arguments,
        :final resultPreview,
        :final finishedAtMs,
        :final startedAtMs,
      ) =>
        _payload(
          id,
          payloadJson,
          finishedAtMs ?? startedAtMs,
          refs: bodies,
          contract: presentationContract,
          callId: callId,
          turnId: turnId,
          waitJson: waitJson,
          inline: {'tool.arguments': ?arguments, 'tool.result': ?resultPreview},
        ),
      WorkGroupAgent(
        :final id,
        :final payloadJson,
        :final finishedAtMs,
        :final startedAtMs,
      ) =>
        _payload(id, payloadJson, finishedAtMs ?? startedAtMs),
      WorkGroupFileChange(
        :final id,
        :final payloadJson,
        :final bodies,
        :final occurredAtMs,
      ) =>
        _payload(id, payloadJson, occurredAtMs, refs: bodies),
      WorkGroupSkill(:final id, :final payloadJson, :final occurredAtMs) =>
        _payload(id, payloadJson, occurredAtMs),
      WorkGroupFallback(:final id, :final reason, :final occurredAtMs) =>
        _fallback(id, reason, null, occurredAtMs),
    };

ChatItemPresentation _workGroup(
  TimelineWorkGroup group,
  TimelineExpansionIntent? expansion,
) {
  final active = group.status == WorkGroupStatus.active;
  final unit = TimelineDisplayUnit(
    expansion: expansion,
    block: DisplayBlock(
      id: group.id,
      blockOrder: group.firstSeq,
      body: WorkDisplayBlock(
        feedGroup: group,
        timing: WorkTiming(
          startedAtMillis: group.startedAtMs,
          finishedAtMillis: group.finishedAtMs,
        ),
        executionPresent: active,
        memberCount: group.memberCount,
        unfinishedCount: active ? 1 : 0,
        groupClosed: !active,
        summary: group.summary,
      ),
    ),
  );
  return ChatItemPresentation(
    id: group.id,
    compatibility: ChatItemCompatibility.current,
    type: 'displayUnit',
    data: const {},
    bodies: const [],
    displayUnit: unit,
    authorId: 'assistant',
  );
}

ChatItemPresentation _payload(
  String id,
  String raw,
  int? time, {
  List<BodyRef> refs = const [],
  String? contract,
  String? callId,
  String? turnId,
  String? waitJson,
  Map<String, String> inline = const {},
}) {
  final decoded = ChatItemPresentation.decodePayloadJson(id, raw);
  if (decoded.compatibility != ChatItemCompatibility.current) return decoded;
  final Map<String, Object?> data;
  try {
    data = waitJson == null
        ? decoded.data
        : Map.unmodifiable({...decoded.data, 'wait': jsonDecode(waitJson)});
  } on FormatException catch (error) {
    return _fallback(id, error.message, raw, time);
  }
  final bodies = {for (final body in decoded.bodies) body.key: body};
  for (final ref in refs) {
    bodies[ref.bodyKey] = _body(ref);
  }
  for (final entry in inline.entries) {
    if (bodies[entry.key]?.hasInline != true &&
        bodies[entry.key]?.hasReference != true) {
      bodies[entry.key] = _text(entry.key, entry.value);
    }
  }
  return ChatItemPresentation(
    id: id,
    compatibility: decoded.compatibility,
    type: decoded.type,
    data: data,
    bodies: List.unmodifiable(bodies.values),
    raw: raw,
    authorId: decoded.authorId,
    createdAt: _date(time) ?? decoded.createdAt,
    presentationContract: contract ?? decoded.presentationContract,
    toolCallId: callId,
    turnId: turnId,
  );
}

ChatItemPresentation _fallback(
  String id,
  String reason,
  String? raw,
  int? time,
) => ChatItemPresentation(
  id: id,
  compatibility: ChatItemCompatibility.malformed,
  type: 'raw',
  data: const {},
  bodies: const [],
  diagnostic: reason,
  raw: raw,
  createdAt: _date(time),
);

ChatItemPresentation _item(
  String id,
  String type,
  int? time, {
  String author = 'assistant',
  Map<String, Object?> data = const {},
  List<ChatBodyPresentation> bodies = const [],
  bool finalTurnDelivery = false,
  StudioModelRecoveryNotice? modelRecovery,
}) => ChatItemPresentation(
  id: id,
  compatibility: ChatItemCompatibility.current,
  type: type,
  authorId: author,
  data: Map.unmodifiable(data),
  bodies: List.unmodifiable(bodies),
  createdAt: _date(time),
  finalTurnDelivery: finalTurnDelivery,
  recoveryNotice: modelRecovery,
);

DateTime? _date(int? ms) => ms != null && ms.abs() <= 8640000000000000
    ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
    : null;

ChatBodyPresentation _text(String key, String text) => ChatBodyPresentation(
  key: key,
  byteLength: utf8.encode(text).length,
  inlineText: text,
);

ChatBodyPresentation _body(BodyRef ref, {String? key}) => ChatBodyPresentation(
  key: key ?? ref.bodyKey,
  byteLength: ref.byteLength,
  mediaType: ref.mediaType,
  inlineText: ref.inlineText,
  feedReference: ref,
);
