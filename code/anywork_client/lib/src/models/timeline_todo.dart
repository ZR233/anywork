part of 'timeline_models.dart';

class TimelineTodoListUpdate {
  const TimelineTodoListUpdate({
    required this.callId,
    required this.items,
    this.agentId,
    this.path,
    this.parentPath,
    this.explanation,
  });

  final String callId;
  final String? agentId;
  final String? path;
  final String? parentPath;
  final String? explanation;
  final List<TimelineTodoItem> items;

  /// 已知待办状态集合；任何不在此集合内的 status 都视为未知。
  static const _knownStatuses = {'completed', 'inProgress', 'pending'};

  String get status {
    // 先识别未知：空集合或任何含未知 status 的集合一律为中性 unknown，
    // 只有全部属于已知集合时才应用已知聚合规则。
    if (items.isEmpty ||
        items.any((item) => !_knownStatuses.contains(item.status))) {
      return 'unknown';
    }
    if (items.any((item) => item.status == 'inProgress')) {
      return 'running';
    }
    if (items.every((item) => item.status == 'completed')) {
      return 'completed';
    }
    return 'pending';
  }
}

class TimelineTodoItem {
  const TimelineTodoItem({required this.step, required this.status});

  final String step;
  final String status;
}
