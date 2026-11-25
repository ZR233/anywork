part of 'studio_api.dart';

const _conversationClosedFailure = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The timeline read scope is closed',
  retryable: false,
  correlationId: 'client-timeline-closed',
);

int? _exactNullableTimelineInt(BigInt? value, String what) =>
    value == null ? null : exactTimelineInt(value, what);

int _exactSignedTimelineInt(Object value) {
  final integer = switch (value) {
    final BigInt number => number,
    final int number => BigInt.from(number),
    _ => throw const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'Timeline integer has an unsupported representation',
      retryable: false,
      correlationId: 'client-timeline-integer-type',
    ),
  };
  final converted = integer.toInt();
  if (BigInt.from(converted) != integer) {
    throw const StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Timeline integer cannot be represented exactly',
      retryable: false,
      correlationId: 'client-timeline-range',
    );
  }
  return converted;
}

ChatSourceId _chatSourceFromFrb(frb_chat_types.BridgeChatSourceId value) =>
    switch (value) {
      frb_chat_types.BridgeChatSourceId_ForegroundTurn(:final turnId) =>
        ForegroundTurnChatSource(turnId: turnId),
      frb_chat_types.BridgeChatSourceId_Input(:final inputId) =>
        InputChatSource(inputId: inputId),
      frb_chat_types.BridgeChatSourceId_InboxMessage(
        :final sourceId,
        :final messageId,
      ) =>
        InboxMessageChatSource(sourceId: sourceId, messageId: messageId),
      frb_chat_types.BridgeChatSourceId_BackgroundResult(:final messageId) =>
        BackgroundResultChatSource(messageId: messageId),
      frb_chat_types.BridgeChatSourceId_Operation(:final operationId) =>
        OperationChatSource(operationId: operationId),
      frb_chat_types.BridgeChatSourceId_Receipt(:final receiptId) =>
        ReceiptChatSource(receiptId: receiptId),
    };

ChatFactPosition _chatPositionFromFrb(
  frb_chat_types.BridgeChatFactPosition value,
) => ChatFactPosition(
  effectSeq: exactTimelineInt(value.effectSeq, 'effect sequence'),
  suborder: value.suborder,
);

ChatSourceState _chatSourceStateFromFrb(
  frb_chat_types.BridgeChatSourceState value,
) => ChatSourceState(
  source: _chatSourceFromFrb(value.source),
  lifecycle: switch (value.lifecycle) {
    frb_chat_types.BridgeChatSourceLifecycle_Unknown() =>
      const UnknownChatSource(),
    frb_chat_types.BridgeChatSourceLifecycle_Active() =>
      const ActiveChatSource(),
    frb_chat_types.BridgeChatSourceLifecycle_Ended(:final outcome) =>
      EndedChatSource(outcome: ChatTerminalOutcome.values.byName(outcome.name)),
  },
  started: value.started == null ? null : _chatPositionFromFrb(value.started!),
  ended: value.ended == null ? null : _chatPositionFromFrb(value.ended!),
);

ThreadBusinessRefs _businessRefsFromFrb(frb.BridgeThreadBusinessRefs value) =>
    ThreadBusinessRefs(
      plan: value.plan == null
          ? null
          : CurrentPlanHead(
              revision: exactTimelineInt(value.plan!.revision, 'plan revision'),
              phase: PlanRuntimePhase.values.byName(value.plan!.phase.name),
              document: value.plan!.document == null
                  ? null
                  : _currentContentRefFromFrb(value.plan!.document!),
            ),
      interactions: value.interactions == null
          ? null
          : _currentCollectionRefFromFrb(value.interactions!),
    );

ContentWindow _contentWindowFromFrb(frb_chat_types.BridgeContentWindow value) =>
    ContentWindow(
      offset: exactTimelineInt(value.offset, 'content offset'),
      bytes: value.bytes,
      generation: value.generation,
      availableThrough: exactTimelineInt(
        value.availableThrough,
        'available bytes',
      ),
      sealed: value.sealed,
    );

frb_chat_types.BridgeReadDemand _readDemandToFrb(ReadDemand value) =>
    frb_chat_types.BridgeReadDemand(
      maxItems: value.maxItems,
      maxBytes: value.maxBytes,
    );

ProductTopicEventPayload _productPayloadFromFrb(
  frb.BridgeProductEventPayload payload,
) {
  return switch (payload) {
    frb.BridgeProductEventPayload_ProjectDirectoryChanged(:final field0) =>
      ProjectDirectoryChangedPayload(_projectDirectoryFromFrb(field0)),
    frb.BridgeProductEventPayload_AgentDirectoryChanged(:final field0) =>
      AgentDirectoryChangedPayload(_agentDirectoryFromFrb(field0)),
    frb.BridgeProductEventPayload_SettingsConfigStateChanged(:final field0) =>
      SettingsConfigStateChangedPayload(_settingsConfigStateFromFrb(field0)),
    frb.BridgeProductEventPayload_ModelCatalogStateChanged(:final field0) =>
      ModelCatalogStateChangedPayload(_modelCatalogStateFromFrb(field0)),
    frb.BridgeProductEventPayload_RecoveryStateChanged(:final field0) =>
      RecoveryStateChangedPayload(_recoveryStateFromFrb(field0)),
    frb.BridgeProductEventPayload_McpCatalogChanged(:final field0) =>
      McpCatalogChangedPayload(_mcpCatalogFromFrb(field0)),
    frb.BridgeProductEventPayload_ThreadMcpStateChanged(:final field0) =>
      ThreadMcpStateChangedPayload(_threadMcpStateFromFrb(field0)),
    frb.BridgeProductEventPayload_ThreadLspStateChanged(:final field0) =>
      ThreadLspStateChangedPayload(_threadLspStateFromFrb(field0)),
    frb.BridgeProductEventPayload_LspStateChanged(:final field0) =>
      LspStateChangedPayload(_lspStateFromFrb(field0)),
    frb.BridgeProductEventPayload_SkillsStateChanged(:final field0) =>
      SkillsStateChangedPayload(_skillsStateFromFrb(field0)),
    frb.BridgeProductEventPayload_ThreadModeCatalogChanged(:final field0) =>
      ThreadModeCatalogChangedPayload(_threadModeCatalogFromFrb(field0)),
    frb.BridgeProductEventPayload_SessionCostsChanged(:final field0) =>
      SessionCostsChangedPayload(_sessionCostsStateFromFrb(field0)),
    frb.BridgeProductEventPayload_ChildInteractionsChanged(:final field0) =>
      ChildInteractionsChangedPayload(_childInteractionsStateFromFrb(field0)),
    frb.BridgeProductEventPayload_UpdaterStateChanged(:final field0) =>
      UpdaterStateChangedPayload(updaterStateFromFrb(field0)),
    frb.BridgeProductEventPayload_PersistenceStateChanged(:final field0) =>
      PersistenceStateChangedPayload(_persistenceStateFromFrb(field0)),
    frb.BridgeProductEventPayload_PersistenceQueueStateChanged(:final field0) =>
      PersistenceQueueStateChangedPayload(
        _persistenceQueueStateFromFrb(field0),
      ),
    frb.BridgeProductEventPayload_AgentProfilesStateChanged(:final field0) =>
      AgentProfilesStateChangedPayload(_agentProfilesStateFromFrb(field0)),
    frb.BridgeProductEventPayload_BotsStateChanged(:final field0) =>
      BotsStateChangedPayload(_botsStateFromFrb(field0)),
  };
}

/// 把 FRB topic 帧信封转换成领域帧；`Closed` 由调用方结束流，返回 null。
///
/// [subscribedTopic] 只用于 `Failure` 帧（信封不携带 topic）；Baseline/Data/Lagged
/// 的 topic 以 owner 声明为准。
ProductTopicFrame? productTopicFrameFromEnvelope(
  ProductTopic subscribedTopic,
  frb_topic_types.BridgeProductTopicStreamEnvelope envelope,
) {
  return switch (envelope) {
    frb_topic_types.BridgeProductTopicStreamEnvelope_Baseline(
      :final topic,
      :final revision,
      :final state,
    ) =>
      ProductTopicBaselineFrame(
        topic: _productTopicFromBridge(topic),
        revision: revision.toInt(),
        state: _productBaselineFromFrb(state),
      ),
    frb_topic_types.BridgeProductTopicStreamEnvelope_Data(:final event) =>
      ProductTopicDataFrame(
        topic: _productPayloadTopicFromBridge(event.payload),
        event: ProductTopicEventEnvelope(
          eventId: event.eventId,
          sequence: event.sequence,
          createdAt: dateFromUnix(event.createdAt),
          payload: _productPayloadFromFrb(event.payload),
        ),
      ),
    frb_topic_types.BridgeProductTopicStreamEnvelope_Lagged(
      :final topic,
      :final dropped,
    ) =>
      ProductTopicLaggedFrame(
        topic: _productTopicFromBridge(topic),
        dropped: dropped.toInt(),
      ),
    frb_topic_types.BridgeProductTopicStreamEnvelope_Failure(:final error) =>
      ProductTopicFailureFrame(
        topic: subscribedTopic,
        error: _studioFailure(error),
      ),
    frb_topic_types.BridgeProductTopicStreamEnvelope_Closed() => null,
  };
}

ProductTopic _productTopicFromBridge(frb_topic_types.BridgeProductTopic topic) {
  return switch (topic) {
    frb_topic_types.BridgeProductTopic_ProjectDirectory() =>
      const ProjectDirectoryTopic(),
    frb_topic_types.BridgeProductTopic_AgentDirectory() =>
      const AgentDirectoryTopic(),
    frb_topic_types.BridgeProductTopic_SettingsConfig() =>
      const SettingsConfigTopic(),
    frb_topic_types.BridgeProductTopic_ModelCatalog() =>
      const ModelCatalogTopic(),
    frb_topic_types.BridgeProductTopic_Recovery() => const RecoveryTopic(),
    frb_topic_types.BridgeProductTopic_McpCatalog(:final scope) =>
      McpCatalogTopic(scope: _mcpScopeFromFrb(scope)),
    frb_topic_types.BridgeProductTopic_ThreadMcp(:final threadId) =>
      ThreadMcpTopic(threadId: threadId),
    frb_topic_types.BridgeProductTopic_ThreadLsp(:final threadId) =>
      ThreadLspTopic(threadId: threadId),
    frb_topic_types.BridgeProductTopic_Lsp() => const LspTopic(),
    frb_topic_types.BridgeProductTopic_Skills(:final workspaceId) =>
      SkillsTopic(workspaceId: workspaceId),
    frb_topic_types.BridgeProductTopic_ThreadModeCatalog() =>
      const ThreadModeCatalogTopic(),
    frb_topic_types.BridgeProductTopic_SessionCosts(:final rootThreadId) =>
      SessionCostsTopic(rootThreadId: rootThreadId),
    frb_topic_types.BridgeProductTopic_ChildInteractions(:final hostThreadId) =>
      ChildInteractionsTopic(hostThreadId: hostThreadId),
    frb_topic_types.BridgeProductTopic_Updater() => const UpdaterTopic(),
    frb_topic_types.BridgeProductTopic_Persistence() =>
      const PersistenceTopic(),
    frb_topic_types.BridgeProductTopic_PersistenceQueue() =>
      const PersistenceQueueTopic(),
    frb_topic_types.BridgeProductTopic_AgentProfiles() =>
      const AgentProfilesTopic(),
    frb_topic_types.BridgeProductTopic_Bots() => const BotsTopic(),
  };
}

ProductTopic _productPayloadTopicFromBridge(
  frb.BridgeProductEventPayload payload,
) {
  return switch (payload) {
    frb.BridgeProductEventPayload_ProjectDirectoryChanged() =>
      const ProjectDirectoryTopic(),
    frb.BridgeProductEventPayload_AgentDirectoryChanged() =>
      const AgentDirectoryTopic(),
    frb.BridgeProductEventPayload_SettingsConfigStateChanged() =>
      const SettingsConfigTopic(),
    frb.BridgeProductEventPayload_ModelCatalogStateChanged() =>
      const ModelCatalogTopic(),
    frb.BridgeProductEventPayload_RecoveryStateChanged() =>
      const RecoveryTopic(),
    frb.BridgeProductEventPayload_McpCatalogChanged(:final field0) =>
      McpCatalogTopic(scope: _mcpScopeFromFrb(field0.scope)),
    frb.BridgeProductEventPayload_ThreadMcpStateChanged(:final field0) =>
      ThreadMcpTopic(threadId: field0.threadId),
    frb.BridgeProductEventPayload_ThreadLspStateChanged(:final field0) =>
      ThreadLspTopic(threadId: field0.threadId),
    frb.BridgeProductEventPayload_LspStateChanged() => const LspTopic(),
    frb.BridgeProductEventPayload_SkillsStateChanged(:final field0) =>
      SkillsTopic(workspaceId: field0.workspaceId),
    frb.BridgeProductEventPayload_ThreadModeCatalogChanged() =>
      const ThreadModeCatalogTopic(),
    frb.BridgeProductEventPayload_SessionCostsChanged(:final field0) =>
      SessionCostsTopic(rootThreadId: field0.rootThreadId),
    frb.BridgeProductEventPayload_ChildInteractionsChanged(:final field0) =>
      ChildInteractionsTopic(hostThreadId: field0.hostThreadId),
    frb.BridgeProductEventPayload_UpdaterStateChanged() => const UpdaterTopic(),
    frb.BridgeProductEventPayload_PersistenceStateChanged() =>
      const PersistenceTopic(),
    frb.BridgeProductEventPayload_PersistenceQueueStateChanged() =>
      const PersistenceQueueTopic(),
    frb.BridgeProductEventPayload_AgentProfilesStateChanged() =>
      const AgentProfilesTopic(),
    frb.BridgeProductEventPayload_BotsStateChanged() => const BotsTopic(),
  };
}

frb_topic_types.BridgeProductTopic bridgeProductTopic(ProductTopic topic) {
  return switch (topic) {
    ProjectDirectoryTopic() =>
      const frb_topic_types.BridgeProductTopic.projectDirectory(),
    ThreadDirectoryTopic() => throw UnsupportedError(
      'ThreadDirectoryTopic uses the dedicated directory observation feed',
    ),
    AgentDirectoryTopic() =>
      const frb_topic_types.BridgeProductTopic.agentDirectory(),
    SettingsConfigTopic() =>
      const frb_topic_types.BridgeProductTopic.settingsConfig(),
    ModelCatalogTopic() =>
      const frb_topic_types.BridgeProductTopic.modelCatalog(),
    RecoveryTopic() => const frb_topic_types.BridgeProductTopic.recovery(),
    McpCatalogTopic(:final scope) =>
      frb_topic_types.BridgeProductTopic.mcpCatalog(
        scope: _mcpScopeToFrb(scope),
      ),
    ThreadMcpTopic(:final threadId) =>
      frb_topic_types.BridgeProductTopic.threadMcp(threadId: threadId),
    ThreadLspTopic(:final threadId) =>
      frb_topic_types.BridgeProductTopic.threadLsp(threadId: threadId),
    LspTopic() => const frb_topic_types.BridgeProductTopic.lsp(),
    SkillsTopic(:final workspaceId) =>
      frb_topic_types.BridgeProductTopic.skills(workspaceId: workspaceId),
    ThreadModeCatalogTopic() =>
      const frb_topic_types.BridgeProductTopic.threadModeCatalog(),
    SessionCostsTopic(:final rootThreadId) =>
      frb_topic_types.BridgeProductTopic.sessionCosts(
        rootThreadId: rootThreadId,
      ),
    ChildInteractionsTopic(:final hostThreadId) =>
      frb_topic_types.BridgeProductTopic.childInteractions(
        hostThreadId: hostThreadId,
      ),
    UpdaterTopic() => const frb_topic_types.BridgeProductTopic.updater(),
    PersistenceTopic() =>
      const frb_topic_types.BridgeProductTopic.persistence(),
    PersistenceQueueTopic() =>
      const frb_topic_types.BridgeProductTopic.persistenceQueue(),
    AgentProfilesTopic() =>
      const frb_topic_types.BridgeProductTopic.agentProfiles(),
    BotsTopic() => const frb_topic_types.BridgeProductTopic.bots(),
  };
}

ProductTopicBaselineState _productBaselineFromFrb(
  frb_topic_types.BridgeProductBaseline baseline,
) {
  return switch (baseline) {
    frb_topic_types.BridgeProductBaseline_ProjectDirectory(:final field0) =>
      ProjectDirectoryBaseline(_projectDirectoryFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_AgentDirectory(:final field0) =>
      AgentDirectoryBaseline(_agentDirectoryFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_SettingsConfig(:final field0) =>
      SettingsConfigBaseline(_settingsConfigStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_ModelCatalog(:final field0) =>
      ModelCatalogBaseline(_modelCatalogStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_Recovery(:final field0) =>
      RecoveryBaseline(_recoveryStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_McpCatalog(:final field0) =>
      McpCatalogBaseline(_mcpCatalogFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_ThreadMcp(:final field0) =>
      ThreadMcpBaseline(_threadMcpStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_ThreadLsp(:final field0) =>
      ThreadLspBaseline(_threadLspStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_Lsp(:final field0) => LspBaseline(
      _lspStateFromFrb(field0),
    ),
    frb_topic_types.BridgeProductBaseline_Skills(:final field0) =>
      SkillsBaseline(_skillsStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_ThreadModeCatalog(:final field0) =>
      ThreadModeCatalogBaseline(_threadModeCatalogFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_SessionCosts(:final field0) =>
      SessionCostsBaseline(_sessionCostsStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_ChildInteractions(:final field0) =>
      ChildInteractionsBaseline(_childInteractionsStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_Updater(:final field0) =>
      UpdaterBaseline(updaterStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_Persistence(:final field0) =>
      PersistenceBaseline(_persistenceStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_PersistenceQueue(:final field0) =>
      PersistenceQueueBaseline(_persistenceQueueStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_AgentProfiles(:final field0) =>
      AgentProfilesBaseline(_agentProfilesStateFromFrb(field0)),
    frb_topic_types.BridgeProductBaseline_Bots(:final field0) => BotsBaseline(
      _botsStateFromFrb(field0),
    ),
  };
}

StudioAgentView _agentDirectoryEntryFromFrb(
  frb.BridgeAgentDirectoryEntryDto agent,
) {
  return StudioAgentView(
    agentId: agent.agentId,
    sessionId: agent.sessionId,
    parentAgentId: agent.parentAgentId,
    threadId: agent.threadId,
    role: agent.role,
    delegationMode: _delegationModeFromFrb(agent.delegationMode),
    delegationPreference: _delegationPreferenceFromFrb(
      agent.delegationPreference,
    ),
    frozenModel: agent.frozenModel == null
        ? null
        : _savedRouteFromFrb(agent.frozenModel!),
    task: agent.task,
    summary: agent.summary,
    activity: switch (agent.activity) {
      frb.BridgeAgentActivity_Native(
        :final state,
        :final execution,
        :final canStop,
        :final awaitingScheduling,
      ) =>
        NativeStudioAgentActivity(
          state: _agentStateFromFrb(state),
          execution: execution == null
              ? null
              : _agentExecutionFromFrb(execution),
          canStop: canStop,
          awaitingScheduling: awaitingScheduling,
        ),
      frb.BridgeAgentActivity_Acp(:final explicitlyClosed) =>
        AcpStudioAgentActivity(explicitlyClosed: explicitlyClosed),
    },
    updatedAt: dateFromUnix(agent.updatedAt),
  );
}

/// 目录行的 typed 身份转换：root/child 与成员归属只读这里的四元组字段。
SessionDirectoryRow _sessionDirectoryRowFromFrb(
  frb.BridgeSessionDirectoryRow value,
) {
  return SessionDirectoryRow(
    sessionId: value.sessionId,
    agentId: value.agentId,
    parentAgentId: value.parentAgentId,
    threadId: value.threadId,
    workspaceId: value.workspaceId,
    title: value.title,
    mode: value.mode == null ? null : ThreadModeId.fromId(value.mode!),
    delegationMode: _delegationModeFromFrb(value.delegationMode),
    delegationPreference: _delegationPreferenceFromFrb(
      value.delegationPreference,
    ),
    workspaceMode: ThreadWorkspaceMode.fromId(value.workspaceMode),
    workspacePath: value.workspacePath,
    role: value.role,
    backend: _agentBackendFromFrb(value.backend),
    createdAt: dateFromUnix(value.createdAt),
    updatedAt: dateFromUnix(value.updatedAt),
    lastUserMessageAt: value.lastUserMessageAt == null
        ? null
        : dateFromUnix(value.lastUserMessageAt!),
    archived: value.archived,
  );
}

AgentBackendView _agentBackendFromFrb(frb.BridgeAgentBackend value) =>
    switch (value) {
      frb.BridgeAgentBackend_Native(:final config, :final status) =>
        NativeAgentBackendView(
          config: NativeAgentConfigView(
            route: config.route == null
                ? null
                : _savedRouteFromFrb(config.route!),
            systemInstructions: config.systemInstructions,
          ),
          status: _threadStatusFromFrb(status),
        ),
      frb.BridgeAgentBackend_Acp(:final reference) => AcpAgentBackendView(
        reference: AcpSessionReferenceView(
          accountId: reference.accountId,
          acpSessionId: reference.acpSessionId,
          cwd: reference.cwd,
        ),
      ),
    };

AgentBindingView agentBindingFromFrb(frb.BridgeAgentBinding value) {
  return switch (value) {
    frb.BridgeAgentBinding_Native(:final route, :final systemInstructions) =>
      NativeAgentBindingView(
        route: route == null ? null : _savedRouteFromFrb(route),
        systemInstructions: systemInstructions,
      ),
    frb.BridgeAgentBinding_Acp(:final accountId) => AcpAgentBindingView(
      accountId: accountId,
    ),
  };
}

frb.BridgeAgentBinding agentBindingToFrb(AgentBindingView value) =>
    switch (value) {
      NativeAgentBindingView(:final route, :final systemInstructions) =>
        frb.BridgeAgentBinding.native(
          route: route == null
              ? null
              : frb.BridgeNewThreadModelRoute(
                  accountId: route.accountId,
                  modelId: route.modelId,
                  effort: route.effort,
                ),
          systemInstructions: systemInstructions,
        ),
      AcpAgentBindingView(:final accountId) => frb.BridgeAgentBinding.acp(
        accountId: accountId,
      ),
    };

ThreadStatusView _threadStatusFromFrb(frb.BridgeThreadStatus value) {
  return switch (value) {
    frb.BridgeThreadStatus.idle => ThreadStatusView.idle,
    frb.BridgeThreadStatus.queued => ThreadStatusView.queued,
    frb.BridgeThreadStatus.running => ThreadStatusView.running,
    frb.BridgeThreadStatus.waitingTool => ThreadStatusView.waitingTool,
    frb.BridgeThreadStatus.waitingInteraction =>
      ThreadStatusView.waitingInteraction,
    frb.BridgeThreadStatus.cancelling => ThreadStatusView.cancelling,
    frb.BridgeThreadStatus.closing => ThreadStatusView.closing,
    frb.BridgeThreadStatus.closed => ThreadStatusView.closed,
    frb.BridgeThreadStatus.faulted => ThreadStatusView.faulted,
  };
}

/// 目录行与主会话运行时的执行身份；阶段是规范枚举，不按轮次投影推导。
AgentExecutionView _agentExecutionFromFrb(frb.BridgeAgentExecution execution) =>
    AgentExecutionView(
      id: execution.id,
      phase: switch (execution.phase) {
        frb.BridgeAgentExecutionPhase.preparing =>
          AgentExecutionPhase.preparing,
        frb.BridgeAgentExecutionPhase.awaitingStorage =>
          AgentExecutionPhase.awaitingStorage,
        frb.BridgeAgentExecutionPhase.awaitingAdmission =>
          AgentExecutionPhase.awaitingAdmission,
        frb.BridgeAgentExecutionPhase.running => AgentExecutionPhase.running,
        frb.BridgeAgentExecutionPhase.stopping => AgentExecutionPhase.stopping,
      },
      turnId: execution.turnId,
    );

StudioAgentState _agentStateFromFrb(frb.BridgeAgentState state) {
  return switch (state) {
    frb.BridgeAgentState_Idle() => const IdleStudioAgent(),
    frb.BridgeAgentState_Running(:final field0) => RunningStudioAgent(
      field0.turnId,
    ),
    frb.BridgeAgentState_WaitingInteraction(:final field0) =>
      WaitingInteractionStudioAgent(field0.turnId, field0.interactionId),
    frb.BridgeAgentState_Closing() => const ClosingStudioAgent(),
    frb.BridgeAgentState_Closed() => const ClosedStudioAgent(),
  };
}

StudioProject _projectFromFrb(frb.ProjectDto project) {
  return StudioProject(
    id: project.id,
    name: project.name,
    path: project.path,
    kind: switch (project.kind) {
      frb.BridgeWorkspaceKind.project => WorkspaceKind.project,
      frb.BridgeWorkspaceKind.standalone => WorkspaceKind.standalone,
    },
    sshAlias: project.sshAlias,
  );
}

SshServer _sshServerFromFrb(frb_ssh_types.SshServerDto server) {
  return SshServer(
    alias: server.alias,
    hostName: server.hostName,
    port: server.port,
    username: server.username,
    identityFile: server.identityFile,
    managed: server.managed,
    hasPassword: server.hasPassword,
  );
}

McpScope _mcpScopeFromFrb(frb.BridgeMcpScope scope) => switch (scope) {
  frb.BridgeMcpScope_Host() => const HostMcpScope(),
  frb.BridgeMcpScope_Ssh(:final sshAlias) => SshMcpScope(sshAlias: sshAlias),
};

frb.BridgeMcpScope _mcpScopeToFrb(McpScope scope) => switch (scope) {
  HostMcpScope() => const frb.BridgeMcpScope.host(),
  SshMcpScope(:final sshAlias) => frb.BridgeMcpScope.ssh(sshAlias: sshAlias),
};

McpDocumentRef _mcpDocumentRefFromFrb(frb.BridgeMcpDocumentRef document) =>
    McpDocumentRef(
      scope: _mcpScopeFromFrb(document.scope),
      relativePath: document.relativePath,
    );

frb.BridgeMcpDocumentRef _mcpDocumentRefToFrb(McpDocumentRef document) =>
    frb.BridgeMcpDocumentRef(
      scope: _mcpScopeToFrb(document.scope),
      relativePath: document.relativePath,
    );

McpConfigStatusKind _mcpConfigStatusFromFrb(
  frb.BridgeMcpConfigStatusKind status,
) => switch (status) {
  frb.BridgeMcpConfigStatusKind.enabled => McpConfigStatusKind.enabled,
  frb.BridgeMcpConfigStatusKind.disabled => McpConfigStatusKind.disabled,
  frb.BridgeMcpConfigStatusKind.shadowedDisable =>
    McpConfigStatusKind.shadowedDisable,
  frb.BridgeMcpConfigStatusKind.missingPrereq =>
    McpConfigStatusKind.missingPrereq,
  frb.BridgeMcpConfigStatusKind.invalidDocument =>
    McpConfigStatusKind.invalidDocument,
};

McpEffectiveSource _mcpEffectiveSourceFromFrb(
  frb.BridgeMcpEffectiveSource source,
) => switch (source) {
  frb.BridgeMcpEffectiveSource.hostServer => McpEffectiveSource.hostServer,
  frb.BridgeMcpEffectiveSource.hostBuiltin => McpEffectiveSource.hostBuiltin,
  frb.BridgeMcpEffectiveSource.inheritedHostServer =>
    McpEffectiveSource.inheritedHostServer,
  frb.BridgeMcpEffectiveSource.inheritedHostBuiltin =>
    McpEffectiveSource.inheritedHostBuiltin,
  frb.BridgeMcpEffectiveSource.sshOverrideServer =>
    McpEffectiveSource.sshOverrideServer,
  frb.BridgeMcpEffectiveSource.sshOverrideBuiltin =>
    McpEffectiveSource.sshOverrideBuiltin,
  frb.BridgeMcpEffectiveSource.sshDisabledTombstone =>
    McpEffectiveSource.sshDisabledTombstone,
  frb.BridgeMcpEffectiveSource.invalidFile => McpEffectiveSource.invalidFile,
};

McpExecutionLocation _mcpExecutionLocationFromFrb(
  frb.BridgeMcpExecutionLocation location,
) => switch (location) {
  frb.BridgeMcpExecutionLocation_HostLocal() =>
    const HostLocalMcpExecutionLocation(),
  frb.BridgeMcpExecutionLocation_HostRemoteStreamableHttp() =>
    const HostRemoteStreamableHttpMcpExecutionLocation(),
  frb.BridgeMcpExecutionLocation_SshRemote(:final sshAlias) =>
    SshRemoteMcpExecutionLocation(sshAlias: sshAlias),
  frb.BridgeMcpExecutionLocation_SshRemoteStreamableHttp(:final sshAlias) =>
    SshRemoteStreamableHttpMcpExecutionLocation(sshAlias: sshAlias),
};

McpCatalogEntry _mcpCatalogEntryFromFrb(frb.BridgeMcpCatalogEntry entry) =>
    McpCatalogEntry(
      id: entry.id,
      document: entry.document == null
          ? null
          : _mcpDocumentRefFromFrb(entry.document!),
      configStatus: _mcpConfigStatusFromFrb(entry.configStatus),
      effectiveSource: _mcpEffectiveSourceFromFrb(entry.effectiveSource),
      executionLocation: entry.executionLocation == null
          ? null
          : _mcpExecutionLocationFromFrb(entry.executionLocation!),
      transport: entry.transport,
      endpointSummary: entry.endpointSummary,
      builtIn: entry.builtIn,
      inheritedFromHost: entry.inheritedFromHost,
      overriddenInScope: entry.overriddenInScope,
      canOverrideInSsh: entry.canOverrideInSsh,
      canDisableInSsh: entry.canDisableInSsh,
      canRestoreInheritance: entry.canRestoreInheritance,
      message: entry.message,
    );

McpDocumentDiagnostic _mcpDocumentDiagnosticFromFrb(
  frb.BridgeMcpDocumentDiagnostic diagnostic,
) => McpDocumentDiagnostic(
  document: _mcpDocumentRefFromFrb(diagnostic.document),
  id: diagnostic.id,
  code: diagnostic.code,
  message: diagnostic.message,
);

McpCatalogSnapshot _mcpCatalogFromFrb(frb.BridgeMcpCatalogSnapshot snapshot) =>
    McpCatalogSnapshot(
      scope: _mcpScopeFromFrb(snapshot.scope),
      revision: snapshot.revision.toInt(),
      entries: snapshot.entries.map(_mcpCatalogEntryFromFrb).toList(),
      diagnostics: snapshot.diagnostics
          .map(_mcpDocumentDiagnosticFromFrb)
          .toList(),
    );

McpDocumentContent _mcpDocumentContentFromFrb(
  frb.BridgeMcpDocumentContent content,
) => McpDocumentContent(
  document: _mcpDocumentRefFromFrb(content.document),
  id: content.id,
  revision: content.revision.toInt(),
  rawToml: content.rawToml,
  diagnostic: content.diagnostic == null
      ? null
      : _mcpDocumentDiagnosticFromFrb(content.diagnostic!),
);

McpDocumentCommitReceipt _mcpDocumentCommitReceiptFromFrb(
  frb.BridgeMcpDocumentCommitReceipt receipt,
) => McpDocumentCommitReceipt(
  document: receipt.document == null
      ? null
      : _mcpDocumentRefFromFrb(receipt.document!),
  revision: receipt.revision.toInt(),
  snapshot: _mcpCatalogFromFrb(receipt.snapshot),
);

ThreadMcpLifecycleKind _threadMcpLifecycleFromFrb(
  frb.BridgeThreadMcpLifecycleKind lifecycle,
) => switch (lifecycle) {
  frb.BridgeThreadMcpLifecycleKind.connecting =>
    ThreadMcpLifecycleKind.connecting,
  frb.BridgeThreadMcpLifecycleKind.available =>
    ThreadMcpLifecycleKind.available,
  frb.BridgeThreadMcpLifecycleKind.unavailable =>
    ThreadMcpLifecycleKind.unavailable,
  frb.BridgeThreadMcpLifecycleKind.unsupported =>
    ThreadMcpLifecycleKind.unsupported,
  frb.BridgeThreadMcpLifecycleKind.shuttingDown =>
    ThreadMcpLifecycleKind.shuttingDown,
};

ThreadMcpServerState _threadMcpServerFromFrb(
  frb.BridgeThreadMcpServerState server,
) => ThreadMcpServerState(
  id: server.id,
  effectiveSource: _mcpEffectiveSourceFromFrb(server.effectiveSource),
  executionLocation: _mcpExecutionLocationFromFrb(server.executionLocation),
  transport: server.transport,
  endpointSummary: server.endpointSummary,
  builtIn: server.builtIn,
  lifecycle: _threadMcpLifecycleFromFrb(server.lifecycle),
  toolCount: server.toolCount?.toInt(),
  message: server.message,
  lastCheckedAt: server.lastCheckedAt,
);

ThreadMcpStateSnapshot _threadMcpStateFromFrb(
  frb.BridgeThreadMcpStateSnapshot snapshot,
) => ThreadMcpStateSnapshot(
  threadId: snapshot.threadId,
  scope: _mcpScopeFromFrb(snapshot.scope),
  generation: snapshot.generation.toInt(),
  servers: snapshot.servers.map(_threadMcpServerFromFrb).toList(),
);

StudioBootstrap studioBootstrapFromFrbSnapshot(
  frb.BridgeStudioStateSnapshot value,
) {
  final projectDirectory = _projectDirectoryFromFrb(value.projectDirectory);
  final threadPage = _threadDirectoryPageFromFrb(value.threadDirectory);
  final configSnapshot = _settingsConfigStateFromFrb(value.settingsConfig);
  final catalogSnapshot = _modelCatalogStateFromFrb(value.modelCatalog);
  var settingsProjection = const SettingsProjectionState();
  if (configSnapshot.state.value != null) {
    settingsProjection = mergeSettingsProjection(
      settingsProjection,
      configSnapshot,
      scope: SettingsMergeScope.configOnly,
    );
    settingsProjection = mergeSettingsProjection(
      settingsProjection,
      catalogSnapshot,
      scope: SettingsMergeScope.catalogOnly,
    );
  }
  return StudioBootstrap(
    ownerEpoch: value.ownerEpoch,
    projectDirectory: projectDirectory,
    threadDirectory: threadPage,
    agentDirectory: _agentDirectoryFromFrb(value.agentDirectory),
    settingsState: settingsProjection.canonical ?? configSnapshot,
    recoveryState: _recoveryStateFromFrb(value.recovery),
    mcpCatalog: _mcpCatalogFromFrb(value.hostMcpCatalog),
    lspState: _lspStateFromFrb(value.lsp),
    skillsByProject: {
      for (final snapshot in value.skillsByProject)
        snapshot.workspaceId: _skillsStateFromFrb(snapshot),
    },
    threadModeCatalog: _threadModeCatalogFromFrb(value.threadModeCatalog),
    updaterState: updaterStateFromFrb(value.updater),
    persistenceState: _persistenceStateFromFrb(value.persistence),
    persistenceQueueState: _persistenceQueueStateFromFrb(
      value.persistenceQueue,
    ),
    agentProfilesState: _agentProfilesStateFromFrb(value.agentProfiles),
    sessionCostsByRoot: {
      for (final session in value.sessionCosts)
        session.rootThreadId: _sessionCostsStateFromFrb(session),
    },
    selectedProjectId: null,
    selectedThreadId: null,
  );
}

PersistenceStateSnapshot _persistenceStateFromFrb(
  frb.BridgePersistenceStateSnapshot snapshot,
) {
  return PersistenceStateSnapshot(
    revision: snapshot.revision.toInt(),
    state: switch (snapshot.state) {
      frb.BridgePersistenceState_Ready(:final pendingCommits) =>
        ReadyPersistenceState(pendingCommits: pendingCommits.toInt()),
      frb.BridgePersistenceState_Flushing(
        :final pendingCommits,
        :final oldestPendingRevision,
      ) =>
        FlushingPersistenceState(
          pendingCommits: pendingCommits.toInt(),
          oldestPendingRevision: oldestPendingRevision?.toInt(),
        ),
      frb.BridgePersistenceState_Degraded(
        :final pendingCommits,
        :final oldestPendingRevision,
        :final firstFailedAt,
        :final error,
      ) =>
        DegradedPersistenceState(
          pendingCommits: pendingCommits.toInt(),
          oldestPendingRevision: oldestPendingRevision?.toInt(),
          firstFailedAt: firstFailedAt.toInt(),
          error: _resourceError(error),
        ),
      frb.BridgePersistenceState_Recovering(
        :final pendingCommits,
        :final oldestPendingRevision,
        :final firstFailedAt,
      ) =>
        RecoveringPersistenceState(
          pendingCommits: pendingCommits.toInt(),
          oldestPendingRevision: oldestPendingRevision?.toInt(),
          firstFailedAt: firstFailedAt.toInt(),
        ),
      frb.BridgePersistenceState_Blocked(
        :final pendingCommits,
        :final oldestPendingRevision,
        :final firstFailedAt,
        :final error,
      ) =>
        BlockedPersistenceState(
          pendingCommits: pendingCommits.toInt(),
          oldestPendingRevision: oldestPendingRevision?.toInt(),
          firstFailedAt: firstFailedAt.toInt(),
          error: _resourceError(error),
        ),
    },
  );
}

PersistenceQueueSnapshot _persistenceQueueFromFrb(
  frb.BridgePersistenceQueueSnapshot snapshot,
) {
  return PersistenceQueueSnapshot(
    statisticsGap: snapshot.statisticsGap,
    pendingOperations: snapshot.pendingOperations.toInt(),
    pendingBytes: snapshot.pendingBytes.toInt(),
    inFlightBytes: snapshot.inFlightBytes.toInt(),
    oldestPendingAgeMillis: snapshot.oldestPendingAgeMillis?.toInt(),
    lastError: snapshot.lastError,
    pressurePaused: snapshot.pressurePaused,
    threads: [
      for (final thread in snapshot.threads)
        ThreadPersistenceSnapshot(
          threadId: thread.threadId,
          faultGeneration: thread.faultGeneration.toInt(),
          fault: thread.fault,
          current: switch (thread.current) {
            final current? => CurrentPersistenceSnapshot(
              runtimeEpoch: current.runtimeEpoch,
              dirty: current.dirty,
              inFlight: current.inFlight,
              savedRuntimeEpoch: current.savedRuntimeEpoch,
              savedRevision: current.savedRevision?.toInt(),
              lastSuccessfulSaveAt: current.lastSuccessfulSaveAt,
              lastSuccessfulCaptureAt: current.lastSuccessfulCaptureAt,
              snapshotAgeMillis: current.snapshotAgeMillis?.toInt(),
              lastError: current.lastError,
            ),
            null => null,
          },
          historyAdmittedSequence: thread.historyAdmittedSequence?.toInt(),
          historyDurableSequence: thread.historyDurableSequence?.toInt(),
          pendingOperations: thread.pendingOperations.toInt(),
          pendingBytes: thread.pendingBytes.toInt(),
          oldestPendingAgeMillis: thread.oldestPendingAgeMillis?.toInt(),
          inFlightBytes: thread.inFlightBytes.toInt(),
          lastError: thread.lastError,
          pressurePaused: thread.pressurePaused,
        ),
    ],
  );
}

ChildInteractionsStateView _childInteractionsStateFromFrb(
  frb_topic_types.BridgeChildInteractionsState value,
) {
  ChildInteractionsData convert(
    frb_topic_types.BridgeChildInteractionsData data,
  ) => ChildInteractionsData(
    items: data.items.map(_childInteractionFromFrb).toList(),
  );

  return ChildInteractionsStateView(
    hostThreadId: value.hostThreadId,
    state: switch (value.state) {
      frb_topic_types.BridgeChildInteractionsResource_Uninitialized(
        :final field0,
      ) =>
        _uninitializedResource(field0),
      frb_topic_types.BridgeChildInteractionsResource_Loading(:final field0) =>
        _loadingResource(field0),
      frb_topic_types.BridgeChildInteractionsResource_Ready(
        :final resource,
        :final value,
      ) =>
        _readyResource(resource, convert(value)),
      frb_topic_types.BridgeChildInteractionsResource_Refreshing(
        :final resource,
        :final value,
      ) =>
        _refreshingResource(resource, convert(value)),
      frb_topic_types.BridgeChildInteractionsResource_Stale(
        :final resource,
        :final value,
      ) =>
        _staleResource(resource, convert(value)),
      frb_topic_types.BridgeChildInteractionsResource_Degraded(
        :final resource,
        :final value,
      ) =>
        _degradedResource(resource, convert(value)),
      frb_topic_types.BridgeChildInteractionsResource_Failed(:final field0) =>
        _failedResource(field0),
      frb_topic_types.BridgeChildInteractionsResource_Stopped(:final field0) =>
        _stoppedResource(field0),
    },
  );
}

ChildInteractionSummary _childInteractionFromFrb(
  frb.BridgeChildInteractionSummary value,
) {
  final interaction = _interactionFromFrb(value.interaction);
  return ChildInteractionSummary(
    childThreadId: value.childThreadId,
    interactionId: value.interactionId,
    kind: _interactionKindFromLabel(value.kind) ?? interaction.kind,
    revision: value.revision.toInt(),
    interaction: interaction,
  );
}

/// 单个 root 会话的作用域费用状态；`cost == null` 是显式清除。
RuntimeCostView _runtimeCostFromFrb(frb.BridgeRuntimeCostAmount value) =>
    RuntimeCostView(currency: value.currency, amount: value.amount);

ResourceStamp _resourceStampFromFrb(frb_command.BridgeResourceStamp value) =>
    ResourceStamp(
      resourceKey: value.resourceKey,
      ownerEpoch: value.ownerEpoch,
      revision: value.revision.toInt(),
    );

SessionCostsStateView _sessionCostsStateFromFrb(
  frb.BridgeSessionCostsState value,
) {
  final updatedAt = value.updatedAt.toInt();
  return SessionCostsStateView(
    rootThreadId: value.rootThreadId,
    revision: value.revision.toInt(),
    updatedAt: updatedAt == 0 ? null : dateFromUnix(value.updatedAt),
    statisticsPending: value.statisticsPending,
    statisticsGap: value.statisticsGap,
    readFailed: value.readFailed,
    cost: value.cost == null
        ? null
        : SessionCostView(
            rootThreadId: value.cost!.rootThreadId,
            purposeCosts: [
              for (final cost in value.cost!.purposeCosts)
                PurposeCostView(
                  purpose: cost.purpose,
                  estimatedCosts: [
                    for (final estimate in cost.estimatedCosts)
                      _runtimeCostFromFrb(estimate),
                  ],
                  hasUnpricedUsage: cost.hasUnpricedUsage,
                ),
            ],
            estimatedCosts: [
              for (final cost in value.cost!.estimatedCosts)
                _runtimeCostFromFrb(cost),
            ],
            hasUnpricedUsage: value.cost!.hasUnpricedUsage,
          ),
  );
}

/// 持久化队列 typed 观测（发布 revision + 时间基线 + 协调器真实观测）。
PersistenceQueueStateView _persistenceQueueStateFromFrb(
  frb.BridgePersistenceQueueStateSnapshot value,
) {
  final updatedAt = value.updatedAt.toInt();
  return PersistenceQueueStateView(
    revision: value.revision.toInt(),
    updatedAt: updatedAt == 0 ? null : dateFromUnix(value.updatedAt),
    queue: _persistenceQueueFromFrb(value.queue),
  );
}

AgentProfileView _agentProfileFromFrb(frb.BridgeAgentProfileDto profile) {
  return AgentProfileView(
    definition: AgentDefinitionView(
      definitionId: profile.definition.definitionId,
      displayName: profile.definition.displayName,
      description: profile.definition.description,
      whenToUse: profile.definition.whenToUse,
      source: profile.definition.source,
      revision: profile.definition.revision,
      contentHash: profile.definition.contentHash,
    ),
    binding: agentBindingFromFrb(profile.binding),
    system: profile.system,
    enabled: profile.enabled,
    workspaceMode: switch (profile.workspaceMode) {
      frb.BridgeAgentWorkspaceMode.unrestricted =>
        AgentWorkspaceMode.unrestricted,
      frb.BridgeAgentWorkspaceMode.directory => AgentWorkspaceMode.directory,
      frb.BridgeAgentWorkspaceMode.worktree => AgentWorkspaceMode.worktree,
      frb.BridgeAgentWorkspaceMode.review => AgentWorkspaceMode.review,
    },
  );
}

/// 配置级 Agent Profiles 的 canonical 资源快照。
AgentProfilesStateView _agentProfilesStateFromFrb(
  frb.BridgeAgentProfilesStateSnapshot snapshot,
) {
  AgentProfilesDataView convert(frb.BridgeAgentProfilesData data) =>
      AgentProfilesDataView(
        profiles: data.profiles.map(_agentProfileFromFrb).toList(),
        diagnostics: [
          for (final diagnostic in data.diagnostics)
            AgentProfileDiagnosticView(
              path: diagnostic.path,
              message: diagnostic.message,
            ),
        ],
      );
  return AgentProfilesStateView(
    state: switch (snapshot.state) {
      frb.BridgeAgentProfilesState_Uninitialized(:final field0) =>
        _uninitializedResource(field0),
      frb.BridgeAgentProfilesState_Loading(:final field0) => _loadingResource(
        field0,
      ),
      frb.BridgeAgentProfilesState_Ready(:final resource, :final value) =>
        _readyResource(resource, convert(value)),
      frb.BridgeAgentProfilesState_Refreshing(:final resource, :final value) =>
        _refreshingResource(resource, convert(value)),
      frb.BridgeAgentProfilesState_Stale(:final resource, :final value) =>
        _staleResource(resource, convert(value)),
      frb.BridgeAgentProfilesState_Degraded(:final resource, :final value) =>
        _degradedResource(resource, convert(value)),
      frb.BridgeAgentProfilesState_Failed(:final field0) => _failedResource(
        field0,
      ),
      frb.BridgeAgentProfilesState_Stopped(:final field0) => _stoppedResource(
        field0,
      ),
    },
  );
}

ProjectDirectoryState _projectDirectoryFromFrb(
  frb.BridgeProjectDirectoryState snapshot,
) {
  List<StudioProject> convert(frb.BridgeProjectDirectoryData data) =>
      data.projects.map(_projectFromFrb).toList();
  return ProjectDirectoryState.fromState(
    state: switch (snapshot) {
      frb.BridgeProjectDirectoryState_Uninitialized(:final field0) =>
        _uninitializedResource(field0),
      frb.BridgeProjectDirectoryState_Loading(:final field0) =>
        _loadingResource(field0),
      frb.BridgeProjectDirectoryState_Ready(:final resource, :final value) =>
        _readyResource(resource, convert(value)),
      frb.BridgeProjectDirectoryState_Refreshing(
        :final resource,
        :final value,
      ) =>
        _refreshingResource(resource, convert(value)),
      frb.BridgeProjectDirectoryState_Stale(:final resource, :final value) =>
        _staleResource(resource, convert(value)),
      frb.BridgeProjectDirectoryState_Degraded(:final resource, :final value) =>
        _degradedResource(resource, convert(value)),
      frb.BridgeProjectDirectoryState_Failed(:final field0) => _failedResource(
        field0,
      ),
      frb.BridgeProjectDirectoryState_Stopped(:final field0) =>
        _stoppedResource(field0),
    },
  );
}

ThreadDirectoryPage _threadDirectoryPageFromFrb(
  frb.BridgeThreadDirectoryPage snapshot,
) {
  ThreadDirectoryPage convert(
    frb.BridgeThreadDirectoryPageData data,
    int revision,
  ) => ThreadDirectoryPage(
    rows: data.rows.map(_sessionDirectoryRowFromFrb).toList(),
    nextCursor: data.nextCursor,
    revision: revision,
  );
  final resource = switch (snapshot) {
    frb.BridgeThreadDirectoryPage_Uninitialized(:final field0) =>
      _uninitializedResource<ThreadDirectoryPage>(field0),
    frb.BridgeThreadDirectoryPage_Loading(:final field0) =>
      _loadingResource<ThreadDirectoryPage>(field0),
    frb.BridgeThreadDirectoryPage_Ready(:final resource, :final value) =>
      _readyResource(resource, convert(value, resource.revision.toInt())),
    frb.BridgeThreadDirectoryPage_Refreshing(:final resource, :final value) =>
      _refreshingResource(resource, convert(value, resource.revision.toInt())),
    frb.BridgeThreadDirectoryPage_Stale(:final resource, :final value) =>
      _staleResource(resource, convert(value, resource.revision.toInt())),
    frb.BridgeThreadDirectoryPage_Degraded(:final resource, :final value) =>
      _degradedResource(resource, convert(value, resource.revision.toInt())),
    frb.BridgeThreadDirectoryPage_Failed(:final field0) =>
      _failedResource<ThreadDirectoryPage>(field0),
    frb.BridgeThreadDirectoryPage_Stopped(:final field0) =>
      _stoppedResource<ThreadDirectoryPage>(field0),
  };
  return resource.value ?? const ThreadDirectoryPage(rows: []);
}

ThreadDirectoryFrame _threadDirectoryFrameFromFrb(
  frb_directory_types.BridgeThreadDirectoryFrame value,
) => ThreadDirectoryFrame(
  query: DirectoryQuery.withThreadIds(
    workspaceId: value.query.workspaceId,
    search: value.query.search,
    archived: value.query.archived,
    filter: switch (value.query.filter) {
      frb_directory_types.BridgeThreadDirectoryFilter.all =>
        DirectoryFilter.all,
      frb_directory_types.BridgeThreadDirectoryFilter.running =>
        DirectoryFilter.running,
      frb_directory_types.BridgeThreadDirectoryFilter.attention =>
        DirectoryFilter.attention,
    },
    threadIds: value.query.threadIds,
    excludedThreadIds: value.query.excludedThreadIds,
  ),
  window: DirectoryWindow(
    before: value.window.before,
    limit: value.window.limit,
  ),
  stamp: _resourceStampFromFrb(value.stamp),
  threadIds: value.threadIds,
  nextCursor: value.nextCursor,
);

ThreadMetadataFrame _threadMetadataFrameFromFrb(
  frb_directory_types.BridgeThreadMetadataFrame value,
) => ThreadMetadataFrame(
  threadId: value.threadId,
  stamp: _resourceStampFromFrb(value.stamp),
  row: value.row == null ? null : _sessionDirectoryRowFromFrb(value.row!),
);

AgentDirectoryState _agentDirectoryFromFrb(
  frb.BridgeAgentDirectoryState snapshot,
) {
  List<StudioAgentView> convert(frb.BridgeAgentDirectoryData data) =>
      data.agents.map(_agentDirectoryEntryFromFrb).toList();
  return AgentDirectoryState.fromState(
    state: switch (snapshot) {
      frb.BridgeAgentDirectoryState_Uninitialized(:final field0) =>
        _uninitializedResource(field0),
      frb.BridgeAgentDirectoryState_Loading(:final field0) => _loadingResource(
        field0,
      ),
      frb.BridgeAgentDirectoryState_Ready(:final resource, :final value) =>
        _readyResource(resource, convert(value)),
      frb.BridgeAgentDirectoryState_Refreshing(:final resource, :final value) =>
        _refreshingResource(resource, convert(value)),
      frb.BridgeAgentDirectoryState_Stale(:final resource, :final value) =>
        _staleResource(resource, convert(value)),
      frb.BridgeAgentDirectoryState_Degraded(:final resource, :final value) =>
        _degradedResource(resource, convert(value)),
      frb.BridgeAgentDirectoryState_Failed(:final field0) => _failedResource(
        field0,
      ),
      frb.BridgeAgentDirectoryState_Stopped(:final field0) => _stoppedResource(
        field0,
      ),
    },
  );
}

RecoveryStateSnapshot _recoveryStateFromFrb(
  frb.BridgeRecoveryStateSnapshot snapshot,
) {
  List<StudioRecoveryIssue> convert(frb.BridgeRecoveryStateData data) =>
      data.issues.map(_recoveryIssueFromFrb).toList();
  return RecoveryStateSnapshot.fromState(
    state: switch (snapshot) {
      frb.BridgeRecoveryStateSnapshot_Uninitialized(:final field0) =>
        _uninitializedResource(field0),
      frb.BridgeRecoveryStateSnapshot_Loading(:final field0) =>
        _loadingResource(field0),
      frb.BridgeRecoveryStateSnapshot_Ready(:final resource, :final value) =>
        _readyResource(resource, convert(value)),
      frb.BridgeRecoveryStateSnapshot_Refreshing(
        :final resource,
        :final value,
      ) =>
        _refreshingResource(resource, convert(value)),
      frb.BridgeRecoveryStateSnapshot_Stale(:final resource, :final value) =>
        _staleResource(resource, convert(value)),
      frb.BridgeRecoveryStateSnapshot_Degraded(:final resource, :final value) =>
        _degradedResource(resource, convert(value)),
      frb.BridgeRecoveryStateSnapshot_Failed(:final field0) => _failedResource(
        field0,
      ),
      frb.BridgeRecoveryStateSnapshot_Stopped(:final field0) =>
        _stoppedResource(field0),
    },
  );
}

LspStateSnapshot _lspStateFromFrb(frb.BridgeLspStateSnapshot snapshot) {
  LspStateData convert(frb.BridgeLspStateData data) => LspStateData(
    activeServers: data.health.activeLspServers,
    servers: data.health.lspServers.map(_lspServerFromFrb).toList(),
  );
  return LspStateSnapshot.fromState(
    state: switch (snapshot) {
      frb.BridgeLspStateSnapshot_Uninitialized(:final field0) =>
        _uninitializedResource(field0),
      frb.BridgeLspStateSnapshot_Loading(:final field0) => _loadingResource(
        field0,
      ),
      frb.BridgeLspStateSnapshot_Ready(:final resource, :final value) =>
        _readyResource(resource, convert(value)),
      frb.BridgeLspStateSnapshot_Refreshing(:final resource, :final value) =>
        _refreshingResource(resource, convert(value)),
      frb.BridgeLspStateSnapshot_Stale(:final resource, :final value) =>
        _staleResource(resource, convert(value)),
      frb.BridgeLspStateSnapshot_Degraded(:final resource, :final value) =>
        _degradedResource(resource, convert(value)),
      frb.BridgeLspStateSnapshot_Failed(:final field0) => _failedResource(
        field0,
      ),
      frb.BridgeLspStateSnapshot_Stopped(:final field0) => _stoppedResource(
        field0,
      ),
    },
  );
}

ThreadLspStateSnapshot _threadLspStateFromFrb(
  frb_thread_lsp_types.BridgeThreadLspStateSnapshot snapshot,
) => ThreadLspStateSnapshot(
  threadId: snapshot.threadId,
  revision: snapshot.revision.toInt(),
  bindingId: snapshot.bindingId,
  servers: snapshot.servers.map(_lspServerFromFrb).toList(),
);

LspServerStateView _lspServerFromFrb(frb.BridgeLspServerDto server) =>
    LspServerStateView(
      id: server.id,
      displayName: server.displayName,
      configurationPath: server.configurationPath,
      phase: server.phase,
      state: switch (server.state) {
        frb.BridgeLspServerState_Checking(:final message) => LspCheckingState(
          message: message,
        ),
        frb.BridgeLspServerState_Available(
          :final checkedAt,
          :final diagnosticCount,
          :final activity,
        ) =>
          LspAvailableState(
            checkedAt: checkedAt.toInt(),
            diagnosticCount: diagnosticCount.toInt(),
            activity: switch (activity) {
              frb.BridgeLspActivity_Idle() => const LspIdleActivity(),
              frb.BridgeLspActivity_Busy(
                :final title,
                :final message,
                :final percentage,
              ) =>
                LspBusyActivity(
                  title: title,
                  message: message,
                  percentage: percentage,
                ),
              frb.BridgeLspActivity_Indexing(
                :final title,
                :final message,
                :final percentage,
              ) =>
                LspIndexingActivity(
                  title: title,
                  message: message,
                  percentage: percentage,
                ),
            },
          ),
        frb.BridgeLspServerState_Unavailable(:final checkedAt, :final error) =>
          LspUnavailableState(
            checkedAt: checkedAt.toInt(),
            code: error.code,
            message: error.message,
            retryable: error.retryable,
          ),
        frb.BridgeLspServerState_Disabled(:final message) => LspDisabledState(
          message: message,
        ),
      },
    );

SkillsStateSnapshot _skillsStateFromFrb(
  frb.BridgeSkillsStateSnapshot snapshot,
) {
  SkillsStateData convert(frb.BridgeSkillsStateData data) => SkillsStateData(
    configFingerprint: data.configFingerprint,
    catalogRevision: data.catalogRevision.toInt(),
    skills: data.skills.map((skill) => skill.name).toList(),
    warnings: data.warnings,
    complete: data.complete,
    summaries: data.skills.map(_skillSummaryFromFrb).toList(),
  );
  return SkillsStateSnapshot.fromState(
    workspaceId: snapshot.workspaceId,
    state: switch (snapshot.state) {
      frb.BridgeSkillsResourceState_Uninitialized(:final field0) =>
        _uninitializedResource(field0),
      frb.BridgeSkillsResourceState_Loading(:final field0) => _loadingResource(
        field0,
      ),
      frb.BridgeSkillsResourceState_Ready(:final resource, :final value) =>
        _readyResource(resource, convert(value)),
      frb.BridgeSkillsResourceState_Refreshing(:final resource, :final value) =>
        _refreshingResource(resource, convert(value)),
      frb.BridgeSkillsResourceState_Stale(:final resource, :final value) =>
        _staleResource(resource, convert(value)),
      frb.BridgeSkillsResourceState_Degraded(:final resource, :final value) =>
        _degradedResource(resource, convert(value)),
      frb.BridgeSkillsResourceState_Failed(:final field0) => _failedResource(
        field0,
      ),
      frb.BridgeSkillsResourceState_Stopped(:final field0) => _stoppedResource(
        field0,
      ),
    },
  );
}

ThreadModeCatalogView _threadModeCatalogFromFrb(
  frb.BridgeThreadModeCatalogSnapshot value,
) => ThreadModeCatalogView(
  revision: value.revision.toInt(),
  modes: [
    for (final mode in value.modes)
      ThreadModeDescriptorView(
        id: mode.id,
        displayName: mode.displayName,
        description: mode.description,
        order: mode.order.toInt(),
        hasWorkflow: mode.hasWorkflow,
        readOnly: mode.readOnly,
      ),
  ],
);

ModeDefinitionSnapshot _modeDefinitionSnapshotFromFrb(
  frb_mode_types.BridgeThreadModeDefinitionSnapshot value,
) => ModeDefinitionSnapshot(
  revision: value.revision.toInt(),
  document: _modeDocumentFromFrb(value.document),
  readOnly: value.readOnly,
);

ModeDocument _modeDocumentFromFrb(
  frb_mode_types.BridgeThreadModeDocument value,
) => ModeDocument(
  definition: _modeDefinitionFromFrb(value.definition),
  editor: _modeEditorLayoutFromFrb(value.editor),
);

ModeDefinition _modeDefinitionFromFrb(
  frb_mode_types.BridgeThreadModeDefinition value,
) => ModeDefinition(
  id: value.id,
  displayName: value.displayName,
  description: value.description,
  order: value.order,
  prompt: value.prompt,
  workflow: value.workflow == null
      ? null
      : _workflowDefinitionFromFrb(value.workflow!),
);

ModeEditorLayout _modeEditorLayoutFromFrb(
  frb_mode_types.BridgeThreadModeEditorLayout value,
) => ModeEditorLayout(
  nodes: [
    for (final node in value.nodes)
      WorkflowNodePosition(stateId: node.stateId, x: node.x, y: node.y),
  ],
);

WorkflowDefinition _workflowDefinitionFromFrb(
  frb_mode_types.BridgeWorkflowDefinition value,
) => WorkflowDefinition(
  title: value.title,
  goal: value.goal,
  initialStateId: value.initialStateId,
  states: [for (final state in value.states) _workflowStateFromFrb(state)],
  transitions: [
    for (final transition in value.transitions)
      _workflowTransitionFromFrb(transition),
  ],
);

WorkflowState _workflowStateFromFrb(frb_mode_types.BridgeWorkflowState value) =>
    WorkflowState(
      id: value.id,
      title: value.title,
      instructions: value.instructions,
      completionCriteria: value.completionCriteria,
      kind: value.kind == frb_mode_types.BridgeWorkflowStateKind.finalState
          ? WorkflowStateKind.finalState
          : WorkflowStateKind.atomic,
    );

WorkflowTransition _workflowTransitionFromFrb(
  frb_mode_types.BridgeWorkflowTransition value,
) => WorkflowTransition(
  sourceStateId: value.sourceStateId,
  targetStateId: value.targetStateId,
  guard: value.guard,
);

ModeDefinitionCommandReply _modeDefinitionCommandReplyFromFrb(
  frb_mode_types.BridgeThreadModeDefinitionCommandReply value,
) => ModeDefinitionCommandReply(
  catalog: _threadModeCatalogFromFrb(value.catalog),
  definition: value.definition == null
      ? null
      : _modeDefinitionSnapshotFromFrb(value.definition!),
  receipt: _commandReceiptFromFrb(value.receipt),
);

ModeValidationResult _modeValidationResultFromFrb(
  frb_mode_types.BridgeThreadModeValidationResult value,
) => ModeValidationResult(
  document: value.document == null
      ? null
      : _modeDocumentFromFrb(value.document!),
  issues: [
    for (final issue in value.issues)
      ModeValidationIssue(
        code: issue.code,
        path: issue.path,
        message: issue.message,
      ),
  ],
);

WorkflowPreviewSnapshot _workflowPreviewSnapshotFromFrb(
  frb_mode_types.BridgeWorkflowPreviewSnapshot value,
) => WorkflowPreviewSnapshot(
  accepted: value.accepted,
  message: value.message,
  currentState: value.currentState == null
      ? null
      : _workflowStateFromFrb(value.currentState!),
  transitions: [
    for (final transition in value.transitions)
      _workflowTransitionFromFrb(transition),
  ],
  path: value.path,
  terminal: value.terminal,
);

frb_mode_types.BridgeThreadModeDocument _bridgeModeDocument(
  ModeDocument value,
) => frb_mode_types.BridgeThreadModeDocument(
  definition: frb_mode_types.BridgeThreadModeDefinition(
    id: value.definition.id,
    displayName: value.definition.displayName,
    description: value.definition.description,
    order: value.definition.order,
    prompt: value.definition.prompt,
    workflow: value.definition.workflow == null
        ? null
        : _bridgeWorkflowDefinition(value.definition.workflow!),
  ),
  editor: frb_mode_types.BridgeThreadModeEditorLayout(
    nodes: [
      for (final node in value.editor.nodes)
        frb_mode_types.BridgeWorkflowNodePosition(
          stateId: node.stateId,
          x: node.x,
          y: node.y,
        ),
    ],
  ),
);

frb_mode_types.BridgeWorkflowDefinition _bridgeWorkflowDefinition(
  WorkflowDefinition value,
) => frb_mode_types.BridgeWorkflowDefinition(
  title: value.title,
  goal: value.goal,
  initialStateId: value.initialStateId,
  states: [
    for (final state in value.states)
      frb_mode_types.BridgeWorkflowState(
        id: state.id,
        title: state.title,
        instructions: state.instructions,
        completionCriteria: state.completionCriteria,
        kind: state.kind == WorkflowStateKind.finalState
            ? frb_mode_types.BridgeWorkflowStateKind.finalState
            : frb_mode_types.BridgeWorkflowStateKind.atomic,
      ),
  ],
  transitions: [
    for (final transition in value.transitions)
      frb_mode_types.BridgeWorkflowTransition(
        sourceStateId: transition.sourceStateId,
        targetStateId: transition.targetStateId,
        guard: transition.guard,
      ),
  ],
);

frb_mode_types.BridgeWorkflowPreviewRequest _bridgeWorkflowPreviewRequest(
  WorkflowPreviewRequest value,
) => frb_mode_types.BridgeWorkflowPreviewRequest(
  document: _bridgeModeDocument(value.document),
  path: value.path,
  targetStateId: value.targetStateId,
  reason: value.reason,
);

SkillSearchResultView _skillSearchResultFromFrb(
  frb.BridgeSkillSearchResult result,
) {
  return SkillSearchResultView(
    workspaceId: result.workspaceId,
    catalogRevision: result.catalogRevision.toInt(),
    matches: result.matches.map(_skillSummaryFromFrb).toList(),
    truncated: result.truncated,
  );
}

SkillSummaryView _skillSummaryFromFrb(frb.SkillSummaryDto skill) {
  return SkillSummaryView(
    name: skill.name,
    description: skill.description,
    category: skill.category,
    platforms: skill.platforms,
    source: skill.source,
    providerId: skill.providerId,
    modelInvocable: skill.invocation.modelInvocable,
    userInvocable: skill.invocation.userInvocable,
    resourceBase: skill.resourceBase.when(
      directory: (path) =>
          SkillResourceBaseView(SkillResourceBaseKind.directory, path),
      url: (url) => SkillResourceBaseView(SkillResourceBaseKind.url, url),
      opaque: (description) =>
          SkillResourceBaseView(SkillResourceBaseKind.opaque, description),
    ),
  );
}

UpdaterStateSnapshot updaterStateFromFrb(
  frb.BridgeUpdaterStateSnapshot snapshot,
) => UpdaterStateSnapshot(
  activity: _updaterActivityFromFrb(snapshot.activity),
  installationError: snapshot.installationError == null
      ? null
      : _updaterErrorFromFrb(snapshot.installationError!),
  readyUpdate: snapshot.readyUpdate == null
      ? null
      : ReadyStudioUpdate(
          update: _updateInfoFromFrb(snapshot.readyUpdate!.update),
          readyAt: dateFromUnix(snapshot.readyUpdate!.readyAt),
        ),
);

UpdaterActivity _updaterActivityFromFrb(
  frb.BridgeUpdaterActivity snapshot,
) => switch (snapshot) {
  frb.BridgeUpdaterActivity_Disabled(:final field0) => DisabledUpdaterActivity(
    revision: field0.revision.toInt(),
    updatedAt: dateFromUnix(field0.updatedAt),
  ),
  frb.BridgeUpdaterActivity_Idle(:final field0) => IdleUpdaterActivity(
    revision: field0.revision.toInt(),
    updatedAt: dateFromUnix(field0.updatedAt),
  ),
  frb.BridgeUpdaterActivity_Checking(:final field0) => CheckingUpdaterActivity(
    revision: field0.revision.toInt(),
    operationId: field0.operationId,
    startedAt: dateFromUnix(field0.startedAt),
  ),
  frb.BridgeUpdaterActivity_UpToDate(:final field0) => UpToDateUpdaterActivity(
    revision: field0.revision.toInt(),
    checkedAt: dateFromUnix(field0.checkedAt),
  ),
  frb.BridgeUpdaterActivity_Available(:final field0) =>
    AvailableUpdaterActivity(
      revision: field0.revision.toInt(),
      checkedAt: dateFromUnix(field0.checkedAt),
      update: _updateInfoFromFrb(field0.update),
    ),
  frb.BridgeUpdaterActivity_Downloading(:final field0) =>
    DownloadingUpdaterActivity(
      revision: field0.revision.toInt(),
      updatedAt: dateFromUnix(field0.updatedAt),
      update: _updateInfoFromFrb(field0.update),
      downloaded: field0.downloaded.toInt(),
      total: field0.total.toInt(),
    ),
  frb.BridgeUpdaterActivity_Verifying(:final field0) =>
    VerifyingUpdaterActivity(
      revision: field0.revision.toInt(),
      updatedAt: dateFromUnix(field0.updatedAt),
      update: _updateInfoFromFrb(field0.update),
      downloaded: field0.downloaded.toInt(),
      total: field0.total.toInt(),
    ),
  frb.BridgeUpdaterActivity_Ready(:final field0) => ReadyUpdaterActivity(
    revision: field0.revision.toInt(),
    readyAt: dateFromUnix(field0.readyAt),
    update: _updateInfoFromFrb(field0.update),
  ),
  frb.BridgeUpdaterActivity_InstallerLaunched(:final field0) =>
    InstallerLaunchedUpdaterActivity(
      revision: field0.revision.toInt(),
      launchedAt: dateFromUnix(field0.launchedAt),
      update: _updateInfoFromFrb(field0.update),
    ),
  frb.BridgeUpdaterActivity_CheckFailed(:final field0) =>
    CheckFailedUpdaterActivity(
      revision: field0.revision.toInt(),
      failedAt: dateFromUnix(field0.failedAt),
      error: _updaterErrorFromFrb(field0.error),
    ),
  frb.BridgeUpdaterActivity_InstallFailed(:final field0) =>
    InstallFailedUpdaterActivity(
      revision: field0.revision.toInt(),
      failedAt: dateFromUnix(field0.failedAt),
      update: _updateInfoFromFrb(field0.update),
      error: _updaterErrorFromFrb(field0.error),
    ),
};

StudioUpdateInfoView _updateInfoFromFrb(
  frb.BridgeVerifiedUpdateSummary update,
) => StudioUpdateInfoView(
  version: update.version,
  publishedAt: dateFromUnix(update.publishedAt),
  notesUrl: update.notesUrl,
);

UpdaterErrorView _updaterErrorFromFrb(frb.BridgeStateError error) =>
    UpdaterErrorView(
      code: error.code,
      message: error.message,
      retryable: error.retryable,
    );

StudioRecoveryIssue _recoveryIssueFromFrb(
  frb.BridgeStudioRecoveryIssueDto issue,
) {
  return StudioRecoveryIssue(
    id: issue.id,
    scope: switch (issue.scope) {
      frb.BridgeRecoveryIssueScope.application =>
        RecoveryIssueScope.application,
      frb.BridgeRecoveryIssueScope.project => RecoveryIssueScope.project,
      frb.BridgeRecoveryIssueScope.thread => RecoveryIssueScope.thread,
    },
    category: switch (issue.category) {
      frb.BridgeRecoveryIssueCategory.processLease =>
        RecoveryIssueCategory.processLease,
      frb.BridgeRecoveryIssueCategory.toolCatalog =>
        RecoveryIssueCategory.toolCatalog,
      frb.BridgeRecoveryIssueCategory.repository =>
        RecoveryIssueCategory.repository,
      frb.BridgeRecoveryIssueCategory.storage => RecoveryIssueCategory.storage,
    },
    impact: switch (issue.impact) {
      frb.BridgeRecoveryImpact.advisory => RecoveryIssueImpact.advisory,
      frb.BridgeRecoveryImpact.executionBlocked =>
        RecoveryIssueImpact.executionBlocked,
      frb.BridgeRecoveryImpact.accessBlocked =>
        RecoveryIssueImpact.accessBlocked,
    },
    availableActions: [
      for (final action in issue.availableActions)
        switch (action) {
          frb.BridgeRecoveryIssueAction.retry => RecoveryIssueAction.retry,
          frb.BridgeRecoveryIssueAction.cleanupWorktree =>
            RecoveryIssueAction.cleanupWorktree,
        },
    ],
    workspaceId: issue.workspaceId,
    threadId: issue.threadId,
    detail: issue.detail,
    worktree: issue.worktree == null
        ? null
        : WorktreeRecoveryPreview(
            inspection: switch (issue.worktree!.inspection) {
              frb.BridgeWorktreeInspection.available =>
                WorktreeInspection.available,
              frb.BridgeWorktreeInspection.missing =>
                WorktreeInspection.missing,
              frb.BridgeWorktreeInspection.identityMismatch =>
                WorktreeInspection.identityMismatch,
              frb.BridgeWorktreeInspection.unavailable =>
                WorktreeInspection.unavailable,
            },
            ownerKind: switch (issue.worktree!.ownerKind) {
              frb.BridgeWorktreeOwner.session => WorktreeOwnerKind.session,
              frb.BridgeWorktreeOwner.child => WorktreeOwnerKind.child,
            },
            ownerThreadId: issue.worktree!.ownerThreadId,
            leaseRevision: issue.worktree!.leaseRevision.toInt(),
            state: issue.worktree!.state,
            repositoryRoot: issue.worktree!.repositoryRoot,
            path: issue.worktree!.path,
            branch: issue.worktree!.branch,
            baseCommit: issue.worktree!.baseCommit,
            headCommit: issue.worktree!.headCommit,
            dirty: issue.worktree!.dirty,
            changedFiles: issue.worktree!.changedFiles,
            ignoredFiles: issue.worktree!.ignoredFiles,
          ),
  );
}

StudioCommandReceipt _commandReceiptFromFrb(
  frb_command.BridgeStudioCommandReceipt value,
) => StudioCommandReceipt(
  operationId: OperationId(value.operationId),
  disposition: switch (value.disposition) {
    frb_command.BridgeCommandDisposition.applied => CommitDisposition.applied,
    frb_command.BridgeCommandDisposition.noChange => CommitDisposition.noChange,
  },
  targets: [for (final target in value.targets) _resourceStampFromFrb(target)],
  effect: switch (value.effect) {
    frb_command.BridgeCommandEffectPoint.immediate => EffectPoint.immediate,
    frb_command.BridgeCommandEffectPoint.nextTurn => EffectPoint.nextTurn,
    frb_command.BridgeCommandEffectPoint.futureSession =>
      EffectPoint.futureSession,
  },
  effective: value.effective,
  durable: value.durable,
  requiresIdentityObservation: value.requiresIdentityObservation,
);

SettingsCommandReply _settingsCommandReplyFromFrb(
  frb_command.BridgeSettingsCommandReply value,
) => SettingsCommandReply(
  snapshot: _settingsStateFromFrb(value.snapshot),
  receipt: _commandReceiptFromFrb(value.receipt),
  accountFrames: [
    for (final account in value.snapshot.config.settings.accounts)
      AccountDetailFrame(
        ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: value.receipt.targets.first.ownerEpoch,
          revision: value.snapshot.config.revision.toInt(),
        ),
        NativeAccountIdentity(account.accountId),
        _nativeAccountDetailsFromFrb(account),
        modelConfiguration: _modelConfigurationFromFrb(account),
      ),
    for (final account in value.snapshot.config.settings.acpAccounts)
      AccountDetailFrame(
        ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: value.receipt.targets.first.ownerEpoch,
          revision: value.snapshot.config.revision.toInt(),
        ),
        AcpAccountIdentity(account.accountId),
        AcpAccountDetails(_acpAccountFromFrb(account)),
      ),
    for (final catalog in value.snapshot.catalog.accounts)
      AccountModelsFrame(
        ResourceStamp(
          resourceKey: 'model-catalog',
          ownerEpoch: value.receipt.targets.first.ownerEpoch,
          revision: value.snapshot.catalog.revision.toInt(),
        ),
        NativeAccountIdentity(catalog.accountId),
        _accountModelCatalogFromFrb(catalog),
      ),
  ],
);
