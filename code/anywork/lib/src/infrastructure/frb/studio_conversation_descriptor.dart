part of 'studio_api.dart';

ConversationDescriptor _descriptorFromFrb(
  frb_descriptor.BridgeTimelineDescriptor value,
) => value.when(
  text: (value) => ConversationTextDescriptor(
    channel: switch (value.channel) {
      frb_item.BridgeThreadTextChannel.user => ThreadTextChannel.user,
      frb_item.BridgeThreadTextChannel.parentAgent =>
        ThreadTextChannel.parentAgent,
      frb_item.BridgeThreadTextChannel.commentary =>
        ThreadTextChannel.commentary,
      frb_item.BridgeThreadTextChannel.final_ => ThreadTextChannel.finalAnswer,
    },
    attachments: List.unmodifiable(value.attachments.map(_attachmentFromFrb)),
    lifecycle: _contentLifecycleFromFrb(value.lifecycle),
  ),
  thinking: (value) => ConversationThinkingDescriptor(
    lifecycle: _contentLifecycleFromFrb(value.lifecycle),
  ),
  tool: _toolDescriptorFromFrb,
  raw: (value) => ConversationRawDescriptor(
    origin: switch (value.origin) {
      frb_item.BridgeRawItemOrigin.stored => ThreadRawItemOrigin.stored,
      frb_item.BridgeRawItemOrigin.runtimeControl =>
        ThreadRawItemOrigin.runtimeControl,
    },
    payloads: List.unmodifiable(
      value.payloads.map(
        (payload) => ConversationRawPayloadDescriptor(
          format: payload.format,
          version: payload.version,
        ),
      ),
    ),
    notice: value.notice,
    recordedAt: _dateFromUnix(value.recordedAt),
  ),
  agent: (identity, state) => ConversationAgentDescriptor(
    ThreadAgentItemStateView(
      identity: ThreadAgentIdentityView(
        id: identity.id,
        path: identity.path,
        parentPath: identity.parentPath,
        role: identity.role,
        task: identity.task,
        depth: identity.depth,
      ),
      lifecycle: _agentLifecycleFromFrb(state),
    ),
  ),
  turn: (state, inputId) => ConversationTurnDescriptor(
    ThreadTurnItemStateView(_turnStateFromFrb(state), inputId: inputId),
  ),
  inference: (inferenceId, model, state) => ConversationInferenceDescriptor(
    ThreadInferenceItemStateView(
      inferenceId: inferenceId,
      model: model,
      lifecycle: _inferenceLifecycleFromFrb(state),
    ),
  ),
  skill: (name, source, providerId, resourceBase, cause, activatedAt) =>
      ConversationSkillDescriptor(
        ThreadSkillItemStateView(
          name: name,
          source: source,
          providerId: providerId,
          resourceBase: resourceBase.when(
            directory: (path) =>
                SkillResourceBaseView(SkillResourceBaseKind.directory, path),
            url: (url) => SkillResourceBaseView(SkillResourceBaseKind.url, url),
            opaque: (description) => SkillResourceBaseView(
              SkillResourceBaseKind.opaque,
              description,
            ),
          ),
          cause: cause.when(
            tool: (toolCallId) => SkillActivationCauseView(
              SkillActivationCauseKind.tool,
              toolCallId,
            ),
            userGesture: (invocationId) => SkillActivationCauseView(
              SkillActivationCauseKind.userGesture,
              invocationId,
            ),
          ),
          activatedAt: _dateFromUnix(activatedAt),
        ),
      ),
  file: (path, mediaType, completedAt) => ConversationFileDescriptor(
    ThreadFileItemStateView(path, mediaType, _dateFromUnix(completedAt)),
  ),
  contextCompaction: (beforeTokens, afterTokens, compactedAt) =>
      ConversationContextCompactionDescriptor(
        ThreadContextCompactionItemStateView(
          beforeTokens == null
              ? null
              : _exactTimelineInt(beforeTokens, 'before tokens'),
          afterTokens == null
              ? null
              : _exactTimelineInt(afterTokens, 'after tokens'),
          _dateFromUnix(compactedAt),
        ),
      ),
);
