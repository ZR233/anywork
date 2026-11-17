import 'dart:async';

import 'package:anywork_client/studio_client.dart';

import 'recording_demo_transport.dart';

/// Only delays/fails transport delivery; Demo owns the actual document bytes.
final class PlanDocumentTransport extends RecordingDemoTransport {
  Completer<void>? nextInitialGate;
  Completer<void>? nextReadGate;
  Object? nextReadError;
  int? responseMaxBytes;
  final reads = <PlanDocumentRead>[];
  int olderReads = 0;
  bool controlInteractionPages = false;
  final interactionPages =
      <(CurrentCollectionRef, String?, Completer<CurrentCollectionPage>)>[];

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final gate = nextInitialGate;
    nextInitialGate = null;
    final reader = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    ) as RecordingCurrentReader;
    await gate?.future;
    return _PlanCurrentReader(reader, this);
  }
}

final class PlanDocumentRead {
  PlanDocumentRead(this.reference, this.range, this.gate, this.error);
  final CurrentContentRef reference;
  final ContentRange range;
  final Completer<void>? gate;
  final Object? error;
  bool delivered = false;
}

final class _PlanCurrentReader implements CurrentReader {
  _PlanCurrentReader(this.inner, this.transport);

  final RecordingCurrentReader inner;
  final PlanDocumentTransport transport;

  @override
  OpenCurrent get metadata => inner.metadata;
  @override
  String get threadId => inner.threadId;
  @override
  CurrentView get initialView => inner.initialView;
  @override
  Future<CurrentView> snapshot(ReadDemand demand) => inner.snapshot(demand);
  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) => inner.watch(after: after, demand: demand);
  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => inner.watchBody(reference: reference, range: range);

  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) {
    if (transport.controlInteractionPages) {
      final result = Completer<CurrentCollectionPage>();
      transport.interactionPages.add((reference, continuation, result));
      return result.future;
    }
    return inner.pageCollection(
      reference: reference,
      continuation: continuation,
      demand: demand,
    );
  }

  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
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
    final window = await inner.readBody(
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
  void requestClose() => inner.requestClose();
  @override
  Future<void> close() => inner.close();
}
