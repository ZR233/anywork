import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import '../../conversation/data/conversation_observation_port.dart';
import '../../models/domain/model_values.dart';
import '../../modes/domain/delegation_values.dart';
import '../../modes/domain/mode_values.dart';
import '../../workspace/domain/directory_values.dart';
import '../domain/draft_values.dart';
import '../domain/submission_values.dart';

part 'new_thread_creation_port.freezed.dart';

/// Frozen before dispatch. Route and delegation have already been resolved from
/// their original compatible materials; native still owns admission/validation.
/// No selection writer, source handle, callback or staging path lives here.
@Freezed(toStringOverride: false)
abstract class NewThreadCreationRequest with _$NewThreadCreationRequest {
  const factory NewThreadCreationRequest({
    required String projectId,
    required StudioPromptInput input,
    required ThreadModeId mode,
    required ModelSelection route,
    required ThreadWorkspaceMode workspaceMode,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
  }) = _NewThreadCreationRequest;
}

/// begin/find share the same native call identity. find must not create a
/// replacement Thread, and null is not proof of non-dispatch or permission to retry.
abstract interface class NewThreadCreationPort {
  Future<NewThreadCreation> begin(
    OperationId id,
    NewThreadCreationRequest request,
  );
  Future<NewThreadCreation?> find(OperationId id);
}

/// Runtime owner of one real creation, its preparation and original projection.
/// Losing progress observers does not cancel creation or release its admission.
abstract interface class NewThreadCreation {
  OperationId get operationId;
  String get projectId;
  String get inputId;
  ReadonlyLatestValue<ThreadPreparationProgress?> get progress;
  Future<StartNewThreadResult> result();
  Future<CreatedInputExecutionSource> executionSource();

  /// Seal new observations/source opens, not the already accepted command.
  /// close joins that command and late opens; transferred feeds keep their pins.
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
