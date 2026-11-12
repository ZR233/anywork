import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'mapped_conversation_feed.dart';
import 'recording_demo_transport.dart';

/// Only delays/fails transport delivery; Demo owns the actual document bytes.
class PlanDocumentTransport extends RecordingDemoTransport {
  Completer<void>? nextInitialGate;
  Completer<void>? nextReadGate;
  Object? nextReadError;
  int? responseMaxBytes;
  final reads = <PlanDocumentRead>[];
  int businessReads = 0;
  int completedReads = 0;
  int olderReads = 0;
  bool controlInteractionPages = false;
  final interactionPages =
      <(CurrentCollectionRef, String?, Completer<CurrentCollectionPage>)>[];

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async {
    final gate = nextInitialGate;
    nextInitialGate = null;
    final feed = await super.openTimelineFeed(threadId, demand: demand);
    (feed as RecordingTimelineFeed).initialGate = gate;
    return MappedTimelineFeed(feed, reader: _PlanReader(feed.reader, this));
  }
}

class PlanDocumentRead {
  PlanDocumentRead(this.reference, this.range, this.gate, this.error);
  final ContentRef reference;
  final ContentRange range;
  final Completer<void>? gate;
  final Object? error;
  bool delivered = false;
}

class _PlanReader implements ConversationReader {
  _PlanReader(this.inner, this.transport);
  final ConversationReader inner;
  final PlanDocumentTransport transport;

  @override
  String get threadId => inner.threadId;
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) async {
    final read = PlanDocumentRead(
      reference,
      range,
      transport.nextReadGate,
      transport.nextReadError,
    );
    transport.nextReadGate = null;
    transport.nextReadError = null;
    transport.reads.add(read);
    // Capture a real window before delaying delivery, including across versions.
    final window = await inner.readContent(
      reference: reference,
      range: ContentRange(
        offset: range.offset,
        maxBytes: transport.responseMaxBytes ?? range.maxBytes,
      ),
    );
    await read.gate?.future;
    read.delivered = true;
    if (read.error case final error?) throw error;
    return window;
  }

  @override
  Future<ThreadBusinessRefs> readBusinessRefs() {
    transport.businessReads++;
    return inner.readBusinessRefs();
  }

  @override
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  }) {
    transport.completedReads++;
    return inner.readCompleted(recordId: recordId, demand: demand);
  }

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    transport.olderReads++;
    return inner.loadOlder(before: before, demand: demand);
  }

  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) => inner.listContents(
    itemId: itemId,
    continuation: continuation,
    demand: demand,
  );
  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) => inner.watchContent(reference: reference, range: range);
  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) {
    if (transport.controlInteractionPages) {
      // Only control delivery; State and the SDK retain reference qualification.
      final result = Completer<CurrentCollectionPage>();
      transport.interactionPages.add((reference, continuation, result));
      return result.future;
    }
    return inner.pageCurrent(
      reference: reference,
      continuation: continuation,
      demand: demand,
    );
  }

  @override
  void requestClose() => inner.requestClose();
  @override
  Future<void> close() => inner.close();
}
