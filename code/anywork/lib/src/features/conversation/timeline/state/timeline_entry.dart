import 'dart:collection';

import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

const timelineEntryKey = 'anywork.conversation.entry';

enum TimelineEntryKind { single, activity, images, hidden }

/// An immutable completed atom, with only its local expansion observable.
final class TimelineMember extends ChangeNotifier {
  TimelineMember(this.item);
  final ConversationItem item;
  void publish() => notifyListeners();
}

/// Message metadata and the owner index borrow this same presentation entry.
/// Its anchor and message identity never change, including across older pages.
final class TimelineEntry extends ChangeNotifier {
  TimelineEntry({
    required this.id,
    required this.kind,
    required this.anchorItemId,
  });

  final String id;
  final TimelineEntryKind kind;
  final String anchorItemId;
  final List<String> _ids = [];
  final Map<String, TimelineMember> _members = {};
  final Map<String, String> _pairs = {};
  List<String> _visibleIds = [];
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
  (int, String) get position => (first.header.appendSeq, first.id);
  List<String> get memberIds => List.unmodifiable(_ids);
  List<String> get visibleMemberIds => List.unmodifiable(_visibleIds);
  int get visibleLength => _visibleIds.length;
  String visibleIdAt(int index) => _visibleIds[index];
  String? pairedToolId(String skillId) => _pairs[skillId];
  int get issueCount => _issues;
  int get toolCount => _toolCount - _pairs.values.toSet().length;
  int get skillCount => _skillCount;
  bool get hasThinking => _thinkingCount != 0;

  // Completed content/tool atoms do not contain a start time. Never infer one
  // from a seal time or the arrival of a page.
  Duration? get elapsedDuration => switch (first.descriptor) {
    ConversationTurnDescriptor(:final outcome) => switch (outcome) {
      ConversationTurnCompleted(:final value) => _duration(
        value.startedAt,
        value.completedAt,
      ),
      ConversationTurnFailed(:final value) => _duration(
        value.startedAt,
        value.completedAt,
      ),
      ConversationTurnCancelled(:final value) => _duration(
        value.startedAt,
        value.completedAt,
      ),
      ConversationTurnBudgetLimited(:final value) => _duration(
        value.startedAt,
        value.completedAt,
      ),
    },
    _ => null,
  };

  bool expanded = false;
  final Set<String> _expandedMembers = {};
  Set<String> get expandedMembers => UnmodifiableSetView(_expandedMembers);
  bool isMemberExpanded(String id) => _expandedMembers.contains(id);

  void appendMembers(Iterable<ConversationItem> values) {
    final added = values.toList(growable: false);
    for (final value in added) {
      _addMember(value);
    }
    _ids.addAll(added.map((value) => value.id));
    _summarize();
  }

  void prependMembers(Iterable<ConversationItem> values) {
    final added = values.toList(growable: false);
    for (final value in added) {
      _addMember(value);
    }
    _ids.insertAll(0, added.map((value) => value.id));
    _summarize();
  }

  void _addMember(ConversationItem value) {
    assert(!_members.containsKey(value.id));
    _members[value.id] = TimelineMember(value);
    switch (value.descriptor) {
      case ConversationToolDescriptor(:final state):
        _toolCount++;
        if (state is ConversationToolFailed ||
            state is ConversationToolDenied) {
          _issues++;
        }
      case ConversationSkillDescriptor():
        _skillCount++;
      case ConversationThinkingDescriptor(:final outcome):
        _thinkingCount++;
        if (outcome is ConversationContentFailed) _issues++;
      case ConversationTextDescriptor(:final outcome):
        if (outcome is ConversationContentFailed) _issues++;
      case ConversationTurnDescriptor(:final outcome):
        if (outcome is ConversationTurnFailed ||
            outcome is ConversationTurnBudgetLimited) {
          _issues++;
        }
      default:
        break;
    }
  }

  /// Pure group-local pairing by typed call identity. No history lookup and no
  /// member replacement: a skill only borrows its completed tool's reference.
  void _summarize() {
    final tools = <(String?, String), String>{};
    for (final value in members) {
      if (value.descriptor
          case ConversationToolDescriptor(
            :final invocation,
            state: ConversationToolSucceeded(),
          )
          when invocation.name == 'skill_view') {
        tools.putIfAbsent((
          value.header.turnId,
          invocation.toolCallId,
        ), () => value.id);
      }
    }
    _pairs.clear();
    for (final atom in members) {
      if (atom.descriptor case ConversationSkillDescriptor(:final value)
          when value.cause.kind == SkillActivationCauseKind.tool) {
        final tool = tools[(atom.header.turnId, value.cause.id)];
        if (tool != null) {
          _pairs[atom.id] = tool;
        }
      }
    }
    final hiddenTools = _pairs.values.toSet();
    _visibleIds = [
      for (final id in _ids)
        if (!hiddenTools.contains(id)) id,
    ];
  }

  void publish() => notifyListeners();

  void toggle() {
    expanded = !expanded;
    notifyListeners();
  }

  void toggleMember(String id) => setMemberExpanded(id, !isMemberExpanded(id));

  void setMemberExpanded(String id, bool expanded) {
    if (!_members.containsKey(id)) return;
    final changed = expanded
        ? _expandedMembers.add(id)
        : _expandedMembers.remove(id);
    if (changed) _members[id]!.publish();
  }

  @override
  void dispose() {
    for (final row in _members.values) {
      row.dispose();
    }
    super.dispose();
  }
}

Duration? _duration(int? start, int end) =>
    start == null || end < start ? null : Duration(seconds: end - start);

TimelineEntry? timelineEntryOf(Message message) =>
    message.metadata?[timelineEntryKey] as TimelineEntry?;

int compareItems(ConversationItem left, ConversationItem right) =>
    left.header.appendSeq.compareTo(right.header.appendSeq);

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
    return TimelineEntryKind.single;
  }
  return switch (item.descriptor) {
    ConversationInferenceDescriptor() => TimelineEntryKind.hidden,
    ConversationTurnDescriptor(outcome: ConversationTurnCompleted()) =>
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
