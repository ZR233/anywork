part of 'studio_api.dart';

ResourceStamp _accountStampFromFrb(frb_command.BridgeResourceStamp stamp) =>
    ResourceStamp(
      resourceKey: stamp.resourceKey,
      ownerEpoch: stamp.ownerEpoch,
      revision: stamp.revision.toInt(),
    );

AccountIdentity _accountIdentityFromFrb(
  frb_accounts.BridgeAccountIdentity identity,
) => switch (identity) {
  frb_accounts.BridgeAccountIdentity_Native(:final accountId) =>
    NativeAccountIdentity(accountId),
  frb_accounts.BridgeAccountIdentity_Acp(:final accountId) =>
    AcpAccountIdentity(accountId),
};
frb_accounts.BridgeAccountIdentity _accountIdentityToFrb(
  AccountIdentity identity,
) => switch (identity) {
  NativeAccountIdentity(:final accountId) =>
    frb_accounts.BridgeAccountIdentity.native(accountId: accountId),
  AcpAccountIdentity(:final accountId) =>
    frb_accounts.BridgeAccountIdentity.acp(accountId: accountId),
};
frb_accounts.BridgeAccountObservationTarget _accountTargetToFrb(
  AccountObservationTarget target,
) => switch (target) {
  AccountSummariesTarget() =>
    const frb_accounts.BridgeAccountObservationTarget.summaries(),
  AccountDetailTarget(:final identity) =>
    frb_accounts.BridgeAccountObservationTarget.detail(
      identity: _accountIdentityToFrb(identity),
    ),
  AccountModelsTarget(:final identity) =>
    frb_accounts.BridgeAccountObservationTarget.models(
      accountId: identity.accountId,
    ),
  AccountUsageTarget() =>
    const frb_accounts.BridgeAccountObservationTarget.usage(),
  AcpAuthTarget() =>
    const frb_accounts.BridgeAccountObservationTarget.acpAuth(),
  AcpInstallTarget() =>
    const frb_accounts.BridgeAccountObservationTarget.acpInstall(),
  ChatGptLoginTarget(:final loginId) =>
    frb_accounts.BridgeAccountObservationTarget.chatGptLogin(loginId: loginId),
};

NativeAccountDetails _nativeAccountDetailsFromFrb(
  frb.BridgeAccountSettingsDto value,
) => NativeAccountDetails(
  identity: NativeAccountIdentity(value.accountId),
  name: value.name,
  authentication: _accountAuthenticationMethodFromFrb(value.authentication),
  chatgptAccount: value.chatgptAccount == null
      ? null
      : _chatGptAccountInfoFromFrb(value.chatgptAccount!),
  protocol: value.protocol,
  templateId: value.templateId,
  baseUrl: value.baseUrl,
  hasBearerToken: value.hasBearerToken,
  credentialRequired: value.credentialRequired,
  usageQueryRevision: value.usageQueryRevision.toInt(),
  customModels: [
    for (final model in value.customModels)
      AccountModelCommand(
        modelId: model.modelId,
        displayName: model.displayName,
        wireApi: model.wireApi,
        contextWindow: model.contextWindow?.toInt(),
        maxOutputTokens: model.maxOutputTokens?.toInt(),
      ),
  ],
);
AccountModelCatalog _accountModelCatalogFromFrb(
  frb.BridgeModelCatalogAccountDto value,
) => AccountModelCatalog(
  identity: NativeAccountIdentity(value.accountId),
  models: value.effectiveModels.map(accountModelFromCatalog),
  status: _modelCatalogStatusFromFrb(value.modelCatalog),
);
AccountModelConfiguration _modelConfigurationFromFrb(
  frb.BridgeAccountSettingsDto value,
) => AccountModelConfiguration(
  modelEnabledOverrides: value.modelEnabledOverrides,
  connections: {
    for (final connection in value.modelConnectionModes)
      connection.modelId: switch (connection.connectionMode) {
        'http' => AccountConnectionMode.http,
        'web_socket' => AccountConnectionMode.webSocket,
        final mode => throw FormatException(
          'Unknown account connection: $mode',
        ),
      },
  },
  autoCompactLimits: {
    for (final compact in value.modelAutoCompactLimits)
      if (compact.overrideLimit case final limit?)
        compact.modelId: limit.toInt(),
  },
);

AccountDomainFrame _accountFrameFromFrb(
  frb_accounts.BridgeAccountDomainFrame frame,
) => switch (frame) {
  frb_accounts.BridgeAccountDomainFrame_Summaries(
    :final stamp,
    :final accounts,
  ) =>
    AccountSummariesFrame(_accountStampFromFrb(stamp), [
      for (final account in accounts)
        AccountSummary(
          identity: _accountIdentityFromFrb(account.identity),
          name: account.name,
          brandKey: account.brandKey,
          displayEndpoint: account.displayEndpoint,
          isDefault: account.isDefault,
          billingKind: account.billingKind == null
              ? null
              : _billingKindFromFrb(account.billingKind!),
          billingKindOverride: account.billingKindOverride == null
              ? null
              : _billingKindFromFrb(account.billingKindOverride!),
          credentialReady: account.credentialReady,
          usageQueryRevision: account.usageQueryRevision?.toInt(),
          acpConnectionRevision: _frbNullableInt(account.acpConnectionRevision),
          capabilities: AccountCapabilities(
            setDefault: account.capabilities.setDefault,
            edit: account.capabilities.edit,
            remove: account.capabilities.remove,
            queryUsage: account.capabilities.queryUsage,
            syncModels: account.capabilities.syncModels,
            editModels: account.capabilities.editModels,
            acpAuth: account.capabilities.acpAuth,
          ),
        ),
    ]),
  frb_accounts.BridgeAccountDomainFrame_Detail(
    :final stamp,
    :final identity,
    :final account,
  ) =>
    AccountDetailFrame(
      _accountStampFromFrb(stamp),
      _accountIdentityFromFrb(identity),
      switch (account) {
        null => null,
        frb_accounts.BridgeAccountDetail_Native(:final field0) =>
          _nativeAccountDetailsFromFrb(field0),
        frb_accounts.BridgeAccountDetail_Acp(:final field0) =>
          AcpAccountDetails(_acpAccountFromFrb(field0)),
      },
      modelConfiguration: account is frb_accounts.BridgeAccountDetail_Native
          ? _modelConfigurationFromFrb(account.field0)
          : null,
    ),
  frb_accounts.BridgeAccountDomainFrame_Models(
    :final stamp,
    :final accountId,
    :final catalog,
  ) =>
    AccountModelsFrame(
      _accountStampFromFrb(stamp),
      NativeAccountIdentity(accountId),
      catalog == null ? null : _accountModelCatalogFromFrb(catalog),
    ),
  frb_accounts.BridgeAccountDomainFrame_Usage(:final stamp, :final accounts) =>
    AccountUsageFrame(
      _accountStampFromFrb(stamp),
      accounts.map(_usageObservationFromFrb),
    ),
  frb_accounts.BridgeAccountDomainFrame_AcpAuth(
    :final stamp,
    :final snapshot,
  ) =>
    AcpAuthFrame(
      _accountStampFromFrb(stamp),
      _acpAuthSnapshotFromFrb(snapshot),
    ),
  frb_accounts.BridgeAccountDomainFrame_AcpInstall(
    :final stamp,
    :final snapshot,
  ) =>
    AcpInstallFrame(
      _accountStampFromFrb(stamp),
      _acpInstallSnapshotFromFrb(snapshot),
    ),
  frb_accounts.BridgeAccountDomainFrame_ChatGptLogin(
    :final stamp,
    :final snapshot,
  ) => ChatGptLoginFrame(
    _accountStampFromFrb(stamp),
    _chatGptLoginSnapshotFromFrb(snapshot),
  ),
};

AccountAuthenticationMethod _accountAuthenticationMethodFromFrb(
  frb_chatgpt.BridgeAccountAuthenticationMethod value,
) => switch (value) {
  frb_chatgpt.BridgeAccountAuthenticationMethod.apiKey =>
    AccountAuthenticationMethod.apiKey,
  frb_chatgpt.BridgeAccountAuthenticationMethod.chatGpt =>
    AccountAuthenticationMethod.chatGpt,
};

frb_chatgpt.BridgeAccountAuthenticationIntent _accountAuthenticationIntentToFrb(
  AccountAuthenticationIntent value,
) => switch (value) {
  KeepAccountAuthentication() =>
    const frb_chatgpt.BridgeAccountAuthenticationIntent.keep(),
  SelectApiKeyAuthentication() =>
    const frb_chatgpt.BridgeAccountAuthenticationIntent.apiKey(),
  SelectChatGptAuthentication(:final loginId, :final editorId) =>
    frb_chatgpt.BridgeAccountAuthenticationIntent.chatGpt(
      loginId: loginId,
      editorId: editorId,
    ),
};

ChatGptAccountInfo _chatGptAccountInfoFromFrb(
  frb_chatgpt.BridgeChatGptAccountInfo value,
) => ChatGptAccountInfo(
  issuer: value.issuer,
  subject: value.subject,
  clientId: value.clientId,
  email: value.email,
  planUsageEnabled: value.planUsageEnabled,
);

ChatGptLoginSnapshot _chatGptLoginSnapshotFromFrb(
  frb_chatgpt.BridgeChatGptLoginSnapshot value,
) => ChatGptLoginSnapshot(
  loginId: value.loginId,
  editorId: value.editorId,
  accountId: value.accountId,
  revision: value.revision.toInt(),
  phase: switch (value.phase) {
    frb_chatgpt.BridgeChatGptLoginPhase.preparing =>
      ChatGptLoginPhase.preparing,
    frb_chatgpt.BridgeChatGptLoginPhase.awaitingBrowser =>
      ChatGptLoginPhase.awaitingBrowser,
    frb_chatgpt.BridgeChatGptLoginPhase.exchangingCode =>
      ChatGptLoginPhase.exchangingCode,
    frb_chatgpt.BridgeChatGptLoginPhase.succeeded =>
      ChatGptLoginPhase.succeeded,
    frb_chatgpt.BridgeChatGptLoginPhase.cancelled =>
      ChatGptLoginPhase.cancelled,
    frb_chatgpt.BridgeChatGptLoginPhase.failed => ChatGptLoginPhase.failed,
  },
  authorizationUrl: value.authorizationUrl,
  expiresAt: _frbNullableInt(value.expiresAt),
  account: value.account == null
      ? null
      : _chatGptAccountInfoFromFrb(value.account!),
  failure: value.failure == null
      ? null
      : ChatGptLoginFailure(
          code: switch (value.failure!.code) {
            frb_chatgpt.BridgeChatGptLoginFailureCode.network =>
              ChatGptLoginFailureCode.network,
            frb_chatgpt.BridgeChatGptLoginFailureCode.authorizationDenied =>
              ChatGptLoginFailureCode.authorizationDenied,
            frb_chatgpt.BridgeChatGptLoginFailureCode.invalidCallback =>
              ChatGptLoginFailureCode.invalidCallback,
            frb_chatgpt.BridgeChatGptLoginFailureCode.invalidIdentity =>
              ChatGptLoginFailureCode.invalidIdentity,
            frb_chatgpt.BridgeChatGptLoginFailureCode.missingPlanPermission =>
              ChatGptLoginFailureCode.missingPlanPermission,
            frb_chatgpt.BridgeChatGptLoginFailureCode.expired =>
              ChatGptLoginFailureCode.expired,
            frb_chatgpt.BridgeChatGptLoginFailureCode.storage =>
              ChatGptLoginFailureCode.storage,
            frb_chatgpt.BridgeChatGptLoginFailureCode.taskFailed =>
              ChatGptLoginFailureCode.taskFailed,
          },
          retryable: value.failure!.retryable,
        ),
);

ChatGptLoginCommandReply _chatGptLoginCommandReplyFromFrb(
  frb_chatgpt.BridgeChatGptLoginCommandReply value,
) => ChatGptLoginCommandReply(
  stamp: _accountStampFromFrb(value.stamp),
  snapshot: _chatGptLoginSnapshotFromFrb(value.snapshot),
);

AccountUsageObservation _usageObservationFromFrb(
  frb_accounts.BridgeAccountUsageObservation value,
) => AccountUsageObservation(
  identity: NativeAccountIdentity(value.accountId),
  queryRevision: value.queryRevision.toInt(),
  revision: value.revision.toInt(),
  phase: switch (value.phase) {
    frb_accounts.BridgeAccountUsagePhase.unchecked =>
      AccountUsagePhase.unchecked,
    frb_accounts.BridgeAccountUsagePhase.querying => AccountUsagePhase.querying,
    frb_accounts.BridgeAccountUsagePhase.succeeded =>
      AccountUsagePhase.succeeded,
    frb_accounts.BridgeAccountUsagePhase.unsupported =>
      AccountUsagePhase.unsupported,
    frb_accounts.BridgeAccountUsagePhase.missingCredential =>
      AccountUsagePhase.missingCredential,
    frb_accounts.BridgeAccountUsagePhase.failed => AccountUsagePhase.failed,
  },
  operationId: value.operationId,
  checkedAt: value.checkedAt?.toInt(),
  failure: value.failure == null
      ? null
      : AccountUsageFailure(
          code: switch (value.failure!.code) {
            frb_accounts.BridgeAccountUsageFailureCode.configuration =>
              AccountUsageFailureCode.configuration,
            frb_accounts.BridgeAccountUsageFailureCode.query =>
              AccountUsageFailureCode.query,
            frb_accounts.BridgeAccountUsageFailureCode.cancelled =>
              AccountUsageFailureCode.cancelled,
            frb_accounts.BridgeAccountUsageFailureCode.taskFailed =>
              AccountUsageFailureCode.taskFailed,
          },
          retryable: value.failure!.retryable,
        ),
  lastGood: value.lastGood == null
      ? null
      : AccountUsageSuccess(
          checkedAt: value.lastGood!.checkedAt.toInt(),
          value: _usageValueFromFrb(value.lastGood!.value),
        ),
);
AccountUsageValue _usageValueFromFrb(
  frb_accounts.BridgeAccountUsageValue value,
) => switch (value) {
  frb_accounts.BridgeAccountUsageValue_Balance(
    :final available,
    :final balances,
  ) =>
    AccountBalance(
      available: available,
      balances: [
        for (final balance in balances)
          AccountMoneyBalance(
            currency: balance.currency,
            total: balance.total,
            granted: balance.granted,
            toppedUp: balance.toppedUp,
          ),
      ],
    ),
  frb_accounts.BridgeAccountUsageValue_Subscription(
    :final level,
    :final quotas,
  ) =>
    AccountSubscription(
      level: level,
      quotas: [
        for (final quota in quotas)
          AccountQuota(
            window: switch (quota.window) {
              frb_accounts.BridgeAccountQuotaWindow_FiveHour() =>
                const AccountQuotaWindow(AccountQuotaWindowKind.fiveHour),
              frb_accounts.BridgeAccountQuotaWindow_Weekly() =>
                const AccountQuotaWindow(AccountQuotaWindowKind.weekly),
              frb_accounts.BridgeAccountQuotaWindow_McpMonthly() =>
                const AccountQuotaWindow(AccountQuotaWindowKind.mcpMonthly),
              frb_accounts.BridgeAccountQuotaWindow_Other(:final field0) =>
                AccountQuotaWindow(AccountQuotaWindowKind.other, name: field0),
            },
            percentage: quota.percentage,
            used: quota.used,
            total: quota.total,
            remaining: quota.remaining,
            resetAt: quota.resetAt?.toInt(),
            details: [
              for (final detail in quota.details)
                AccountQuotaDetail(
                  name: detail.name,
                  used: detail.used,
                  total: detail.total,
                  percentage: detail.percentage,
                ),
            ],
          ),
      ],
    ),
};

AccountCatalogView accountCatalogFromFrb(
  frb.BridgeAccountCatalogSnapshot snapshot,
) {
  return AccountCatalogView(
    schemaVersion: snapshot.schemaVersion,
    revision: snapshot.revision,
    templates: [
      for (final template in snapshot.templates)
        AccountTemplateView(
          id: template.id,
          displayName: template.displayName,
          description: template.description ?? '',
          baseUrl: template.baseUrl,
          credentialLabel: template.credentialLabel,
          credentialEnv: template.credentialEnv ?? '',
          modelCatalogId: template.modelCatalogId,
          protocol: template.protocol,
          suggestedModelId: template.suggestedModelId,
          defaultBillingKind: _billingKindFromFrb(template.defaultBillingKind),
          supportsModelDiscovery: template.supportsModelDiscovery,
          supportsUsageQuery: template.supportsUsageQuery,
          hostedWebSearch:
              template.serviceCapabilities.webSearch.hostedResponses,
          hostedWebSearchDialect:
              template.serviceCapabilities.webSearch.hostedDialect,
          standaloneWebSearch:
              template.serviceCapabilities.webSearch.standalone ?? '',
          promptCacheDialect: template.serviceCapabilities.promptCacheDialect,
          responsesProgrammaticToolCalling:
              template.serviceCapabilities.responsesProgrammaticToolCalling,
          iconKey: template.iconKey,
        ),
    ],
    modelCatalogs: {
      for (final catalog in snapshot.modelCatalogs)
        catalog.id: [
          for (final model in catalog.models) accountModelFromCatalog(model),
        ],
    },
  );
}

AccountModelView accountModelFromCatalog(frb.BridgeModelDescriptor model) {
  final capabilities = <String>[
    if (model.capabilities.streaming) 'streaming',
    if (model.capabilities.temperature) 'temperature',
    if (model.capabilities.reasoning) 'reasoning',
    if (model.capabilities.webSearch) 'web search',
    if (model.capabilities.functionCalling) 'tools',
    if (model.capabilities.parallelToolCalls) 'parallel tools',
    if (model.capabilities.customTools) 'custom tools',
    if (model.capabilities.freeformTools) 'freeform tools',
    if (model.capabilities.instructionSnapshotOverrides) '历史指令更新',
  ];
  final reasoning = model.reasoning;
  final pricing = model.pricing;
  return AccountModelView(
    modelId: model.modelId,
    enabled: model.enabled,
    typeSupport: [
      for (final support in model.typeSupport)
        ModelTypeSupportView(
          modelType: switch (support.modelType) {
            frb.BridgeModelType.text => ModelType.text,
          },
          exclusions: [
            for (final reason in support.exclusions)
              switch (reason) {
                frb.BridgeModelTypeExclusion.textInputUnsupported =>
                  ModelTypeExclusion.textInputUnsupported,
                frb.BridgeModelTypeExclusion.textOutputUnsupported =>
                  ModelTypeExclusion.textOutputUnsupported,
                frb.BridgeModelTypeExclusion.contextParametersInvalid =>
                  ModelTypeExclusion.contextParametersInvalid,
                frb.BridgeModelTypeExclusion.inputBudgetExhausted =>
                  ModelTypeExclusion.inputBudgetExhausted,
                frb.BridgeModelTypeExclusion.contextWindowUnknown =>
                  ModelTypeExclusion.contextWindowUnknown,
              },
          ],
        ),
    ],
    displayName: model.displayName,
    description: model.description ?? '',
    contextWindow: model.contextWindow?.toInt(),
    maxContextWindow: model.maxContextWindow?.toInt(),
    context: ModelContextView(
      unavailable: switch (model.context.unavailable) {
        null => null,
        frb.BridgeModelContextUnavailable.windowUnknown =>
          ModelContextUnavailable.windowUnknown,
        frb.BridgeModelContextUnavailable.invalidParameters =>
          ModelContextUnavailable.invalidParameters,
        frb.BridgeModelContextUnavailable.inputBudgetExhausted =>
          ModelContextUnavailable.inputBudgetExhausted,
      },
      contextWindow: model.context.contextWindow?.toInt(),
      inputTokenLimit: model.context.inputTokenLimit?.toInt(),
      autoCompactLimit: model.context.autoCompactLimit?.toInt(),
      adjustment: model.context.adjustment == null
          ? null
          : ModelContextAdjustment.safetyLimit,
    ),
    maxOutputTokens: model.maxOutputTokens?.toInt(),
    inputCapabilities: model.capabilities.input
        .map(_modelInputCapabilityFromFrb)
        .toList(),
    outputModalities: [
      for (final modality in model.capabilities.output)
        _modelModalityFromFrb(modality),
    ],
    capabilities: capabilities,
    reasoningEfforts: reasoning?.candidates ?? const [],
    reasoningLabel: reasoning?.label ?? '',
    defaultReasoningEffort: reasoning?.defaultCandidate ?? '',
    currency: pricing?.currency ?? '',
    priceSource: pricing?.source ?? '',
    priceVerifiedAt: pricing?.verifiedAt.toInt(),
    priceTiers: [
      for (final tier in pricing?.tiers ?? <frb.BridgeModelPriceTier>[])
        ModelPriceTierView(
          label: tier.label,
          input: tier.inputPerMtok,
          output: tier.outputPerMtok,
          cacheRead: tier.cacheReadPerMtok,
          cacheWrite: tier.cacheWritePerMtok,
        ),
    ],
    wireApi: model.transport.protocol,
    supportedConnectionModes: [
      for (final mode in model.transport.connectionModes) mode.id,
    ],
    defaultConnectionMode: model.transport.defaultConnectionMode,
    connectionMode: model.transport.defaultConnectionMode,
    origin: switch (model.origin) {
      frb.BridgeModelOrigin.bundled => ModelOrigin.bundled,
      frb.BridgeModelOrigin.online => ModelOrigin.online,
      frb.BridgeModelOrigin.manual => ModelOrigin.manual,
    },
  );
}

ModelModalityView _modelModalityFromFrb(frb.BridgeModelModality modality) {
  return switch (modality) {
    frb.BridgeModelModality.text => ModelModalityView.text,
    frb.BridgeModelModality.image => ModelModalityView.image,
    frb.BridgeModelModality.audio => ModelModalityView.audio,
    frb.BridgeModelModality.video => ModelModalityView.video,
    frb.BridgeModelModality.file => ModelModalityView.file,
  };
}

ModelInputCapabilityView _modelInputCapabilityFromFrb(
  frb.BridgeModelInputCapability capability,
) => ModelInputCapabilityView(
  modality: _modelModalityFromFrb(capability.modality),
  sources: [
    for (final source in capability.sources)
      switch (source) {
        frb.BridgeModelInputSource.local => ModelInputSourceView.local,
        frb.BridgeModelInputSource.remoteUrl => ModelInputSourceView.remoteUrl,
      },
  ],
  maxCount: capability.maxCount,
  maxBytes: capability.maxBytes?.toInt(),
  maxTotalBytes: capability.maxTotalBytes?.toInt(),
  maxWidth: capability.maxWidth,
  maxHeight: capability.maxHeight,
  mediaTypes: capability.mediaTypes,
);
