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

enum TimelinePresentationKind { single, activity, images, imageCard, recovery }

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

  /// 当前可见的工具行数量：被技能行接管的原始调用不再单独计一次。
  int toolCount = 0;
  int runningToolCount = 0;

  /// 当前可见的技能行数量：每次激活各自是一行，重复加载不合并。
  int skillCount = 0;
  int imageCount = 0;
  final List<String> _visibleIds = [];
  final Map<String, String> _pairedTools = {};
  final Set<String> _hiddenIds = {};

  /// 成功 `skill_view` 调用的 tool call 身份 → 该成员身份。
  ///
  /// 只登记可配对的调用，配对收敛时按单个调用身份查找，不扫描整组。
  final Map<String, String> _skillViewCalls = {};

  /// tool call 身份 → 以它为来源的技能成员集合（用户手势来源不登记）。
  final Map<String, Set<String>> _skillMembersByCause = {};

  /// 本组最近一次操作是否改变了可见行；只有成员更新需要据此补发结构通知。
  bool _rowsChanged = false;
  int _version = 0;

  TimelinePresentationKind get kind;
  int get length => _ids.length;
  List<String> get memberIds => UnmodifiableListView(_ids);

  /// 组内可见活动行的成员身份，按 canonical 顺序。
  ///
  /// 它与 [memberIds] 的差异只有一处派生：成功主技能读取接管的原调用不再单独成行。
  /// 原始成员、顺序、revision、保存水位与详情引用仍分别保留，不因视觉去重被删除
  /// （design/26 §26.8）。
  List<String> get visibleMemberIds => UnmodifiableListView(_visibleIds);

  /// 技能行接管的原始 `skill_view` 调用；null 表示这次激活没有可配对的成功调用。
  String? pairedToolId(String skillId) => _pairedTools[skillId];

  /// 该成员是否以独立活动行出现。
  bool memberIsVisible(String id) => !_hiddenIds.contains(id);

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
    imageCount +=
        direction *
        (payload.item.tool?.attachments
                .where((a) => a.modality == AttachmentModalityView.image)
                .length ??
            0);
  }

  /// 可配对的成功 `skill_view` 调用身份；其它成员返回 null。
  ///
  /// 只读 typed 调用名、成功状态与 tool call 身份，不解析工具输出。
  static String? _skillViewCallId(TimelineMessagePayload payload) {
    final tool = payload.item.tool;
    if (tool == null || tool.name != 'skill_view') return null;
    if (payload.item.state is! ThreadToolItemStateView) return null;
    if (payload.item.status != 'succeeded') return null;
    return tool.toolCallId.isEmpty ? null : tool.toolCallId;
  }

  /// 技能激活的 typed 来源调用身份；用户手势来源不参与配对。
  static String? _skillCauseCallId(TimelineMessagePayload payload) {
    final skill = payload.item.skill;
    if (skill == null) return null;
    if (skill.cause.kind != SkillActivationCauseKind.tool) return null;
    return skill.cause.id.isEmpty ? null : skill.cause.id;
  }

  TimelineCanonicalKey _keyOf(String id) {
    final payload = _members[id]!.value;
    return (payload.order, payload.id);
  }

  /// 可见行的类别计数：被技能行接管的调用不计入工具数，同一次激活只算一次。
  void _applyRowCount(TimelineMessagePayload payload, int direction) {
    final state = payload.item.state;
    if (state is ThreadSkillItemStateView) {
      skillCount += direction;
      return;
    }
    if (state is ThreadToolItemStateView) {
      toolCount += direction;
      if (!payload.terminal) runningToolCount += direction;
    }
  }

  /// 可见行列表按 canonical key 的有序定位：返回该 key 的插入点（或已存在位置）。
  ///
  /// 查找是 O(log n)；Dart `List` 的插入/删除仍需移动尾部元素，这里是标准有序列表
  /// 的结构移动，不是每次正文更新都发生的整组扫描。
  int _visibleRowIndex(TimelineCanonicalKey key) {
    var low = 0;
    var high = _visibleIds.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_compareKeys(_keyOf(_visibleIds[middle]), key) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void _insertVisibleRow(String id, TimelineMessagePayload payload) {
    final index = _visibleRowIndex((payload.order, payload.id));
    _visibleIds.insert(index, id);
    _applyRowCount(payload, 1);
    _rowsChanged = true;
  }

  void _removeVisibleRow(String id, [TimelineMessagePayload? payload]) {
    // 成员移出时它已不在 `_members` 中，由调用方给出它的最后事实。
    final value = payload ?? _members[id]?.value;
    if (value == null) return;
    final index = _visibleRowIndex((value.order, value.id));
    if (index >= _visibleIds.length || _visibleIds[index] != id) return;
    _visibleIds.removeAt(index);
    _applyRowCount(value, -1);
    _rowsChanged = true;
  }

  /// 被技能行接管的调用不再单独占一行；该转换幂等，只影响这一个成员。
  void _setToolHidden(String toolId, bool hidden) {
    final payload = _members[toolId]?.value;
    if (payload == null) return;
    if (hidden) {
      if (!_hiddenIds.add(toolId)) return;
      _removeVisibleRow(toolId);
      return;
    }
    if (!_hiddenIds.remove(toolId)) return;
    _insertVisibleRow(toolId, payload);
  }

  /// 只按一个调用身份收敛配对：不遍历整组，也不重算其它调用。
  ///
  /// 一次成功的主技能读取同时有 canonical Skill 与 Tool 两份成员：技能激活的
  /// `cause.kind == tool` 且 `cause.id` 等于同 Turn `skill_view` 调用的 tool call 身份时，
  /// 二者只共享一条可见技能行，canonical 成员与详情仍分别保留（design/26 §26.8）。
  void _refreshPairing(String callId) {
    final toolId = _skillViewCalls[callId];
    final hasTool = toolId != null && _members.containsKey(toolId);
    final skills = _skillMembersByCause[callId];
    String? preferred;
    if (hasTool && skills != null) {
      for (final skillId in skills) {
        if (preferred == null ||
            _compareKeys(_keyOf(skillId), _keyOf(preferred)) < 0) {
          preferred = skillId;
        }
      }
    }
    if (skills != null) {
      for (final skillId in skills) {
        final desired = skillId == preferred ? toolId : null;
        if (_pairedTools[skillId] == desired) continue;
        if (desired == null) {
          _pairedTools.remove(skillId);
        } else {
          _pairedTools[skillId] = desired;
        }
        _rowsChanged = true;
      }
    }
    if (hasTool) {
      // 一条成功调用最多被一个技能行接管，其余激活各自保留自己的行。
      _setToolHidden(toolId, preferred != null);
    }
  }

  /// 配对索引登记：一个成员只可能是工具侧或技能侧之一。
  void _registerPairingKeys(String id, TimelineMessagePayload payload) {
    final callId = _skillViewCallId(payload);
    if (callId != null) {
      _skillViewCalls.putIfAbsent(callId, () => id);
      return;
    }
    final causeId = _skillCauseCallId(payload);
    if (causeId == null) return;
    (_skillMembersByCause[causeId] ??= <String>{}).add(id);
  }

  void _unregisterPairingKeys(String id, TimelineMessagePayload payload) {
    final callId = _skillViewCallId(payload);
    if (callId != null && _skillViewCalls[callId] == id) {
      _skillViewCalls.remove(callId);
    }
    final causeId = _skillCauseCallId(payload);
    if (causeId == null) return;
    final skills = _skillMembersByCause[causeId];
    if (skills == null) return;
    skills.remove(id);
    if (skills.isEmpty) _skillMembersByCause.remove(causeId);
  }

  /// 成员更新只按自身与受影响调用增量刷新；普通正文、参数与 token 更新不改任何索引。
  void _updateMemberRows(
    String id,
    TimelineMessagePayload previous,
    TimelineMessagePayload next,
  ) {
    // 可见行计数只依赖类别与终态，先按同一成员替换修正计数。
    if (!_hiddenIds.contains(id)) {
      _applyRowCount(previous, -1);
      _applyRowCount(next, 1);
    }
    final oldTool = _skillViewCallId(previous);
    final newTool = _skillViewCallId(next);
    final oldCause = _skillCauseCallId(previous);
    final newCause = _skillCauseCallId(next);
    if (oldTool == newTool && oldCause == newCause) return;
    // 该成员自己原本的配对必须先显式撤销：来源改变后它不再属于旧调用的候选集合，
    // 只靠旧调用收敛会漏掉这一条残留配对（工具行与技能行会同时给出同一份详情）。
    final ownPair = _pairedTools.remove(id);
    if (ownPair != null) {
      _rowsChanged = true;
      _setToolHidden(ownPair, false);
    }
    _unregisterPairingKeys(id, previous);
    _registerPairingKeys(id, next);
    for (final callId in {?oldTool, ?newTool, ?oldCause, ?newCause}) {
      _refreshPairing(callId);
    }
    if (next.item.state is ThreadToolItemStateView) {
      // 该成员自己的可见性只取决于它是否仍被某个技能行接管。
      _setToolHidden(id, _pairedTools.containsValue(id));
    }
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
    _registerPairingKeys(payload.id, payload);
    _insertVisibleRow(payload.id, payload);
    final callId = _skillViewCallId(payload) ?? _skillCauseCallId(payload);
    if (callId != null) _refreshPairing(callId);
    // 归属仍由 controller 在所有成员提交后统一发布结构通知。
    _rowsChanged = false;
  }

  _PresentationMember _take(String id) {
    final member = _members[id]!;
    final payload = member.value;
    final index = _ids.indexOf(id);
    _ids.removeAt(index);
    if (anchorId == id && _ids.isNotEmpty) {
      anchorId = _ids[index.clamp(0, _ids.length - 1)];
      final anchor = _members[anchorId]!.value;
      _position = (anchor.order, anchor.id);
    }
    _count(payload, -1);
    // 先撤销自己的可见行与隐藏标记，再收敛其它成员的可见性；该成员此时仍在 `_members`
    // 中，可见行的二分定位可用它自己的 canonical key。
    _removeVisibleRow(id, payload);
    _hiddenIds.remove(id);
    final pairedTool = _pairedTools.remove(id);
    if (pairedTool != null) {
      _rowsChanged = true;
      _setToolHidden(pairedTool, false);
    }
    _unregisterPairingKeys(id, payload);
    final callId = _skillViewCallId(payload) ?? _skillCauseCallId(payload);
    if (callId != null) _refreshPairing(callId);
    _members.remove(id);
    _rowsChanged = false;
    return member;
  }

  /// Publish only after the controller has committed every member's ownership.
  void _publishStructure() {
    _structure.value++;
    notifyListeners();
  }

  void _replace(String id, TimelineMessagePayload next) {
    final member = _members[id]!;
    final previous = member.value;
    // 成员值先提交但不通知：计数、配对与可见索引全部就位后才发布，监听者不会读到
    // new payload 搭配旧配对/可见行的半更新状态。
    member.replace(next, notify: false);
    _count(previous, -1);
    _count(next, 1);
    _updateMemberRows(id, previous, next);
    _version++;
    final rowsChanged = _rowsChanged;
    _rowsChanged = false;
    if (rowsChanged) _structure.value++;
    member.publish();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final member in _members.values) {
      member.dispose();
    }
    _members.clear();
    _ids.clear();
    _visibleIds.clear();
    _pairedTools.clear();
    _hiddenIds.clear();
    _skillViewCalls.clear();
    _skillMembersByCause.clear();
    _rowsChanged = false;
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

/// 展示工具（`show_image`）的独立图片卡片（design/19 §19.9、design/25 §25.6）。
///
/// 卡片只派生展示属性：所属调用、typed 附件与工具参数中的展示文案；图片字节仍由
/// Thread 附件缓存按身份读取。它不并入普通工具活动组，也不与图片读取组共用摘要，
/// 每条展示调用各占一张卡片。
final class TimelineImageCardGroup extends TimelinePresentationItem {
  TimelineImageCardGroup({
    required super.id,
    required super.serial,
    required super.anchor,
  });
  @override
  TimelinePresentationKind get kind => TimelinePresentationKind.imageCard;
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
      ThreadItemKind.publicArtifact => true,
      ThreadItemKind.turn =>
        payload.item.isTerminal && payload.item.error?.isNotEmpty == true,
      _ => true,
    };

TimelinePresentationKind _kindOf(TimelineMessagePayload payload) {
  if (payload.source is StudioTimelineRecoverySource) {
    return TimelinePresentationKind.recovery;
  }
  if (_isImageCard(payload)) return TimelinePresentationKind.imageCard;
  return switch (payload.item.state) {
    ThreadThinkingItemStateView() => TimelinePresentationKind.activity,
    // 技能激活与相邻同轮思考、普通工具同属一个活动组，不单独划分组边界。
    ThreadSkillItemStateView() => TimelinePresentationKind.activity,
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

/// 展示工具按工具身份独立成卡片，先于通用图片附件分类判定。
///
/// 判定只读 canonical 工具名，不看返回内容：即使回执里没有图片附件，也仍是一张
/// 可读的错误态卡片，而不是退回普通工具活动组。
bool _isImageCard(TimelineMessagePayload payload) =>
    payload.item.kind == ThreadItemKind.toolCall &&
    payload.item.tool?.name == 'show_image';

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
