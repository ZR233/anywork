import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

/// Borrowed UI resources. No repository, query, subscription or platform API.
abstract interface class TimelineUiControllers {
  Key get chatKey;
  ChatController get controller;
  ScrollController get scrollController;
  bool get isRetired;
  ValueListenable<StreamState>? streamFor(String itemId);
  void bind();
  Future<void> unbind();
}
