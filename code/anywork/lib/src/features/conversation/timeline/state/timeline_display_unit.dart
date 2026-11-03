import 'package:anywork_client/conversation.dart';
import 'package:flutter/widgets.dart';

import 'timeline_display_diagnostics.dart';

/// Only local disclosure intent and its synchronously revocable capabilities.
/// No membership, completion ranges or source-order facts are retained here.
final class TimelineExpansionIntent extends ChangeNotifier {
  bool? expanded;
  TimelineDisplayUnit? current;
  final ValueNotifier<bool> retirement = ValueNotifier(false);
  VoidCallback Function(TimelineGroupDisplay display)? registerDisplay;
  bool Function()? isDisplayActive;
  Future<ConversationContent> Function(TimelineMembersRef, ReadDemand)? openMembers;
  final Set<Object> _bodyDisplays = {};
  bool _retired = false;
  Object bodyGeneration = Object();
  bool get isRetired => _retired;
  bool get bodyActive => !_retired && _bodyDisplays.isNotEmpty;
  Future<ContentWindow> Function(Object, ContentRef, ContentRange)? readBody;
  VoidCallback? retireBody;

  void retire() {
    if (_retired) return;
    _retired = true;
    retirement.value = true;
    _bodyDisplays.clear();
    bodyGeneration = Object();
    retireBody?.call();
    current = null;
    notifyListeners();
  }

  void setBodyVisible(Object token, bool visible) {
    if (_retired) return;
    final wasActive = bodyActive;
    if (visible) {
      _bodyDisplays.add(token);
    } else {
      _bodyDisplays.remove(token);
    }
    if (wasActive == bodyActive) return;
    bodyGeneration = Object();
    // Revoke descendants before ExpansionTile's closing animation/disposal.
    retirement.value = !bodyActive;
    if (!bodyActive) retireBody?.call();
    notifyListeners();
  }
}

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

/// A wire item and a local disclosure capability. Rust owns all product facts.
final class TimelineDisplayUnit {
  TimelineDisplayUnit({
    required this.item,
    required this.live,
    TimelineExpansionIntent? expansion,
  }) : expansion = expansion ?? TimelineExpansionIntent();

  final TimelineItem item;
  final bool live;
  final TimelineExpansionIntent expansion;
  String get id => item.id;
}

const timelineDisplayUnitKey = 'timelineDisplayUnit';
