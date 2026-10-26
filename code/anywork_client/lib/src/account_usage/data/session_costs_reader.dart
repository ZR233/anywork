import '../../../resources.dart';
import '../domain/session_costs_values.dart';
import 'account_read_fields.dart';
import 'session_costs_port.dart';
import 'session_costs_reads.dart';

/// Reads one root-session cost inside its original pinned scope. The returned
/// root identity must be the borrowed one; a scope that answers for another root
/// is a protocol failure, not another session's cost.
Future<SessionCost?> readSessionCost(
  SessionCostsReadConnection scope,
  String rootThreadId,
) async {
  final read = (await scope.header()).cost;
  if (read == null) return null;
  Future<String> text(ReadText value) => readAccountText(value, scope.text);
  Future<List<RuntimeCost>> amounts(TypedListRef reference) async {
    final values = await readAccountList<RuntimeCostRead>(reference, (
      offset,
    ) async {
      final page = await scope.amounts(
        reference.listId,
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
    return List.unmodifiable([
      for (final value in values)
        RuntimeCost(currency: await text(value.currency), amount: value.amount),
    ]);
  }

  final root = await text(read.rootThreadId);
  if (root != rootThreadId)
    throw accountDataProtocol(
      'The session cost scope returned another root Thread.',
    );
  final purposes = await readAccountList<PurposeCostRead>(read.purposeCosts, (
    offset,
  ) async {
    final page = await scope.purposes(
      read.purposeCosts.listId,
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
  return SessionCost(
    rootThreadId: root,
    purposeCosts: List.unmodifiable([
      for (final purpose in purposes)
        PurposeCost(
          purpose: purpose.purpose == null
              ? null
              : await text(purpose.purpose!),
          estimatedCosts: await amounts(purpose.estimatedCosts),
          hasUnpricedUsage: purpose.hasUnpricedUsage,
        ),
    ]),
    estimatedCosts: await amounts(read.estimatedCosts),
    hasUnpricedUsage: read.hasUnpricedUsage,
  );
}
