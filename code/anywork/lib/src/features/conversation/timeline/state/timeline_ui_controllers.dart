import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

/// Borrowed UI resources. No repository, query, subscription or platform API.
abstract interface class TimelineUiControllers {
  Key get chatKey;
  ChatController get controller;
  ScrollController get scrollController;
  bool get isRetired;
  void bind();
  Future<void> unbind();
}
