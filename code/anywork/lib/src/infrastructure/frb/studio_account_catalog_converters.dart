part of 'studio_api.dart';

AccountCatalogView accountCatalogFromFrb(
  frb.BridgeAccountCatalogSnapshot snapshot,
) {
  return AccountCatalogView(
    schemaVersion: snapshot.schemaVersion,
    revision: snapshot.revision,
    templates: [
      for (final template in snapshot.templates)
        AccountTemplateView(
          pricingEnabled: template.pricingEnabled,
          id: template.id,
          displayName: template.displayName,
          description: template.description ?? '',
          baseUrl: template.baseUrl,
          credentialLabel: template.credentialLabel,
          credentialEnv: template.credentialEnv ?? '',
          modelCatalogId: template.modelCatalogId,
          protocol: template.protocol,
          suggestedModelId: template.suggestedModelId,
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
