import 'package:anywork_client/conversation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'read_material.dart';

part 'thread_status_state.freezed.dart';

@Freezed(toStringOverride: false)
abstract class ThreadStatusViewState with _$ThreadStatusViewState {
  const factory ThreadStatusViewState({
    required String threadId,
    ThreadExecutionState? execution,
    ThreadConfigurationState? configuration,
    WorkflowBrief? workflow,
    @Default(ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem>())
    ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead,
    @Default(ReadMaterial<StorageReadHeader, Never>()) ReadMaterial<StorageReadHeader, Never> storageRead,
    @Default(ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem>())
    ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead,
    @Default(ReadMaterial<WorkflowReadHeader, Never>()) ReadMaterial<WorkflowReadHeader, Never> workflowRead,
    @Default(ReadMaterial<TurnReadHeader, Never>()) ReadMaterial<TurnReadHeader, Never> turnRead,
    ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets,
    @Default({}) Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool,
    @Default(false) bool detailsVisible,
  }) = _ThreadStatusViewState;
}
