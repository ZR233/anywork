import 'package:anywork_client/conversation.dart';

bool isDisplayObservationReference(ContentRef reference) =>
    switch (reference.target) {
      BodyContentTarget(owner: DisplayObservationContentOwner()) => true,
      _ => false,
    };

/// Value identity of protocol references. Producer snapshots allocate new Dart
/// objects; allocation identity is not a content owner/generation boundary.
Object contentReferenceIdentity(ContentRef reference) => (
  reference.databaseId,
  switch (reference.target) {
    ItemPayloadTarget(:final itemId) => ('payload', itemId),
    BodyContentTarget(:final owner, :final key) => (
      'body',
      switch (owner) {
        ItemContentOwner(:final itemId) => ('item', itemId),
        DisplayObservationContentOwner(:final blockId, :final memberKey) => (
          'displayObservation',
          blockId,
          memberKey,
        ),
        CurrentContentOwner(:final domain, :final id, :final revision) => (
          'current',
          domain,
          id,
          revision,
        ),
      },
      key,
    ),
  },
);

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
