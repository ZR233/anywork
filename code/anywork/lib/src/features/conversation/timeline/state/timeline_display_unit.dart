import 'package:flutter/widgets.dart';

import 'timeline_display_models.dart';
export 'timeline_display_models.dart';

/// Disclosure and synchronous read qualification for one mounted work group.
final class TimelineExpansionIntent extends ChangeNotifier {
  bool? expanded;
  TimelineDisplayUnit? current;
  final _bodyDisplays = <Object>{};
  bool _retired = false;
  Object bodyGeneration = Object();
  bool get isRetired => _retired;
  bool get bodyActive => !_retired && _bodyDisplays.isNotEmpty;

  void retire() {
    if (_retired) return;
    _retired = true;
    current = null;
    _bodyDisplays.clear();
    bodyGeneration = Object();
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

final class TimelineDisplayUnit {
  TimelineDisplayUnit({
    required DisplayBlock block,
    TimelineExpansionIntent? expansion,
  }) : id = block.id,
       blockOrder = block.blockOrder,
       body = block.body,
       expansion = expansion ?? TimelineExpansionIntent();

  final String id;
  final int blockOrder;
  final WorkDisplayBlock body;
  final TimelineExpansionIntent expansion;
  DisplayBlockState get state =>
      body.groupClosed ? DisplayBlockState.sealed : DisplayBlockState.open;
  bool get executionPresent => body.executionPresent;
  bool get hasUnfinishedMembers => body.unfinishedCount > 0;
  String? get thinkingSummary => body.summary;
  WorkTiming get timing => body.timing;
}

const timelineDisplayUnitKey = 'timelineDisplayUnit';
