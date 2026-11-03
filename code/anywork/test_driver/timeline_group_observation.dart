/// Borrow only mounted display windows. No implicit query, source range,
/// synthetic Children parent or hidden whole-group reconstruction.
List<Map<String, dynamic>> timelineGroupDisplays(
  Map<String, dynamic> snapshot,
) {
  final timeline = snapshot['timeline'];
  if (timeline is! Map || timeline['groups'] is! List) {
    throw StateError('Actual group display diagnostics are unavailable');
  }
  return [for (final value in timeline['groups'] as List) _group(value)];
}

/// An already mounted member and its actual display identity, never a guessed
/// source/unit ID or a query that materializes a hidden group.
({Map<String, dynamic> group, Map<String, dynamic> item})?
timelineGroupMemberWhere(
  Map<String, dynamic> snapshot,
  bool Function(Map<String, dynamic> item) matches,
) {
  ({Map<String, dynamic> group, Map<String, dynamic> item})? found;
  for (final group in timelineGroupDisplays(snapshot)) {
    if (group['error'] != null) {
      throw StateError('Mounted group failed: ${group['error']}');
    }
    if (group['loading'] == true || group['expanded'] != true) continue;
    for (final raw in group['items'] as List) {
      if (raw is! Map || raw['id'] is! String) {
        throw StateError('Mounted member has no actual identity');
      }
      final item = raw.cast<String, dynamic>();
      if (!matches(item)) continue;
      if (found != null) {
        throw StateError('Ambiguous mounted group member');
      }
      found = (group: group, item: item);
    }
  }
  return found;
}

/// Tool identity has two canonical representations: decoded immutable payload
/// facts, or the actual header of a current atom without an immutable payload.
/// This is not an old/new UI fallback; neither branch fabricates a call mapping.
({Map<String, dynamic> group, Map<String, dynamic> item})?
timelineToolGroupMember(
  Map<String, dynamic> snapshot,
  String callId, {
  required String name,
}) => timelineGroupMemberWhere(snapshot, (item) {
  final tool = item['tool'];
  final atomic = item['atomic'];
  final actualCall = tool is Map
      ? tool['callId']
      : atomic is Map
      ? atomic['toolCallId']
      : null;
  if (actualCall != callId) return false;
  final actualName = tool is Map ? tool['name'] : (atomic as Map)['toolName'];
  if (actualName != name) {
    throw StateError('Tool $callId has name $actualName, expected $name');
  }
  return true;
});

Map<String, dynamic>? timelineMountedGroup(
  Map<String, dynamic> snapshot,
  String unitId,
) {
  final groups = timelineGroupDisplays(snapshot)
      .where((group) => group['unitId'] == unitId)
      .toList();
  if (groups.length > 1) throw StateError('Duplicate mounted unit $unitId');
  if (groups.isEmpty) return null;
  final group = groups.single;
  if (group['error'] != null) {
    throw StateError('Mounted unit $unitId failed: ${group['error']}');
  }
  return group;
}

Map<String, dynamic> _group(Object? value) {
  if (value is! Map ||
      value['unitId'] is! String ||
      value['expanded'] is! bool ||
      value['loading'] is! bool ||
      value['items'] is! List ||
      (value['before'] != null && value['before'] is! String) ||
      (value['completionAnchor'] != null &&
          value['completionAnchor'] is! int)) {
    throw StateError('Malformed mounted group observation');
  }
  return value.cast<String, dynamic>();
}

Iterable<Map<dynamic, dynamic>> timelineDisplayedAtoms(
  Map<String, dynamic> snapshot,
) sync* {
  final timeline = snapshot['timeline'];
  if (timeline is! Map || timeline['items'] is! List) {
    throw StateError('Timeline is unavailable');
  }
  for (final item in timeline['items'] as List) {
    if (item is! Map) throw StateError('Malformed timeline item');
    if (item['kind'] != 'workGroup') yield item;
  }
  for (final group in timelineGroupDisplays(snapshot)) {
    if (group['error'] != null) {
      throw StateError('Ordinary atom window failed: ${group['error']}');
    }
    if (group['expanded'] != true || group['loading'] == true) continue;
    for (final item in group['items'] as List) {
      if (item is! Map) throw StateError('Malformed mounted member');
      yield item;
    }
  }
}
