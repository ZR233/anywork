part of 'timeline_presentation.dart';

/// Incremental GUI projection. Indexes contain identity/position or references to the same owners;
/// the stock controller's custom messages own the only loaded preview values.
final class TimelinePresentationController {
  TimelinePresentationController(this.controller, {required this.generation});
  final InMemoryChatController controller;
  final int generation;
  final _ordered = SplayTreeMap<TimelineCanonicalKey, String>(_compareKeys);
  final _visible = SplayTreeMap<TimelineCanonicalKey, String>(_compareKeys);
  final Map<String, TimelinePresentationItem> _owners = {};
  final Map<TimelinePresentationItem, Message> _messages = {};
  final Map<(String, String, String), TimelineRecoveryGroup> _recoveries = {};
  final Set<TimelineItemListener> _listeners = {};
  final Set<TimelinePresentationItem> _structuralChanges = {};
  int _serial = 0;

  int get length => _owners.length;
  bool contains(String id) => _owners.containsKey(id);
  TimelineMessagePayload? payload(String id) => _owners[id]?.payload(id);
  TimelinePresentationItem? ownerOf(String id) => _owners[id];
  Iterable<TimelineMessagePayload> get payloads sync* {
    for (final id in _ordered.values) {
      yield _owners[id]!.payload(id)!;
    }
  }

  void addItemListener(TimelineItemListener listener) =>
      _listeners.add(listener);
  void removeItemListener(TimelineItemListener listener) =>
      _listeners.remove(listener);
  void _emit(String id, TimelineMessagePayload? payload) {
    for (final listener in List<TimelineItemListener>.of(_listeners)) {
      listener(id, payload);
    }
  }

  void add(TimelineMessagePayload payload) {
    _add(_PresentationMember(payload));
    _publishStructure();
  }

  void _publishStructure() {
    final changes = List<TimelinePresentationItem>.of(_structuralChanges);
    _structuralChanges.clear();
    for (final group in changes) {
      if (_messages.containsKey(group)) group._publishStructure();
    }
  }

  void _add(
    _PresentationMember member, {
    bool emit = true,
    ({String id, int serial})? identity,
  }) {
    final payload = member.value;
    final key = (payload.order, payload.id);
    if (_owners.containsKey(payload.id)) {
      throw StateError('Duplicate timeline identity: ${payload.id}');
    }
    final visible = timelinePayloadIsVisible(payload);
    final before = visible ? _neighbor(_visible.lastKeyBefore(key)) : null;
    final after = visible ? _neighbor(_visible.firstKeyAfter(key)) : null;
    final kind = _kindOf(payload);
    if (before != null &&
        identical(before, after) &&
        !_accepts(before, payload)) {
      _split(before, key);
    }
    TimelinePresentationItem? group;
    if (identity == null && kind == TimelinePresentationKind.recovery) {
      final source = payload.source as StudioTimelineRecoverySource;
      group =
          _recoveries[(
            payload.item.threadId,
            payload.item.turnId,
            source.attemptId,
          )];
    } else if (identity == null && kind != TimelinePresentationKind.single) {
      // Splitting may have moved one neighbor to its new owner.
      final left = _neighbor(_visible.lastKeyBefore(key));
      final right = _neighbor(_visible.firstKeyAfter(key));
      if (left != null && _accepts(left, payload)) group = left;
      if (right != null && _accepts(right, payload)) {
        group = group == null || identical(group, right)
            ? right
            : _merge(group, right);
      }
    }
    final created = group == null;
    group ??= _create(payload, identity: identity);
    group._insert(member);
    _owners[payload.id] = group;
    _ordered[key] = payload.id;
    if (visible) _visible[key] = payload.id;
    if (created) _insertMessage(group);
    if (identity != null &&
        kind != TimelinePresentationKind.single &&
        kind != TimelinePresentationKind.recovery) {
      final left = _neighbor(_visible.lastKeyBefore(key));
      final right = _neighbor(_visible.firstKeyAfter(key));
      if (left != null && !identical(left, group) && _accepts(left, payload)) {
        group = _merge(group, left);
      }
      if (right != null &&
          !identical(right, group) &&
          _accepts(right, payload)) {
        group = _merge(group, right);
      }
    }
    _structuralChanges.add(group);
    if (emit) _emit(payload.id, payload);
  }

  bool _accepts(
    TimelinePresentationItem group,
    TimelineMessagePayload payload,
  ) =>
      group.kind != TimelinePresentationKind.single &&
      group.kind == _kindOf(payload) &&
      group.first.item.threadId == payload.item.threadId &&
      group.first.item.turnId == payload.item.turnId &&
      group.first.item.contextDisposition == payload.item.contextDisposition;

  TimelinePresentationItem? _neighbor(TimelineCanonicalKey? key) =>
      key == null ? null : _owners[_visible[key]];

  TimelinePresentationItem _create(
    TimelineMessagePayload payload, {
    ({String id, int serial})? identity,
  }) {
    final serial = identity?.serial ?? ++_serial;
    final id = identity?.id ?? 'presentation:$generation:$serial';
    return switch (_kindOf(payload)) {
      TimelinePresentationKind.single => TimelineSingleItem(
        id: identity?.id ?? payload.id,
        serial: serial,
        anchor: payload,
      ),
      TimelinePresentationKind.activity => TimelineActivityGroup(
        id: id,
        serial: serial,
        anchor: payload,
      ),
      TimelinePresentationKind.images => TimelineImageReadGroup(
        id: id,
        serial: serial,
        anchor: payload,
      ),
      TimelinePresentationKind.recovery => _createRecovery(id, serial, payload),
    };
  }

  TimelineRecoveryGroup _createRecovery(
    String id,
    int serial,
    TimelineMessagePayload payload,
  ) {
    final source = payload.source as StudioTimelineRecoverySource;
    final group = TimelineRecoveryGroup(
      id: id,
      serial: serial,
      anchor: payload,
      attemptId: source.attemptId,
    );
    _recoveries[(
          payload.item.threadId,
          payload.item.turnId,
          source.attemptId,
        )] =
        group;
    return group;
  }

  void replace(String id, TimelineMessagePayload next) {
    final group = _owners[id]!;
    final previous = group.payload(id)!;
    final recoveryMatches =
        previous.source is! StudioTimelineRecoverySource ||
        next.source is StudioTimelineRecoverySource &&
            (previous.source as StudioTimelineRecoverySource).attemptId ==
                (next.source as StudioTimelineRecoverySource).attemptId;
    if (group.kind == _kindOf(next) &&
        recoveryMatches &&
        previous.item.threadId == next.item.threadId &&
        previous.item.turnId == next.item.turnId &&
        previous.item.contextDisposition == next.item.contextDisposition &&
        timelinePayloadIsVisible(previous) == timelinePayloadIsVisible(next)) {
      group._replace(id, next);
      if (group is TimelineSingleItem) {
        final old = _messages[group]!;
        final message = _messageForPresentation(group);
        _messages[group] = message;
        unawaited(controller.updateMessage(old, message));
      }
    } else {
      final expanded = group.expanded;
      final identity = group.anchorId == id
          ? (id: group.id, serial: group.serial)
          : null;
      if (identity != null && group.length > 1) {
        // The original display identity follows its anchor through reclassification.
        // The remaining side receives a new owner while retaining its member listenables.
        final remaining = group.memberIds
            .where((memberId) => memberId != id)
            .toList();
        final split = _create(group.payload(remaining.first)!)
          ..expanded = expanded;
        for (final memberId in remaining) {
          split._insert(group._take(memberId));
          _owners[memberId] = split;
        }
        _insertMessage(split);
        _structuralChanges.add(split);
      }
      final member = _remove(id, emit: false);
      member.replace(next, notify: false);
      _add(member, emit: false, identity: identity);
      if (expanded) _owners[id]!.setExpanded(true);
      _publishStructure();
      member.publish();
    }
    _emit(id, next);
  }

  void remove(String id) {
    if (!_owners.containsKey(id)) return;
    _remove(id).dispose();
    _publishStructure();
  }

  _PresentationMember _remove(String id, {bool emit = true}) {
    final group = _owners.remove(id)!;
    final payload = group.payload(id)!;
    final key = (payload.order, payload.id);
    _ordered.remove(key);
    _visible.remove(key);
    final position = group.position;
    final member = group._take(id);
    if (group.length == 0) {
      _dropMessage(group);
    } else {
      if (position != group.position) _reposition(group);
      _structuralChanges.add(group);
    }
    final left = _neighbor(_visible.lastKeyBefore(key));
    final right = _neighbor(_visible.firstKeyAfter(key));
    if (left != null &&
        right != null &&
        !identical(left, right) &&
        _accepts(left, right.first) &&
        left is! TimelineRecoveryGroup) {
      _merge(left, right);
    }
    if (emit) _emit(id, null);
    return member;
  }

  TimelinePresentationItem _merge(
    TimelinePresentationItem left,
    TimelinePresentationItem right,
  ) {
    final keep = left.serial <= right.serial ? left : right;
    final drop = identical(keep, left) ? right : left;
    keep.expanded = keep.expanded || drop.expanded;
    final ids = List<String>.of(drop._ids);
    for (final id in ids) {
      keep._insert(drop._take(id));
      _owners[id] = keep;
    }
    _dropMessage(drop);
    _structuralChanges.add(keep);
    return keep;
  }

  void _split(TimelinePresentationItem group, TimelineCanonicalKey boundary) {
    if (group is! TimelineActivityGroup && group is! TimelineImageReadGroup) {
      return;
    }
    final anchor = group.payload(group.anchorId)!;
    final keepRight = _compareKeys((anchor.order, anchor.id), boundary) > 0;
    final moving = [
      for (final payload in group.payloads)
        if ((_compareKeys((payload.order, payload.id), boundary) < 0) ==
            keepRight)
          payload.id,
    ];
    if (moving.isEmpty || moving.length == group.length) return;
    final split = _create(group.payload(moving.first)!)
      ..expanded = group.expanded;
    for (final id in moving) {
      split._insert(group._take(id));
      _owners[id] = split;
    }
    _insertMessage(split);
    _structuralChanges.addAll([group, split]);
  }

  void _reposition(TimelinePresentationItem group) {
    final messages = controller.messages;
    final current = _messages[group]!;
    final index = messages.indexOf(current);
    if ((index == 0 ||
            _compareKeys(
                  timelinePresentationOf(messages[index - 1])!.position,
                  group.position,
                ) <=
                0) &&
        (index == messages.length - 1 ||
            _compareKeys(
                  group.position,
                  timelinePresentationOf(messages[index + 1])!.position,
                ) <=
                0)) {
      return;
    }
    // A real anchor deletion can cross an invisible bookkeeping row. Keep the ID and owner;
    // express the necessary move with the stock controller's public operations.
    unawaited(controller.removeMessage(current, animated: false));
    _insertMessage(group);
  }

  void _insertMessage(TimelinePresentationItem group) {
    final message = _messageForPresentation(group);
    final messages = controller.messages;
    var low = 0;
    var high = messages.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final other = timelinePresentationOf(messages[middle])!;
      if (_compareKeys(other.position, group.position) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _messages[group] = message;
    unawaited(controller.insertMessage(message, index: low, animated: false));
  }

  void _dropMessage(TimelinePresentationItem group) {
    _structuralChanges.remove(group);
    final message = _messages.remove(group)!;
    if (group is TimelineRecoveryGroup) {
      _recoveries.removeWhere((_, value) => identical(value, group));
    }
    unawaited(controller.removeMessage(message, animated: false));
    group.dispose();
  }

  void dispose() {
    _listeners.clear();
    _clear();
  }

  void reset() {
    _clear();
    unawaited(controller.setMessages(const [], animated: false));
  }

  void _clear() {
    for (final group in _messages.keys) {
      group.dispose();
    }
    _messages.clear();
    _ordered.clear();
    _visible.clear();
    _owners.clear();
    _recoveries.clear();
    _structuralChanges.clear();
  }
}
