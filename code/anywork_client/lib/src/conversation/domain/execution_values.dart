import 'package:freezed_annotation/freezed_annotation.dart';

import '../../resources/persistence/domain/persistence_values.dart';
import '../../workspace/domain/directory_values.dart';
import 'thread_identity.dart';
import 'turn_values.dart';

part 'execution_values.freezed.dart';

enum InteractionKind { userInput, toolApproval }

enum InteractionStatus { pending, resolved, cancelled, expired }

enum ThreadActivityKind {
  preparing,
  waitingApi,
  thinking,
  responding,
  planning,
  runningTool,
  awaitingApproval,
  awaitingInput,
  stopping,
}

@freezed
abstract class InteractionBrief with _$InteractionBrief {
  const factory InteractionBrief({
    required InteractionReadRef reference,
    required int revision,
    required InteractionKind kind,
    required InteractionStatus status,
    required int createdAt,
    required int updatedAt,
  }) = _InteractionBrief;
}

@freezed
abstract class InteractionIndexHeader with _$InteractionIndexHeader {
  const factory InteractionIndexHeader({
    required InteractionIndexRef reference,
    required int total,
    required int pending,
  }) = _InteractionIndexHeader;
}

@freezed
final class InteractionDelta with _$InteractionDelta {
  InteractionDelta({
    required this.baseIndexRevision,
    required this.index,
    required List<InteractionBrief> upserted,
    required List<int> removedEntries,
    required List<InteractionBrief> terminalFacts,
  }) : upserted = List.unmodifiable(upserted),
       removedEntries = List.unmodifiable(removedEntries),
       terminalFacts = List.unmodifiable(terminalFacts);
  final int baseIndexRevision;
  final InteractionIndexHeader index;
  final List<InteractionBrief> upserted;
  final List<int> removedEntries;
  final List<InteractionBrief> terminalFacts;
}

@freezed
abstract class ActivityBrief with _$ActivityBrief {
  const factory ActivityBrief({
    required ActivityReadRef reference,
    required int revision,
    required ThreadActivityKind kind,
    required int toolCount,
    required int backgroundCount,
    required int activeCount,
    required bool hasLatestStarted,
  }) = _ActivityBrief;
}

/// History fault and storage execution enums are owned by resources/persistence.
@freezed
abstract class StorageBrief with _$StorageBrief {
  const factory StorageBrief({
    required StorageReadRef reference,
    required HistoryFault? fault,
    required int faultGeneration,
    required int? acceptedSequence,
    required int? durableSequence,
    required ThreadStorageExecution execution,
    required bool pressurePaused,
    required bool resumeRequired,
    required bool canResume,
    required bool hasLastError,
  }) = _StorageBrief;
}

@freezed
abstract class ThreadExecutionBaseline with _$ThreadExecutionBaseline {
  const factory ThreadExecutionBaseline({
    required ThreadStatus status,
    required TurnBrief? activeTurn,
    required TurnBrief? recentTerminalTurn,
    required InteractionIndexHeader interactions,
    required ActivityBrief? activity,
    required StorageBrief? storage,
  }) = _ThreadExecutionBaseline;
}

@freezed
abstract class TurnsReplacement with _$TurnsReplacement {
  const factory TurnsReplacement({
    required TurnBrief? activeTurn,
    required TurnBrief? recentTerminalTurn,
  }) = _TurnsReplacement;
}

@freezed
sealed class ActivityReplacement with _$ActivityReplacement {
  const factory ActivityReplacement.unchanged() = UnchangedActivity;
  const factory ActivityReplacement.replace({required ActivityBrief? value}) =
      ReplacedActivity;
}

@freezed
sealed class StorageReplacement with _$StorageReplacement {
  const factory StorageReplacement.unchanged() = UnchangedStorage;
  const factory StorageReplacement.replace({required StorageBrief? value}) =
      ReplacedStorage;
}

@freezed
abstract class ThreadExecutionChange with _$ThreadExecutionChange {
  const factory ThreadExecutionChange({
    required ThreadStatus? status,
    required TurnsReplacement? turns,
    required InteractionDelta? interactions,
    required ActivityReplacement activity,
    required StorageReplacement storage,
  }) = _ThreadExecutionChange;
}
