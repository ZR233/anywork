import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

const timelineEntryKey = 'anywork.conversation.entry';

enum TimelineEntryKind { single, activity, images, recovery, hidden }

/// One authoritative preview reference per member, observed only by its row.
final class TimelineMember extends ChangeNotifier {
  TimelineMember(this.item);
  ConversationItem item;
  void publish() => notifyListeners();
}

/// Owned by Message.metadata. All other indices borrow this same entry.
final class TimelineEntry extends ChangeNotifier {
  TimelineEntry({
    required this.id,
    required this.serial,
    required this.kind,
    required this.anchorItemId,
  });

  final String id;
  final int serial;
  TimelineEntryKind kind;
  String anchorItemId;
  final List<String> _ids = [];
  final Map<String, TimelineMember> _members = {};
  final Map<(String?, String), Set<String>> _tools = {};
  final Map<(String?, String), Set<String>> _skills = {};
  final Map<String, String> _pairs = {};
  final Set<String> _hiddenTools = {};
  List<String> _visibleIds = [];
  int _active = 0;
  int _issues = 0;
  int _toolCount = 0;
  int _skillCount = 0;
  int _thinkingCount = 0;

  Iterable<ConversationItem> get members => _ids.map((id) => item(id)!);
  ConversationItem? item(String id) => _members[id]?.item;
  TimelineMember member(String id) => _members[id]!;
  TimelineMember? memberOrNull(String id) => _members[id];
  ConversationItem get first => item(_ids.first)!;
  int get length => _ids.length;
  (int, String) get position => (first.header.ordinal, first.id);
  List<String> get memberIds => List.unmodifiable(_ids);
  List<String> get visibleMemberIds => List.unmodifiable(_visibleIds);
  int get visibleLength => _visibleIds.length;
  String visibleIdAt(int index) => _visibleIds[index];
  String? pairedToolId(String skillId) => _pairs[skillId];
  int get activeCount => _active;
  int get issueCount => _issues;
  int get toolCount => _toolCount - _hiddenTools.length;
  int get skillCount => _skillCount;
  bool get hasThinking => _thinkingCount != 0;
  ConversationItem? get latestRecovery =>
      kind == TimelineEntryKind.recovery && _ids.isNotEmpty
      ? item(_ids.last)
      : null;
  String get recoveryText => switch (latestRecovery?.descriptor) {
    ConversationRawDescriptor(:final notice) => notice,
    _ => latestRecovery == null ? '' : timelineText(latestRecovery!),
  };
  Duration? get elapsedDuration {
    if (_ids.isEmpty || activeCount != 0) return null;
    DateTime? start;
    DateTime? end;
    for (final item in members) {
      final completed = timelineCompletedAt(item);
      if (completed == null) return null;
      if (start == null || item.header.createdAt.isBefore(start)) {
        start = item.header.createdAt;
      }
      if (end == null || completed.isAfter(end)) end = completed;
    }
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  bool expanded = false;
  final Set<String> expandedMembers = {};
  int version = 0;

  (String?, String)? _pairKey(ConversationItem item) =>
      switch (item.descriptor) {
        ConversationToolDescriptor(:final invocation, :final state)
            when invocation.name == 'skill_view' &&
                state is ConversationToolSucceeded =>
          (item.header.turnId, invocation.toolCallId),
        ConversationSkillDescriptor(:final value)
            when value.cause.kind == SkillActivationCauseKind.tool =>
          (item.header.turnId, value.cause.id),
        _ => null,
      };

  void _count(ConversationItem item, int delta) {
    if (!item.terminal) _active += delta;
    if (switch (item.descriptor) {
      ConversationToolDescriptor(:final state) =>
        state is ConversationToolFailed || state is ConversationToolDenied,
      ConversationThinkingDescriptor(:final lifecycle) ||
      ConversationTextDescriptor(
        :final lifecycle,
      ) => lifecycle is FailedThreadContentView,
      ConversationTurnDescriptor(:final value) =>
        value.state is FailedStudioTurnState ||
            value.state is BudgetLimitedStudioTurnState,
      _ => false,
    }) {
      _issues += delta;
    }
    switch (item.descriptor) {
      case ConversationToolDescriptor():
        _toolCount += delta;
      case ConversationSkillDescriptor():
        _skillCount += delta;
      case ConversationThinkingDescriptor():
        _thinkingCount += delta;
      default:
        break;
    }
  }

  void _indexPair(ConversationItem item, bool add) {
    final key = _pairKey(item);
    if (key == null) return;
    final index = item.descriptor is ConversationToolDescriptor
        ? _tools
        : _skills;
    if (add) {
      (index[key] ??= {}).add(item.id);
    } else {
      index[key]?.remove(item.id);
      if (index[key]?.isEmpty ?? false) index.remove(key);
    }
  }

  // Only the matching typed call identity is visited, never the whole group.
  bool _refreshPair((String?, String)? key) {
    if (key == null) return false;
    final skills = _skills[key] ?? const <String>{};
    final tools = _tools[key] ?? const <String>{};
    String? tool;
    for (final id in tools) {
      if (tool == null || compareItems(item(id)!, item(tool)!) < 0) tool = id;
    }
    var changed = false;
    for (final id in skills) {
      final previous = _pairs[id];
      if (previous != tool) {
        if (tool == null) {
          _pairs.remove(id);
        } else {
          _pairs[id] = tool;
        }
        changed = true;
      }
    }
    return changed;
  }

  void _visible() {
    _hiddenTools
      ..clear()
      ..addAll(_pairs.values);
    _visibleIds = [
      for (final id in _ids)
        if (!_hiddenTools.contains(id)) id,
    ];
  }

  /// Membership-only changes need no repartition or body traversal. Sorted
  /// lists contain identities; every comparison borrows the indexed preview.
  void insert(ConversationItem value) {
    var low = 0;
    var high = _ids.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (compareItems(item(_ids[middle])!, value) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _ids.insert(low, value.id);
    _members[value.id] = TimelineMember(value);
    _count(value, 1);
    _indexPair(value, true);
    if (_refreshPair(_pairKey(value))) {
      _visible();
    } else {
      low = 0;
      high = _visibleIds.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        if (compareItems(item(_visibleIds[middle])!, value) < 0) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      _visibleIds.insert(low, value.id);
    }
  }

  void removeMember(String id) {
    final row = _members[id]!;
    final key = _pairKey(row.item);
    _count(row.item, -1);
    _indexPair(row.item, false);
    final removedPair = _pairs.remove(id);
    _members.remove(id);
    _ids.remove(id);
    expandedMembers.remove(id);
    if (anchorItemId == id && _ids.isNotEmpty) anchorItemId = _ids.first;
    if (_refreshPair(key) || removedPair != null) {
      _visible();
    } else {
      _visibleIds.remove(id);
    }
    row.dispose();
  }

  /// Structural path only. The controller commits every owner/index before
  /// publishing these entries or member notifications.
  void resetMembers(Iterable<ConversationItem> values) {
    final previous = Map<String, TimelineMember>.of(_members);
    _ids.clear();
    _members.clear();
    _tools.clear();
    _skills.clear();
    _pairs.clear();
    _active = _issues = _toolCount = _skillCount = _thinkingCount = 0;
    for (final value in values) {
      _ids.add(value.id);
      final row = previous.remove(value.id) ?? TimelineMember(value);
      row.item = value;
      _members[value.id] = row;
      _count(value, 1);
      _indexPair(value, true);
    }
    for (final row in previous.values) {
      row.dispose();
    }
    for (final key in _skills.keys) {
      _refreshPair(key);
    }
    _visible();
  }

  // Used only inside a controller structural transaction, before publication.
  void stage(ConversationItem value) => _members[value.id]!.item = value;

  /// Constant-time body update; only a changed pairing visits its typed call.
  /// Returns whether group summary/visible topology changed.
  bool replace(String id, ConversationItem next) {
    final row = _members[id]!;
    final previous = row.item;
    final before = (
      _active,
      _issues,
      toolCount,
      _skillCount,
      _thinkingCount,
      recoveryText,
    );
    final oldKey = _pairKey(previous);
    final newKey = _pairKey(next);
    final pairRoleChanged =
        oldKey != newKey ||
        (previous.descriptor is ConversationToolDescriptor) !=
            (next.descriptor is ConversationToolDescriptor);
    _count(previous, -1);
    _count(next, 1);
    if (pairRoleChanged) {
      _indexPair(previous, false);
      _pairs.remove(id);
    }
    row.item = next;
    var pairChanged = false;
    if (pairRoleChanged) {
      _indexPair(next, true);
      pairChanged = _refreshPair(oldKey);
      pairChanged = _refreshPair(newKey) || pairChanged;
      _visible();
    }
    row.publish();
    // A paired skill row reads the same tool reference for its details.
    if (next.descriptor is ConversationToolDescriptor && newKey != null) {
      for (final skill in _skills[newKey] ?? const <String>{}) {
        if (_pairs[skill] == id) _members[skill]?.publish();
      }
    }
    final changed =
        (kind == TimelineEntryKind.activity &&
            (previous.header.createdAt != next.header.createdAt ||
                timelineCompletedAt(previous) != timelineCompletedAt(next))) ||
        pairChanged ||
        before !=
            (
              _active,
              _issues,
              toolCount,
              _skillCount,
              _thinkingCount,
              recoveryText,
            );
    if (changed) publish();
    return changed;
  }

  void publish() {
    version++;
    notifyListeners();
  }

  void publishMembers() {
    for (final row in _members.values) {
      row.publish();
    }
  }

  void toggle() {
    expanded = !expanded;
    notifyListeners();
  }

  void toggleMember(String id) {
    if (!expandedMembers.remove(id)) expandedMembers.add(id);
    _members[id]?.publish();
  }

  @override
  void dispose() {
    for (final row in _members.values) {
      row.dispose();
    }
    super.dispose();
  }
}

TimelineEntry? timelineEntryOf(Message message) =>
    message.metadata?[timelineEntryKey] as TimelineEntry?;

int compareItems(ConversationItem left, ConversationItem right) {
  final order = left.header.ordinal.compareTo(right.header.ordinal);
  return order == 0 ? left.id.compareTo(right.id) : order;
}

String timelineAuthor(ConversationItem item) => switch (item.descriptor) {
  ConversationTextDescriptor(:final channel)
      when channel == ThreadTextChannel.user ||
          channel == ThreadTextChannel.parentAgent =>
    'user',
  _ => 'assistant',
};
String timelineText(ConversationItem item) =>
    item.fieldFor(const ThreadTextFieldView())?.text ?? '';

TimelineEntryKind timelineKind(ConversationItem item) {
  if (item.source is ConversationRecoverySource) {
    return TimelineEntryKind.recovery;
  }
  return switch (item.descriptor) {
    ConversationInferenceDescriptor() ||
    ConversationFileDescriptor() => TimelineEntryKind.hidden,
    ConversationTurnDescriptor(:final value)
        when value.state is CompletedStudioTurnState || value.state.isBusy =>
      TimelineEntryKind.hidden,
    ConversationThinkingDescriptor() ||
    ConversationSkillDescriptor() => TimelineEntryKind.activity,
    ConversationToolDescriptor(:final invocation, :final userInput)
        when userInput == null && invocation.name != 'show_image' =>
      invocation.name == 'view_image' ||
              timelineAttachments(item).any(
                (attachment) =>
                    attachment.modality == AttachmentModalityView.image,
              )
          ? TimelineEntryKind.images
          : TimelineEntryKind.activity,
    _ => TimelineEntryKind.single,
  };
}

List<ThreadAttachmentView> timelineAttachments(ConversationItem item) =>
    switch (item.descriptor) {
      ConversationTextDescriptor(:final attachments) => attachments,
      ConversationToolDescriptor(:final state) => switch (state) {
        ConversationToolSucceeded(:final output) => output.attachments,
        ConversationToolFailed(:final output) =>
          output?.attachments ?? const [],
        _ => const [],
      },
      _ => const [],
    };

DateTime? timelineCompletedAt(ConversationItem item) =>
    switch (item.descriptor) {
      ConversationThinkingDescriptor(:final lifecycle) => lifecycle.terminalAt,
      ConversationToolDescriptor(:final state) => switch (state) {
        ConversationToolSucceeded(:final completedAt) => completedAt,
        ConversationToolFailed(:final failedAt) => failedAt,
        ConversationToolCancelled(:final cancelledAt) => cancelledAt,
        ConversationToolDenied(:final deniedAt) => deniedAt,
        ConversationToolInterrupted(:final interruptedAt) => interruptedAt,
        _ => null,
      },
      ConversationSkillDescriptor(:final value) => value.activatedAt,
      _ => null,
    };
