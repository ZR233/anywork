import '../../../resources.dart';
import '../../../resources_ports.dart' show resourceCancelled, resourceProtocol;
import '../../configuration/domain/configuration_state.dart'
    show ConfigurationRoleReadTarget;
import '../domain/delegation_model_values.dart';
import '../domain/model_evaluation_values.dart';
import '../domain/model_guide_values.dart';
import '../domain/model_values.dart';
import 'delegation_model_port.dart';
import 'delegation_model_reads.dart';
import 'model_reader.dart';

Future<DelegationModelDetail> readDelegationModel(
  DelegationModelReadConnection scope,
  DelegationModelReadTarget target,
) async {
  _validateSources(target.sources);
  final catalog = target.sources.catalog;
  final identity = scope.identity;
  final version = identity.version;
  if (scope.target != target ||
      identity.scopeId.isEmpty ||
      identity.ownerEpoch != catalog.origin.ownerEpoch ||
      identity.incarnation != catalog.origin.incarnation ||
      version is! ProductValueReadVersion ||
      version.entry != catalog.reference.entry ||
      version.revision != catalog.reference.revision) {
    throw resourceProtocol(
      'The exact-model read opened another catalog origin or target.',
    );
  }
  final header = await scope.header();
  if (scope.identity != identity ||
      scope.target != target ||
      header.scope != identity ||
      header.target != target) {
    throw resourceProtocol(
      'Model reference fields belong to another original read scope.',
    );
  }
  if (header.recentEvaluations.total < 0 ||
      header.recentEvaluations.total > 10) {
    throw resourceProtocol(
      'The native model evaluation window exceeds its bound.',
    );
  }
  final access = ModelFieldReadAccess(scope);
  final descriptor = await access.model(header.descriptor);
  if (descriptor.modelId != target.model.modelId) {
    throw resourceProtocol('The native detail returned a different model.');
  }
  final evaluations = await readModelList<AgentEvaluationRead>(
    header.recentEvaluations,
    (offset) async {
      final page = await scope.evaluations(
        header.recentEvaluations.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    },
  );
  final recent = <AgentEvaluation>[];
  final children = <String>{};
  for (final value in evaluations) {
    final evaluation = await _evaluation(access, value);
    if (evaluation.model.model != target.model ||
        !children.add(evaluation.agentId)) {
      throw resourceProtocol(
        'The model evaluation window changed account/model or repeated a child.',
      );
    }
    recent.add(evaluation);
  }
  return DelegationModelDetail(
    target: target,
    scope: identity,
    accountName: await access.string(header.accountName),
    descriptor: descriptor,
    available: header.available,
    unavailableReason: await access.optional(header.unavailableReason),
    billingKind: header.billingKind,
    guide: await _guide(scope, access, header.guide),
    performance: header.performance,
    evaluations: header.evaluations,
    recentEvaluations: recent,
  );
}

/// Only structural consistency and the complete echo can be checked in Dart.
/// Ref revisions, business clocks and source incarnations are distinct domains;
/// their compatibility must be proven by native lookup of this pair reference,
/// never inferred from numeric equality or a current Configuration read.
void _validateSources(ConfigurationRoleReadTarget sources) {
  final configuration = sources.configuration;
  final catalog = sources.catalog;
  if (sources.reference.entry < 0 ||
      sources.reference.revision < 0 ||
      configuration.origin.ownerEpoch.isEmpty ||
      configuration.origin.incarnation < 0 ||
      configuration.reference.entry < 0 ||
      configuration.reference.revision < 0 ||
      catalog.origin.ownerEpoch.isEmpty ||
      catalog.origin.incarnation < 0 ||
      catalog.reference.entry < 0 ||
      catalog.reference.revision < 0 ||
      sources.stamp.settingsRevision < 0 ||
      sources.stamp.modelCatalogRevision < 0) {
    throw resourceProtocol(
      'The model detail pairing credential has invalid origins, refs or source clocks.',
    );
  }
  if (sources.stamp.closing) throw resourceCancelled;
}

Future<ModelSelectionGuide?> _guide(
  DelegationModelReadConnection scope,
  ModelFieldReadAccess access,
  ModelSelectionGuideRead? value,
) async {
  if (value == null) return null;
  if (value.sources.total < 0 || value.sources.total > 6) {
    throw resourceProtocol('The model guide exceeds its native source bound.');
  }
  final sources = await readModelList<ModelSelectionSourceRead>(value.sources, (
    offset,
  ) async {
    final page = await scope.selectionSources(
      value.sources.listId,
      offset: offset,
      limit: 32,
    );
    return (
      listId: page.listId,
      offset: page.offset,
      total: page.total,
      items: page.items,
      nextOffset: page.nextOffset,
    );
  });
  return ModelSelectionGuide(
    summary: await access.string(value.summary),
    taskSuitability: value.taskSuitability,
    limitations: await access.stringList(value.limitations),
    sources: [
      for (final source in sources)
        ModelSelectionSource(
          kind: source.kind,
          url: await access.string(source.url),
          verifiedAt: source.verifiedAt,
          measurement: await _measurement(access, source.measurement),
        ),
    ],
  );
}

Future<ModelSelectionMeasurement?> _measurement(
  ModelFieldReadAccess access,
  ModelSelectionMeasurementRead? value,
) async => value == null
    ? null
    : ModelSelectionMeasurement(
        model: await access.string(value.model),
        effort: await access.optional(value.effort),
        metric: await access.string(value.metric),
        metricVersion: await access.optional(value.metricVersion),
        score: value.score,
      );

Future<AgentEvaluation> _evaluation(
  ModelFieldReadAccess access,
  AgentEvaluationRead value,
) async => AgentEvaluation(
  agentId: await access.string(value.agentId),
  parentAgentId: await access.string(value.parentAgentId),
  model: ModelSelection(
    model: AccountModelKey(
      accountId: await access.string(value.accountId),
      modelId: await access.string(value.modelId),
    ),
    effort: await access.optional(value.effort),
  ),
  profileId: await access.string(value.profileId),
  mode: value.mode,
  preference: value.preference,
  turnId: await access.string(value.turnId),
  revision: value.revision,
  taskCategory: value.taskCategory,
  outcome: value.outcome,
  quality: value.quality,
  instructionFollowing: value.instructionFollowing,
  comment: await access.string(value.comment),
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
);
