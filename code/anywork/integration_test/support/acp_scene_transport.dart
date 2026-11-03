import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';

import '../../../anywork_client/test/support/accounts_test_runtime.dart';

/// External transport responses are controlled. AppGraph, the SDK Client,
/// command lanes, account feeds, Riverpod and all widgets remain production code.
class AcpSceneTransport extends DemoStudioTransport {
  final _observers = <TestAccountObservation>{};
  AcpAuthSnapshotView snapshot = const AcpAuthSnapshotView.empty();
  String? _epoch;
  int starts = 0;
  int continuations = 0;
  int cancels = 0;
  String? target;
  String? method;

  @override
  Future<SettingsCommandReply> saveAcpAccount(
    int expectedSettingsRevision,
    AcpAccountUpdateView account, {
    required OperationId operationId,
  }) async => _committedAccountWrite(
    await super.saveAcpAccount(
      expectedSettingsRevision,
      account,
      operationId: operationId,
    ),
  );

  @override
  Future<SettingsCommandReply> removeAcpAccount(
    int expectedSettingsRevision,
    String accountId, {
    required OperationId operationId,
  }) async => _committedAccountWrite(
    await super.removeAcpAccount(
      expectedSettingsRevision,
      accountId,
      operationId: operationId,
    ),
  );

  // The controlled endpoint acknowledges account commits. Demo deliberately
  // never claims durability; returning its volatile receipt would leave the
  // production deletion waiting correctly for a commit that cannot arrive.
  SettingsCommandReply _committedAccountWrite(SettingsCommandReply reply) {
    final receipt = reply.receipt;
    return SettingsCommandReply(
      snapshot: reply.snapshot,
      accountFrames: reply.accountFrames,
      receipt: StudioCommandReceipt(
        operationId: receipt.operationId,
        disposition: receipt.disposition,
        targets: receipt.targets,
        effect: receipt.effect,
        effective: receipt.effective,
        durable: true,
        requiresIdentityObservation: receipt.requiresIdentityObservation,
      ),
    );
  }

  static const methods = [
    AcpAuthMethodView(
      id: 'browser',
      name: 'Browser',
      kind: AcpAuthMethodKindView.agent,
    ),
    AcpAuthMethodView(
      id: 'other',
      name: 'Other browser',
      kind: AcpAuthMethodKindView.agent,
    ),
  ];
  static const server = AcpServerInfoView(
    name: 'antigravity',
    version: '1.4.5',
  );

  ResourceStamp get stamp => ResourceStamp(
    resourceKey: 'acp-auth',
    ownerEpoch: _epoch!,
    revision: snapshot.revision,
  );

  @override
  Future<AccountDomainFrame> readAccountDomain(
    AccountObservationTarget target,
  ) async {
    final original = await super.readAccountDomain(target);
    if (target is! AcpAuthTarget) return original;
    _epoch = original.stamp.ownerEpoch;
    return AcpAuthFrame(stamp, snapshot);
  }

  @override
  Future<AccountDomainObservation> openAccountObservation(
    AccountObservationTarget target,
  ) async {
    if (target is! AcpAuthTarget) return super.openAccountObservation(target);
    await readAccountDomain(target);
    late TestAccountObservation observation;
    observation = TestAccountObservation(() => _observers.remove(observation));
    _observers.add(observation);
    observation.emit(AcpAuthFrame(stamp, snapshot));
    return observation;
  }

  void publish(String accountId, int revision, AcpAuthStateView state) {
    snapshot = AcpAuthSnapshotView(
      revision: snapshot.revision + 1,
      updatedAt: snapshot.updatedAt + 1,
      accounts: [
        AcpAuthAccountView(
          accountId: accountId,
          connectionRevision: revision,
          state: state,
        ),
      ],
    );
    for (final observer in _observers.toList()) {
      observer.emit(AcpAuthFrame(stamp, snapshot));
    }
  }

  AcpAuthCommandReply reply(OperationId operationId) => AcpAuthCommandReply(
    snapshot: snapshot,
    receipt: StudioCommandReceipt(
      operationId: operationId,
      disposition: CommitDisposition.applied,
      targets: [stamp],
      effect: EffectPoint.immediate,
      effective: true,
      durable: false,
    ),
  );

  @override
  Future<AcpAuthCommandReply> startAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required AcpAuthActionView action,
  }) async {
    starts++;
    target = operationId.value;
    publish(
      accountId,
      expectedConnectionRevision,
      AcpRequiredState(operationId: target!, server: server, methods: methods),
    );
    return reply(operationId);
  }

  @override
  Future<AcpAuthCommandReply> continueAcpAuth({
    required OperationId operationId,
    required String accountId,
    required int expectedConnectionRevision,
    required OperationId targetOperationId,
    required String methodId,
  }) async {
    if (targetOperationId.value != target) {
      throw StateError('Stale continuation');
    }
    continuations++;
    method = methodId;
    publish(
      accountId,
      expectedConnectionRevision,
      AcpAuthenticatingState(operationId: target!, methodId: methodId),
    );
    return reply(operationId);
  }

  @override
  Future<AcpAuthCommandReply> cancelAcpAuth({
    required OperationId operationId,
    required String accountId,
    required OperationId targetOperationId,
  }) async {
    if (targetOperationId.value != target) {
      throw StateError('Stale cancellation');
    }
    cancels++;
    final revision = snapshot.accounts.single.connectionRevision;
    publish(accountId, revision, const AcpCancelledState());
    return reply(operationId);
  }
}
