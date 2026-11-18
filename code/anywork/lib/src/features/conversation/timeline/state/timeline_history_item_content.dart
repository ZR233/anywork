import 'package:anywork_client/conversation.dart';
import 'package:flutter/widgets.dart' show AsyncSnapshot, ConnectionState;

import 'chat_item_presentation.dart';
import 'content_reference_identity.dart';
import 'timeline_display_models.dart';

/// One immutable row's bounded reads, handed off by its original History owner.
final class TimelineHistoryItemContent {
  const TimelineHistoryItemContent({
    required this.item,
    required this.bodyReads,
  });
  final ChatItemPresentation item;
  final Map<Object, AsyncSnapshot<ContentWindow>> bodyReads;
}

typedef TimelinePreparedHistoryItem = ({
  Object identity,
  AsyncSnapshot<TimelineHistoryItemContent> result,
});

Object timelineHistoryItemIdentity(ChatItemPresentation item) => (
  item.id,
  item.atom?.id,
  item.atom?.source,
  item.historyEventId,
  item.historyDetailEventId,
  switch (item.displayRecord?.contentSource) {
    CurrentAtomSource() => (CurrentAtomSource,),
    FrozenObservation(:final capturedAt, :final available) => (
      FrozenObservation,
      capturedAt,
      available,
    ),
    CompletedOriginal(:final completionId) => (CompletedOriginal, completionId),
    null => null,
  },
);

String timelineHistoryItemError(Object error) =>
    error is FormatException ? error.message : '完成内容读取失败';

/// The supplied scope owns admission, cancellation and joining every query.
Future<TimelineHistoryItemContent> readTimelineHistoryItem(
  HistoryReadScope history,
  ChatItemPresentation item,
) async {
  final detailId = item.historyDetailEventId ?? item.historyEventId!;
  final event = await history.readEvent(
    eventId: detailId,
    demand: const HistoryDemand(maxRows: 1, maxBytes: 64 * 1024),
  );
  var reference = event.payloadRef;
  if (reference == null) {
    final bodyEventId = item.historyEventId!;
    final bodyEvent = bodyEventId == detailId
        ? event
        : await history.readEvent(
            eventId: bodyEventId,
            demand: const HistoryDemand(maxRows: 1, maxBytes: 64 * 1024),
          );
    reference = bodyEvent.payloadRef;
  }
  if (reference == null) {
    final bodies = await history.listBodies(
      eventId: item.historyEventId!,
      demand: const HistoryDemand(maxRows: 32, maxBytes: 64 * 1024),
    );
    reference = bodies.entries
        .where(
          (entry) =>
              entry.role.kind == HistoryBodyRoleKind.canonicalPayload ||
              entry.role.kind == HistoryBodyRoleKind.body,
        )
        .firstOrNull
        ?.reference;
  }
  if (reference == null || reference.byteLength > 64 * 1024) {
    throw const FormatException('完成内容超出单次读取预算或缺失');
  }
  final window = await history.readBody(
    reference: reference,
    offset: 0,
    maxBytes: 64 * 1024,
  );
  if (window.offset != 0 ||
      window.totalLength != reference.byteLength ||
      window.bytes.length != window.totalLength) {
    throw const FormatException('完成内容窗口不连续');
  }
  final resolved = item.resolvePayload(InlinePayload(bytes: window.bytes));
  if (resolved.compatibility != ChatItemCompatibility.current) {
    throw const FormatException('完成内容格式无法解析');
  }
  final bodyReads = <Object, AsyncSnapshot<ContentWindow>>{};
  if (resolved.type == 'text' || resolved.type == 'input') {
    for (final body in resolved.bodies) {
      final reference = body.historyReference;
      if (body.key != 'body' || reference == null) continue;
      final key = historyBodyIdentity(reference);
      try {
        final window = await history.readBody(
          reference: reference,
          offset: 0,
          maxBytes: 64 * 1024,
        );
        bodyReads[key] = AsyncSnapshot.withData(
          ConnectionState.done,
          historyBodyWindow(reference, window),
        );
      } catch (error, stack) {
        if (!history.isActive) rethrow;
        bodyReads[key] = AsyncSnapshot.withError(
          ConnectionState.done,
          error,
          stack,
        );
      }
    }
  }
  return TimelineHistoryItemContent(
    item: resolved,
    bodyReads: Map.unmodifiable(bodyReads),
  );
}
