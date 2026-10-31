import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/timeline_atom_equality.dart';
import '../state/timeline_entry.dart';
import '../state/timeline_image_resources.dart';

/// Two-ended projection of immutable completed atoms onto stock Flyer messages.
/// The presentation owner serializes page and completion acceptance.
final class TimelineMessageController {
  TimelineMessageController(
    this.controller, {
    required this.generation,
    required this.imageResources,
  });

  final InMemoryChatController controller;
  final int generation;
  final TimelineImageResources imageResources;
  final Map<String, TimelineEntry> _owners = {};
  final Map<int, String> _sequences = {};
  final List<String> _ids = [];
  final Map<TimelineEntry, Message> _messages = {};
  TimelineEntry? _head;
  TimelineEntry? _tail;
  bool _initialized = false;
  bool _disposed = false;

  int get length => _ids.length;
  Iterable<ConversationItem> get items => _ids.map((id) => item(id)!);
  ConversationItem? item(String id) => _owners[id]?.item(id);
  TimelineEntry? ownerOf(String id) => _owners[id];
  Listenable? memberObservation(String id) => _owners[id]?.memberOrNull(id);

  Future<void> initialize(Iterable<ConversationItem> items) async {
    _checkAlive();
    if (_initialized) throw StateError('Timeline already initialized');
    final added = _validate(items, prepend: false);
    final groups = _group(added);
    _initialized = true;
    final messages = _commitGroups(groups);
    _ids.addAll(added.map((item) => item.id));
    await controller.setMessages(messages, animated: false);
  }

  Future<void> append(Iterable<ConversationItem> items) async {
    _checkInitialized();
    final projection = _projectAppend(items);
    if (projection.items.isEmpty) return;
    final boundary = projection.boundary;
    if (boundary != null) {
      boundary.appendMembers(projection.boundaryMembers);
      _retain(projection.boundaryMembers, boundary);
    }
    final messages = _commitGroups(projection.groups);
    _ids.addAll(projection.items.map((item) => item.id));
    if (boundary != null) await _updateBoundary(boundary);
    if (messages.isNotEmpty) await controller.insertAllMessages(messages);
  }

  Future<int> prepend(Iterable<ConversationItem> items) async {
    _checkInitialized();
    final projection = _projectPrepend(items);
    if (projection.items.isEmpty) return 0;
    final boundary = projection.boundary;
    if (boundary != null) {
      boundary.prependMembers(projection.boundaryMembers);
      _retain(projection.boundaryMembers, boundary);
    }
    final messages = _commitGroups(projection.groups, prepend: true);
    _ids.insertAll(0, projection.items.map((item) => item.id));
    if (boundary != null) await _updateBoundary(boundary);
    if (messages.isNotEmpty) {
      await controller.insertAllMessages(messages, index: 0, animated: false);
    }
    return projection.items.length;
  }

  /// Validate the entire batch before touching entries, images or Flyer.
  List<ConversationItem> _validate(
    Iterable<ConversationItem> values, {
    required bool prepend,
  }) {
    final added = <ConversationItem>[];
    final batchIds = <String, ConversationItem>{};
    int? previous;
    final edge = _ids.isEmpty
        ? null
        : item(prepend ? _ids.first : _ids.last)!.header.appendSeq;
    for (final value in values) {
      final sequence = value.header.appendSeq;
      if (previous != null && sequence <= previous) {
        throw StateError('Timeline batch appendSeq must strictly increase');
      }
      previous = sequence;
      if (value.header.threadId != imageResources.threadId) {
        throw StateError('Timeline atom belongs to another thread');
      }
      final existing = item(value.id) ?? batchIds[value.id];
      final sequenceOwner = _sequences[sequence];
      if (existing != null) {
        if (!timelineAtomsEqual(existing, value)) {
          throw StateError('Conflicting completed atom: ${value.id}');
        }
        continue;
      }
      if (sequenceOwner != null) {
        throw StateError('Conflicting timeline appendSeq: $sequence');
      }
      if (edge != null && (prepend ? sequence >= edge : sequence <= edge)) {
        throw StateError('New timeline atom is outside the requested end');
      }
      batchIds[value.id] = value;
      added.add(value);
    }
    return added;
  }

  _Projection _projectAppend(Iterable<ConversationItem> values) {
    final added = _validate(values, prepend: false);
    final groups = _group(added);
    final first = groups.where((group) => !_hidden(group)).firstOrNull;
    final boundary =
        first != null && _tail != null && _joins(_tail!.first, first.first)
        ? _tail
        : null;
    final members = boundary == null ? const <ConversationItem>[] : first!;
    if (boundary != null) groups.remove(first);
    return _Projection(added, groups, boundary, members);
  }

  _Projection _projectPrepend(Iterable<ConversationItem> values) {
    final added = _validate(values, prepend: true);
    final groups = _group(added);
    final last = groups.where((group) => !_hidden(group)).lastOrNull;
    final boundary =
        last != null && _head != null && _joins(last.first, _head!.first)
        ? _head
        : null;
    final members = boundary == null ? const <ConversationItem>[] : last!;
    if (boundary != null) groups.remove(last);
    return _Projection(added, groups, boundary, members);
  }

  // Hidden facts are retained in atom order but are transparent to display
  // adjacency. Every visible non-activity atom breaks the activity run.
  List<List<ConversationItem>> _group(List<ConversationItem> values) {
    final groups = <List<ConversationItem>>[];
    List<ConversationItem>? visible;
    for (final value in values) {
      if (timelineKind(value) == TimelineEntryKind.hidden) {
        groups.add([value]);
      } else if (visible != null && _joins(visible.last, value)) {
        visible.add(value);
      } else {
        visible = [value];
        groups.add(visible);
      }
    }
    return groups;
  }

  bool _hidden(List<ConversationItem> group) =>
      timelineKind(group.first) == TimelineEntryKind.hidden;

  bool _joins(ConversationItem left, ConversationItem right) =>
      timelineKind(left) == TimelineEntryKind.activity &&
      timelineKind(right) == TimelineEntryKind.activity &&
      left.header.turnId != null &&
      left.header.turnId!.isNotEmpty &&
      left.header.turnId == right.header.turnId;

  List<Message> _commitGroups(
    List<List<ConversationItem>> groups, {
    bool prepend = false,
  }) {
    final messages = <Message>[];
    final visible = <TimelineEntry>[];
    for (final group in groups) {
      final anchor = group.first;
      final kind = timelineKind(anchor);
      final entry = TimelineEntry(
        id: 'timeline-entry:$generation:${anchor.id}',
        kind: kind,
        anchorItemId: anchor.id,
      )..appendMembers(group);
      _retain(group, entry);
      if (kind == TimelineEntryKind.hidden) continue;
      visible.add(entry);
      final message = _message(entry);
      _messages[entry] = message;
      messages.add(message);
    }
    if (visible.isNotEmpty) {
      if (prepend) {
        _head = visible.first;
        _tail ??= visible.last;
      } else {
        _head ??= visible.first;
        _tail = visible.last;
      }
    }
    return messages;
  }

  void _retain(Iterable<ConversationItem> items, TimelineEntry entry) {
    for (final item in items) {
      _owners[item.id] = entry;
      _sequences[item.header.appendSeq] = item.id;
      imageResources.retainItem(item.id, timelineAttachments(item));
    }
  }

  Future<void> _updateBoundary(TimelineEntry entry) async {
    final previous = _messages[entry]!;
    final next = _message(entry);
    _messages[entry] = next;
    await controller.updateMessage(previous, next);
    entry.publish();
  }

  Message _message(TimelineEntry entry) {
    final anchor = entry.item(entry.anchorItemId)!;
    final sealedAt = anchor.header.sealedAt;
    final createdAt = sealedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sealedAt * 1000, isUtc: true);
    final metadata = <String, dynamic>{
      timelineEntryKey: entry,
      // Stock updateMessage compares Message values; the same entry reference
      // needs a changed scalar when its immutable membership expands.
      'memberCount': entry.length,
    };
    if (entry.kind == TimelineEntryKind.single &&
        anchor.descriptor is ConversationTextDescriptor) {
      return Message.text(
        id: entry.id,
        authorId: timelineAuthor(anchor),
        text: timelineText(anchor),
        createdAt: createdAt,
        metadata: metadata,
      );
    }
    return Message.custom(
      id: entry.id,
      authorId: timelineAuthor(anchor),
      createdAt: createdAt,
      metadata: metadata,
    );
  }

  void _checkAlive() {
    if (_disposed) throw StateError('Timeline disposed');
  }

  void _checkInitialized() {
    _checkAlive();
    if (!_initialized) throw StateError('Timeline not initialized');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _owners.values.toSet()) {
      entry.dispose();
    }
    for (final id in _ids) {
      imageResources.dropItem(id);
    }
    _owners.clear();
    _sequences.clear();
    _ids.clear();
    _messages.clear();
    _head = _tail = null;
  }
}

final class _Projection {
  const _Projection(
    this.items,
    this.groups,
    this.boundary,
    this.boundaryMembers,
  );
  final List<ConversationItem> items;
  final List<List<ConversationItem>> groups;
  final TimelineEntry? boundary;
  final List<ConversationItem> boundaryMembers;
}
