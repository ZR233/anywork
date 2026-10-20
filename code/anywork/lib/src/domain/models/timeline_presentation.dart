import 'dart:async';
import 'dart:collection';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'timeline_messages.dart';

export 'timeline_messages.dart';

part 'timeline_presentation_controller.dart';

typedef TimelineCanonicalKey = (int, String);
typedef TimelineItemListener = void Function(
  String id,
  TimelineMessagePayload? payload,
);

enum TimelinePresentationKind { single, activity, images, recovery }

/// 当前代次中一条自定义消息的唯一预览 owner。原始身份与展示身份分别表达。
sealed class TimelinePresentationItem extends ChangeNotifier {
  TimelinePresentationItem({
    required this.id,
    required this.serial,
    required TimelineMessagePayload anchor,
  }) : _position = (anchor.order, anchor.id),
       anchorId = anchor.id;

  final String id;
  final int serial;
  TimelineCanonicalKey _position;
  TimelineCanonicalKey get position => _position;
  String anchorId;
  final Map<String, _PresentationMember> _members = {};
  final List<String> _ids = [];
  final ValueNotifier<int> _structure = ValueNotifier(0);
  bool expanded = false;
  int activeCount = 0;
  int issueCount = 0;
  int thinkingCount = 0;
  int toolCount = 0;
  int runningToolCount = 0;
  int imageCount = 0;
  int _version = 0;

  TimelinePresentationKind get kind;
  int get length => _ids.length;
  List<String> get memberIds => UnmodifiableListView(_ids);
  ValueListenable<int> get structure => _structure;
  TimelineMessagePayload get first => _members[_ids.first]!.value;
  TimelineMessagePayload get latest => _members[_ids.last]!.value;
  Iterable<TimelineMessagePayload> get payloads sync* {
    for (final id in _ids) {
      yield _members[id]!.value;
    }
  }

  ValueListenable<TimelineMessagePayload> member(String id) => _members[id]!;
  TimelineMessagePayload? payload(String id) => _members[id]?.value;

  void setExpanded(bool value) {
    if (expanded == value) return;
    expanded = value;
    notifyListeners();
  }

  void _count(TimelineMessagePayload payload, int direction) {
    activeCount += payload.terminal ? 0 : direction;
    issueCount += _hasIssue(payload) ? direction : 0;
    thinkingCount += payload.item.state is ThreadThinkingItemStateView
        ? direction
        : 0;
    toolCount += payload.item.state is ThreadToolItemStateView ? direction : 0;
    runningToolCount +=
        payload.item.state is ThreadToolItemStateView && !payload.terminal
        ? direction
        : 0;
    imageCount +=
        direction *
        (payload.item.tool?.attachments
                .where((a) => a.modality == AttachmentModalityView.image)
                .length ??
            0);
  }

  void _insert(_PresentationMember member) {
    final payload = member.value;
    var low = 0;
    var high = _ids.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final other = _members[_ids[middle]]!.value;
      if (_compareKeys((other.order, other.id), (payload.order, payload.id)) <
          0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _ids.insert(low, payload.id);
    _members[payload.id] = member;
    _count(payload, 1);
  }

  _PresentationMember _take(String id) {
    final member = _members.remove(id)!;
    final index = _ids.indexOf(id);
    _ids.removeAt(index);
    if (anchorId == id && _ids.isNotEmpty) {
      anchorId = _ids[index.clamp(0, _ids.length - 1)];
      final anchor = _members[anchorId]!.value;
      _position = (anchor.order, anchor.id);
    }
    _count(member.value, -1);
    return member;
  }

  /// Publish only after the controller has committed every member's ownership.
  void _publishStructure() {
    _structure.value++;
    notifyListeners();
  }

  void _replace(String id, TimelineMessagePayload next) {
    final member = _members[id]!;
    _count(member.value, -1);
    _count(next, 1);
    member.replace(next);
    _version++;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final member in _members.values) {
      member.dispose();
    }
    _members.clear();
    _ids.clear();
    _structure.dispose();
    super.dispose();
  }
}

final class TimelineSingleItem extends TimelinePresentationItem {
  TimelineSingleItem({
    required super.id,
    required super.serial,
    required super.anchor,
  });
  @override
  TimelinePresentationKind get kind => TimelinePresentationKind.single;
}

final class TimelineActivityGroup extends TimelinePresentationItem {
  TimelineActivityGroup({
    required super.id,
    required super.serial,
    required super.anchor,
  });
  @override
  TimelinePresentationKind get kind => TimelinePresentationKind.activity;
}

final class TimelineImageReadGroup extends TimelinePresentationItem {
  TimelineImageReadGroup({
    required super.id,
    required super.serial,
    required super.anchor,
  });
  @override
  TimelinePresentationKind get kind => TimelinePresentationKind.images;
}

final class TimelineRecoveryGroup extends TimelinePresentationItem {
  TimelineRecoveryGroup({
    required super.id,
    required super.serial,
    required super.anchor,
    required this.attemptId,
  });
  final String attemptId;
  @override
  TimelinePresentationKind get kind => TimelinePresentationKind.recovery;
}

final class _PresentationMember extends ChangeNotifier
    implements ValueListenable<TimelineMessagePayload> {
  _PresentationMember(this._value);
  TimelineMessagePayload _value;
  @override
  TimelineMessagePayload get value => _value;
  void replace(TimelineMessagePayload value, {bool notify = true}) {
    _value = value;
    if (notify) publish();
  }

  void publish() => notifyListeners();
}

bool _hasIssue(TimelineMessagePayload payload) => const {
  'failed',
  'cancelled',
  'denied',
  'interrupted',
  'budgetLimited',
}.contains(payload.item.status);

bool timelinePayloadIsVisible(TimelineMessagePayload payload) =>
    switch (payload.item.kind) {
      ThreadItemKind.inference || ThreadItemKind.file => false,
      ThreadItemKind.turn =>
        payload.item.isTerminal && payload.item.error?.isNotEmpty == true,
      _ => true,
    };

TimelinePresentationKind _kindOf(TimelineMessagePayload payload) {
  if (payload.source is StudioTimelineRecoverySource) {
    return TimelinePresentationKind.recovery;
  }
  return switch (payload.item.state) {
    ThreadThinkingItemStateView() => TimelinePresentationKind.activity,
    ThreadToolItemStateView(:final userInput) when userInput == null =>
      payload.item.tool?.name == 'view_image' ||
              (payload.item.tool?.attachments.any(
                    (a) => a.modality == AttachmentModalityView.image,
                  ) ??
                  false)
          ? TimelinePresentationKind.images
          : TimelinePresentationKind.activity,
    _ => TimelinePresentationKind.single,
  };
}

int _compareKeys(TimelineCanonicalKey left, TimelineCanonicalKey right) {
  final order = left.$1.compareTo(right.$1);
  return order == 0 ? left.$2.compareTo(right.$2) : order;
}

const timelinePayloadMetadataKey = 'anywork.timeline';

TimelinePresentationItem? timelinePresentationOf(Message message) {
  final payload = message.metadata?[timelinePayloadMetadataKey];
  return payload is TimelinePresentationItem ? payload : null;
}

Iterable<TimelineMessagePayload> timelinePayloadsOf(Message message) =>
    timelinePresentationOf(message)?.payloads ?? const [];

/// 单成员消息的便捷读取；多成员组必须显式选择原始身份。
TimelineMessagePayload? timelinePayloadOf(Message message) {
  final item = timelinePresentationOf(message);
  return item?.length == 1 ? item!.first : null;
}

String timelineAuthorId(ThreadItemView item) => switch (item.state) {
  ThreadTextItemStateView(:final channel)
      when channel == ThreadTextChannel.user ||
          channel == ThreadTextChannel.parentAgent =>
    'user',
  _ => 'assistant',
};

Message _messageForPresentation(TimelinePresentationItem item) =>
    Message.custom(
      id: item.id,
      authorId: timelineAuthorId(item.first.item),
      createdAt: item.first.item.createdAt,
      updatedAt: item.latest.item.updatedAt,
      metadata: {timelinePayloadMetadataKey: item, 'version': item._version},
    );

Message timelineMessageFor(StudioTimelineItem item) =>
    timelineMessageOfPayload(TimelineMessagePayload.fromItem(item));

Message timelineMessageOfPayload(TimelineMessagePayload payload) {
  final item = TimelineSingleItem(id: payload.id, serial: 0, anchor: payload)
    .._insert(_PresentationMember(payload));
  return _messageForPresentation(item);
}

Message? applyTimelineItemUpdate(
  Message current,
  StudioTimelineUpdateItem change,
) {
  final payload = timelinePayloadOf(current);
  if (payload == null || payload.id != change.itemId) return null;
  final next = payload.applyUpdate(change);
  return next == null ? null : timelineMessageOfPayload(next);
}
