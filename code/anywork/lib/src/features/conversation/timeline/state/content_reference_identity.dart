import 'package:anywork_client/conversation.dart';

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
    (reference.databaseId, reference.collection, reference.revision);
