/// Deferred State metadata retained from the canonical Rust runtime snapshot.
///
/// Body fields are exact JSON windows. Collection fields are real paged
/// collections; their inline array is only a bounded placeholder while this
/// head is present.
sealed class CurrentStateField {
  const CurrentStateField({required this.field});

  factory CurrentStateField.fromJson(Map<String, dynamic> json) {
    final field = _requiredString(json, 'field');
    return switch (_requiredString(json, 'kind')) {
      'body' => BodyCurrentStateField(
        field: field,
        reference: _contentRef(_requiredMap(json, 'reference')),
        byteLength: _requiredInt(json, 'byteLength'),
      ),
      'collection' => CollectionCurrentStateField(
        field: field,
        reference: _collectionRef(_requiredMap(json, 'reference')),
        count: _requiredInt(json, 'count'),
      ),
      final kind => throw FormatException(
        'Unknown CurrentStateField kind: $kind',
      ),
    };
  }

  final String field;
}

final class BodyCurrentStateField extends CurrentStateField {
  const BodyCurrentStateField({
    required super.field,
    required this.reference,
    required this.byteLength,
  });

  final CurrentContentRef reference;
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is BodyCurrentStateField &&
      field == other.field &&
      reference == other.reference &&
      byteLength == other.byteLength;

  @override
  int get hashCode => Object.hash(field, reference, byteLength);
}

final class CollectionCurrentStateField extends CurrentStateField {
  const CollectionCurrentStateField({
    required super.field,
    required this.reference,
    required this.count,
  });

  final CurrentCollectionRef reference;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is CollectionCurrentStateField &&
      field == other.field &&
      reference == other.reference &&
      count == other.count;

  @override
  int get hashCode => Object.hash(field, reference, count);
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$key must be an object');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$key must be a non-empty string');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int && value >= 0) return value;
  throw FormatException('$key must be a non-negative integer');
}

CurrentContentRef _contentRef(Map<String, dynamic> json) => CurrentContentRef(
  ownerId: _requiredString(json, 'ownerId'),
  domain: _requiredString(json, 'domain'),
  entityId: _requiredString(json, 'entityId'),
  contentKey: _requiredString(json, 'contentKey'),
  generation: _requiredString(json, 'generation'),
);

CurrentCollectionRef _collectionRef(Map<String, dynamic> json) =>
    CurrentCollectionRef(
      ownerId: _requiredString(json, 'ownerId'),
      collection: _requiredString(json, 'collection'),
      revision: _requiredInt(json, 'revision'),
    );

final class CurrentContentRef {
  const CurrentContentRef({
    required this.ownerId,
    required this.domain,
    required this.entityId,
    required this.contentKey,
    required this.generation,
  });

  final String ownerId;
  final String domain;
  final String entityId;
  final String contentKey;
  final String generation;
  @override
  bool operator ==(Object other) =>
      other is CurrentContentRef &&
      ownerId == other.ownerId &&
      domain == other.domain &&
      entityId == other.entityId &&
      contentKey == other.contentKey &&
      generation == other.generation;
  @override
  int get hashCode =>
      Object.hash(ownerId, domain, entityId, contentKey, generation);
}

final class CurrentCollectionRef {
  const CurrentCollectionRef({
    required this.ownerId,
    required this.collection,
    required this.revision,
  });

  final String ownerId;
  final String collection;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is CurrentCollectionRef &&
      ownerId == other.ownerId &&
      collection == other.collection &&
      revision == other.revision;
  @override
  int get hashCode => Object.hash(ownerId, collection, revision);
}
