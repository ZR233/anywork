part of 'chat_models.dart';

const completedHistoryVersion = 2;
const completedReadIndexVersion = 2;

final class CompletedEntry {
  const CompletedEntry({
    required this.recordId,
    required this.completionSeq,
    required this.atom,
  });
  final String recordId;
  final int completionSeq;
  final ChatAtom atom;
}

sealed class ActivityIdentity {
  const ActivityIdentity();
}

final class ModelPartActivityIdentity extends ActivityIdentity {
  const ModelPartActivityIdentity({required this.atomId});
  final String atomId;
  @override
  bool operator ==(Object other) =>
      other is ModelPartActivityIdentity && atomId == other.atomId;
  @override
  int get hashCode => Object.hash(ModelPartActivityIdentity, atomId);
}

final class ForegroundToolActivityIdentity extends ActivityIdentity {
  const ForegroundToolActivityIdentity({required this.callId});
  final String callId;
  @override
  bool operator ==(Object other) =>
      other is ForegroundToolActivityIdentity && callId == other.callId;
  @override
  int get hashCode => Object.hash(ForegroundToolActivityIdentity, callId);
}

final class BackgroundToolActivityIdentity extends ActivityIdentity {
  const BackgroundToolActivityIdentity({required this.callId});
  final String callId;
  @override
  bool operator ==(Object other) =>
      other is BackgroundToolActivityIdentity && callId == other.callId;
  @override
  int get hashCode => Object.hash(BackgroundToolActivityIdentity, callId);
}

final class OtherActivityIdentity extends ActivityIdentity {
  const OtherActivityIdentity({required this.domain, required this.id});
  final String domain;
  final String id;
  @override
  bool operator ==(Object other) =>
      other is OtherActivityIdentity &&
      domain == other.domain &&
      id == other.id;
  @override
  int get hashCode => Object.hash(OtherActivityIdentity, domain, id);
}

final class ActivityEntry {
  const ActivityEntry({required this.identity, required this.atom});
  final ActivityIdentity identity;
  final ChatAtom atom;
}

final class ActivitySnapshot {
  ActivitySnapshot({
    required this.revision,
    required this.completedThrough,
    required this.executionPresent,
    required List<ActivityEntry> entries,
  }) : entries = List.unmodifiable(entries);
  final int revision;
  final int completedThrough;
  final bool executionPresent;
  final List<ActivityEntry> entries;
}

/// Only typed producer metadata participates. Payload and display names never do.
ActivityIdentity? completedActivityIdentity(CompletedEntry entry) {
  final atom = entry.atom;
  if (atom.lifecycle is! TerminalChatAtom) return null;
  if ((atom.kind == ChatAtomKind.text || atom.kind == ChatAtomKind.reasoning) &&
      atom.attemptId != null) {
    return ModelPartActivityIdentity(atomId: atom.id);
  }
  if (atom.kind == ChatAtomKind.compaction) {
    if (atom.source case OperationChatSource(:final operationId)) {
      return OtherActivityIdentity(domain: 'operation', id: operationId);
    }
    return null;
  }
  final tool = atom.tool;
  if (tool == null ||
      !const {
        ChatAtomKind.toolCall,
        ChatAtomKind.plan,
        ChatAtomKind.interaction,
        ChatAtomKind.fileChange,
        ChatAtomKind.skill,
      }.contains(atom.kind))
    return null;
  if (atom.source is BackgroundResultChatSource) {
    return BackgroundToolActivityIdentity(callId: tool.callId);
  }
  if (atom.delivery != ChatDeliveryKind.independent) {
    return ForegroundToolActivityIdentity(callId: tool.callId);
  }
  return null;
}
