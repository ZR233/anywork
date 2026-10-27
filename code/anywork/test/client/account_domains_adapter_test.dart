import 'dart:async';

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart'
    show OperationId, LspTopic, StudioFailure;
import 'package:flutter_test/flutter_test.dart';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/accounts/types.dart'
    as frb_accounts;
import 'package:anywork/src/rust/api/studio/types/command.dart' as frb_command;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;

/// Only supplies generated DTOs. The production transport performs target and
/// summary conversion; no native library or parallel mapper is installed.
final class _SummaryBridgeApi implements RustLibApi {
  late frb_accounts.BridgeAccountDomainFrame frame;
  final targets = <frb_accounts.BridgeAccountObservationTarget>[];

  @override
  Future<frb_accounts.BridgeAccountDomainFrame>
  crateApiStudioAccountsFeedReadAccountDomain({
    required frb_accounts.BridgeAccountObservationTarget target,
  }) async {
    targets.add(target);
    return frame;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

Future<void> _close(AppGraph graph) async {
  final report = await graph.close(
    deadline: DateTime.now().add(const Duration(seconds: 2)),
  );
  expect(
    report.complete,
    isTrue,
    reason: '${report.unresolved.map((value) => value.reason)}',
  );
}

void main() {
  test('FRB summaries preserve typed ACP connection revisions without loading details', () async {
    final api = _SummaryBridgeApi();
    RustLib.initMock(api: api);
    FrbStudioTransport.debugOverrideInitialization(() async {});
    addTearDown(() {
      FrbStudioTransport.debugOverrideInitialization(null);
      RustLib.dispose();
    });
    final transport = FrbStudioTransport();
    const capabilities = frb_accounts.BridgeAccountCapabilities(
      setDefault: false,
      edit: true,
      remove: true,
      queryUsage: false,
      syncModels: false,
      editModels: false,
      acpAuth: true,
    );
    for (final connectionRevision in [0, 9007199254740993]) {
      api.frame = frb_accounts.BridgeAccountDomainFrame.summaries(
        stamp: frb_command.BridgeResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: 'summary-owner',
          revision: BigInt.from(99),
        ),
        accounts: [
          const frb_accounts.BridgeAccountSummary(
            identity: frb_accounts.BridgeAccountIdentity.native(
              accountId: 'same',
            ),
            name: 'Same name',
            isDefault: false,
            capabilities: capabilities,
          ),
          frb_accounts.BridgeAccountSummary(
            identity: const frb_accounts.BridgeAccountIdentity.acp(
              accountId: 'same',
            ),
            name: 'Same name',
            isDefault: false,
            capabilities: capabilities,
            acpConnectionRevision: BigInt.from(connectionRevision),
          ),
        ],
      );
      final frame = await transport.readAccountDomain(
        const AccountSummariesTarget(),
      ) as AccountSummariesFrame;
      final native = frame.accounts.singleWhere(
        (account) => account.identity == const NativeAccountIdentity('same'),
      );
      final acp = frame.accounts.singleWhere(
        (account) => account.identity == const AcpAccountIdentity('same'),
      );
      expect(native.acpConnectionRevision, isNull);
      expect(
        acp.acpConnectionRevision,
        connectionRevision,
        reason: 'Zero is not null and a u64 within Dart int range must not pass through double',
      );
      expect(frame.stamp.revision, 99);
    }
    expect(api.targets, const [
      frb_accounts.BridgeAccountObservationTarget.summaries(),
      frb_accounts.BridgeAccountObservationTarget.summaries(),
    ]);
  });

  test('demo shutdown cancels accepted install and LSP timers before reporting clean', () async {
    final timers = <Timer>[];
    addTearDown(() {
      for (final timer in timers) {
        timer.cancel();
      }
    });
    await runZoned(
      () async {
        final transport = DemoStudioTransport(lspActivityLoop: true);
        final lsp = transport
            .subscribeProductTopic(const LspTopic())
            .listen((_) {});
        addTearDown(lsp.cancel);
        await transport.startAcpInstall(
          operationId: const OperationId('shutdown-install'),
          provider: AcpProviderView.antigravity,
        );
        expect(timers.where((timer) => timer.isActive), isNotEmpty);
        await transport.beginRuntimeExit(remainingMs: 1000);
        final issues = await transport.cancelDartSubscriptions(budgetMs: 1000);
        expect(issues, isEmpty);
        expect(
          timers.where((timer) => timer.isActive),
          isEmpty,
          reason: 'Closing display observations cannot stand in for stopping accepted business timers',
        );
        final frame = await transport.readAccountDomain(
          const AcpInstallTarget(),
        ) as AcpInstallFrame;
        expect(
          frame.snapshot.stateOf(AcpProviderView.antigravity),
          isA<AcpInstallCancelledState>(),
        );
        await expectLater(
          transport.startAcpInstall(
            operationId: const OperationId('after-exit'),
            provider: AcpProviderView.antigravity,
          ),
          throwsA(isA<StudioFailure>()),
        );
        final shutdown = await transport.shutdownRuntime(remainingMs: 2000);
        expect(shutdown.shutdown.isClean, isTrue);
        expect(timers.where((timer) => timer.isActive), isEmpty);
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, period, callback) {
          final timer = parent.createPeriodicTimer(zone, period, callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
  });
  test('demo ports drive the real SDK domains without retaining account cards in general settings', () async {
    final graph = AppGraph.demo();
    addTearDown(() => _close(graph));
    await graph.initialize();
    final demand = graph.accounts.observeSummaries();
    addTearDown(demand.release);
    final initial = await graph.accounts.state.waitFor((state) => state.loaded);
    expect(initial.accounts, isNotEmpty);
    expect(
      graph.models.state.value.accounts,
      isEmpty,
      reason: 'The account list did not request the shared catalog',
    );
    expect(graph.client.settings.state.canonical!.accounts, isEmpty);
    expect(graph.client.settings.state.canonical!.acpAccounts, isEmpty);
    await graph.accounts.loadTemplates();
    final template = graph.accounts.state.value.templates.templates.first;
    const identity = NativeAccountIdentity('adapter-contract');
    const model = AccountModelIdentity(
      account: identity,
      modelId: 'manual-contract',
    );
    final created = await graph.accounts.create(
      CreateAccountCommand(
        identity: identity,
        name: 'Contract account',
        protocol: template.protocol,
        templateId: template.id,
        baseUrl: template.baseUrl,
        secret: const AccountSecretCommand.replace('synthetic-demo-only'),
        customModels: const [
          AccountModelCommand(
            modelId: 'manual-contract',
            displayName: 'Manual contract',
            wireApi: 'chat_completions',
            contextWindow: 65536,
            maxOutputTokens: 8192,
          ),
        ],
      ),
    );
    expect(created.observed, isTrue);
    final configured = graph.models.state.value.accounts[identity]!.value!;
    expect(configured.model(model.modelId)!.origin, ModelOrigin.manual);
    await graph.models.setAutoCompact(model, AutoCompactIntent.set(12345));
    expect(
      graph
          .models
          .state
          .value
          .configurations[identity]!
          .value!
          .autoCompactLimits[model.modelId],
      12345,
    );
    await graph.accounts.patch(
      const PatchAccountCommand(
        identity: identity,
        name: AccountTextPatch.set('Renamed only'),
      ),
    );
    expect(
      (graph.accounts.details(identity).value.value as NativeAccountDetails)
          .name,
      'Renamed only',
    );
    expect(
      graph
          .models
          .state
          .value
          .configurations[identity]!
          .value!
          .autoCompactLimits[model.modelId],
      12345,
      reason: 'Name patch did not replay stale model overrides',
    );
    await graph.models.removeManual(model);
    expect(
      graph.models.state.value.accounts[identity]!.value!.model(model.modelId),
      isNull,
    );
    expect(
      graph
          .models
          .state
          .value
          .configurations[identity]!
          .value!
          .autoCompactLimits
          .containsKey(model.modelId),
      isFalse,
    );
    await graph.accountUsage.refresh(identity);
    expect(
      graph.accountUsage.state.value.value![identity]!.phase,
      AccountUsagePhase.unsupported,
    );
    expect(
      graph.accounts.state.value.account(identity)!.billingKind,
      isNot(BillingKind.noCharge),
    );
    await graph.accounts.remove(identity);
    expect(graph.accounts.details(identity).value.loaded, isTrue);
    expect(graph.accounts.details(identity).value.value, isNull);
    expect(graph.models.state.value.accounts[identity]!.value, isNull);
  });

  test(
    'demo pull observation has one pending next and close really joins it',
    () async {
      final transport = DemoStudioTransport();
      final observation = await transport.openAccountObservation(
        const AccountSummariesTarget(),
      );
      final initial = await observation.next() as AccountSummariesFrame;
      final native = initial.accounts.first;
      expect(native.identity, isA<NativeAccountIdentity>());
      expect(native.acpConnectionRevision, isNull);
      var revision = initial.stamp.revision;
      for (final name in ['Original', 'Renamed only']) {
        final reply = await transport.saveAcpAccount(
          revision,
          AcpAccountUpdateView(
            accountId: native.identity.accountId,
            name: name,
            provider: AcpProviderView.antigravity,
          ),
          operationId: OperationId('summary-save-$revision'),
        );
        revision = reply.snapshot.revision;
        final summary = await observation.next() as AccountSummariesFrame;
        final acp = summary.accounts.singleWhere(
          (account) =>
              account.identity == AcpAccountIdentity(native.identity.accountId),
        );
        expect(acp.acpConnectionRevision, 1);
        expect(
          acp.acpConnectionRevision,
          reply.snapshot.acpAccounts.single.connectionRevision,
        );
        expect(
          summary.accounts
              .singleWhere((account) => account.identity == native.identity)
              .acpConnectionRevision,
          isNull,
        );
      }
      final waiting = observation.next();
      await expectLater(observation.next(), throwsStateError);
      observation.requestClose();
      expect(await waiting, isNull);
      await observation.close();
      final issues = await transport.cancelDartSubscriptions(budgetMs: 1000);
      expect(issues, isEmpty);
      await expectLater(
        transport.openAccountObservation(const AccountUsageTarget()),
        throwsStateError,
      );
    },
  );

  test('two AppGraphs use independent account canonical values and model directories', () async {
    final first = AppGraph.demo();
    final second = AppGraph.demo();
    addTearDown(() => _close(first));
    addTearDown(() => _close(second));
    await first.initialize();
    await second.initialize();
    await first.accounts.loadTemplates();
    final template = first.accounts.state.value.templates.templates.first;
    const identity = NativeAccountIdentity('only-first');
    await first.accounts.create(
      CreateAccountCommand(
        identity: identity,
        name: 'Only first',
        protocol: template.protocol,
        templateId: template.id,
        baseUrl: template.baseUrl,
        secret: const AccountSecretCommand.replace('synthetic-demo-only'),
      ),
    );
    expect(
      first.accounts.details(identity).value.value,
      isA<NativeAccountDetails>(),
    );
    expect(second.accounts.details(identity).value.loaded, isFalse);
    expect(second.models.state.value.accounts, isEmpty);
    expect(
      identical(first.client.settingsWrites, second.client.settingsWrites),
      isFalse,
    );
    // The transport remains a real typed port, not an app/UI fake branch.
    final rejected = (first.client.transport as AccountConfigurationPort)
        .createAccount(
          first.client.settingsWrites.stamp!.revision,
          CreateAccountCommand(
            identity: identity,
            name: 'Duplicate',
            protocol: template.protocol,
            templateId: template.id,
            baseUrl: template.baseUrl,
            secret: const AccountSecretCommand.preserve(),
          ),
          operationId: const OperationId('duplicate'),
        );
    await expectLater(rejected, throwsArgumentError);
  });
}
