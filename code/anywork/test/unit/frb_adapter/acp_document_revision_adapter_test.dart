import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/accounts/types.dart' as account_dto;
import 'package:anywork/src/rust/api/studio/types/acp.dart' as acp_dto;
import 'package:anywork/src/rust/api/studio/types/command.dart' as command_dto;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart'
    show OperationId, StudioFailure;
import 'package:flutter_test/flutter_test.dart';

// Only supplies/records generated DTOs. The production transport owns all
// mapping; this boundary has no CAS, retry, or parallel conversion logic.
final class _AcpDocumentBoundary implements RustLibApi {
  _AcpDocumentBoundary(this.documentRevision);

  final BigInt documentRevision;
  final reads = <account_dto.BridgeAccountObservationTarget>[];
  final saves =
      <
        ({
          String operationId,
          BigInt settingsRevision,
          BigInt? documentRevision,
          acp_dto.BridgeAcpAccountUpdate account,
        })
      >[];
  final removals =
      <
        ({
          String operationId,
          BigInt settingsRevision,
          BigInt documentRevision,
          String accountId,
        })
      >[];

  @override
  Future<account_dto.BridgeAccountDomainFrame>
  crateApiStudioAccountsFeedReadAccountDomain({
    required account_dto.BridgeAccountObservationTarget target,
  }) async {
    reads.add(target);
    return account_dto.BridgeAccountDomainFrame.detail(
      stamp: command_dto.BridgeResourceStamp(
        resourceKey: 'settings',
        ownerEpoch: 'acp-document-test',
        revision: BigInt.from(9),
      ),
      identity: const account_dto.BridgeAccountIdentity.acp(
        accountId: 'local-command',
      ),
      account: account_dto.BridgeAccountDetail.acp(
        acp_dto.BridgeAcpAccountSettings(
          accountId: 'local-command',
          name: 'Local command',
          command: 'test-agent',
          enabled: true,
          args: const ['acp', 'two words', ''],
          env: const {'TEST_MODE': 'preview'},
          documentRevision: documentRevision,
          connectionRevision: BigInt.from(7),
        ),
      ),
    );
  }

  @override
  Future<command_dto.BridgeSettingsCommandReply>
  crateApiStudioHandlersAcpSaveAcpAccount({
    required String operationId,
    required BigInt expectedSettingsRevision,
    BigInt? expectedDocumentRevision,
    required acp_dto.BridgeAcpAccountUpdate account,
  }) async {
    saves.add((
      operationId: operationId,
      settingsRevision: expectedSettingsRevision,
      documentRevision: expectedDocumentRevision,
      account: account,
    ));
    // Stop after dispatch, without native side effects or fabricated success.
    throw StateError('stopped at generated API boundary');
  }

  @override
  Future<command_dto.BridgeSettingsCommandReply>
  crateApiStudioHandlersAcpRemoveAcpAccount({
    required String operationId,
    required BigInt expectedSettingsRevision,
    required String accountId,
    required BigInt expectedDocumentRevision,
  }) async {
    removals.add((
      operationId: operationId,
      settingsRevision: expectedSettingsRevision,
      documentRevision: expectedDocumentRevision,
      accountId: accountId,
    ));
    throw StateError('stopped at generated API boundary');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

void main() {
  for (final revision in [
    BigInt.parse('9223372036854775808'),
    BigInt.parse('18446744073709551615'),
  ]) {
    test('production FRB preserves ACP document u64 $revision', () async {
      final api = _AcpDocumentBoundary(revision);
      RustLib.initMock(api: api);
      FrbStudioTransport.debugOverrideInitialization(() async {});
      addTearDown(() {
        FrbStudioTransport.debugOverrideInitialization(null);
        RustLib.dispose();
      });
      final transport = FrbStudioTransport();
      const identity = AcpAccountIdentity('local-command');
      final frame = await transport.readAccountDomain(
        const AccountDetailTarget(identity),
      ) as AccountDetailFrame;
      final saved = (frame.account! as AcpAccountDetails).account;
      expect(api.reads, [
        const account_dto.BridgeAccountObservationTarget.detail(
          identity: account_dto.BridgeAccountIdentity.acp(
            accountId: 'local-command',
          ),
        ),
      ]);
      expect(frame.identity, identity);
      expect(frame.stamp.revision, 9);
      expect(saved.documentRevision, revision);
      expect(saved.connectionRevision, 7);
      expect(saved.accountId, identity.accountId);
      expect(saved.template, isNull);
      expect(saved.command, 'test-agent');
      expect(saved.args, ['acp', 'two words', '']);
      expect(saved.env, {'TEST_MODE': 'preview'});
      final update = AcpAccountUpdateView(
        accountId: saved.accountId,
        name: 'Renamed',
        command: saved.command,
        args: saved.args,
        env: saved.env,
        enabled: saved.enabled,
        template: saved.template,
      );
      await expectLater(
        transport.saveAcpAccount(
          frame.stamp.revision,
          update,
          operationId: const OperationId('update-once'),
          expectedDocumentRevision: saved.documentRevision,
        ),
        throwsA(isA<StudioFailure>()),
      );
      final sent = api.saves.single;
      expect(sent.operationId, 'update-once');
      expect(sent.settingsRevision, BigInt.from(9));
      expect(sent.documentRevision, revision);
      expect(sent.account.accountId, saved.accountId);
      expect(sent.account.name, 'Renamed');
      expect(sent.account.command, saved.command);
      expect(sent.account.args, saved.args);
      expect(sent.account.env, saved.env);
      expect(sent.account.enabled, saved.enabled);
      expect(sent.account.template, isNull);

      await expectLater(
        transport.removeAcpAccount(
          frame.stamp.revision,
          saved.accountId,
          operationId: const OperationId('remove-once'),
          expectedDocumentRevision: saved.documentRevision,
        ),
        throwsA(isA<StudioFailure>()),
      );
      expect(api.removals.single, (
        operationId: 'remove-once',
        settingsRevision: BigInt.from(9),
        documentRevision: revision,
        accountId: saved.accountId,
      ));
      await expectLater(
        transport.saveAcpAccount(
          frame.stamp.revision,
          update,
          operationId: const OperationId('create-once'),
          expectedDocumentRevision: null,
        ),
        throwsA(isA<StudioFailure>()),
      );
      expect(api.saves, hasLength(2));
      expect(api.saves.last.operationId, 'create-once');
      expect(api.saves.last.documentRevision, isNull);
    });
  }
}
