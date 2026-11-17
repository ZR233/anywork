import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/widgets.dart';

import 'timeline_display_diagnostics.dart';
import '../view_models/display_member_controller.dart';

import 'timeline_display_models.dart';
export 'timeline_display_models.dart';

/// Only local disclosure intent and its synchronously revocable capabilities.
/// No membership, completion ranges or source-order facts are retained here.
final class TimelineExpansionIntent extends ChangeNotifier {
  bool? expanded;
  TimelineDisplayUnit? current;
  final ValueNotifier<bool> retirement = ValueNotifier(false);
  VoidCallback Function(TimelineGroupDisplay display)? registerDisplay;
  bool Function()? isDisplayActive;
  Future<DisplayMembers> Function(
    DisplayBlockRef,
    DisplayMemberWindow,
    ReadDemand,
    bool,
  )?
  openDisplayMembers;
  DisplayMemberController? members;
  final Set<Object> _bodyDisplays = {};
  bool _retired = false;
  Object bodyGeneration = Object();
  bool get isRetired => _retired;
  bool get bodyActive => !_retired && _bodyDisplays.isNotEmpty;
  Future<ContentWindow> Function(Object, HistoryEventBodyRef, ContentRange)?
  readHistoryBody;
  Future<ContentWindow> Function(Object, CurrentContentRef, ContentRange)?
  readCurrentBody;
  CurrentBodyWatch Function(Object, CurrentContentRef, ContentRange)?
  watchCurrentBody;
  VoidCallback? retireBody;

  /// A new opaque member capability revokes the old scope without changing
  /// this item's local expansion intent or interpreting its generation value.
  void replaceBody() {
    if (_retired) return;
    bodyGeneration = Object();
    retirement.value = true;
    retireBody?.call();
    final previousMembers = members;
    members = null;
    previousMembers?.retire();
    if (previousMembers != null) {
      unawaited(previousMembers.close());
    }
    notifyListeners();
    retirement.value = !bodyActive;
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    retirement.value = true;
    _bodyDisplays.clear();
    bodyGeneration = Object();
    retireBody?.call();
    final previousMembers = members;
    members = null;
    previousMembers?.retire();
    if (previousMembers != null) {
      unawaited(previousMembers.close());
    }
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
    if (!bodyActive && expanded != true) {
      retireBody?.call();
      final previousMembers = members;
      members = null;
      previousMembers?.retire();
      if (previousMembers != null) {
        unawaited(previousMembers.close());
      }
    }
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

/// One producer-defined block and its display-lease disclosure capability.
final class TimelineDisplayUnit {
  TimelineDisplayUnit({
    required DisplayBlock block,
    TimelineExpansionIntent? expansion,
  }) : id = block.id,
       blockOrder = block.blockOrder,
       body = block.body,
       state = switch (block.body) {
         WorkDisplayBlock(:final groupClosed) =>
           groupClosed ? DisplayBlockState.sealed : DisplayBlockState.open,
         SingleDisplayBlock() => DisplayBlockState.sealed,
       },
       executionPresent = switch (block.body) {
         WorkDisplayBlock(:final executionPresent) => executionPresent,
         SingleDisplayBlock() => false,
       },
       hasUnfinishedMembers = switch (block.body) {
         WorkDisplayBlock(:final unfinishedCount) => unfinishedCount > 0,
         SingleDisplayBlock() => false,
       },
       thinkingSummary = switch (block.body) {
         WorkDisplayBlock(:final summary) => summary,
         SingleDisplayBlock() => null,
       },
       expansion = expansion ?? TimelineExpansionIntent();

  final String id;
  final int blockOrder;
  final DisplayBlockBody body;
  final DisplayBlockState state;
  final bool executionPresent;
  final bool hasUnfinishedMembers;
  final String? thinkingSummary;
  final TimelineExpansionIntent expansion;
  DisplayBlock get block =>
      DisplayBlock(id: id, blockOrder: blockOrder, body: body);
  DisplayBlockRef? get memberReference => switch (body) {
    WorkDisplayBlock(:final members) => members,
    SingleDisplayBlock() => null,
  };
  WorkTiming? get timing => switch (body) {
    WorkDisplayBlock(:final timing) => timing,
    SingleDisplayBlock() => null,
  };
  ChatAtom? get atom => switch (body) {
    SingleDisplayBlock(:final record) => record.atom,
    WorkDisplayBlock() => null,
  };
}

const timelineDisplayUnitKey = 'timelineDisplayUnit';
