import 'dart:async';

import 'models.dart';

abstract interface class ConversationTransport
    implements HistoryTransport, CurrentTransport {}

abstract interface class HistoryTransport {
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  });
}

abstract interface class CurrentTransport {
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  });
}

abstract interface class HistoryReader {
  OpenHistory get metadata;
  String get threadId;
  Future<HistoryCut> capture();
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  });
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  });
  Future<HistoryAccounting?> accounting({HistoryCut? cut});
  Future<HistoryTimelinePage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryCut> waitChanged(HistoryCut after);
  void requestClose();
  Future<void> close();
}

final class OpenHistory {
  const OpenHistory({
    required this.readerId,
    required this.historyProtocolVersion,
  });
  final String readerId;
  final int historyProtocolVersion;
}

abstract interface class CurrentReader {
  OpenCurrent get metadata;
  String get threadId;
  CurrentView get initialView;
  Future<CurrentView> snapshot(ReadDemand demand);
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  });
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  });
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  });
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  });
  void requestClose();
  Future<void> close();
}

final class OpenCurrent {
  const OpenCurrent({
    required this.readerId,
    required this.currentProtocolVersion,
    required this.currentOwnerId,
  });
  final String readerId;
  final int currentProtocolVersion;
  final String currentOwnerId;
}

abstract interface class CurrentWatch {
  Stream<CurrentFrame> get frames;
  void requestClose();
  Future<void> close();
}

abstract interface class CurrentBodyWatch {
  Stream<ContentWindow> get windows;
  void requestClose();
  Future<void> close();
}
