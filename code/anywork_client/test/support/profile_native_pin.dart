import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

/// Scripted native read lifetime only. Queries do not publish canonical state;
/// native close still joins their actual replies.
abstract class ProfileNativePin {
  ProfileNativePin(this.id);
  final String id;
  bool sealed = false;
  bool closed = false;
  int _pending = 0;
  Completer<void>? _idle;

  void admit() {
    if (sealed)
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'The original scripted Profile pin is sealed.',
        retryable: false,
        correlationId: 'profile-native-pin',
      );
  }

  Future<T> reply<T>(Future<T> response) {
    admit();
    _pending++;
    return response.whenComplete(() {
      if (--_pending == 0) {
        _idle?.complete();
        _idle = null;
      }
    });
  }

  void requestClose() => sealed = true;
  Future<FeedCloseReport> close() async {
    requestClose();
    if (_pending != 0) await (_idle ??= Completer<void>()).future;
    closed = true;
    return FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean());
  }

  Future<FeedCloseReport> retryClose() => close();

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Profile pin capability: ${invocation.memberName}',
  );
}

ProductProjectionStamp profileStamp(ProductReadOrigin origin, int revision) =>
    ProductProjectionStamp(
      ownerEpoch: origin.ownerEpoch,
      incarnation: origin.incarnation,
      revision: revision,
    );

ProductFeedIdentity profileIdentity(
  String feedId,
  ProductReadOrigin origin,
  ProductResource resource,
) => ProductFeedIdentity(
  feedId: feedId,
  ownerEpoch: origin.ownerEpoch,
  incarnation: origin.incarnation,
  resource: resource,
);

ProductCollectionRef profileCollection(int revision, int total) =>
    ProductCollectionRef(entry: 2, revision: revision, total: total);

ObservedHeader profileSource(int revision) => ObservedHeader(
  brief: ObservedBrief.ready(
    revision: revision,
    updatedAt: revision,
    lastCheckedAt: null,
  ),
  status: ProductSourceStatusRef(entry: 9, revision: revision),
);

final class ProfileSourcePin extends ProfileNativePin
    implements ProductSourceStatusReadConnection {
  ProfileSourcePin(this.revision) : super('profile-source-$revision');
  final int revision;
  @override
  Future<ProductSourceStatusReadHeader> header() async {
    admit();
    return ProductSourceStatusReadHeader.ready(
      revision: revision,
      updatedAt: revision,
      lastCheckedAt: null,
    );
  }
}
