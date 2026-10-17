import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';

/// Uses Demo's real directory/runtime/window behavior. Only resource ownership
/// is recorded; this fixture never claims to exercise a native FRB handle.
class RecordingDemoTransport extends DemoStudioTransport {
  RecordingDemoTransport() : super(lspActivityLoop: false);

  final List<RecordingChatWindow> windows = [];
  final bootstrapDelivered = Completer<void>();
  int bootstrapCalls = 0;

  @override
  Duration get shutdownPhaseDelay => Duration.zero;

  @override
  Future<StudioBootstrap> readBootstrap() async {
    bootstrapCalls++;
    final result = await super.readBootstrap();
    if (!bootstrapDelivered.isCompleted) bootstrapDelivered.complete();
    return result;
  }

  @override
  Future<StudioChatWindow> openChatWindow(String threadId) async {
    final window = RecordingChatWindow(
      threadId: threadId,
      inner: await super.openChatWindow(threadId),
    );
    windows.add(window);
    return window;
  }
}

class RecordingChatWindow implements StudioChatWindow {
  RecordingChatWindow({required this.threadId, required this.inner});

  final String threadId;
  final StudioChatWindow inner;
  final nextEntered = Completer<void>();
  final joined = Completer<void>();
  int initialCalls = 0;
  int nextCalls = 0;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  final List<String?> focusRequests = [];

  @override
  Future<StudioChatSnapshot> initial() {
    initialCalls++;
    return inner.initial();
  }

  @override
  Future<StudioChatFrame?> next() {
    nextCalls++;
    if (!nextEntered.isCompleted) nextEntered.complete();
    return inner.next();
  }

  @override
  Future<StudioChatReceipt> load(TimelineDirection direction) =>
      inner.load(direction);

  @override
  Future<StudioChatReceipt> focus(String? itemId) {
    focusRequests.add(itemId);
    return inner.focus(itemId);
  }

  @override
  Future<StudioChatReceipt> expandItem(String itemId) =>
      inner.expandItem(itemId);

  @override
  void requestClose() {
    requestCloseCalls++;
    inner.requestClose();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await inner.close();
    if (!joined.isCompleted) joined.complete();
  }
}
