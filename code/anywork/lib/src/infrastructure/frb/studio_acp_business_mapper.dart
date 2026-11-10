import 'package:anywork_client/acp_sessions.dart';

import '../../rust/api/studio/types/acp.dart' as auth;
import '../../rust/api/studio/types/acp_business.dart' as b;
import '../../rust/api/studio/types/acp_business/content.dart' as c;
import '../../rust/api/studio/types/acp_business/notification.dart' as n;

// Only structural translation. No protocol parser, state, replay or Native DTOs.
AcpJsonObject? acpMetaFromFrb(Map<String, b.BridgeAcpJsonValue>? value) =>
    value == null
    ? null
    : AcpJsonObject(value.map((k, v) => MapEntry(k, acpJsonFromFrb(v))));
Map<String, b.BridgeAcpJsonValue>? acpMetaToFrb(AcpJsonObject? value) =>
    value?.values.map((k, v) => MapEntry(k, acpJsonToFrb(v)));

AcpJsonValue acpJsonFromFrb(b.BridgeAcpJsonValue value) => switch (value) {
  b.BridgeAcpJsonValue_Null() => const AcpJsonNull(),
  b.BridgeAcpJsonValue_Bool(:final value) => AcpJsonBool(value),
  b.BridgeAcpJsonValue_String(:final value) => AcpJsonString(value),
  b.BridgeAcpJsonValue_Number(:final value) => switch (value) {
    b.BridgeAcpJsonNumber_Signed(:final value) => AcpJsonInteger(
      BigInt.from(value),
    ),
    b.BridgeAcpJsonNumber_Unsigned(:final value) => AcpJsonInteger(value),
    b.BridgeAcpJsonNumber_Float(:final value) => AcpJsonDecimal(value),
  },
  b.BridgeAcpJsonValue_Array(:final values) => AcpJsonArray(
    values.map(acpJsonFromFrb),
  ),
  b.BridgeAcpJsonValue_Object(:final fields) => acpMetaFromFrb(fields)!,
};

int _signed64(BigInt value) {
  if (value < -(BigInt.one << 63) || value >= (BigInt.one << 63)) {
    throw RangeError('ACP signed integer is outside i64');
  }
  return value.toInt();
}

b.BridgeAcpJsonNumber _numberToFrb(BigInt value) {
  if (value.isNegative) {
    return b.BridgeAcpJsonNumber.signed(value: _signed64(value));
  }
  if (value >= (BigInt.one << 64)) {
    throw RangeError('ACP integer is outside u64');
  }
  return b.BridgeAcpJsonNumber.unsigned(value: value);
}

b.BridgeAcpJsonValue acpJsonToFrb(AcpJsonValue value) => switch (value) {
  AcpJsonNull() => const b.BridgeAcpJsonValue.null_(),
  AcpJsonBool(:final value) => b.BridgeAcpJsonValue.bool(value: value),
  AcpJsonInteger(:final value) => b.BridgeAcpJsonValue.number(
    value: _numberToFrb(value),
  ),
  AcpJsonDecimal(:final value) => b.BridgeAcpJsonValue.number(
    value: b.BridgeAcpJsonNumber.float(value: value),
  ),
  AcpJsonString(:final value) => b.BridgeAcpJsonValue.string(value: value),
  AcpJsonArray(:final values) => b.BridgeAcpJsonValue.array(
    values: values.map(acpJsonToFrb).toList(),
  ),
  AcpJsonObject() => b.BridgeAcpJsonValue.object(fields: acpMetaToFrb(value)!),
};

AcpSessionTargetView acpTargetFromFrb(b.BridgeAcpSessionTarget v) =>
    AcpSessionTargetView(
      sessionId: v.sessionId,
      agentId: v.agentId,
      threadId: v.threadId,
      instance: v.instance,
    );
b.BridgeAcpSessionTarget acpTargetToFrb(AcpSessionTargetView v) =>
    b.BridgeAcpSessionTarget(
      sessionId: v.sessionId,
      agentId: v.agentId,
      threadId: v.threadId,
      instance: v.instance,
    );
AcpRunIdView acpRunFromFrb(b.BridgeAcpRunId v) =>
    AcpRunIdView(instance: v.instance, sequence: v.sequence);
b.BridgeAcpRunId acpRunToFrb(AcpRunIdView v) =>
    b.BridgeAcpRunId(instance: v.instance, sequence: v.sequence);
b.BridgeOpenAcpSessionRequest acpOpenToFrb(OpenAcpSessionRequestView v) =>
    b.BridgeOpenAcpSessionRequest(
      accountId: v.accountId,
      expectedConnectionRevision: v.expectedConnectionRevision,
      workspaceId: v.workspaceId,
      threadId: v.threadId,
      intent: switch (v.intent) {
        AcpNewIntentView() => const b.BridgeAcpOpenIntent.new_(),
        AcpLoadIntentView(:final sessionId) => b.BridgeAcpOpenIntent.load(
          sessionId: b.BridgeAcpRemoteSessionId(value: sessionId.value),
        ),
        AcpResumeIntentView(:final sessionId) => b.BridgeAcpOpenIntent.resume(
          sessionId: b.BridgeAcpRemoteSessionId(value: sessionId.value),
        ),
      },
    );

AcpAnnotationsView _annotationsFromFrb(c.BridgeAcpAnnotations v) =>
    AcpAnnotationsView(
      audience: v.audience?.map(
        (v) => switch (v) {
          c.BridgeAcpRole.assistant => AcpContentRoleView.assistant,
          c.BridgeAcpRole.user => AcpContentRoleView.user,
        },
      ),
      lastModified: v.lastModified,
      priority: v.priority,
      meta: acpMetaFromFrb(v.meta),
    );
c.BridgeAcpAnnotations _annotationsToFrb(AcpAnnotationsView v) =>
    c.BridgeAcpAnnotations(
      audience: v.audience
          ?.map(
            (v) => switch (v) {
              AcpContentRoleView.assistant => c.BridgeAcpRole.assistant,
              AcpContentRoleView.user => c.BridgeAcpRole.user,
            },
          )
          .toList(),
      lastModified: v.lastModified,
      priority: v.priority,
      meta: acpMetaToFrb(v.meta),
    );
AcpContentBlockView acpContentFromFrb(c.BridgeAcpContentBlock v) {
  final annotations = v.annotations == null
      ? null
      : _annotationsFromFrb(v.annotations!);
  final meta = acpMetaFromFrb(v.meta);
  return switch (v) {
    c.BridgeAcpContentBlock_Text() => AcpTextContentView(
      text: v.text,
      annotations: annotations,
      meta: meta,
    ),
    c.BridgeAcpContentBlock_Image() => AcpImageContentView(
      data: v.data,
      mimeType: v.mimeType,
      uri: v.uri,
      annotations: annotations,
      meta: meta,
    ),
    c.BridgeAcpContentBlock_Audio() => AcpAudioContentView(
      data: v.data,
      mimeType: v.mimeType,
      annotations: annotations,
      meta: meta,
    ),
    c.BridgeAcpContentBlock_ResourceLink() => AcpResourceLinkView(
      name: v.name,
      uri: v.uri,
      description: v.description,
      mimeType: v.mimeType,
      size: v.size == null ? null : BigInt.from(v.size!),
      title: v.title,
      annotations: annotations,
      meta: meta,
    ),
    c.BridgeAcpContentBlock_Resource() => AcpEmbeddedResourceView(
      resource: switch (v.resource) {
        c.BridgeAcpEmbeddedResource_Text(
          :final text,
          :final uri,
          :final mimeType,
          :final meta,
        ) =>
          AcpTextResourceContentsView(
            text: text,
            uri: uri,
            mimeType: mimeType,
            meta: acpMetaFromFrb(meta),
          ),
        c.BridgeAcpEmbeddedResource_Blob(
          :final blob,
          :final uri,
          :final mimeType,
          :final meta,
        ) =>
          AcpBlobResourceContentsView(
            blob: blob,
            uri: uri,
            mimeType: mimeType,
            meta: acpMetaFromFrb(meta),
          ),
      },
      annotations: annotations,
      meta: meta,
    ),
  };
}

c.BridgeAcpContentBlock acpContentToFrb(AcpContentBlockView v) {
  final annotations = v.annotations == null
      ? null
      : _annotationsToFrb(v.annotations!);
  final meta = acpMetaToFrb(v.meta);
  return switch (v) {
    AcpTextContentView() => c.BridgeAcpContentBlock.text(
      text: v.text,
      annotations: annotations,
      meta: meta,
    ),
    AcpImageContentView() => c.BridgeAcpContentBlock.image(
      data: v.data,
      mimeType: v.mimeType,
      uri: v.uri,
      annotations: annotations,
      meta: meta,
    ),
    AcpAudioContentView() => c.BridgeAcpContentBlock.audio(
      data: v.data,
      mimeType: v.mimeType,
      annotations: annotations,
      meta: meta,
    ),
    AcpResourceLinkView() => c.BridgeAcpContentBlock.resourceLink(
      name: v.name,
      uri: v.uri,
      description: v.description,
      mimeType: v.mimeType,
      size: v.size == null ? null : _signed64(v.size!),
      title: v.title,
      annotations: annotations,
      meta: meta,
    ),
    AcpEmbeddedResourceView() => c.BridgeAcpContentBlock.resource(
      resource: switch (v.resource) {
        AcpTextResourceContentsView(
          :final text,
          :final uri,
          :final mimeType,
          :final meta,
        ) =>
          c.BridgeAcpEmbeddedResource.text(
            text: text,
            uri: uri,
            mimeType: mimeType,
            meta: acpMetaToFrb(meta),
          ),
        AcpBlobResourceContentsView(
          :final blob,
          :final uri,
          :final mimeType,
          :final meta,
        ) =>
          c.BridgeAcpEmbeddedResource.blob(
            blob: blob,
            uri: uri,
            mimeType: mimeType,
            meta: acpMetaToFrb(meta),
          ),
      },
      annotations: annotations,
      meta: meta,
    ),
  };
}

AcpConfigCategoryView _category(b.BridgeAcpConfigCategory v) => switch (v) {
  b.BridgeAcpConfigCategory_Mode() => const AcpConfigCategoryView.known(
    AcpConfigCategoryKindView.mode,
  ),
  b.BridgeAcpConfigCategory_Model() => const AcpConfigCategoryView.known(
    AcpConfigCategoryKindView.model,
  ),
  b.BridgeAcpConfigCategory_ModelConfig() => const AcpConfigCategoryView.known(
    AcpConfigCategoryKindView.modelConfig,
  ),
  b.BridgeAcpConfigCategory_ThoughtLevel() => const AcpConfigCategoryView.known(
    AcpConfigCategoryKindView.thoughtLevel,
  ),
  b.BridgeAcpConfigCategory_Other(:final value) => AcpConfigCategoryView.other(
    value,
  ),
};
AcpSelectOptionView _selectOption(b.BridgeAcpSelectOption v) =>
    AcpSelectOptionView(
      value: AcpConfigValueId(v.value.value),
      name: v.name,
      description: v.description,
      meta: acpMetaFromFrb(v.meta),
    );
AcpSessionConfigOptionView acpConfigFromFrb(b.BridgeAcpConfigOption v) =>
    AcpSessionConfigOptionView(
      id: AcpConfigId(v.id.value),
      name: v.name,
      description: v.description,
      category: v.category == null ? null : _category(v.category!),
      meta: acpMetaFromFrb(v.meta),
      kind: switch (v.kind) {
        b.BridgeAcpConfigKind_Boolean(:final currentValue) =>
          AcpBooleanConfigView(currentValue: currentValue),
        b.BridgeAcpConfigKind_Select(:final currentValue, :final options) =>
          AcpSelectConfigView(
            currentValue: AcpConfigValueId(currentValue.value),
            options: switch (options) {
              b.BridgeAcpSelectOptions_Ungrouped(:final options) =>
                AcpUngroupedOptionsView(options.map(_selectOption)),
              b.BridgeAcpSelectOptions_Grouped(:final groups) =>
                AcpGroupedOptionsView(
                  groups.map(
                    (v) => AcpSelectGroupView(
                      group: AcpConfigGroupId(v.group),
                      name: v.name,
                      options: v.options.map(_selectOption),
                      meta: acpMetaFromFrb(v.meta),
                    ),
                  ),
                ),
            },
          ),
      },
    );
b.BridgeAcpConfigValue acpConfigValueToFrb(AcpSessionConfigValueView v) =>
    switch (v) {
      AcpBooleanConfigValueView(:final value) => b.BridgeAcpConfigValue.boolean(
        value: value,
      ),
      AcpSelectConfigValueView(:final value) => b.BridgeAcpConfigValue.valueId(
        value: b.BridgeAcpConfigValueId(value: value.value),
      ),
    };
AcpSessionModeStateView _modes(b.BridgeAcpModeState v) =>
    AcpSessionModeStateView(
      currentModeId: AcpModeId(v.currentModeId.value),
      availableModes: v.availableModes.map(
        (v) => AcpSessionModeView(
          id: AcpModeId(v.id.value),
          name: v.name,
          description: v.description,
          meta: acpMetaFromFrb(v.meta),
        ),
      ),
      meta: acpMetaFromFrb(v.meta),
    );
AcpNewSessionResponseView _ready(b.BridgeAcpNewSessionResponse v) =>
    AcpNewSessionResponseView(
      sessionId: AcpRemoteSessionId(v.sessionId.value),
      modes: v.modes == null ? null : _modes(v.modes!),
      configOptions: v.configOptions?.map(acpConfigFromFrb),
      meta: acpMetaFromFrb(v.meta),
    );
AcpListSessionsResponseView acpListFromFrb(b.BridgeAcpListResponse v) =>
    AcpListSessionsResponseView(
      sessions: v.sessions.map(
        (v) => AcpSessionInfoView(
          sessionId: AcpRemoteSessionId(v.sessionId.value),
          cwd: v.cwd,
          additionalDirectories: v.additionalDirectories,
          title: v.title,
          updatedAt: v.updatedAt,
          meta: acpMetaFromFrb(v.meta),
        ),
      ),
      nextCursor: v.nextCursor,
      meta: acpMetaFromFrb(v.meta),
    );

AcpBusinessFailureView acpFailureFromFrb(
  b.BridgeAcpBusinessFailure v,
) => AcpBusinessFailureView(
  kind: switch (v.kind) {
    b.BridgeAcpBusinessFailureKind.busy => AcpBusinessFailureKindView.busy,
    b.BridgeAcpBusinessFailureKind.stale => AcpBusinessFailureKindView.stale,
    b.BridgeAcpBusinessFailureKind.notReady =>
      AcpBusinessFailureKindView.notReady,
    b.BridgeAcpBusinessFailureKind.closed => AcpBusinessFailureKindView.closed,
    b.BridgeAcpBusinessFailureKind.unsupported =>
      AcpBusinessFailureKindView.unsupported,
    b.BridgeAcpBusinessFailureKind.unsupportedVersion =>
      AcpBusinessFailureKindView.unsupportedVersion,
    b.BridgeAcpBusinessFailureKind.serverVersionMismatch =>
      AcpBusinessFailureKindView.serverVersionMismatch,
    b.BridgeAcpBusinessFailureKind.invalidOption =>
      AcpBusinessFailureKindView.invalidOption,
    b.BridgeAcpBusinessFailureKind.rpc => AcpBusinessFailureKindView.rpc,
    b.BridgeAcpBusinessFailureKind.installRequired =>
      AcpBusinessFailureKindView.installRequired,
    b.BridgeAcpBusinessFailureKind.installationInvalid =>
      AcpBusinessFailureKindView.installationInvalid,
    b.BridgeAcpBusinessFailureKind.unsupportedPlatform =>
      AcpBusinessFailureKindView.unsupportedPlatform,
    b.BridgeAcpBusinessFailureKind.missingExecutable =>
      AcpBusinessFailureKindView.missingExecutable,
    b.BridgeAcpBusinessFailureKind.invalidWorkingDirectory =>
      AcpBusinessFailureKindView.invalidWorkingDirectory,
    b.BridgeAcpBusinessFailureKind.invalidDefinition =>
      AcpBusinessFailureKindView.invalidDefinition,
    b.BridgeAcpBusinessFailureKind.io => AcpBusinessFailureKindView.io,
    b.BridgeAcpBusinessFailureKind.cancelled =>
      AcpBusinessFailureKindView.cancelled,
    b.BridgeAcpBusinessFailureKind.preparation =>
      AcpBusinessFailureKindView.preparation,
    b.BridgeAcpBusinessFailureKind.publication =>
      AcpBusinessFailureKindView.publication,
  },
  message: v.message,
  rpcCode: v.rpcCode,
  rpcData: v.rpcData == null ? null : acpJsonFromFrb(v.rpcData!),
  authMethods: v.authMethods.map(_authMethod),
);
AcpBusinessAuthMethodView _authMethod(auth.BridgeAcpAuthMethod v) =>
    AcpBusinessAuthMethodView(
      id: v.id,
      name: v.name,
      description: v.description,
      kind: switch (v.kind) {
        auth.BridgeAcpAuthMethodKind.agent => AcpAuthMethodKindView.agent,
        auth.BridgeAcpAuthMethodKind.terminal => AcpAuthMethodKindView.terminal,
        auth.BridgeAcpAuthMethodKind.unsupported =>
          AcpAuthMethodKindView.unsupported,
      },
    );
AcpObservationGapView _gap(b.BridgeAcpObservationGap v) => switch (v) {
  b.BridgeAcpObservationGap.windowExceeded =>
    AcpObservationGapView.windowExceeded,
  b.BridgeAcpObservationGap.disconnected => AcpObservationGapView.disconnected,
  b.BridgeAcpObservationGap.encoding => AcpObservationGapView.encoding,
};
AcpResultView<AcpPromptResponseView> _promptResult(b.BridgeAcpPromptResult v) =>
    switch (v) {
      b.BridgeAcpPromptResult_Failed(:final failure) => AcpFailureView(
        acpFailureFromFrb(failure),
      ),
      b.BridgeAcpPromptResult_Succeeded(:final response) => AcpSuccessView(
        AcpPromptResponseView(
          stopReason: switch (response.stopReason) {
            b.BridgeAcpStopReason.endTurn => AcpStopReasonView.endTurn,
            b.BridgeAcpStopReason.maxTokens => AcpStopReasonView.maxTokens,
            b.BridgeAcpStopReason.maxTurnRequests =>
              AcpStopReasonView.maxTurnRequests,
            b.BridgeAcpStopReason.refusal => AcpStopReasonView.refusal,
            b.BridgeAcpStopReason.cancelled => AcpStopReasonView.cancelled,
          },
          meta: acpMetaFromFrb(response.meta),
        ),
      ),
    };
AcpCompletedRunView _completed(b.BridgeAcpCompletedRun v) =>
    AcpCompletedRunView(
      run: acpRunFromFrb(v.run),
      completionSequence: v.completionSequence,
      result: _promptResult(v.result),
      summary: v.summary,
      truncated: v.truncated,
    );
AcpBusinessSnapshotView acpSnapshotFromFrb(b.BridgeAcpBusinessSnapshot v) =>
    AcpBusinessSnapshotView(
      target: acpTargetFromFrb(v.target),
      acpSessionId: v.acpSessionId == null
          ? null
          : AcpRemoteSessionId(v.acpSessionId!.value),
      ready: v.ready,
      closing: v.closing,
      configPending: v.configPending,
      configOptions: v.configOptions?.map(acpConfigFromFrb),
      modes: v.modes == null ? null : _modes(v.modes!),
      activeRun: v.activeRun == null ? null : acpRunFromFrb(v.activeRun!),
      lastCompleted: v.lastCompleted == null
          ? null
          : _completed(v.lastCompleted!),
      observationGap: v.observationGap == null ? null : _gap(v.observationGap!),
      authMethods: v.authMethods.map(_authMethod),
    );
AcpBusinessCloseView acpCloseFromFrb(b.BridgeAcpBusinessClose v) =>
    AcpBusinessCloseView(
      localComplete: v.localComplete,
      sdkFinished: v.sdkFinished,
      cleanupTimedOut: v.cleanupTimedOut,
      remoteCloseError: v.remoteCloseError == null
          ? null
          : acpFailureFromFrb(v.remoteCloseError!),
      sdkError: v.sdkError == null ? null : acpFailureFromFrb(v.sdkError!),
      workerError: v.workerError,
      driverError: v.driverError,
      unfinishedPrompt: v.unfinishedPrompt == null
          ? null
          : acpRunFromFrb(v.unfinishedPrompt!),
      unfinishedControls: v.unfinishedControls,
      lastCompleted: v.lastCompleted == null
          ? null
          : _completed(v.lastCompleted!),
      ownerFailures: v.ownerFailures.map(
        (v) =>
            AcpMemberCloseFailureView(threadId: v.threadId, message: v.message),
      ),
    );

AcpSessionFrameView acpFrameFromFrb(b.BridgeAcpSessionFrame v) => switch (v) {
  b.BridgeAcpSessionFrame_Accepted(:final target, :final hasObservation) =>
    AcpAcceptedFrameView(
      target: acpTargetFromFrb(target),
      hasObservation: hasObservation,
    ),
  b.BridgeAcpSessionFrame_Settled(:final result) => AcpSettledFrameView(
    switch (result) {
      b.BridgeAcpSettlement_Succeeded() => const AcpSuccessView<void>(null),
      b.BridgeAcpSettlement_Failed(:final failure) => AcpFailureView<void>(
        acpFailureFromFrb(failure),
      ),
    },
  ),
  b.BridgeAcpSessionFrame_Event(:final event) => AcpEventFrameView(
    switch (event) {
      b.BridgeAcpSessionEvent_Update(:final update) => AcpUpdateEventView(
        AcpSessionNotificationView(
          sessionId: AcpRemoteSessionId(update.sessionId.value),
          update: acpUpdateFromFrb(update.update),
          meta: acpMetaFromFrb(update.meta),
        ),
      ),
      b.BridgeAcpSessionEvent_Ready(:final response) => AcpReadyEventView(
        _ready(response),
      ),
      b.BridgeAcpSessionEvent_Failed(:final failure) => AcpFailedEventView(
        acpFailureFromFrb(failure),
      ),
      b.BridgeAcpSessionEvent_Permission(:final id, :final request) =>
        AcpPermissionEventView(
          id: AcpPermissionIdView(instance: id.instance, sequence: id.sequence),
          request: AcpPermissionRequestView(
            sessionId: AcpRemoteSessionId(request.sessionId.value),
            toolCall: _toolUpdate(request.toolCall),
            options: request.options.map(
              (v) => AcpPermissionOptionView(
                optionId: AcpPermissionOptionId(v.optionId.value),
                name: v.name,
                kind: switch (v.kind) {
                  n.BridgeAcpPermissionKind.allowOnce =>
                    AcpPermissionOptionKindView.allowOnce,
                  n.BridgeAcpPermissionKind.allowAlways =>
                    AcpPermissionOptionKindView.allowAlways,
                  n.BridgeAcpPermissionKind.rejectOnce =>
                    AcpPermissionOptionKindView.rejectOnce,
                  n.BridgeAcpPermissionKind.rejectAlways =>
                    AcpPermissionOptionKindView.rejectAlways,
                },
                meta: acpMetaFromFrb(v.meta),
              ),
            ),
            meta: acpMetaFromFrb(request.meta),
          ),
        ),
      b.BridgeAcpSessionEvent_Configured(:final configOptions, :final meta) =>
        AcpConfiguredEventView(
          AcpConfiguredResponseView(
            configOptions: configOptions.map(acpConfigFromFrb),
            meta: acpMetaFromFrb(meta),
          ),
        ),
      b.BridgeAcpSessionEvent_ModeSet(:final modeId) => AcpModeSetEventView(
        AcpModeId(modeId.value),
      ),
      b.BridgeAcpSessionEvent_Completed(:final completed) =>
        AcpCompletedEventView(_completed(completed)),
      b.BridgeAcpSessionEvent_Gap(:final gap) => AcpGapEventView(_gap(gap)),
    },
  ),
};

AcpToolKindView _toolKind(n.BridgeAcpToolKind v) => switch (v) {
  n.BridgeAcpToolKind.read => AcpToolKindView.read,
  n.BridgeAcpToolKind.edit => AcpToolKindView.edit,
  n.BridgeAcpToolKind.delete => AcpToolKindView.delete,
  n.BridgeAcpToolKind.move => AcpToolKindView.move,
  n.BridgeAcpToolKind.search => AcpToolKindView.search,
  n.BridgeAcpToolKind.execute => AcpToolKindView.execute,
  n.BridgeAcpToolKind.think => AcpToolKindView.think,
  n.BridgeAcpToolKind.fetch => AcpToolKindView.fetch,
  n.BridgeAcpToolKind.switchMode => AcpToolKindView.switchMode,
  n.BridgeAcpToolKind.other => AcpToolKindView.other,
};
AcpToolCallStatusView _toolStatus(n.BridgeAcpToolStatus v) => switch (v) {
  n.BridgeAcpToolStatus.pending => AcpToolCallStatusView.pending,
  n.BridgeAcpToolStatus.inProgress => AcpToolCallStatusView.inProgress,
  n.BridgeAcpToolStatus.completed => AcpToolCallStatusView.completed,
  n.BridgeAcpToolStatus.failed => AcpToolCallStatusView.failed,
};
AcpToolCallContentView _toolContent(n.BridgeAcpToolContent v) => switch (v) {
  n.BridgeAcpToolContent_Content(:final content, :final meta) =>
    AcpToolContentView(
      content: acpContentFromFrb(content),
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpToolContent_Diff(
    :final path,
    :final oldText,
    :final newText,
    :final meta,
  ) =>
    AcpToolDiffView(
      path: path,
      oldText: oldText,
      newText: newText,
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpToolContent_Terminal(:final terminalId, :final meta) =>
    AcpToolTerminalView(
      terminalId: AcpTerminalId(terminalId),
      meta: acpMetaFromFrb(meta),
    ),
};
AcpToolCallLocationView _location(n.BridgeAcpToolLocation v) =>
    AcpToolCallLocationView(
      path: v.path,
      line: v.line,
      meta: acpMetaFromFrb(v.meta),
    );
AcpToolCallView _toolCall(n.BridgeAcpToolCall v) => AcpToolCallView(
  toolCallId: AcpToolCallId(v.toolCallId),
  title: v.title,
  name: v.name,
  kind: _toolKind(v.kind),
  status: _toolStatus(v.status),
  content: v.content.map(_toolContent),
  locations: v.locations.map(_location),
  rawInput: v.rawInput == null ? null : acpJsonFromFrb(v.rawInput!),
  rawOutput: v.rawOutput == null ? null : acpJsonFromFrb(v.rawOutput!),
  meta: acpMetaFromFrb(v.meta),
);
AcpToolCallUpdateView _toolUpdate(n.BridgeAcpToolCallUpdate v) =>
    AcpToolCallUpdateView(
      toolCallId: AcpToolCallId(v.toolCallId),
      fields: AcpToolCallUpdateFieldsView(
        kind: v.kind == null ? null : _toolKind(v.kind!),
        status: v.status == null ? null : _toolStatus(v.status!),
        title: v.title,
        name: v.name,
        content: v.content?.map(_toolContent),
        locations: v.locations?.map(_location),
        rawInput: v.rawInput == null ? null : acpJsonFromFrb(v.rawInput!),
        rawOutput: v.rawOutput == null ? null : acpJsonFromFrb(v.rawOutput!),
      ),
      meta: acpMetaFromFrb(v.meta),
    );
AcpContentChunkView _chunk(n.BridgeAcpContentChunk v) => AcpContentChunkView(
  content: acpContentFromFrb(v.content),
  messageId: v.messageId == null ? null : AcpMessageId(v.messageId!),
  meta: acpMetaFromFrb(v.meta),
);
AcpOptionalField<String> _stringField(n.BridgeAcpStringField v) => switch (v) {
  n.BridgeAcpStringField_Undefined() => const AcpFieldAbsent(),
  n.BridgeAcpStringField_Null() => const AcpFieldNull(),
  n.BridgeAcpStringField_Value(:final value) => AcpFieldValue(value),
};
AcpOptionalField<List<AcpContentBlockView>> _contentField(
  n.BridgeAcpContentField v,
) => switch (v) {
  n.BridgeAcpContentField_Undefined() => const AcpFieldAbsent(),
  n.BridgeAcpContentField_Null() => const AcpFieldNull(),
  n.BridgeAcpContentField_Value(:final value) => AcpFieldValue(
    value.map(acpContentFromFrb).toList(),
  ),
};
AcpOptionalField<AcpJsonObject> _metaField(n.BridgeAcpMetaField v) =>
    switch (v) {
      n.BridgeAcpMetaField_Undefined() => const AcpFieldAbsent(),
      n.BridgeAcpMetaField_Null() => const AcpFieldNull(),
      n.BridgeAcpMetaField_Value(:final value) => AcpFieldValue(
        acpMetaFromFrb(value)!,
      ),
    };
AcpCompactionStatusView _compactionStatus(
  n.BridgeAcpCompactionStatus v,
) => switch (v) {
  n.BridgeAcpCompactionStatus_InProgress() =>
    const AcpCompactionStatusView.known(AcpCompactionStatusKindView.inProgress),
  n.BridgeAcpCompactionStatus_Completed() =>
    const AcpCompactionStatusView.known(AcpCompactionStatusKindView.completed),
  n.BridgeAcpCompactionStatus_Failed() => const AcpCompactionStatusView.known(
    AcpCompactionStatusKindView.failed,
  ),
  n.BridgeAcpCompactionStatus_Cancelled() =>
    const AcpCompactionStatusView.known(AcpCompactionStatusKindView.cancelled),
  n.BridgeAcpCompactionStatus_Other(:final value) =>
    AcpCompactionStatusView.other(value),
};
AcpNoticeSeverityView _severity(n.BridgeAcpNoticeSeverity v) => switch (v) {
  n.BridgeAcpNoticeSeverity_Info() => const AcpNoticeSeverityView.known(
    AcpNoticeSeverityKindView.info,
  ),
  n.BridgeAcpNoticeSeverity_Warning() => const AcpNoticeSeverityView.known(
    AcpNoticeSeverityKindView.warning,
  ),
  n.BridgeAcpNoticeSeverity_Error() => const AcpNoticeSeverityView.known(
    AcpNoticeSeverityKindView.error,
  ),
  n.BridgeAcpNoticeSeverity_Other(:final value) => AcpNoticeSeverityView.other(
    value,
  ),
};
AcpSessionUpdateView acpUpdateFromFrb(
  n.BridgeAcpSessionUpdate v,
) => switch (v) {
  n.BridgeAcpSessionUpdate_UserMessageChunk(:final chunk) =>
    AcpUserMessageChunkView(_chunk(chunk)),
  n.BridgeAcpSessionUpdate_AgentMessageChunk(:final chunk) =>
    AcpAgentMessageChunkView(_chunk(chunk)),
  n.BridgeAcpSessionUpdate_AgentThoughtChunk(:final chunk) =>
    AcpAgentThoughtChunkView(_chunk(chunk)),
  n.BridgeAcpSessionUpdate_ToolCall(:final call) =>
    AcpToolCallSessionUpdateView(_toolCall(call)),
  n.BridgeAcpSessionUpdate_ToolCallUpdate(:final update) =>
    AcpToolCallChangedView(_toolUpdate(update)),
  n.BridgeAcpSessionUpdate_Plan(:final entries, :final meta) => AcpPlanView(
    entries: entries.map(
      (v) => AcpPlanEntryView(
        content: v.content,
        priority: switch (v.priority) {
          n.BridgeAcpPlanPriority.high => AcpPlanPriorityView.high,
          n.BridgeAcpPlanPriority.medium => AcpPlanPriorityView.medium,
          n.BridgeAcpPlanPriority.low => AcpPlanPriorityView.low,
        },
        status: switch (v.status) {
          n.BridgeAcpPlanStatus.pending => AcpPlanStatusView.pending,
          n.BridgeAcpPlanStatus.inProgress => AcpPlanStatusView.inProgress,
          n.BridgeAcpPlanStatus.completed => AcpPlanStatusView.completed,
        },
        meta: acpMetaFromFrb(v.meta),
      ),
    ),
    meta: acpMetaFromFrb(meta),
  ),
  n.BridgeAcpSessionUpdate_AvailableCommands(:final commands, :final meta) =>
    AcpAvailableCommandsUpdateView(
      commands: commands.map(
        (v) => AcpAvailableCommandView(
          name: v.name,
          description: v.description,
          input: switch (v.input) {
            null => null,
            n.BridgeAcpCommandInput(:final hint, :final meta) =>
              AcpUnstructuredCommandInputView(
                hint: hint,
                meta: acpMetaFromFrb(meta),
              ),
          },
          meta: acpMetaFromFrb(v.meta),
        ),
      ),
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpSessionUpdate_CurrentMode(:final modeId, :final meta) =>
    AcpCurrentModeUpdateView(
      currentModeId: AcpModeId(modeId.value),
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpSessionUpdate_ConfigOptions(:final configOptions, :final meta) =>
    AcpConfigOptionsUpdateView(
      configOptions: configOptions.map(acpConfigFromFrb),
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpSessionUpdate_SessionInfo(
    :final title,
    :final updatedAt,
    :final meta,
  ) =>
    AcpSessionInfoUpdateView(
      title: _stringField(title),
      updatedAt: _stringField(updatedAt),
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpSessionUpdate_Usage(
    :final used,
    :final size,
    :final cost,
    :final meta,
  ) =>
    AcpUsageUpdateView(
      used: used,
      size: size,
      cost: cost == null
          ? null
          : AcpCostView(
              amount: cost.amount,
              currency: cost.currency,
              meta: acpMetaFromFrb(cost.meta),
            ),
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpSessionUpdate_Notice(
    :final severity,
    :final title,
    :final description,
    :final meta,
  ) =>
    AcpNoticeView(
      severity: _severity(severity),
      title: title,
      description: description,
      meta: acpMetaFromFrb(meta),
    ),
  n.BridgeAcpSessionUpdate_Compaction(
    :final compactionId,
    :final status,
    :final summary,
    :final error,
    :final meta,
  ) =>
    AcpCompactionUpdateView(
      compactionId: AcpCompactionId(compactionId),
      status: _compactionStatus(status),
      summary: _contentField(summary),
      error: _stringField(error),
      meta: _metaField(meta),
    ),
  n.BridgeAcpSessionUpdate_CompactionSummary(
    :final compactionId,
    :final content,
    :final meta,
  ) =>
    AcpCompactionSummaryChunkView(
      compactionId: AcpCompactionId(compactionId),
      content: acpContentFromFrb(content),
      meta: acpMetaFromFrb(meta),
    ),
};
