import '../../models/account_models.dart';
import '../../models/delegation_models.dart';

/// Snapshot collection ownership at the adapter/domain boundary. Existing model
/// descriptors are reused by route consumers, but never expose mutable lists.
AccountModelView immutableModelDescriptor(AccountModelView model) =>
    model.copyWith(
      reasoningEfforts: List.unmodifiable(model.reasoningEfforts),
      typeSupport: List.unmodifiable([
        for (final support in model.typeSupport)
          ModelTypeSupportView(
            modelType: support.modelType,
            exclusions: List.unmodifiable(support.exclusions),
          ),
      ]),
      inputCapabilities: List.unmodifiable([
        for (final capability in model.inputCapabilities)
          ModelInputCapabilityView(
            modality: capability.modality,
            sources: List.unmodifiable(capability.sources),
            maxCount: capability.maxCount,
            maxBytes: capability.maxBytes,
            maxTotalBytes: capability.maxTotalBytes,
            maxWidth: capability.maxWidth,
            maxHeight: capability.maxHeight,
            mediaTypes: List.unmodifiable(capability.mediaTypes),
          ),
      ]),
      outputModalities: List.unmodifiable(model.outputModalities),
      capabilities: List.unmodifiable(model.capabilities),
      priceTiers: List.unmodifiable(model.priceTiers),
      supportedConnectionModes: List.unmodifiable(
        model.supportedConnectionModes,
      ),
    );

DelegationModelDetail immutableModelDetail(DelegationModelDetail detail) =>
    DelegationModelDetail(
      key: detail.key,
      accountName: detail.accountName,
      descriptor: immutableModelDescriptor(detail.descriptor),
      available: detail.available,
      unavailableReason: detail.unavailableReason,
      billingKind: detail.billingKind,
      guide: detail.guide == null
          ? null
          : ModelSelectionGuide(
              summary: detail.guide!.summary,
              taskSuitability: List.unmodifiable(detail.guide!.taskSuitability),
              limitations: List.unmodifiable(detail.guide!.limitations),
              sources: List.unmodifiable(detail.guide!.sources),
            ),
      performance: detail.performance,
      evaluations: detail.evaluations,
      recentEvaluations: List.unmodifiable(detail.recentEvaluations),
    );
