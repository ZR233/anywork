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
