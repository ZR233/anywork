import 'dart:typed_data';

import 'runtime_models.dart';
import 'thread_activity_models.dart';
import 'thread_directory_models.dart';
import 'thread_models.dart' show ThreadTextChannel;
import 'thread_wait_models.dart';
import 'turn_models.dart';

part 'chat_atom_models.dart';

/// The caller's item and encoded-byte demand, mechanically mapped to the Rust protocol.
final class ReadDemand {
  const ReadDemand({required this.maxItems, required this.maxBytes});

  final int maxItems;
  final int maxBytes;
}

sealed class ChatScope {
  const ChatScope();
}

final class MainChatScope extends ChatScope {
  const MainChatScope();
}

final class ChildrenChatScope extends ChatScope {
  const ChildrenChatScope({required this.parentId});

  final String parentId;
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

/// The sole message delivery model. Null current means retain the previous current snapshot.
final class ChatBatch {
  ChatBatch({
    required this.placement,
    required List<ChatEntry> entries,
    this.before,
    this.current,
  }) : entries = List.unmodifiable(entries);

  final ChatPlacement placement;
  final List<ChatEntry> entries;
  final String? before;
  final CurrentProjection? current;
}

final class ContentRef {
  const ContentRef({required this.databaseId, required this.target});

  final String databaseId;
  final ContentTarget target;
}

sealed class ContentTarget {
  const ContentTarget();
}

final class ItemPayloadTarget extends ContentTarget {
  const ItemPayloadTarget({required this.itemId});

  final String itemId;
}

final class BodyContentTarget extends ContentTarget {
  const BodyContentTarget({required this.owner, required this.key});

  final ContentOwner owner;
  final String key;
}

sealed class ContentOwner {
  const ContentOwner();
}

final class ItemContentOwner extends ContentOwner {
  const ItemContentOwner({required this.itemId});

  final String itemId;
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

final class CurrentProjection {
  CurrentProjection({
    required this.sourceEffectSeq,
    required this.logicalStatus,
    required this.executionPresent,
    this.active,
    this.activeTurn,
    required List<ChatSourceState> sources,
    required List<ChatAtom> atoms,
    this.plan,
    this.interactions,
    required List<CurrentContentPreview> previews,
    required List<CurrentCollectionRef> collections,
  }) : sources = List.unmodifiable(sources),
       atoms = List.unmodifiable(atoms),
       previews = List.unmodifiable(previews),
       collections = List.unmodifiable(collections);

  final int sourceEffectSeq;
  final ThreadStatusView logicalStatus;
  final bool executionPresent;
  final CurrentActivityHead? active;
  final CurrentTurnHead? activeTurn;
  final List<ChatSourceState> sources;
  final List<ChatAtom> atoms;
  final CurrentPlanHead? plan;
  final CurrentCollectionRef? interactions;
  final List<CurrentContentPreview> previews;
  final List<CurrentCollectionRef> collections;
}

final class CurrentActivityHead {
  const CurrentActivityHead({
    required this.id,
    required this.kind,
    required this.summary,
    this.thinkingSummary,
    this.thinkingSeconds,
    required this.toolCount,
    required this.backgroundToolCount,
    this.latestTool,
  });

  final String id;
  final ThreadActivityKind kind;
  final String summary;
  final String? thinkingSummary;
  final int? thinkingSeconds;
  final int toolCount;
  final int backgroundToolCount;
  final CurrentToolHead? latestTool;
}

final class CurrentToolHead {
  const CurrentToolHead({
    required this.callId,
    required this.name,
    required this.state,
  });

  final String callId;
  final String name;
  final ThreadActivityToolState state;
}

final class CurrentTurnHead {
  const CurrentTurnHead({required this.id, required this.phase});

  final String id;
  final StudioTurnActivity phase;
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
}

enum CurrentContentRole { reasoning, response, toolArguments, toolOutput }

final class CurrentContentPreview {
  const CurrentContentPreview({
    required this.id,
    required this.role,
    required this.text,
    required this.reference,
    this.textChannel,
  });

  final String id;
  final CurrentContentRole role;

  /// Original producer channel, not inferred from the display role or body.
  final ThreadTextChannel? textChannel;
  final String text;
  final ContentRef reference;
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
