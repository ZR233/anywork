import 'dart:typed_data';

import 'runtime_models.dart';
import 'thread_models.dart' show ThreadTextChannel;
import 'thread_wait_models.dart';

part 'chat_atom_models.dart';
part 'completed_models.dart';

/// The caller's item and encoded-byte demand, mechanically mapped to the Rust protocol.
final class ReadDemand {
  const ReadDemand({required this.maxItems, required this.maxBytes});

  final int maxItems;
  final int maxBytes;
}

sealed class ChatClassFilter {
  const ChatClassFilter();
}

final class ExactChatClass extends ChatClassFilter {
  const ExactChatClass(this.value);
  final String value;
}

final class AllChatClasses extends ChatClassFilter {
  const AllChatClasses();
}

/// 原件业务过滤；All 必须由调用者明确指定。
final class ChatScope {
  const ChatScope({required this.queryClass, this.parentId});
  const ChatScope.conversation({this.parentId})
    : queryClass = const ExactChatClass('conversation');
  final ChatClassFilter queryClass;
  final String? parentId;
}

sealed class PayloadData {
  const PayloadData();
}

final class InlinePayload extends PayloadData {
  InlinePayload({required List<int> bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final Uint8List bytes;
}

final class DeferredPayload extends PayloadData {
  const DeferredPayload({required this.reference, required this.byteLength});

  final ContentRef reference;
  final int byteLength;
}

enum ChatPlacement { set, prepend, append }

/// Immutable completion envelopes in producer order; no presentation grouping.
final class ChatBatch {
  ChatBatch({
    required this.placement,
    required List<CompletedEntry> entries,
    this.before,
    this.fromSeq,
    required this.throughSeq,
  }) : entries = List.unmodifiable(entries);

  final ChatPlacement placement;
  final List<CompletedEntry> entries;
  final String? before;
  final int? fromSeq;
  final int throughSeq;
}

final class ContentRef {
  const ContentRef({required this.databaseId, required this.target});

  final String databaseId;
  final ContentTarget target;
  @override
  bool operator ==(Object other) =>
      other is ContentRef &&
      databaseId == other.databaseId &&
      target == other.target;
  @override
  int get hashCode => Object.hash(databaseId, target);
}

sealed class ContentTarget {
  const ContentTarget();
}

final class ItemPayloadTarget extends ContentTarget {
  const ItemPayloadTarget({required this.itemId});

  final String itemId;
  @override
  bool operator ==(Object other) =>
      other is ItemPayloadTarget && itemId == other.itemId;
  @override
  int get hashCode => Object.hash(ItemPayloadTarget, itemId);
}

final class BodyContentTarget extends ContentTarget {
  const BodyContentTarget({required this.owner, required this.key});

  final ContentOwner owner;
  final String key;
  @override
  bool operator ==(Object other) =>
      other is BodyContentTarget && owner == other.owner && key == other.key;
  @override
  int get hashCode => Object.hash(BodyContentTarget, owner, key);
}

sealed class ContentOwner {
  const ContentOwner();
}

final class DisplayObservationContentOwner extends ContentOwner {
  const DisplayObservationContentOwner({
    required this.blockId,
    required this.memberKey,
  });
  final String blockId;
  final String memberKey;
  @override
  bool operator ==(Object other) =>
      other is DisplayObservationContentOwner &&
      blockId == other.blockId &&
      memberKey == other.memberKey;
  @override
  int get hashCode =>
      Object.hash(DisplayObservationContentOwner, blockId, memberKey);
}

final class ItemContentOwner extends ContentOwner {
  const ItemContentOwner({required this.itemId});

  final String itemId;
  @override
  bool operator ==(Object other) =>
      other is ItemContentOwner && itemId == other.itemId;
  @override
  int get hashCode => Object.hash(ItemContentOwner, itemId);
}

final class CurrentContentOwner extends ContentOwner {
  const CurrentContentOwner({
    required this.domain,
    required this.id,
    required this.revision,
  });

  final String domain;
  final String id;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is CurrentContentOwner &&
      domain == other.domain &&
      id == other.id &&
      revision == other.revision;
  @override
  int get hashCode => Object.hash(CurrentContentOwner, domain, id, revision);
}

final class ContentRange {
  const ContentRange({required this.offset, required this.maxBytes});

  final int offset;
  final int maxBytes;
}

final class ContentWindow {
  ContentWindow({
    required this.offset,
    required List<int> bytes,
    required this.generation,
    required this.availableThrough,
    required this.sealed,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final int offset;
  final Uint8List bytes;
  final String generation;
  final int availableThrough;
  final bool sealed;
}

final class ContentManifestEntry {
  ContentManifestEntry({
    required this.key,
    required List<int> payload,
    required this.reference,
  }) : payload = Uint8List.fromList(payload).asUnmodifiableView();

  final String key;
  final Uint8List payload;
  final ContentRef reference;
}

final class ContentManifestPage {
  ContentManifestPage({
    required List<ContentManifestEntry> entries,
    this.continuation,
  }) : entries = List.unmodifiable(entries);

  final List<ContentManifestEntry> entries;
  final String? continuation;
}

final class CurrentPlanHead {
  const CurrentPlanHead({
    required this.revision,
    required this.phase,
    this.document,
  });

  final int revision;
  final PlanRuntimePhase phase;
  final ContentRef? document;
  @override
  bool operator ==(Object other) =>
      other is CurrentPlanHead &&
      revision == other.revision &&
      phase == other.phase &&
      document == other.document;
  @override
  int get hashCode => Object.hash(revision, phase, document);
}

final class CurrentCollectionRef {
  const CurrentCollectionRef({
    required this.databaseId,
    required this.collection,
    required this.revision,
  });

  final String databaseId;
  final String collection;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is CurrentCollectionRef &&
      databaseId == other.databaseId &&
      collection == other.collection &&
      revision == other.revision;
  @override
  int get hashCode => Object.hash(databaseId, collection, revision);
}

final class ThreadBusinessRefs {
  const ThreadBusinessRefs({required this.plan, required this.interactions});
  final CurrentPlanHead? plan;
  final CurrentCollectionRef? interactions;
  @override
  bool operator ==(Object other) =>
      other is ThreadBusinessRefs &&
      plan == other.plan &&
      interactions == other.interactions;
  @override
  int get hashCode => Object.hash(plan, interactions);
}

final class CurrentCollectionEntry {
  const CurrentCollectionEntry({
    required this.id,
    required this.position,
    required this.payload,
  });

  final String id;
  final int position;
  final PayloadData payload;
}

final class CurrentCollectionPage {
  CurrentCollectionPage({
    required this.revision,
    required List<CurrentCollectionEntry> entries,
    this.continuation,
  }) : entries = List.unmodifiable(entries);

  final int revision;
  final List<CurrentCollectionEntry> entries;
  final String? continuation;
}
