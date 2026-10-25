import 'dart:async';

import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/scripted_feed.dart';

final class _CatalogPort implements ModelsPort {
  final feeds = <ScriptedFeed<ModelCatalogFrame>>[];
  final _feedWaiters = <int, Completer<ScriptedFeed<ModelCatalogFrame>>>{};
  final reads = <({ProductReadOrigin origin, ModelCatalogReadRef reference})>[];

  Future<ScriptedFeed<ModelCatalogFrame>> opened(int index) {
    if (index < feeds.length) return Future.value(feeds[index]);
    return _feedWaiters
        .putIfAbsent(index, Completer<ScriptedFeed<ModelCatalogFrame>>.new)
        .future;
  }

  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() async {
    final index = feeds.length;
    final feed = ScriptedFeed<ModelCatalogFrame>(
      feedId: 'catalog-$index',
      sequenceOf: (frame) =>
          frame is ModelCatalogData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ModelCatalogData,
    );
    feeds.add(feed);
    _feedWaiters.remove(index)?.complete(feed);
    return feed;
  }

  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    reads.add((origin: origin, reference: reference));
    return _CatalogRead(
      origin.ownerEpoch == 'old-owner' ? 'old' : 'fresh',
      'catalog-read-${reads.length}',
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected model capability: ${invocation.memberName}',
  );
}

/// Only the environment's typed root policy. This does not implement the
/// Models mirror, origin validation, resync or command-target synchronization.
final class _CatalogRead implements ModelCatalogReadConnection {
  _CatalogRead(this.mode, this.id);
  final String mode;
  final String id;
  bool closing = false;

  @override
  Future<ModelCatalogReadHeader> header() async {
    if (closing) throw StateError('The original catalog pin is closed');
    return ModelCatalogReadHeader(
      accounts: const TypedListRef(listId: 1, total: 0),
      webSearch: EffectiveWebSearchRead(
        effectiveMode: ReadText.inline(text: mode),
        availability: const ReadText.inline(text: 'available'),
        accountId: null,
        modelId: null,
      ),
      deepseekWebSearch: const EffectiveDeepSeekSearchRead(
        effectiveEnabled: false,
        effectiveFetchEnabled: false,
        availability: ReadText.inline(text: 'unavailable'),
        accountId: null,
      ),
    );
  }

  @override
  void requestClose() => closing = true;
  @override
  Future<FeedCloseReport> close() async {
    requestClose();
    return FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean());
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected catalog body read: ${invocation.memberName}',
  );
}

ModelCatalogHeader _header(int revision) => ModelCatalogHeader(
  source: ObservedHeader(
    brief: ObservedBrief.ready(
      revision: revision,
      updatedAt: 1,
      lastCheckedAt: null,
    ),
    status: ProductSourceStatusRef(entry: 9, revision: revision),
  ),
  catalogRevision: revision,
  updatedAt: 1,
  reference: ModelCatalogReadRef(entry: 1, revision: revision),
);

ProductCollectionRef _collection(int revision) =>
    ProductCollectionRef(entry: 2, revision: revision, total: 0);

ProductFeedIdentity _identity(
  ScriptedFeed<ModelCatalogFrame> feed,
  String owner,
  int incarnation,
) => ProductFeedIdentity(
  feedId: feed.feedId,
  ownerEpoch: owner,
  incarnation: incarnation,
  resource: ProductResource.modelCatalog,
);

ModelCatalogFrame _baseline(
  ScriptedFeed<ModelCatalogFrame> feed, {
  required String owner,
  required int incarnation,
  required int revision,
}) => ModelCatalogFrame.data(
  deliverySequence: 1,
  event: ModelCatalogEvent.baseline(
    identity: _identity(feed, owner, incarnation),
    stamp: ProductProjectionStamp(
      ownerEpoch: owner,
      incarnation: incarnation,
      revision: revision,
    ),
    value: ModelCatalogBaseline(
      header: _header(revision),
      collection: _collection(revision),
    ),
  ),
);

void main() {
  test('a new native baseline resets origin and an old-owner delta cannot corrupt its materialized value', () async {
    final port = _CatalogPort();
    final budget = ResourceBudget();
    final models = createModelsRepository(
      port: port,
      budget: budget,
    ).repository;
    addTearDown(() => models.close());
    expect(
      port.feeds,
      isEmpty,
      reason: 'Constructing a Repository is not feed demand',
    );
    final oldRead = models.loadWebSearch();
    final first = await port.opened(0);
    await first.listened.future;
    first.emit(
      _baseline(first, owner: 'old-owner', incarnation: 1, revision: 50),
    );
    expect((await oldRead).effectiveMode, 'old');
    await first.acknowledged(1);

    // A low revision is legal on a new owner after an explicit resync baseline.
    first.emit(
      ModelCatalogFrame.resyncRequired(
        identity: _identity(first, 'old-owner', 1),
        reason: ProductResyncReason.revisionGap,
      ),
    );
    final replacement = await port.opened(1);
    await replacement.listened.future;
    final freshRead = models.loadWebSearch();
    replacement.emit(
      _baseline(replacement, owner: 'new-owner', incarnation: 2, revision: 1),
    );
    expect((await freshRead).effectiveMode, 'fresh');
    await replacement.acknowledged(1);
    final current = models.state.value;
    final fresh =
        current.webSearch
            as ReadyReadValue<EffectiveWebSearch, ModelCatalogReadRef>;
    expect(
      fresh.current.origin,
      const ProductReadOrigin(ownerEpoch: 'new-owner', incarnation: 2),
    );

    // Migration of the former writable canonical-patch regression: exercise
    // the real public Repository reducer rather than a removed writable helper.
    // Delivery is contiguous; only the business source origin is invalid.
    replacement.emit(
      ModelCatalogFrame.data(
        deliverySequence: 2,
        event: ModelCatalogEvent.change(
          stamp: const ProductProjectionStamp(
            ownerEpoch: 'old-owner',
            incarnation: 1,
            revision: 51,
          ),
          baseRevision: 1,
          value: ModelCatalogChange(
            header: _header(51),
            baseCollectionRevision: 1,
            collection: _collection(51),
            upserted: const [],
            removedEntries: const [],
          ),
        ),
      ),
    );
    final failed = await models.state.waitFor(
      (state) => state.projection.sync.phase == ResourceSyncPhase.failed,
    );
    expect(failed.projection.sync.error?.code, StudioFailureCode.protocol);
    expect(failed.projection.stamp, current.projection.stamp);
    expect(failed.projection.header, current.projection.header);
    expect(
      failed.webSearch,
      current.webSearch,
      reason: 'The stale delta must not rebrand or overwrite the fresh canonical read',
    );
    expect(replacement.acknowledgements, [
      1,
    ], reason: 'Rejected conversion/reduction is not ACKed');
    expect(port.reads.map((read) => read.origin.ownerEpoch), [
      'old-owner',
      'new-owner',
    ]);
    expect((await models.close()).complete, isTrue);
    expect(budget.usage, isEmpty);
  });
}
