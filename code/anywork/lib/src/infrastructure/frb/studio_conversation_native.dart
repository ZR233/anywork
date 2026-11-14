part of 'studio_api.dart';

/// Shared query capability only; it carries no delivery queue, cursor or ACK.
abstract interface class _FrbContentOwner {
  String get threadId;
  bool get _admissionsClosed;
  _FrbNativeReader get _native;
  Set<_FrbContentWatch> get _contentWatches;
  void requestClose();
  Future<void> close();
}

class _FrbNativeReader {
  _FrbNativeReader.conversation(frb_chat.BridgeConversationFeed native)
    : threadId = native.threadId,
      requestClose = native.requestClose,
      close = native.close,
      dispose = native.dispose,
      loadOlder = native.loadOlder,
      readCompleted = native.readCompleted,
      readBusinessRefs = native.readBusinessRefs,
      listContents = native.listContents,
      readContent = native.readContent,
      pageCurrent = native.pageCurrent,
      openContentWatch = native.openContentWatch,
      nextContentWindow = native.nextContentWindow,
      requestCloseContentWatch = native.requestCloseContentWatch,
      closeContentWatch = native.closeContentWatch;
  _FrbNativeReader.timeline(frb_timeline.BridgeTimelineReader native)
    : threadId = (() => native.threadId()),
      requestClose = native.requestClose,
      close = native.close,
      dispose = native.dispose,
      loadOlder = native.loadCompletedOlder,
      readCompleted = native.readCompleted,
      readBusinessRefs = native.readBusinessRefs,
      listContents = native.listContents,
      readContent = native.readContent,
      pageCurrent = native.pageCurrent,
      openContentWatch = native.openContentWatch,
      nextContentWindow = native.nextContentWindow,
      requestCloseContentWatch = native.requestCloseContentWatch,
      closeContentWatch = native.closeContentWatch;

  final String Function() threadId;
  final void Function() requestClose;
  final Future<void> Function() close;
  final void Function() dispose;
  final Future<frb_chat_types.BridgeChatBatch> Function({
    required String before,
    required frb_chat_types.BridgeReadDemand demand,
  })
  loadOlder;
  final Future<frb_chat_types.BridgeCompletedEntry> Function({
    required String recordId,
    required frb_chat_types.BridgeReadDemand demand,
  })
  readCompleted;
  final Future<frb.BridgeThreadBusinessRefs> Function() readBusinessRefs;
  final Future<frb_chat_types.BridgeContentManifestPage> Function({
    required String itemId,
    String? continuation,
    required frb_chat_types.BridgeReadDemand demand,
  })
  listContents;
  final Future<frb_chat_types.BridgeContentWindow> Function({
    required frb_chat_types.BridgeContentRef reference,
    required frb_chat_types.BridgeContentRange range,
  })
  readContent;
  final Future<frb_chat_types.BridgeCurrentCollectionPage> Function({
    required frb_chat_types.BridgeCurrentCollectionRef reference,
    String? continuation,
    required frb_chat_types.BridgeReadDemand demand,
  })
  pageCurrent;
  final Future<String> Function({
    required frb_chat_types.BridgeContentRef reference,
    required frb_chat_types.BridgeContentRange range,
  })
  openContentWatch;
  final Future<frb_chat_types.BridgeContentWindow?> Function({
    required String watchId,
  })
  nextContentWindow;
  final void Function({required String watchId}) requestCloseContentWatch;
  final Future<void> Function({required String watchId}) closeContentWatch;
}

final class _FrbNativeConversation extends _FrbNativeReader {
  _FrbNativeConversation.conversation(super.native)
    : subscriptionId = native.subscriptionId,
      events = native.events,
      acknowledge = native.acknowledge,
      super.conversation();
  final String Function() subscriptionId;
  final Stream<frb_chat_types.BridgeConversationFrame> Function() events;
  final void Function({
    required String subscriptionId,
    required BigInt deliverySequence,
  })
  acknowledge;
}
