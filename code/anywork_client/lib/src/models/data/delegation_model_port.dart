import '../../../resources.dart';
import '../domain/delegation_model_values.dart';
import 'delegation_model_reads.dart';
import 'model_field_read_connection.dart';

/// Native ModelReadScope lifecycle, not an HTTP/raw snapshot fallback. Opening
/// must resolve target.sources.reference in the original Configuration pairing
/// owner, verify the entire issued credential and pin its original material.
/// Expired material fails; echoing targets or reading current is not proof.
/// Guide/performance/evaluations are immutable after this scope opens, without
/// promising a cross-database transaction with the configuration/catalog pair.
abstract interface class DelegationModelReadConnection
    implements ModelFieldReadConnection {
  /// Original native scope identity, independent of descriptor conversion.
  /// Remains readable after Clean/dispose; never inferred from a close report.
  /// If initially unavailable, only the same original handle may recover it.
  String get scopeId;
  ProductReadScopeIdentity get identity;
  DelegationModelReadTarget get target;
  Future<DelegationModelReadHeader> header();
  Future<ModelSelectionSourceReadPage> selectionSources(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<AgentEvaluationReadPage> evaluations(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
