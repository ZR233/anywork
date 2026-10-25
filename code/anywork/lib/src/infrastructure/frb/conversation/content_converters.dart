import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/types/thread_stream/item.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'content_nested_converters.dart';
import 'content_question_converters.dart';
import 'content_turn_converters.dart';

ThreadItemView contentItemFromBridge(
  native.BridgeThreadItem value, {
  required String expectedThreadId,
  required bool saved,
  required bool executionTerminal,
  required int omittedBytes,
}) {
  if (value.threadId != expectedThreadId) {
    throw adapterProtocol('timeline-item-thread');
  }
  return ThreadItemView(
    id: value.id,
    threadId: value.threadId,
    turnId: value.turnId,
    ordinal: exactU64(value.ordinal, 'Timeline item ordinal'),
    revision: exactU64(value.revision, 'Timeline item revision'),
    createdAt: exactI64(
      BigInt.from(value.createdAt),
      'Timeline item created Unix seconds',
    ),
    updatedAt: exactI64(
      BigInt.from(value.updatedAt),
      'Timeline item updated Unix seconds',
    ),
    state: switch (value.state) {
      native.BridgeThreadItemState_Raw(
        :final payloads,
        :final notice,
        :final recordedAt,
      ) =>
        ThreadItemStateView.raw(
          List.unmodifiable([
            for (final payload in payloads)
              RawHistoryPayload(
                payload.format,
                payload.version,
                payload.content,
              ),
          ]),
          notice,
          exactI64(BigInt.from(recordedAt), 'raw item recorded Unix seconds'),
        ),
      native.BridgeThreadItemState_Text(
        :final channel,
        :final text,
        :final attachments,
        :final lifecycle,
      ) =>
        ThreadItemStateView.text(
          channel: switch (channel) {
            native.BridgeThreadTextChannel.user => ThreadTextChannel.user,
            native.BridgeThreadTextChannel.parentAgent =>
              ThreadTextChannel.parentAgent,
            native.BridgeThreadTextChannel.commentary =>
              ThreadTextChannel.commentary,
            native.BridgeThreadTextChannel.final_ =>
              ThreadTextChannel.finalAnswer,
          },
          text: text,
          attachments: List.unmodifiable(attachments.map(attachmentFromBridge)),
          lifecycle: contentLifecycleFromBridge(lifecycle),
        ),
      native.BridgeThreadItemState_Thinking(
        :final summary,
        :final content,
        :final lifecycle,
      ) =>
        ThreadItemStateView.thinking(
          summary: List.unmodifiable(summary),
          content: List.unmodifiable(content),
          lifecycle: contentLifecycleFromBridge(lifecycle),
        ),
      native.BridgeThreadItemState_Tool(
        :final invocation,
        :final state,
        :final userInput,
        :final wait,
      ) =>
        ThreadItemStateView.tool(
          invocation: toolInvocationFromBridge(invocation),
          lifecycle: toolLifecycleFromBridge(state),
          userInput: userInput == null
              ? null
              : contentQuestionsFromBridge(userInput),
          wait: wait == null ? null : contentWaitFromBridge(wait),
        ),
      native.BridgeThreadItemState_Agent(:final identity, :final state) =>
        ThreadItemStateView.agent(
          identity: agentIdentityFromBridge(identity),
          lifecycle: agentLifecycleFromBridge(state),
        ),
      native.BridgeThreadItemState_Turn(:final state, :final inputId) =>
        ThreadItemStateView.turn(
          contentTurnFromBridge(state),
          inputId: inputId,
        ),
      native.BridgeThreadItemState_Inference(
        :final inferenceId,
        :final model,
        :final state,
      ) =>
        ThreadItemStateView.inference(
          inferenceId: inferenceId,
          model: model,
          lifecycle: inferenceLifecycleFromBridge(state),
        ),
      native.BridgeThreadItemState_Skill(
        :final name,
        :final source,
        :final providerId,
        :final resourceBase,
        :final cause,
        :final activatedAt,
      ) =>
        ThreadItemStateView.skill(
          name: name,
          source: source,
          providerId: providerId,
          resourceBase: switch (resourceBase) {
            native.BridgeSkillResourceBase_Directory(:final path) =>
              SkillResourceBaseView(SkillResourceBaseKind.directory, path),
            native.BridgeSkillResourceBase_Url(:final url) =>
              SkillResourceBaseView(SkillResourceBaseKind.url, url),
            native.BridgeSkillResourceBase_Opaque(:final description) =>
              SkillResourceBaseView(SkillResourceBaseKind.opaque, description),
          },
          cause: switch (cause) {
            native.BridgeSkillActivationCause_Tool(:final toolCallId) =>
              SkillActivationCauseView(
                SkillActivationCauseKind.tool,
                toolCallId,
              ),
            native.BridgeSkillActivationCause_UserGesture(
              :final invocationId,
            ) =>
              SkillActivationCauseView(
                SkillActivationCauseKind.userGesture,
                invocationId,
              ),
          },
          activatedAt: exactI64(
            BigInt.from(activatedAt),
            'skill activated Unix seconds',
          ),
        ),
      native.BridgeThreadItemState_File(
        :final path,
        :final mediaType,
        :final completedAt,
      ) =>
        ThreadItemStateView.file(
          path,
          mediaType,
          exactI64(BigInt.from(completedAt), 'file completed Unix seconds'),
        ),
      native.BridgeThreadItemState_ContextCompaction(
        :final beforeTokens,
        :final afterTokens,
        :final compactedAt,
      ) =>
        ThreadItemStateView.contextCompaction(
          nullableU64(beforeTokens, 'context tokens before compact'),
          nullableU64(afterTokens, 'context tokens after compact'),
          exactI64(BigInt.from(compactedAt), 'context compacted Unix seconds'),
        ),
    },
    saved: saved,
    executionTerminal: executionTerminal,
    bodyOmittedUnits: omittedBytes,
  );
}
