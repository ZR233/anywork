import 'package:anywork_client/conversation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' show Message;

import 'timeline_display_diagnostics.dart';

enum TimelineUnitKind { text, work, receipt }

enum TimelineProcessKind {
  thinking,
  read,
  image,
  command,
  search,
  edit,
  wait,
  other,
}

TimelineProcessKind timelineProcessKind(ChatAtom atom) => switch (atom.kind) {
  ChatAtomKind.reasoning => TimelineProcessKind.thinking,
  ChatAtomKind.fileChange => TimelineProcessKind.edit,
  ChatAtomKind.toolCall => switch (atom.tool?.name) {
    'read_file' => TimelineProcessKind.read,
    'read_image' ||
    'generate_image' ||
    'show_image' => TimelineProcessKind.image,
    'exec' => TimelineProcessKind.command,
    'web_search' => TimelineProcessKind.search,
    'apply_patch' => TimelineProcessKind.edit,
    'wait' || 'sleep' => TimelineProcessKind.wait,
    _ => TimelineProcessKind.other,
  },
  _ => TimelineProcessKind.other,
};

final class TimelineExpansionIntent extends ChangeNotifier {
  bool? expanded;
  TimelineDisplayUnit? current;
  Message? committedMessage;
  Future<void> Function()? readEarlier;
  void Function(Object token, bool visible)? onVisibilityChanged;
  VoidCallback Function(TimelineGroupDisplay display)? registerDisplay;
  bool Function()? isDisplayActive;
  int? completionAnchor;
  final Object ordinaryRange = Object();
  String? before;
  bool hasPage = false;
  bool loading = false;
  Object? error;
  final Set<Object> _bodyDisplays = {};
  bool _retired = false;
  Object bodyGeneration = Object();
  bool get isRetired => _retired;
  bool get bodyActive => !_retired && _bodyDisplays.isNotEmpty;
  Future<ContentWindow> Function(Object, ContentRef, ContentRange)? readBody;
  VoidCallback? retireBody;

  /// Permanently revoke this fragment before its old subtree can be unmounted.
  /// Unlike folding, visibility callbacks must never reopen a retired intent.
  void retire() {
    if (_retired) return;
    _retired = true;
    _bodyDisplays.clear();
    bodyGeneration = Object();
    notifyListeners();
    retireBody?.call();
  }

  void setBodyVisible(Object token, bool visible) {
    if (_retired) return;
    if (visible) {
      final reopening = _bodyDisplays.isEmpty;
      _bodyDisplays.add(token);
      if (reopening) {
        bodyGeneration = Object();
        notifyListeners();
      }
    } else {
      _bodyDisplays.remove(token);
      if (_bodyDisplays.isEmpty) {
        bodyGeneration = Object();
        retireBody?.call();
        notifyListeners();
      }
    }
  }

  void changed() => notifyListeners();
}

/// The existing display object's local capability. Descendant body connectors
/// inherit its qualification even when a caller supplies a custom body builder.
class TimelineGroupBodyIntent extends InheritedWidget {
  const TimelineGroupBodyIntent({
    required this.intent,
    required super.child,
    super.key,
  });
  final TimelineExpansionIntent intent;
  static TimelineExpansionIntent? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TimelineGroupBodyIntent>()
      ?.intent;
  @override
  bool updateShouldNotify(TimelineGroupBodyIntent oldWidget) =>
      !identical(intent, oldWidget.intent);
}

/// An owner-local display object, not a wire/storage group. Only bounded member
/// props and scalar loaded evidence survive; the controller owns committed units.
final class TimelineDisplayUnit {
  TimelineDisplayUnit({
    required this.id,
    required this.source,
    required this.kind,
    required List<ChatAtom> members,
    required this.live,
    required this.closedForAdmission,
    required this.memberCount,
    required this.activeCount,
    required this.failedCount,
    required this.stoppedCount,
    this.firstOrder,
    this.lastOrder,
    this.completionThrough,
    this.startedAt,
    this.finishedAt,
    this.olderCursor,
    TimelineExpansionIntent? expansion,
    Map<TimelineProcessKind, int> categories = const {},
    this.sourceLifecycle,
    this.streamConnected = false,
    this.lowerSeparator,
    this.upperSeparator,
    this.incompleteRange,
  }) : expansion = expansion ?? TimelineExpansionIntent(),
       categories = Map.unmodifiable(categories),
       members = List.unmodifiable(members);
  final Map<TimelineProcessKind, int> categories;
  final ChatSourceLifecycle? sourceLifecycle;
  ChatAtom? get lastCompletion {
    ChatAtom? last;
    for (final atom in members) {
      if (atom.completionSeq != null &&
          (last == null || atom.completionSeq! > last.completionSeq!)) {
        last = atom;
      }
    }
    return last;
  }

  /// Reliable starts observed continuously by this owner, not numeric adjacency.
  final bool streamConnected;
  final int? lowerSeparator;
  final int? upperSeparator;

  /// Local identity of the ordinary cursor interval whose prefix is unknown.
  /// Not a source range, wire cursor, member index or second history collection.
  final Object? incompleteRange;
  final TimelineExpansionIntent expansion;
  final String id;
  final ChatSourceId source;
  final TimelineUnitKind kind;
  final List<ChatAtom> members;
  final bool live;
  final bool closedForAdmission;
  final int memberCount;
  final int activeCount;
  final int failedCount;
  final int stoppedCount;
  final int? firstOrder;
  final int? lastOrder;
  final int? completionThrough;
  final int? startedAt;
  final int? finishedAt;

  /// An observed ordinary atomic cursor. It may cross sources; never a group API.
  final String? olderCursor;
  bool get ready => closedForAdmission && activeCount == 0;
  TimelineDisplayUnit copy({
    List<ChatAtom>? members,
    bool? live,
    bool? closedForAdmission,
    int? memberCount,
    int? activeCount,
    int? failedCount,
    int? stoppedCount,
    int? firstOrder,
    int? lastOrder,
    int? completionThrough,
    int? startedAt,
    int? finishedAt,
    String? olderCursor,
    Map<TimelineProcessKind, int>? categories,
    ChatSourceLifecycle? sourceLifecycle,
    bool? streamConnected,
    int? lowerSeparator,
    int? upperSeparator,
    Object? incompleteRange,
  }) => TimelineDisplayUnit(
    id: id,
    source: source,
    kind: kind,
    members: members ?? this.members,
    live: live ?? this.live,
    closedForAdmission: closedForAdmission ?? this.closedForAdmission,
    memberCount: memberCount ?? this.memberCount,
    activeCount: activeCount ?? this.activeCount,
    failedCount: failedCount ?? this.failedCount,
    stoppedCount: stoppedCount ?? this.stoppedCount,
    firstOrder: firstOrder ?? this.firstOrder,
    lastOrder: lastOrder ?? this.lastOrder,
    completionThrough: completionThrough ?? this.completionThrough,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    olderCursor: olderCursor ?? this.olderCursor,
    expansion: expansion,
    categories: categories ?? this.categories,
    sourceLifecycle: sourceLifecycle ?? this.sourceLifecycle,
    streamConnected: streamConnected ?? this.streamConnected,
    lowerSeparator: lowerSeparator ?? this.lowerSeparator,
    upperSeparator: upperSeparator ?? this.upperSeparator,
    incompleteRange: incompleteRange ?? this.incompleteRange,
  );
}

const timelineDisplayUnitKey = 'timelineDisplayUnit';
