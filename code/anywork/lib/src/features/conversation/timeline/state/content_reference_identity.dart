import 'package:anywork_client/conversation.dart';

Object currentCollectionIdentity(CurrentCollectionRef reference) =>
    (reference.ownerId, reference.collection, reference.revision);

Object currentContentIdentity(CurrentContentRef reference) => (
  reference.ownerId,
  reference.domain,
  reference.entityId,
  reference.contentKey,
  reference.generation,
);

Object historyBodyIdentity(HistoryEventBodyRef reference) => (
  reference.databaseId,
  reference.ownerEventId,
  reference.bodyKey,
  reference.bodyId,
  reference.byteStart,
  reference.byteLength,
);
