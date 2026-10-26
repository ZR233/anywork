import 'dart:async';

import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'scripted_feed.dart';

/// Native ACP environment only: two independent feeds, two independent command
/// channels and three bounded reads. Nothing here publishes canonical state,
/// merges the two revisions, retries a cancelled command or invents an
/// acceptance snapshot — every fact is declared by the test that uses it.
const acpAuthOrigin = ProductReadOrigin(
  ownerEpoch: 'acp-auth-native',
  incarnation: 1,
);
const acpInstallOrigin = ProductReadOrigin(
  ownerEpoch: 'acp-install-native',
  incarnation: 1,
);

const acpTestAccountId = 'acct-antigravity';
const acpTestConnectionRevision = 3;

/// The receipt resource keys the two ACP owners bind their evidence to.
const acpAuthResourceKey = 'acp-auth';
const acpInstallResourceKey = 'acp-install';

/// One observed account row; the caller chooses the state and watermarks.
AcpAuthSnapshot acpAuthSnapshot({
  required int revision,
  required AcpAuthState state,
  String accountId = acpTestAccountId,
  int connectionRevision = acpTestConnectionRevision,
  int? updatedAt,
}) => AcpAuthSnapshot(
  revision: revision,
  updatedAt: updatedAt ?? revision,
  accounts: [
    AcpAuthAccount(
      accountId: accountId,
      connectionRevision: connectionRevision,
      state: state,
    ),
  ],
);

/// One observed installation row; the caller chooses the state and progress.
AcpInstallSnapshot acpInstallSnapshot({
  required int revision,
  required AcpInstallState state,
  AcpProvider provider = AcpProvider.antigravity,
  int? updatedAt,
}) => AcpInstallSnapshot(
  revision: revision,
  updatedAt: updatedAt ?? revision,
  installations: [AcpInstallEntry(provider: provider, state: state)],
);

/// The fixed managed release the product pins; `sha256` stays null because the
/// 1.4.1 manifest has no publisher checksum.
AcpInstallRelease acpRelease() => const AcpInstallRelease(
  version: '1.4.1',
  target: 'linux-x86_64',
  archiveUrl:
      'https://dl.google.com/agy-extensions/releases/linux/'
      'agy-acp-server-1.4.1-linux-x86_64.zip',
  sha256: null,
);

/// A whole-domain `acpAuth` receipt naming one operation and one watermark.
CommitReceipt acpAuthReceipt(
  OperationId operationId, {
  required int revision,
  String ownerEpoch = 'acp-auth-native',
}) => CommitReceipt(
  operationId: operationId,
  disposition: CommitDisposition.applied,
  targets: [
    ResourceStamp(
      resourceKey: acpAuthResourceKey,
      ownerEpoch: ownerEpoch,
      revision: revision,
    ),
  ],
  effect: EffectPoint.immediate,
);

/// A whole-domain `acpInstall` receipt naming one operation and one watermark.
CommitReceipt acpInstallReceipt(
  OperationId operationId, {
  required int revision,
  String ownerEpoch = 'acp-install-native',
}) => CommitReceipt(
  operationId: operationId,
  disposition: CommitDisposition.applied,
  targets: [
    ResourceStamp(
      resourceKey: acpInstallResourceKey,
      ownerEpoch: ownerEpoch,
      revision: revision,
    ),
  ],
  effect: EffectPoint.immediate,
);

/// One scripted `acpAuth` subscription. Frames are emitted explicitly: the
/// test chooses the projection stamp, the publisher `baseRevision` and whether
/// the reducer is expected to acknowledge the delivery.
final class ScriptedAcpAuthFeed {
  ScriptedAcpAuthFeed(this.index, {this.origin = acpAuthOrigin});

  final int index;
  final ProductReadOrigin origin;
  late final ScriptedFeed<AcpAuthFrame> feed = ScriptedFeed<AcpAuthFrame>(
    feedId: 'acp-auth-$index',
    sequenceOf: (frame) => frame is AcpAuthData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! AcpAuthData,
  );

  int _sequence = 0;

  /// Completes on the actual listen, which is the only moment a frame is legal.
  Future<void> get listened => feed.listened.future;

  ProductFeedIdentity get identity => ProductFeedIdentity(
    feedId: feed.feedId,
    ownerEpoch: origin.ownerEpoch,
    incarnation: origin.incarnation,
    resource: ProductResource.acpAuth,
  );

  ProductProjectionStamp stamp(int revision, {ProductReadOrigin? origin}) {
    final source = origin ?? this.origin;
    return ProductProjectionStamp(
      ownerEpoch: source.ownerEpoch,
      incarnation: source.incarnation,
      revision: revision,
    );
  }

  /// Emits a baseline frame and returns its delivery sequence without waiting
  /// for the acknowledgement. A frame the reducer must reject is never
  /// acknowledged, so rejection tests observe the owner's sync failure instead.
  int sendBaseline(
    AcpAuthSnapshot snapshot, {
    ProductProjectionStamp? stamp,
    ProductFeedIdentity? identity,
  }) => _send(
    AcpAuthEvent.baseline(
      identity: identity ?? this.identity,
      stamp: stamp ?? this.stamp(snapshot.revision),
      snapshot: snapshot,
    ),
  );

  int sendChanged(
    AcpAuthSnapshot snapshot, {
    required int baseRevision,
    ProductProjectionStamp? stamp,
  }) => _send(
    AcpAuthEvent.changed(
      stamp: stamp ?? this.stamp(snapshot.revision),
      baseRevision: baseRevision,
      snapshot: snapshot,
    ),
  );

  int sendResyncRequired({
    ProductResyncReason reason = ProductResyncReason.revisionGap,
  }) {
    feed.emit(AcpAuthFrame.resyncRequired(identity: identity, reason: reason));
    return _sequence;
  }

  int sendFailure(StudioFailure failure) {
    feed.emit(AcpAuthFrame.failure(identity: identity, error: failure));
    return _sequence;
  }

  int sendOwnerReplaced() {
    feed.emit(
      AcpAuthFrame.closed(
        identity: identity,
        reason: ProductFeedCloseReason.ownerReplaced,
      ),
    );
    return _sequence;
  }

  int _send(AcpAuthEvent event) {
    final sequence = ++_sequence;
    feed.emit(AcpAuthFrame.data(deliverySequence: sequence, event: event));
    return sequence;
  }

  /// Waits until the reducer consumed (and therefore acknowledged) a delivery.
  Future<void> acknowledged(int deliverySequence) =>
      feed.acknowledged(deliverySequence);

  /// Publishes a baseline the reducer is expected to accept.
  Future<void> publishBaseline(AcpAuthSnapshot snapshot) async {
    await listened;
    await acknowledged(sendBaseline(snapshot));
  }

  /// Publishes a change the reducer is expected to accept.
  Future<void> publishChanged(
    AcpAuthSnapshot snapshot, {
    required int baseRevision,
  }) async {
    await listened;
    await acknowledged(sendChanged(snapshot, baseRevision: baseRevision));
  }
}

/// One scripted `acpInstall` subscription, structurally independent from the
/// authentication feed: its own identity, revision and delivery sequence.
final class ScriptedAcpInstallFeed {
  ScriptedAcpInstallFeed(this.index, {this.origin = acpInstallOrigin});

  final int index;
  final ProductReadOrigin origin;
  late final ScriptedFeed<AcpInstallFrame> feed = ScriptedFeed<AcpInstallFrame>(
    feedId: 'acp-install-$index',
    sequenceOf: (frame) =>
        frame is AcpInstallData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! AcpInstallData,
  );

  int _sequence = 0;

  Future<void> get listened => feed.listened.future;

  ProductFeedIdentity get identity => ProductFeedIdentity(
    feedId: feed.feedId,
    ownerEpoch: origin.ownerEpoch,
    incarnation: origin.incarnation,
    resource: ProductResource.acpInstall,
  );

  ProductProjectionStamp stamp(int revision, {ProductReadOrigin? origin}) {
    final source = origin ?? this.origin;
    return ProductProjectionStamp(
      ownerEpoch: source.ownerEpoch,
      incarnation: source.incarnation,
      revision: revision,
    );
  }

  int sendBaseline(
    AcpInstallSnapshot snapshot, {
    ProductProjectionStamp? stamp,
    ProductFeedIdentity? identity,
  }) => _send(
    AcpInstallEvent.baseline(
      identity: identity ?? this.identity,
      stamp: stamp ?? this.stamp(snapshot.revision),
      snapshot: snapshot,
    ),
  );

  int sendChanged(
    AcpInstallSnapshot snapshot, {
    required int baseRevision,
    ProductProjectionStamp? stamp,
  }) => _send(
    AcpInstallEvent.changed(
      stamp: stamp ?? this.stamp(snapshot.revision),
      baseRevision: baseRevision,
      snapshot: snapshot,
    ),
  );

  int sendFailure(StudioFailure failure) {
    feed.emit(AcpInstallFrame.failure(identity: identity, error: failure));
    return _sequence;
  }

  int _send(AcpInstallEvent event) {
    final sequence = ++_sequence;
    feed.emit(AcpInstallFrame.data(deliverySequence: sequence, event: event));
    return sequence;
  }

  Future<void> acknowledged(int deliverySequence) =>
      feed.acknowledged(deliverySequence);

  Future<void> publishBaseline(AcpInstallSnapshot snapshot) async {
    await listened;
    await acknowledged(sendBaseline(snapshot));
  }

  Future<void> publishChanged(
    AcpInstallSnapshot snapshot, {
    required int baseRevision,
  }) async {
    await listened;
    await acknowledged(sendChanged(snapshot, baseRevision: baseRevision));
  }
}

/// One recorded native command invocation. The reply is never defaulted: a
/// pending `Future` is how the test expresses "the transport has not answered".
final class ScriptedAcpCommand<TRequest, TReply> {
  ScriptedAcpCommand(this.request);
  final TRequest request;
  final reply = Completer<TReply>();

  /// The acceptance reply; the caller declares its own receipt and snapshot.
  void accept(TReply value) => reply.complete(value);

  /// Dispatch evidence raised by the native boundary itself.
  void reject(CommandDispatchFailure failure) => reply.completeError(failure);

  /// A plain failure, which is exactly what an FRB call can produce.
  void fail(StudioFailure failure) {
    reply.completeError(failure);
  }
}

/// Explicit native identity plus independent result/close gates are not part of
/// this boundary: the ACP commands return one acceptance reply only.
final class ScriptedAcpPort implements AcpPort {
  /// Origin used by the next opened feed; a new incarnation scripts an owner
  /// restart without inventing a watermark in this file.
  ProductReadOrigin authFeedOrigin = acpAuthOrigin;
  ProductReadOrigin installFeedOrigin = acpInstallOrigin;

  final authFeeds = <ScriptedAcpAuthFeed>[];
  final installFeeds = <ScriptedAcpInstallFeed>[];
  final _authFeedWaiters = <int, Completer<ScriptedAcpAuthFeed>>{};
  final _installFeedWaiters = <int, Completer<ScriptedAcpInstallFeed>>{};

  final authStarts =
      <ScriptedAcpCommand<AcpAuthStartRequest, AcpAuthCommandReply>>[];
  final authCancels =
      <ScriptedAcpCommand<AcpAuthCancelRequest, AcpAuthCommandReply>>[];
  final installStarts =
      <ScriptedAcpCommand<AcpInstallStartRequest, AcpInstallCommandReply>>[];
  final installCancels =
      <ScriptedAcpCommand<AcpInstallCancelRequest, AcpInstallCommandReply>>[];

  final _authStartWaiters = <int, Completer<void>>{};
  final _authCancelWaiters = <int, Completer<void>>{};
  final _installStartWaiters = <int, Completer<void>>{};
  final _installCancelWaiters = <int, Completer<void>>{};

  final authReads = <Completer<AcpAuthSnapshot>>[];
  final installReads = <Completer<AcpInstallSnapshot>>[];
  final catalogReads = <Completer<AcpAccountCatalog>>[];

  Future<ScriptedAcpAuthFeed> authFeedOpened(int index) =>
      index < authFeeds.length
      ? Future.value(authFeeds[index])
      : _authFeedWaiters.putIfAbsent(index, Completer.new).future;

  Future<ScriptedAcpInstallFeed> installFeedOpened(int index) =>
      index < installFeeds.length
      ? Future.value(installFeeds[index])
      : _installFeedWaiters.putIfAbsent(index, Completer.new).future;

  Future<ScriptedAcpCommand<AcpAuthStartRequest, AcpAuthCommandReply>>
  authStarted(int index) => _recorded(authStarts, _authStartWaiters, index);

  Future<ScriptedAcpCommand<AcpAuthCancelRequest, AcpAuthCommandReply>>
  authCancelled(int index) => _recorded(authCancels, _authCancelWaiters, index);

  Future<ScriptedAcpCommand<AcpInstallStartRequest, AcpInstallCommandReply>>
  installStarted(int index) =>
      _recorded(installStarts, _installStartWaiters, index);

  Future<ScriptedAcpCommand<AcpInstallCancelRequest, AcpInstallCommandReply>>
  installCancelled(int index) =>
      _recorded(installCancels, _installCancelWaiters, index);

  Future<ScriptedAcpCommand<TRequest, TReply>> _recorded<TRequest, TReply>(
    List<ScriptedAcpCommand<TRequest, TReply>> calls,
    Map<int, Completer<void>> waiters,
    int index,
  ) {
    final known = index < calls.length;
    if (known) return Future.value(calls[index]);
    return waiters
        .putIfAbsent(index, Completer.new)
        .future
        .then((_) => calls[index]);
  }

  void _notify(Map<int, Completer<void>> waiters, int index) {
    waiters.remove(index)?.complete();
  }

  /// Answers a bounded `readAuthState` call by its invocation order.
  void answerAuthRead(int index, AcpAuthSnapshot value) =>
      authReads[index].complete(value);

  void rejectAuthRead(int index, Object error) =>
      authReads[index].completeError(error);

  void answerInstallRead(int index, AcpInstallSnapshot value) =>
      installReads[index].complete(value);

  void answerCatalogRead(int index, AcpAccountCatalog value) =>
      catalogReads[index].complete(value);

  @override
  Future<FeedConnection<AcpAuthFrame>> openAcpAuth() async {
    final feed = ScriptedAcpAuthFeed(authFeeds.length, origin: authFeedOrigin);
    authFeeds.add(feed);
    _authFeedWaiters.remove(feed.index)?.complete(feed);
    return feed.feed;
  }

  @override
  Future<FeedConnection<AcpInstallFrame>> openAcpInstall() async {
    final feed = ScriptedAcpInstallFeed(
      installFeeds.length,
      origin: installFeedOrigin,
    );
    installFeeds.add(feed);
    _installFeedWaiters.remove(feed.index)?.complete(feed);
    return feed.feed;
  }

  @override
  Future<AcpAccountCatalog> readAccountCatalog() {
    final reply = Completer<AcpAccountCatalog>();
    catalogReads.add(reply);
    return reply.future;
  }

  @override
  Future<AcpAuthSnapshot> readAuthState() {
    final reply = Completer<AcpAuthSnapshot>();
    authReads.add(reply);
    return reply.future;
  }

  @override
  Future<AcpInstallSnapshot> readInstallState() {
    final reply = Completer<AcpInstallSnapshot>();
    installReads.add(reply);
    return reply.future;
  }

  @override
  Future<AcpAuthCommandReply> startAuth(AcpAuthStartRequest request) {
    final call = ScriptedAcpCommand<AcpAuthStartRequest, AcpAuthCommandReply>(
      request,
    );
    authStarts.add(call);
    _notify(_authStartWaiters, authStarts.length - 1);
    return call.reply.future;
  }

  @override
  Future<AcpAuthCommandReply> cancelAuth(AcpAuthCancelRequest request) {
    final call = ScriptedAcpCommand<AcpAuthCancelRequest, AcpAuthCommandReply>(
      request,
    );
    authCancels.add(call);
    _notify(_authCancelWaiters, authCancels.length - 1);
    return call.reply.future;
  }

  @override
  Future<AcpInstallCommandReply> startInstall(AcpInstallStartRequest request) {
    final call =
        ScriptedAcpCommand<AcpInstallStartRequest, AcpInstallCommandReply>(
          request,
        );
    installStarts.add(call);
    _notify(_installStartWaiters, installStarts.length - 1);
    return call.reply.future;
  }

  @override
  Future<AcpInstallCommandReply> cancelInstall(
    AcpInstallCancelRequest request,
  ) {
    final call =
        ScriptedAcpCommand<AcpInstallCancelRequest, AcpInstallCommandReply>(
          request,
        );
    installCancels.add(call);
    _notify(_installCancelWaiters, installCancels.length - 1);
    return call.reply.future;
  }
}

/// The production factories and operation registry; only the native port is
/// scripted. Both owners share one budget/registry exactly like the composition
/// root, which must not make them share a revision or a close channel.
final class AcpPortFixture {
  AcpPortFixture({ResourceBudget? budget})
    : budget = budget ?? ResourceBudget() {
    operations = OperationRegistry(
      clientId: 'acp-client-test',
      budget: this.budget,
    );
    auth = createAcpAuthRepository(
      port: port,
      budget: this.budget,
      operations: operations,
    );
    install = createAcpInstallRepository(
      port: port,
      budget: this.budget,
      operations: operations,
    );
  }

  final ResourceBudget budget;
  final port = ScriptedAcpPort();
  late final OperationRegistry operations;
  late final AcpAuthRepository auth;
  late final AcpInstallRepository install;
}

/// Opens the `acpAuth` subscription, publishes one baseline and waits until the
/// owner reports ready — the precondition every explicit command test needs.
Future<ScriptedAcpAuthFeed> establishAcpAuth(
  AcpPortFixture fixture, {
  int revision = 1,
  AcpAuthState state = const AcpAuthState.unchecked(),
}) async {
  final synchronizing = fixture.auth.synchronize();
  final feed = await fixture.port.authFeedOpened(0);
  await feed.publishBaseline(acpAuthSnapshot(revision: revision, state: state));
  await synchronizing;
  return feed;
}

/// Opens the `acpInstall` subscription, publishes one baseline and waits until
/// the owner reports ready; the two ACP resources never share this step.
Future<ScriptedAcpInstallFeed> establishAcpInstall(
  AcpPortFixture fixture, {
  int revision = 1,
  AcpInstallState state = const AcpInstallState.idle(),
}) async {
  final synchronizing = fixture.install.synchronize();
  final feed = await fixture.port.installFeedOpened(0);
  await feed.publishBaseline(
    acpInstallSnapshot(revision: revision, state: state),
  );
  await synchronizing;
  return feed;
}
