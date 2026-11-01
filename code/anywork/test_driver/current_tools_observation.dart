import 'dart:convert';

/// A query of existing Driver facts. Parsing never expands or reads a resource.
final class CurrentToolsObservation {
  CurrentToolsObservation._(
    this.threadId,
    this.mainGeneration,
    this.turnId,
    this.childrenParentId,
    this.activityId,
    this.expanded,
    this.collection,
    this.windows,
  );

  static CurrentToolsObservation? optional(Map<String, dynamic> snapshot) {
    final timeline = snapshot['timeline'];
    if (timeline == null) return null;
    final main = _map(timeline, 'timeline');
    if (!main.containsKey('current')) {
      throw StateError('timeline.current is absent');
    }
    if (main['current'] == null) return null;
    final current = _map(main['current'], 'timeline.current');
    final expanded = _bool(current, 'expanded');
    CurrentToolsCollection? tools;
    for (final raw in _list(current, 'collections')) {
      final value = _map(raw, 'current collection');
      if (value['collection'] != 'tools') continue;
      if (tools != null) throw StateError('duplicate current tools collection');
      tools = CurrentToolsCollection.parse(value, outerExpanded: expanded);
    }
    return CurrentToolsObservation._(
      _string(main, 'threadId'),
      _int(main, 'generation'),
      _optionalString(current, 'turnId'),
      _optionalString(current, 'childrenParentId'),
      _optionalString(current, 'activityId'),
      expanded,
      tools,
      _list(current, 'windows'),
    );
  }

  final String threadId;
  final int mainGeneration;
  final String? turnId, childrenParentId, activityId;
  final bool expanded;
  final CurrentToolsCollection? collection;
  final List<dynamic> windows;

  Object get owner =>
      (threadId, mainGeneration, turnId, childrenParentId, activityId);
  Object get qualification =>
      (owner, collection?.reference, collection?.generation);

  String requireChildrenParentId() =>
      childrenParentId ??
      (throw StateError('Current Turn has no observed childrenParentId'));

  void requirePage() {
    final page = collection;
    if (!expanded ||
        page == null ||
        !page.expanded ||
        !page.ready ||
        page.loading ||
        page.error != null) {
      throw StateError(
        'No qualified visible current tools page: ${evidence()}',
      );
    }
  }

  void requireSame(CurrentToolsObservation previous) {
    previous.requirePage();
    if (collection?.error case final error?) {
      throw StateError('Current tools read failed: $error');
    }
    if (qualification != previous.qualification) {
      throw StaleCurrentTools('Current tools qualification changed');
    }
    requirePage();
  }

  CurrentToolObservation? toolByPrefix(String prefix) {
    requirePage();
    final matches = <CurrentToolObservation>[];
    for (final entry in collection!.entries) {
      final tool = decode(entry);
      if (tool != null && tool.callId.startsWith(prefix)) matches.add(tool);
    }
    if (matches.length > 1) {
      throw StateError('ambiguous current call prefix $prefix');
    }
    return matches.singleOrNull;
  }

  CurrentToolObservation? toolByCallId(String callId) {
    requirePage();
    for (final entry in collection!.entries) {
      final tool = decode(entry);
      if (tool?.callId == callId) return tool;
    }
    return null;
  }

  CurrentToolObservation? decode(CurrentToolEntry entry) {
    requirePage();
    if (entry.inline != null) {
      return CurrentToolObservation.parse(entry, entry.inline!);
    }
    // Deferred remains unknown until an explicitly displayed, complete window
    // with the original reference is actually present. Never parse an excerpt.
    for (final raw in windows) {
      final view = _map(raw, 'current window');
      if (view['id'] != entry.id ||
          canonicalCurrentJson(view['reference']) !=
              canonicalCurrentJson(entry.reference)) {
        continue;
      }
      if (_optionalString(view, 'error') case final error?) {
        throw StateError('Current entry window failed: $error');
      }
      if (view['window'] == null) continue;
      final window = _map(view['window'], 'current window bytes');
      final bytes = _bytes(window);
      final generation = _int(window, 'generation');
      if (_int(view, 'offset') != 0 ||
          _int(window, 'offset') != 0 ||
          bytes.length > 64 * 1024 ||
          !_bool(window, 'sealed') ||
          _int(window, 'availableThrough') != entry.byteLength ||
          bytes.length != entry.byteLength) {
        continue;
      }
      return CurrentToolObservation.parse(
        entry,
        bytes,
        windowGeneration: generation,
      );
    }
    return null;
  }

  Map<String, Object?> evidence() => {
    'threadId': threadId,
    'mainGeneration': mainGeneration,
    'turnId': turnId,
    'childrenParentId': childrenParentId,
    'activityId': activityId,
    'expanded': expanded,
    if (collection case final page?) ...page.evidence(),
  };
}

final class CurrentToolsCollection {
  CurrentToolsCollection._(
    this.databaseId,
    this.revision,
    this.generation,
    this.expanded,
    this.loading,
    this.error,
    this.ready,
    this.continuation,
    this.entries,
  );

  factory CurrentToolsCollection.parse(
    Map<String, dynamic> map, {
    required bool outerExpanded,
  }) {
    final expanded = _bool(map, 'expanded');
    final ready = _bool(map, 'ready');
    final raw = _list(map, 'entries');
    if (!map.containsKey('continuation') || !map.containsKey('error')) {
      throw StateError('Current tools cursor/error is not observable');
    }
    if (raw.isNotEmpty && (!expanded || !outerExpanded || !ready)) {
      throw StateError(
        'Driver exposed a page outside its actual expanded display',
      );
    }
    final entries = <CurrentToolEntry>[];
    final ids = <String>{};
    for (final value in raw) {
      final entry = CurrentToolEntry.parse(_map(value, 'current entry'));
      if (!ids.add(entry.id) ||
          (entries.isNotEmpty && entry.compareOrderTo(entries.last) <= 0)) {
        throw StateError('Current page has duplicated or reordered entries');
      }
      entries.add(entry);
    }
    return CurrentToolsCollection._(
      _string(map, 'databaseId'),
      _int(map, 'revision'),
      _int(map, 'generation'),
      expanded,
      _bool(map, 'loading'),
      _optionalString(map, 'error'),
      ready,
      _optionalString(map, 'continuation'),
      List.unmodifiable(entries),
    );
  }

  final String databaseId;
  final int revision, generation;
  final bool expanded, loading, ready;
  final String? error, continuation;
  final List<CurrentToolEntry> entries;
  Object get reference => (databaseId, 'tools', revision);
  Map<String, Object?> evidence() => {
    'databaseId': databaseId,
    'collection': 'tools',
    'revision': revision,
    'generation': generation,
    'collectionExpanded': expanded,
    'loading': loading,
    'ready': ready,
    'error': error,
    'continuation': continuation,
  };
}

final class CurrentToolEntry {
  CurrentToolEntry._(
    this.id,
    this.position,
    this.byteLength,
    this.inline,
    this.reference,
  );
  factory CurrentToolEntry.parse(Map<String, dynamic> map) {
    final payload = _map(map['payload'], 'current payload');
    final bytes = switch (payload['kind']) {
      'inline' => _bytes(payload),
      'deferred' => null,
      _ => throw StateError('Unknown current payload kind'),
    };
    final reference = bytes == null
        ? _map(payload['reference'], 'Deferred reference')
        : null;
    return CurrentToolEntry._(
      _string(map, 'id'),
      _signedInt(map, 'position'),
      _int(payload, 'byteLength'),
      bytes,
      reference,
    );
  }
  final String id;
  final int position, byteLength;
  final List<int>? inline;
  final Map<String, dynamic>? reference;

  // The producer cursor orders (i64 position, String id), including equal
  // positions. Rust String order compares UTF-8 bytes rather than UTF-16 units.
  int compareOrderTo(CurrentToolEntry other) {
    final order = position.compareTo(other.position);
    if (order != 0) return order;
    final left = utf8.encode(id);
    final right = utf8.encode(other.id);
    for (var index = 0; index < left.length && index < right.length; index++) {
      final order = left[index].compareTo(right[index]);
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }
}

/// Exact ThreadActivityToolEntry JSON, not a completed Tool item DTO.
final class CurrentToolObservation {
  CurrentToolObservation._(
    this.entry,
    this.raw,
    this.callId,
    this.name,
    this.summary,
    this.arguments,
    this.state,
    this.ordinal,
    this.startedAt,
    this.taskId,
    this.wait,
    this.windowGeneration,
  );
  factory CurrentToolObservation.parse(
    CurrentToolEntry entry,
    List<int> bytes, {
    int? windowGeneration,
  }) {
    final raw = utf8.decode(bytes);
    final map = _map(jsonDecode(raw), 'ThreadActivityToolEntry');
    final arguments = _enum(map, 'arguments', {
      'commandLine',
      'opaque',
      'streaming',
      'unavailable',
    });
    final state = _enum(map, 'state', {
      'running',
      'awaitingApproval',
      'cancelling',
      'finished',
    });
    return CurrentToolObservation._(
      entry,
      raw,
      _string(map, 'callId'),
      _string(map, 'name'),
      _string(map, 'summary', empty: true),
      arguments,
      state,
      map['ordinal'] == null ? null : _int(map, 'ordinal'),
      map['startedAt'] == null ? null : _signedInt(map, 'startedAt'),
      _optionalString(map, 'taskId'),
      map['wait'] == null
          ? null
          : CurrentWaitObservation.parse(_map(map['wait'], 'wait')),
      windowGeneration,
    );
  }
  final CurrentToolEntry entry;
  final String raw, callId, name, summary, arguments, state;
  final int? ordinal, startedAt, windowGeneration;
  final String? taskId;
  final CurrentWaitObservation? wait;
  bool get waiting => state == 'running' && wait?.state == 'waiting';
  Map<String, Object?> evidence() => {
    'entryId': entry.id,
    'position': entry.position,
    'callId': callId,
    'name': name,
    'summary': summary,
    'payloadByteLength': entry.byteLength,
    'arguments': arguments,
    'state': state,
    'taskId': taskId,
    'ordinal': ordinal,
    'startedAt': startedAt,
    'wait': wait?.raw,
    'reference': entry.reference,
    'windowGeneration': windowGeneration,
  };
}

final class CurrentWaitObservation {
  CurrentWaitObservation._(
    this.raw,
    this.kind,
    this.state,
    this.targets,
    this.timeoutMs,
    this.durationMs,
    this.messagesReady,
  );
  factory CurrentWaitObservation.parse(Map<String, dynamic> map) {
    final state = _enum(map, 'state', {
      'waiting',
      'ready',
      'timedOut',
      'elapsed',
      'cancelled',
      'failed',
      'interrupted',
    });
    final intent = _map(map['intent'], 'wait.intent');
    final data = _map(intent['data'], 'wait.intent.data');
    final kind = _enum(intent, 'kind', {'events', 'timer'});
    final targets = <CurrentWaitTarget>[];
    final ids = <String>{};
    if (kind == 'events') {
      for (final raw in _list(data, 'targets')) {
        final target = CurrentWaitTarget.parse(_map(raw, 'wait target'));
        if (!ids.add(target.taskId)) throw StateError('Duplicated wait target');
        targets.add(target);
      }
    }
    final messagesReady = map['messagesReady'] == null
        ? null
        : _bool(map, 'messagesReady');
    if (messagesReady != null && state != 'ready') {
      throw StateError('messagesReady is only a Ready fact');
    }
    return CurrentWaitObservation._(
      map,
      kind,
      state,
      List.unmodifiable(targets),
      kind == 'events' ? _int(data, 'timeoutMs') : null,
      kind == 'timer' ? _int(data, 'durationMs') : null,
      messagesReady,
    );
  }
  final Map<String, dynamic> raw;
  final String kind, state;
  final List<CurrentWaitTarget> targets;
  final int? timeoutMs, durationMs;
  final bool? messagesReady;
  CurrentWaitTarget? target(String taskId) =>
      targets.where((target) => target.taskId == taskId).singleOrNull;

  bool targetsRunning(Iterable<String?> expected) {
    final ids = expected.toList();
    if (state != 'waiting' ||
        kind != 'events' ||
        ids.any((id) => id == null) ||
        ids.toSet().length != ids.length ||
        targets.length != ids.length) {
      return false;
    }
    return targets.every(
      (target) => ids.contains(target.taskId) && target.status == 'running',
    );
  }
}

final class CurrentWaitTarget {
  CurrentWaitTarget._(
    this.taskId,
    this.toolName,
    this.summary,
    this.summaryTruncated,
    this.status,
  );
  factory CurrentWaitTarget.parse(Map<String, dynamic> map) =>
      CurrentWaitTarget._(
        _string(map, 'taskId'),
        _optionalString(map, 'toolName'),
        _optionalString(map, 'summary'),
        map.containsKey('summaryTruncated')
            ? _bool(map, 'summaryTruncated')
            : false,
        map['status'] == null
            ? null
            : _enum(map, 'status', {
                'running',
                'succeeded',
                'failed',
                'cancelled',
                'interrupted',
              }),
      );
  final String taskId;
  final String? toolName, summary, status;
  // Rust serde explicitly defaults this boolean to false.
  final bool summaryTruncated;
}

final class StaleCurrentTools implements Exception {
  StaleCurrentTools(this.message);
  final String message;
  @override
  String toString() => 'StaleCurrentTools: $message';
}

String canonicalCurrentJson(Object? value) => jsonEncode(_sorted(value));
Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final key in (value.keys.cast<String>().toList()..sort()))
      key: _sorted(value[key]),
  },
  List() => [for (final item in value) _sorted(item)],
  _ => value,
};
Map<String, dynamic> _map(Object? value, String context) {
  if (value is! Map) throw StateError('$context is not an object');
  return value.cast<String, dynamic>();
}

List<dynamic> _list(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) throw StateError('$key is not a list');
  return value;
}

String _string(Map<String, dynamic> map, String key, {bool empty = false}) {
  final value = map[key];
  if (value is! String || (!empty && value.isEmpty)) {
    throw StateError('$key is not a string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String key) =>
    map[key] == null ? null : _string(map, key);
int _signedInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! int) throw StateError('$key is not an integer');
  return value;
}

int _int(Map<String, dynamic> map, String key) {
  final value = _signedInt(map, key);
  if (value < 0) throw StateError('$key is negative');
  return value;
}

bool _bool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! bool) throw StateError('$key is not a boolean');
  return value;
}

String _enum(Map<String, dynamic> map, String key, Set<String> values) {
  final value = _string(map, key);
  if (!values.contains(value)) throw StateError('Unknown $key: $value');
  return value;
}

List<int> _bytes(Map<String, dynamic> map) {
  final bytes = base64Decode(_string(map, 'base64', empty: true));
  if (bytes.length != _int(map, 'byteLength')) {
    throw StateError('Payload byteLength disagrees');
  }
  return bytes;
}
