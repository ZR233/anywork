import 'dart:async';

import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart' show FeedConnection;

import 'profile_native_pin.dart' show profileIdentity, profileStamp;
import 'scripted_feed.dart';

/// Immutable native material of one root-session cost read scope.
final class SessionCostsReadScript {
  SessionCostsReadScript({
    required this.cost,
    Map<int, List<PurposeCostRead>> purposes = const {},
    Map<int, List<RuntimeCostRead>> amounts = const {},
  }) : purposes = Map<int, List<PurposeCostRead>>.unmodifiable({
         for (final entry in purposes.entries)
           entry.key: List<PurposeCostRead>.unmodifiable(entry.value),
       }),
       amounts = Map<int, List<RuntimeCostRead>>.unmodifiable({
         for (final entry in amounts.entries)
           entry.key: List<RuntimeCostRead>.unmodifiable(entry.value),
       });

  final SessionCostRead? cost;
  final Map<int, List<PurposeCostRead>> purposes;
  final Map<int, List<RuntimeCostRead>> amounts;
}

/// Scripted native close rights for one cost read scope.
abstract base class ScriptedSessionCostsHandle {
  ScriptedSessionCostsHandle(this.id);

  final String id;
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  bool closed = false;
  FeedCloseOutcome outcome = const FeedCloseOutcome.clean();

  void requestClose() {
    requestCloseCalls++;
  }

  Future<FeedCloseReport> close() {
    closeCalls++;
    return _report();
  }

  Future<FeedCloseReport> retryClose() {
    retryCloseCalls++;
    return _report();
  }

  Future<FeedCloseReport> _report() async {
    requestClose();
    closed = true;
    return FeedCloseReport(feedId: id, outcome: outcome);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted session-costs native capability: ${invocation.memberName}',
  );
}

final class ScriptedSessionCostsRead extends ScriptedSessionCostsHandle
    implements SessionCostsReadConnection {
  ScriptedSessionCostsRead(this.ordinal, this.script)
    : super('session-costs-read-$ordinal');

  final int ordinal;
  final SessionCostsReadScript script;
  final purposePages = <({int listId, int offset})>[];
  final amountPages = <({int listId, int offset})>[];
  int headerCalls = 0;

  @override
  Future<SessionCostsReadHeader> header() async {
    headerCalls++;
    return SessionCostsReadHeader(cost: script.cost);
  }

  @override
  Future<PurposeCostReadPage> purposes(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    purposePages.add((listId: listId, offset: offset));
    final values = script.purposes[listId];
    if (values == null) {
      throw UnsupportedError('No scripted purpose cost list $listId');
    }
    final page = _page(values, offset, limit);
    return PurposeCostReadPage(
      listId: listId,
      offset: offset,
      total: values.length,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  @override
  Future<RuntimeCostReadPage> amounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    amountPages.add((listId: listId, offset: offset));
    final values = script.amounts[listId];
    if (values == null) {
      throw UnsupportedError('No scripted runtime cost list $listId');
    }
    final page = _page(values, offset, limit);
    return RuntimeCostReadPage(
      listId: listId,
      offset: offset,
      total: values.length,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  }

  @override
  Future<TextChunk> text(
    int fieldId, {
    int offset = 0,
    int maxBytes = 65536,
  }) async =>
      throw UnsupportedError('No scripted session cost text field $fieldId');

  static ({List<T> items, int? nextOffset}) _page<T>(
    List<T> values,
    int offset,
    int limit,
  ) {
    final capped = offset + limit > values.length
        ? values.length
        : offset + limit;
    return (
      items: values.sublist(offset, capped),
      nextOffset: capped == values.length ? null : capped,
    );
  }
}

/// Scripted root-session cost transport: one feed per root plus the fixed read
/// scopes a test declares. Merging, isolation and close rights stay production
/// behavior.
final class ScriptedSessionCostsPort implements SessionCostsPort {
  ScriptedSessionCostsPort({required this.origin});

  final ProductReadOrigin origin;
  final reads = <SessionCostsReadRef, SessionCostsReadScript>{};
  final feedOpens = <String>[];
  final readOpens =
      <({ProductReadOrigin origin, SessionCostsReadRef reference})>[];
  final readConnections = <ScriptedSessionCostsRead>[];
  final _feeds = <String, ScriptedFeed<SessionCostsFrame>>{};
  final _feedWaiters = <String, Completer<ScriptedFeed<SessionCostsFrame>>>{};

  Future<ScriptedFeed<SessionCostsFrame>> feedFor(String rootThreadId) {
    final feed = _feeds[rootThreadId];
    if (feed != null) return Future.value(feed);
    return (_feedWaiters[rootThreadId] ??=
            Completer<ScriptedFeed<SessionCostsFrame>>())
        .future;
  }

  @override
  Future<FeedConnection<SessionCostsFrame>> openSessionCosts(
    String rootThreadId,
  ) async {
    feedOpens.add(rootThreadId);
    final feed = ScriptedFeed<SessionCostsFrame>(
      feedId: 'session-costs-$rootThreadId',
      sequenceOf: (frame) =>
          frame is SessionCostsData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! SessionCostsData,
    );
    _feeds[rootThreadId] = feed;
    _feedWaiters.remove(rootThreadId)?.complete(feed);
    return feed;
  }

  @override
  Future<SessionCostsReadConnection> openSessionCostsRead(
    SessionCostsReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    readOpens.add((origin: origin, reference: reference));
    final script = reads[reference];
    if (script == null) {
      throw UnsupportedError(
        'No scripted session cost material for $reference',
      );
    }
    final read = ScriptedSessionCostsRead(readConnections.length + 1, script);
    readConnections.add(read);
    return read;
  }
}

SessionCostsFrame sessionCostsBaseline({
  required String feedId,
  required ProductReadOrigin origin,
  required SessionCostsHeader header,
  int deliverySequence = 1,
}) => SessionCostsFrame.data(
  deliverySequence: deliverySequence,
  event: SessionCostsEvent.baseline(
    identity: profileIdentity(feedId, origin, ProductResource.sessionCosts),
    stamp: profileStamp(origin, header.revision),
    value: header,
  ),
);
