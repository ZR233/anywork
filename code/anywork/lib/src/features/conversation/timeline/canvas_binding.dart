import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

/// UI-only borrowing surface. No Session, query, close or payload access.
abstract interface class TimelineCanvasBinding {
  String get threadId;
  int get displayGeneration;
  Key get chatKey;
  ChatController get chatController;
  ScrollController get scrollController;
  TimelineCanvasMount mount();
}

abstract interface class TimelineCanvasMount {
  /// Releases only this actual subtree's borrowing token, exactly once.
  void unmount();
}
