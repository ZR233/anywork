import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

import '../state/timeline_entry.dart';
import '../state/timeline_image_resources.dart';

/// The SDK owns content reduction. These indices only borrow Message-owned
/// entries/messages or retain IDs and positions, never a second body snapshot.
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
  final List<String> _ids = [];
  final Map<TimelineEntry, List<String>> _messageIds = {};
  final Map<String, Message> _messages = {};
  final List<String> _order = [];
  final Map<String, int> _positions = {};
  final Map<String, ValueNotifier<StreamState>> _streams = {};
  int _serial = 0;

  int get length => _ids.length;
  int get activeStreamCount => _streams.length;
  Iterable<ConversationItem> get items => _ids.map((id) => item(id)!);
  ConversationItem? item(String id) => _owners[id]?.item(id);
  TimelineEntry? ownerOf(String id) => _owners[id];
  Listenable? memberObservation(String id) => _owners[id]?.memberOrNull(id);
  ValueListenable<StreamState>? streamFor(String id) {
    final direct = _streams[id];
    if (direct != null) return direct;
    final message = _messages[id];
    return message == null
        ? null
        : _streams[timelineEntryOf(message)!.first.id];
  }

  bool _joins(ConversationItem left, ConversationItem right) {
    final kind = timelineKind(left);
    if (kind != timelineKind(right)) return false;
    if (kind == TimelineEntryKind.recovery) {
      return (left.source as ConversationRecoverySource).attemptId ==
          (right.source as ConversationRecoverySource).attemptId;
    }
    return (kind == TimelineEntryKind.activity ||
            kind == TimelineEntryKind.images) &&
        left.header.turnId == right.header.turnId;
  }

  TimelineEntry _newEntry(ConversationItem value) {
    final kind = timelineKind(value);
    final serial = ++_serial;
    return TimelineEntry(
      id: kind == TimelineEntryKind.single || kind == TimelineEntryKind.hidden
          ? value.id
          : 'timeline-group:$generation:$serial',
      serial: serial,
      kind: kind,
      anchorItemId: value.id,
    );
  }

  int _insertion(ConversationItem value) {
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
    return low;
  }

  void prepend(Iterable<ConversationItem> values) => _structure(values);
  TimelineEntry? _neighbor(int index, int step) {
    while (index >= 0 && index < _ids.length) {
      final entry = _owners[_ids[index]]!;
      if (entry.kind != TimelineEntryKind.hidden) return entry;
      index += step;
    }
    return null;
  }

  void add(ConversationItem value) {
    assert(!_owners.containsKey(value.id));
    imageResources.retainItem(value.id, timelineAttachments(value));
    final index = _insertion(value);
    final left = _neighbor(index - 1, -1);
    final right = _neighbor(index, 1);
    final hidden = timelineKind(value) == TimelineEntryKind.hidden;
    final joinsLeft = !hidden && left != null && _joins(left.first, value);
    final joinsRight = !hidden && right != null && _joins(right.first, value);
    if ((!hidden && left != null && identical(left, right) && !joinsLeft) ||
        (joinsLeft && joinsRight && !identical(left, right))) {
      _structure([value]);
      return;
    }
    final entry = joinsLeft
        ? left
        : joinsRight
        ? right
        : _newEntry(value);
    entry.insert(value);
    _ids.insert(index, value.id);
    _owners[value.id] = entry;
    _commitEntry(entry);
    entry.publish();
  }

  void remove(String id) {
    final entry = _owners[id];
    if (entry == null) return;
    if (entry.length == 1) {
      _structure(const [], removed: id);
      return;
    }
    imageResources.dropItem(id);
    entry.removeMember(id);
    _ids.remove(id);
    _owners.remove(id);
    _streams.remove(id)?.dispose();
    _commitEntry(entry);
    entry.publish();
  }

  void _commitEntry(TimelineEntry entry) {
    final previous = _messageIds[entry] ?? const <String>[];
    final messages = _project(entry);
    final nextIds = [for (final message in messages) message.id];
    _messageIds[entry] = nextIds;
    if (previous.isNotEmpty && listEquals(previous, nextIds)) {
      final start = _positions[previous.first]!;
      final end = start + previous.length;
      final left = start == 0
          ? null
          : timelineEntryOf(_messages[_order[start - 1]]!);
      final right = end == _order.length
          ? null
          : timelineEntryOf(_messages[_order[end]]!);
      if ((left == null || compareItems(left.first, entry.first) < 0) &&
          (right == null || compareItems(entry.first, right.first) < 0)) {
        for (final message in messages) {
          final old = _messages[message.id]!;
          _messages[message.id] = message;
          unawaited(controller.updateMessage(old, message));
        }
        return;
      }
    }
    for (final id in previous) {
      _removeStock(id);
    }
    var low = 0;
    var high = _order.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final other = timelineEntryOf(_messages[_order[middle]]!)!;
      if (compareItems(other.first, entry.first) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _insertStock(messages, low);
  }

  bool _sameAttachments(ConversationItem previous, ConversationItem next) {
    final left = timelineAttachments(previous);
    final right = timelineAttachments(next);
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id ||
          left[index].modality != right[index].modality) {
        return false;
      }
    }
    return true;
  }

  bool _sameStructure(ConversationItem previous, ConversationItem next) =>
      timelineKind(previous) == timelineKind(next) &&
      previous.header.turnId == next.header.turnId &&
      compareItems(previous, next) == 0 &&
      (previous.source is ConversationRecoverySource
          ? next.source is ConversationRecoverySource &&
                (previous.source as ConversationRecoverySource).attemptId ==
                    (next.source as ConversationRecoverySource).attemptId
          : next.source is! ConversationRecoverySource) &&
      _sameAttachments(previous, next);

  void replace(String id, ConversationItem next) {
    final entry = _owners[id]!;
    if (!_sameStructure(entry.item(id)!, next)) {
      _structure([next]);
      return;
    }
    imageResources.retainItem(next.id, timelineAttachments(next));
    entry.replace(id, next);
    if (entry.kind != TimelineEntryKind.single) return;
    // No application-level history/group lookup on the content hot path.
    // Attachments and order are known unchanged, so update existing references.
    for (final message in _project(entry)) {
      final previous = _messages[message.id]!;
      _messages[message.id] = message;
      unawaited(controller.updateMessage(previous, message));
    }
  }

  /// A page / structural change is a single local topology transaction. Until
  /// every partition and anchor is known, nothing is published to stock Chat.
  void _structure(Iterable<ConversationItem> values, {String? removed}) {
    final incoming = values.toList(growable: false);
    if (removed != null) imageResources.dropItem(removed);
    for (final value in incoming) {
      imageResources.retainItem(value.id, timelineAttachments(value));
    }
    final affected = <TimelineEntry>{};
    void around(int index) {
      for (final step in [-1, 1]) {
        var cursor = step < 0 ? index - 1 : index;
        while (cursor >= 0 && cursor < _ids.length) {
          final entry = _owners[_ids[cursor]]!;
          if (entry.kind != TimelineEntryKind.hidden) {
            affected.add(entry);
            break;
          }
          cursor += step;
        }
      }
    }

    if (removed != null) {
      final entry = _owners[removed]!;
      affected.add(entry);
      final index = _ids.indexOf(removed);
      around(index);
      _ids.removeAt(index);
      around(index);
    }
    for (final value in incoming) {
      final previous = _owners[value.id];
      if (previous != null) {
        affected.add(previous);
        final index = _ids.indexOf(value.id);
        around(index);
        _ids.removeAt(index);
        around(index);
        previous.stage(value);
      }
      final index = _insertion(value);
      around(index);
      if (previous == null) {
        final staging = _newEntry(value)..resetMembers([value]);
        _owners[value.id] = staging;
        affected.add(staging);
      }
      _ids.insert(index, value.id);
    }
    if (affected.isEmpty) return;

    // Transaction-local maps contain only IDs and the already owned row/entry
    // references. They do not cache/copy historical body values.
    final rows = <String, TimelineMember>{};
    final previousOwners = <String, TimelineEntry>{};
    final intents = <TimelineEntry, (bool, Set<String>)>{};
    final anchorOwners = <String, List<TimelineEntry>>{};
    final oldMessageIds = <String>{};
    for (final entry in affected) {
      intents[entry] = (entry.expanded, {...entry.expandedMembers});
      oldMessageIds.addAll(_messageIds[entry] ?? const []);
      for (final value in entry.members) {
        if (value.id == removed) continue;
        rows[value.id] = entry.member(value.id);
        previousOwners[value.id] = entry;
      }
      if (entry.anchorItemId == removed) {
        final survivors = entry.memberIds.where((id) => id != removed);
        if (survivors.isNotEmpty) entry.anchorItemId = survivors.first;
      }
      if (entry.anchorItemId != removed) {
        (anchorOwners[entry.anchorItemId] ??= []).add(entry);
      }
    }
    final sorted = rows.keys.toList()
      ..sort((a, b) => compareItems(rows[a]!.item, rows[b]!.item));
    // Separate affected neighborhoods may have untouched visible entries in
    // between (for example, an ordinal move). Never join across that boundary.
    final rawPositions = <String, int>{
      for (var index = 0; index < _ids.length; index++) _ids[index]: index,
    };
    final previousVisible = <String, String?>{};
    for (final id in sorted) {
      var cursor = rawPositions[id]! - 1;
      while (cursor >= 0) {
        final previousId = _ids[cursor];
        final row = rows[previousId];
        final kind = row == null
            ? _owners[previousId]!.kind
            : timelineKind(row.item);
        if (kind != TimelineEntryKind.hidden) break;
        cursor--;
      }
      previousVisible[id] = cursor < 0 ? null : _ids[cursor];
    }
    final partitions = <List<String>>[];
    List<String>? visible;
    for (final id in sorted) {
      final value = rows[id]!.item;
      if (timelineKind(value) == TimelineEntryKind.hidden) {
        partitions.add([id]);
      } else if (visible != null &&
          previousVisible[id] == visible.last &&
          _joins(rows[visible.last]!.item, value)) {
        visible.add(id);
      } else {
        visible = [id];
        partitions.add(visible);
      }
    }
    final retained = <TimelineEntry>{};
    final partitionOwners = <TimelineEntry, List<String>>{};
    for (final partition in partitions) {
      TimelineEntry? owner;
      for (final id in partition) {
        for (final candidate in anchorOwners[id] ?? const <TimelineEntry>[]) {
          if (owner == null || candidate.serial < owner.serial) {
            owner = candidate;
          }
        }
      }
      owner ??= _newEntry(rows[partition.first]!.item);
      retained.add(owner);
      partitionOwners[owner] = partition;
      owner.kind = timelineKind(rows[partition.first]!.item);
      owner.expanded = false;
      final expandedMembers = <String>{};
      for (final id in partition) {
        final intent = intents[previousOwners[id]]!;
        owner.expanded = owner.expanded || intent.$1;
        if (intent.$2.contains(id)) expandedMembers.add(id);
        _owners[id] = owner;
      }
      owner.stageExpandedMembers(expandedMembers);
    }
    if (removed != null) {
      _owners.remove(removed);
      _streams.remove(removed)?.dispose();
    }
    for (final id in rows.keys) {
      final value = rows[id]!.item;
      if (_owners[id]!.kind != TimelineEntryKind.single ||
          value.descriptor is! ConversationTextDescriptor ||
          value.terminal ||
          timelineAuthor(value) != 'assistant') {
        _streams.remove(id)?.dispose();
      }
    }
    // Every ownership index is final before row/entry notifications begin.
    for (final entry in retained) {
      entry.resetMembers(partitionOwners[entry]!.map((id) => rows[id]!.item));
    }
    final projected = <String, Message>{};
    for (final entry in affected) {
      _messageIds.remove(entry);
    }
    final orderedEntries = retained.toList()
      ..sort((a, b) => compareItems(a.first, b.first));
    for (final entry in orderedEntries) {
      final messages = _project(entry);
      _messageIds[entry] = [for (final message in messages) message.id];
      for (final message in messages) {
        projected[message.id] = message;
      }
    }
    _commitStructure(oldMessageIds, projected);
    for (final entry in retained) {
      entry.publish();
      entry.publishMembers();
    }
    for (final entry in affected.difference(retained)) {
      // Structural observers rebind by item ID while every new owner/member
      // index is already committed. Notify before disposing the old notifier.
      entry.publish();
      entry.dispose();
    }
  }

  void _reindex(int start) {
    for (var index = start; index < _order.length; index++) {
      _positions[_order[index]] = index;
    }
  }

  void _removeStock(String id) {
    final message = _messages.remove(id)!;
    final index = _positions.remove(id)!;
    _order.removeAt(index);
    _reindex(index);
    unawaited(controller.removeMessage(message, animated: false));
  }

  void _insertStock(List<Message> messages, int index) {
    if (messages.isEmpty) return;
    _order.insertAll(index, messages.map((message) => message.id));
    for (final message in messages) {
      _messages[message.id] = message;
    }
    _reindex(index);
    unawaited(
      controller.insertAllMessages(messages, index: index, animated: false),
    );
  }

  void _commitStructure(Set<String> previous, Map<String, Message> projected) {
    // Only IDs are retained for structural ordering. Stock messages themselves
    // are accessed through same-object references, not controller list scans.
    final desired = [
      for (final id in _order)
        if (!previous.contains(id)) id,
    ];
    for (final id in projected.keys) {
      final next = projected[id]!;
      final entry = timelineEntryOf(next)!;
      var low = 0;
      var high = desired.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        final other = timelineEntryOf(
          projected[desired[middle]] ?? _messages[desired[middle]]!,
        )!;
        final comparison = compareItems(other.first, entry.first);
        // projected is entry-ordered with attachment siblings in fixed order.
        if (comparison <= 0) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      desired.insert(low, id);
    }
    for (final id in previous) {
      if (!projected.containsKey(id)) _removeStock(id);
    }
    // Batch only genuinely new messages preceding every existing message.
    final prefix = <Message>[];
    for (final id in desired) {
      if (_messages.containsKey(id)) break;
      prefix.add(projected[id]!);
    }
    _insertStock(prefix, 0);
    for (var index = 0; index < desired.length; index++) {
      final id = desired[index];
      while (index < _order.length &&
          _order[index] != id &&
          !projected.containsKey(id)) {
        _removeStock(_order[index]);
      }
      if (index >= _order.length || _order[index] != id) {
        if (_messages.containsKey(id)) _removeStock(id);
        _insertStock([projected[id]!], index);
      } else if (projected[id] case final next?) {
        final previous = _messages[id]!;
        _messages[id] = next;
        unawaited(controller.updateMessage(previous, next));
      }
    }
  }

  Message _primary(TimelineEntry entry) {
    final item = entry.first;
    final metadata = <String, dynamic>{
      timelineEntryKey: entry,
      'version': entry.version,
      'revision': item.revision,
    };
    final author = timelineAuthor(item);
    if (entry.kind != TimelineEntryKind.single ||
        item.descriptor is! ConversationTextDescriptor ||
        author != 'assistant' ||
        item.terminal) {
      _streams.remove(item.id)?.dispose();
    }
    if (entry.kind == TimelineEntryKind.single &&
        item.descriptor is ConversationTextDescriptor) {
      final text = timelineText(item);
      if (author == 'assistant' && !item.terminal) {
        final stream = _streams.putIfAbsent(
          item.id,
          () => ValueNotifier<StreamState>(const StreamStateLoading()),
        );
        stream.value = StreamStateStreaming(text);
        return Message.textStream(
          id: entry.id,
          authorId: author,
          streamId: '$generation:${item.id}',
          createdAt: item.header.createdAt,
          updatedAt: item.header.updatedAt,
          metadata: metadata,
        );
      }
      _streams.remove(item.id)?.dispose();
      return Message.text(
        id: entry.id,
        authorId: author,
        text: text,
        createdAt: item.header.createdAt,
        updatedAt: item.header.updatedAt,
        metadata: metadata,
      );
    }
    return Message.custom(
      id: entry.id,
      authorId: author,
      createdAt: item.header.createdAt,
      metadata: metadata,
    );
  }

  List<Message> _project(TimelineEntry entry) {
    final primary = _primary(entry);
    final messages = <Message>[primary];
    if (entry.kind == TimelineEntryKind.single) {
      final item = entry.first;
      final attachments = timelineAttachments(item);
      final descriptor = item.descriptor;
      final projectedAttachments =
          descriptor is ConversationToolDescriptor &&
              descriptor.invocation.name == 'show_image'
          ? attachments
                .where(
                  (attachment) =>
                      attachment.modality == AttachmentModalityView.image,
                )
                .take(1)
          : attachments;
      for (final attachment in projectedAttachments) {
        final id = '${item.id}:attachment:${attachment.id}';
        final metadata = <String, dynamic>{
          timelineEntryKey: entry,
          'attachment': attachment,
        };
        // Opaque identity, never a filesystem path or remote credentialed URL.
        final source = 'anywork-attachment:${attachment.id}';
        messages.add(
          attachment.modality == AttachmentModalityView.image
              ? Message.image(
                  id: id,
                  authorId: primary.authorId,
                  source: source,
                  width: attachment.width?.toDouble(),
                  height: attachment.height?.toDouble(),
                  size: attachment.byteSize,
                  metadata: metadata,
                )
              : Message.file(
                  id: id,
                  authorId: primary.authorId,
                  source: source,
                  name: attachment.filename ?? attachment.mediaType,
                  size: attachment.byteSize,
                  mimeType: attachment.mediaType,
                  metadata: metadata,
                ),
        );
      }
    }
    return messages;
  }

  void dispose() {
    for (final stream in _streams.values) {
      stream.dispose();
    }
    for (final entry in _messageIds.keys) {
      entry.dispose();
    }
    _streams.clear();
    _owners.clear();
    _ids.clear();
    _messageIds.clear();
    _messages.clear();
    _order.clear();
    _positions.clear();
  }
}
