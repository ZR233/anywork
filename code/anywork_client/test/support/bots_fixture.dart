import 'dart:async';

import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'scripted_feed.dart';

const botsOrigin = ProductReadOrigin(ownerEpoch: 'bots-epoch', incarnation: 1);

ProductFeedIdentity get botsFeedIdentity => const ProductFeedIdentity(
  feedId: 'bots-feed',
  ownerEpoch: 'bots-epoch',
  incarnation: 1,
  resource: ProductResource.bots,
);

BotModelRoute get botsFixtureRoute => const BotModelRoute(
  accountId: 'account-a',
  modelId: 'model-a',
  effort: 'high',
);

BotSnapshot botsFixtureBot({
  String id = 'bot-1',
  int configRevision = 1,
  String name = 'Feishu',
  String projectId = 'p1',
  String appId = 'cli_1',
  bool enabled = true,
  BotModelRoute? modelRoute,
  BotCredentialAvailability credential = BotCredentialAvailability.missing,
}) => BotSnapshot(
  lastActivityAt: null,
  id: id,
  name: name,
  projectId: projectId,
  appId: appId,
  platform: BotPlatform.feishuChina,
  enabled: enabled,
  toolsEnabled: false,
  modelRoute: modelRoute,
  workspacePath: '/workspace',
  configRevision: configRevision,
  trustedOpenIds: const [],
  trustedChatIds: const [],
  connection: const BotConnectionState.disabled(),
  credential: credential,
  credentialOperation: const BotCredentialOperation.idle(),
  pairing: const [],
  diagnostic: null,
  canChangeProject: true,
  canChangeAppId: true,
  createdAt: 0,
  updatedAt: configRevision,
);

BotsHeader botsHeader(int revision) => BotsHeader(
  source: ObservedHeader(
    brief: ObservedBrief.ready(
      revision: revision,
      updatedAt: revision,
      lastCheckedAt: null,
    ),
    status: ProductSourceStatusRef(entry: 7, revision: revision),
  ),
  botsRevision: revision,
  updatedAt: revision,
);

BotsStateSnapshot botsSnapshot(
  int revision, {
  List<BotSnapshot> bots = const [],
  BotRegistrationAttempt? registration,
}) => BotsStateSnapshot(
  revision: revision,
  updatedAt: revision,
  bots: bots,
  registration: registration,
  pendingCredentialOperations: const [],
);

/// One real composition root. Only the native transport is scripted: it never
/// sorts revisions, rejects stale frames, coalesces queries or retains results.
final class BotsEnvironment {
  BotsEnvironment({String clientId = 'bots-lifecycle', ResourceBudget? budget})
    : budget = budget ?? ResourceBudget() {
    operations = OperationRegistry(clientId: clientId, budget: this.budget);
    repository = createBotsRepository(
      port: port,
      budget: this.budget,
      operations: operations,
    );
  }

  final ResourceBudget budget;
  late final OperationRegistry operations;
  late final BotsRepository repository;
  final port = ScriptedBotsPort();
  int _delivery = 0;
  int _sourceRevision = 0;
  ScriptedFeed<BotsFrame>? _sequenceOwner;

  ScriptedFeed<BotsFrame>? get feed => port.feed;

  /// Delivery credit is per native connection: a replacement feed starts again
  /// at 1 while the business projection revision keeps advancing.
  int _nextSequence() {
    final current = feed!;
    if (!identical(current, _sequenceOwner)) {
      _sequenceOwner = current;
      _delivery = 0;
    }
    return ++_delivery;
  }

  int get feedCount => port.feeds.length;
  Future<ScriptedFeed<BotsFrame>> feedAt(int index) => port.feedAt(index);
  int used(ResourceKind kind) => budget.used(kind);

  BotSnapshot bot(String id) => repository.state.value.snapshot!.value.bots
      .singleWhere((BotSnapshot item) => item.id == id);

  Future<void> establish({
    required int revision,
    List<BotSnapshot> bots = const [],
  }) async {
    final ready = repository.synchronize();
    final feed = await port.opened();
    await feed.listened.future;
    publishBaseline(revision: revision, bots: bots);
    await feed.acknowledged(1);
    await ready;
    expect(
      repository.state.value.projection.sync.phase,
      ResourceSyncPhase.ready,
    );
  }

  void publishBaseline({
    required int revision,
    List<BotSnapshot> bots = const [],
  }) {
    expect(revision, greaterThan(_sourceRevision));
    _sourceRevision = revision;
    feed!.emit(
      BotsData(
        deliverySequence: _nextSequence(),
        event: BotsBaseline(
          identity: botsFeedIdentity,
          stamp: ProductProjectionStamp(
            ownerEpoch: botsOrigin.ownerEpoch,
            incarnation: botsOrigin.incarnation,
            revision: revision,
          ),
          header: botsHeader(revision),
          state: botsSnapshot(revision, bots: bots),
        ),
      ),
    );
  }

  void publishChange({
    required int baseRevision,
    required int revision,
    List<BotSnapshot> bots = const [],
  }) {
    expect(revision, greaterThan(_sourceRevision));
    _sourceRevision = revision;
    feed!.emit(
      BotsData(
        deliverySequence: _nextSequence(),
        event: BotsStateChangedPayload(
          stamp: ProductProjectionStamp(
            ownerEpoch: botsOrigin.ownerEpoch,
            incarnation: botsOrigin.incarnation,
            revision: revision,
          ),
          baseRevision: baseRevision,
          header: botsHeader(revision),
          state: botsSnapshot(revision, bots: bots),
        ),
      ),
    );
  }

  /// Emits the frame the owner must reject, then waits for its terminal
  /// publication. A rejected frame neither rewrites nor clears last-known data.
  Future<void> publishRejected(BotsEvent event) async {
    feed!.emit(BotsData(deliverySequence: _nextSequence(), event: event));
    await feed!.closeStarted.future;
    await Future<void>.delayed(Duration.zero);
  }

  Future<CloseReport> close({DateTime? deadline}) =>
      repository.close(deadline: deadline);
}

BotsCommandReply botsCommandReply({
  required OperationId operationId,
  required int revision,
  BotSnapshot? bot,
  BotRegistrationAttempt? registration,
}) {
  final stamp = ResourceStamp(
    resourceKey: 'bots',
    ownerEpoch: botsOrigin.ownerEpoch,
    revision: revision,
  );
  return BotsCommandReply(
    bot: bot,
    registration: registration,
    receipt: CommitReceipt(
      operationId: operationId,
      disposition: CommitDisposition.applied,
      targets: [stamp],
      effect: EffectPoint.immediate,
      effective: true,
      durable: false,
    ),
    stamp: stamp,
  );
}

final class BotsSendCall {
  BotsSendCall(this.request);
  final SendBotMessageRequest request;
  final reply = Completer<BotSendResult>();
}

final class BotsSaveCall {
  BotsSaveCall(this.request);
  final SaveBotRequest request;
  final reply = Completer<BotsCommandReply>();
}

final class BotsMessageReadCall {
  BotsMessageReadCall(this.query);
  final BotMessageQuery query;
  final reply = Completer<BotMessagePage>();
}

final class BotsConversationOpen {
  BotsConversationOpen(this.botId);
  final String botId;
  final reply = Completer<BotConversationReadConnection>();
}

/// The native boundary only. Every unscripted capability fails loudly instead
/// of fabricating a reply, and no policy of the Repository is implemented here.
final class ScriptedBotsPort implements BotsPort {
  final saves = <BotsSaveCall>[];
  final messageReads = <BotsMessageReadCall>[];
  final sends = <BotsSendCall>[];
  final conversationOpens = <BotsConversationOpen>[];
  final _saveWaiters = <int, Completer<BotsSaveCall>>{};
  final _readWaiters = <int, Completer<BotsMessageReadCall>>{};
  final _sendWaiters = <int, Completer<BotsSendCall>>{};
  final _openWaiters = <int, Completer<BotsConversationOpen>>{};
  final _feedWaiters = <int, Completer<ScriptedFeed<BotsFrame>>>{};
  final _feedOpened = Completer<ScriptedFeed<BotsFrame>>();
  final feeds = <ScriptedFeed<BotsFrame>>[];
  ScriptedFeed<BotsFrame>? feed;

  /// The real owner opens the feed from its own bootstrap step, so waiting is
  /// part of the fixture rather than an assumption about call order.
  Future<ScriptedFeed<BotsFrame>> opened() =>
      feed != null ? Future.value(feed) : _feedOpened.future;

  /// Every original native feed, in open order. A restarted owner must reuse
  /// this exact order rather than opening a parallel subscription.
  Future<ScriptedFeed<BotsFrame>> feedAt(int index) => index < feeds.length
      ? Future.value(feeds[index])
      : _feedWaiters
            .putIfAbsent(index, Completer<ScriptedFeed<BotsFrame>>.new)
            .future;

  Future<BotsSaveCall> savedBot(int index) => _call(saves, _saveWaiters, index);
  Future<BotsMessageReadCall> messageRead(int index) =>
      _call(messageReads, _readWaiters, index);
  Future<BotsSendCall> sent(int index) => _call(sends, _sendWaiters, index);
  Future<BotsConversationOpen> conversationOpened(int index) =>
      _call(conversationOpens, _openWaiters, index);

  Future<T> _call<T>(
    List<T> calls,
    Map<int, Completer<T>> waiters,
    int index,
  ) => index < calls.length
      ? Future.value(calls[index])
      : waiters.putIfAbsent(index, Completer<T>.new).future;

  void _record<T>(T call, List<T> calls, Map<int, Completer<T>> waiters) {
    calls.add(call);
    waiters.remove(calls.length - 1)?.complete(call);
  }

  @override
  Future<FeedConnection<BotsFrame>> openBots() async {
    final connecting = ScriptedFeed<BotsFrame>(
      feedId: 'bots-feed',
      sequenceOf: (frame) => frame is BotsData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! BotsData,
    );
    final index = feeds.length;
    feeds.add(connecting);
    feed = connecting;
    _feedWaiters.remove(index)?.complete(connecting);
    if (!_feedOpened.isCompleted) _feedOpened.complete(connecting);
    return connecting;
  }

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) {
    final call = BotsSaveCall(request);
    _record(call, saves, _saveWaiters);
    return call.reply.future;
  }

  @override
  Future<BotConversationReadConnection> openConversations(String botId) {
    final call = BotsConversationOpen(botId);
    _record(call, conversationOpens, _openWaiters);
    return call.reply.future;
  }

  @override
  Future<BotMessagePage> readMessages(BotMessageQuery query) {
    final call = BotsMessageReadCall(query);
    _record(call, messageReads, _readWaiters);
    return call.reply.future;
  }

  @override
  Future<BotSendResult> sendMessage(SendBotMessageRequest request) {
    final call = BotsSendCall(request);
    _record(call, sends, _sendWaiters);
    return call.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected live Bots capability: ${invocation.memberName}',
  );
}

final class ScriptedConversationConnection
    implements BotConversationReadConnection {
  ScriptedConversationConnection(this.botId, {required this.declaredBotId});
  @override
  final String botId;

  /// The identity this scripted native handle reports, so a foreign reply is
  /// representable without inventing a second adapter layer.
  final String? declaredBotId;
  final pages = <ListBotConversationsRequest>[];
  Future<BotConversationPage> Function(ListBotConversationsRequest)? onPage;
  int requestCloseCalls = 0;
  final pageEntered = Completer<void>();

  @override
  Future<BotConversationPage> page(ListBotConversationsRequest request) {
    pages.add(request);
    if (!pageEntered.isCompleted) pageEntered.complete();
    final page = onPage;
    if (page == null) throw StateError('Unscripted bot conversation page');
    return page(request);
  }

  @override
  void requestClose() => requestCloseCalls++;

  @override
  Future<FeedCloseReport> close() async => FeedCloseReport(
    feedId: 'bots:conversations:$botId',
    outcome: const FeedCloseOutcome.clean(),
  );

  @override
  Future<FeedCloseReport> retryClose() => close();
}
