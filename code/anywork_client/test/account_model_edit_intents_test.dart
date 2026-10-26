import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models.dart' show BillingKind;
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_command_fixture.dart';
import 'support/configuration_fixture.dart';

AccountConfiguration _account() => AccountConfiguration(
  accountId: 'fixture',
  templateId: 'template-a',
  protocol: 'openai',
  name: 'Canonical account',
  baseUrl: 'https://fixture.invalid',
  hasBearerToken: true,
  bearerTokenEnv: null,
  billingKind: BillingKind.metered,
  billingKindOverride: null,
  disabledModels: const [],
  usageQueryRevision: 9,
  catalogId: 'catalog',
  customModels: [
    customModel('alpha'),
    customModel('beta', contextWindow: 2000),
  ],
  modelConnectionModes: const [
    ModelConnection(modelId: 'alpha', connectionMode: 'http'),
    ModelConnection(modelId: 'beta', connectionMode: 'auto'),
    ModelConnection(modelId: 'online-not-displayed', connectionMode: 'http'),
  ],
  modelAutoCompactLimits: const [
    ModelAutoCompact(modelId: 'alpha', overrideLimit: 111),
    ModelAutoCompact(modelId: 'beta', overrideLimit: 250),
    ModelAutoCompact(modelId: 'online-not-displayed', overrideLimit: 777),
  ],
);

Future<ConfigurationFixture> _fixture({AccountConfiguration? account}) async {
  final fixture = ConfigurationFixture();
  await fixture.establish(account ?? _account());
  addTearDown(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      fixture.repository.close(deadline: deadline),
      fixture.models.close(deadline: deadline),
    ]);
    expect(reports.expand((report) => report.unresolved), isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

Map<String, int> _limits(AccountSettingsUpdate update) => {
  for (final item in update.modelAutoCompactLimits) item.modelId: item.limit,
};
Map<String, String> _connections(AccountSettingsUpdate update) => {
  for (final item in update.modelConnectionModes)
    item.modelId: item.connectionMode,
};

const _nativeRefusal = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The scripted native boundary declined this prepared write',
  retryable: false,
  correlationId: 'configuration-native-refusal',
);

/// The real Repository must construct the correct full native request before
/// native validation can accept or reject it. Explicit rejection then proves
/// there was no optimistic canonical edit or fabricated command receipt.
Future<void> _reject(
  RecordedConfigurationCall<UpdateAccountRequest> call,
  OperationTicket<Unit> ticket,
) async {
  await call.native.resultRead(0);
  call.native
      .resultAt(0)
      .reply
      .completeError(
        const CommandDispatchFailure.rejected(failure: _nativeRefusal),
      );
  final result = await ticket.result;
  expect(result, isA<RejectedCommandResult<Unit>>());
  expect((result as RejectedCommandResult<Unit>).error, _nativeRefusal);
  final closing = await call.native.closed(0);
  expect(closing.retry, isFalse);
  expect(call.native.requestCloseCalls, 1);
  closing.reply.complete(
    FeedCloseReport(
      feedId: call.native.callId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

void main() {
  test('rename moves the explicit limit, drops the old connection and freezes caller-owned edits', () async {
    final fixture = await _fixture();
    final changes = <CustomModelChange>[
      CustomModelChange.upsert(
        originalModelId: 'alpha',
        value: modelUpdate('renamed'),
      ),
    ];
    final ticket = fixture.repository.saveAccount(accountEdit(models: changes));
    changes.clear();
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(call.request.expectedRevision, 1);
    expect(update.customModels.map((model) => model.modelId), [
      'renamed',
      'beta',
    ]);
    expect(_limits(update), {
      'renamed': 111,
      'beta': 250,
      'online-not-displayed': 777,
    });
    expect(_connections(update), {
      'beta': 'auto',
      'online-not-displayed': 'http',
    });
    expect(update.secret, isA<PreserveAccountSecret>());
    await _reject(call, ticket);
    expect(
      await fixture.repository.loadAccount('fixture'),
      _account(),
      reason: 'A rejected native write must not install the prepared rename',
    );
  });

  test('wire API changes clear old transport overrides before applying explicit new choices', () async {
    final fixture = await _fixture();
    for (final explicit in [false, true]) {
      final ticket = fixture.repository.saveAccount(
        accountEdit(
          models: [
            CustomModelChange.upsert(
              originalModelId: 'alpha',
              value: modelUpdate('alpha', wireApi: 'responses'),
            ),
          ],
          connections: explicit
              ? const [
                  ModelConnectionChange(
                    modelId: 'alpha',
                    connectionMode: 'auto',
                  ),
                ]
              : const [],
        ),
      );
      final call = await fixture.port.saved(explicit ? 1 : 0);
      expect(call.request.account.customModels.first.wireApi, 'responses');
      expect(_connections(call.request.account), {
        if (explicit) 'alpha': 'auto',
        'beta': 'auto',
        'online-not-displayed': 'http',
      });
      expect(_limits(call.request.account), {
        'alpha': 111,
        'beta': 250,
        'online-not-displayed': 777,
      });
      await _reject(call, ticket);
    }
  });

  test('removal clears both associated overrides without filtering unrelated catalog-only members', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(
      accountEdit(models: const [CustomModelChange.remove(modelId: 'alpha')]),
    );
    final call = await fixture.port.saved(0);
    expect(call.request.account.customModels.map((model) => model.modelId), [
      'beta',
    ]);
    expect(_limits(call.request.account), {
      'beta': 250,
      'online-not-displayed': 777,
    });
    expect(_connections(call.request.account), {
      'beta': 'auto',
      'online-not-displayed': 'http',
    });
    await _reject(call, ticket);
  });

  test(
    'ordinary model metadata changes preserve overrides and unknown capacities',
    () async {
      final fixture = await _fixture();
      final ticket = fixture.repository.saveAccount(
        accountEdit(
          models: [
            CustomModelChange.upsert(
              originalModelId: 'alpha',
              value: modelUpdate(
                'alpha',
                name: 'New display name',
                maxOutputTokens: 4096,
              ),
            ),
          ],
        ),
      );
      final call = await fixture.port.saved(0);
      expect(
        call.request.account.customModels.first.displayName,
        'New display name',
      );
      expect(call.request.account.customModels.first.contextWindow, isNull);
      expect(call.request.account.customModels.first.maxOutputTokens, 4096);
      expect(_connections(call.request.account), {
        'alpha': 'http',
        'beta': 'auto',
        'online-not-displayed': 'http',
      });
      expect(_limits(call.request.account), {
        'alpha': 111,
        'beta': 250,
        'online-not-displayed': 777,
      });
      await _reject(call, ticket);
    },
  );

  test(
    'renaming an account model with no explicit limit never manufactures one',
    () async {
      final initial = _account().copyWith(
        modelAutoCompactLimits: const [
          ModelAutoCompact(modelId: 'alpha', overrideLimit: null),
          ModelAutoCompact(modelId: 'beta', overrideLimit: 250),
        ],
      );
      final fixture = await _fixture(account: initial);
      final ticket = fixture.repository.saveAccount(
        accountEdit(
          models: [
            CustomModelChange.upsert(
              originalModelId: 'alpha',
              value: modelUpdate('renamed'),
            ),
          ],
        ),
      );
      final call = await fixture.port.saved(0);
      expect(_limits(call.request.account), {'beta': 250});
      await _reject(call, ticket);
    },
  );

  test('explicit same-template rebuild clears only the model configuration base before new intents', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(
      accountEdit(
        rebuild: true,
        // This remains an explicit rebuild even when the final template equals
        // the canonical ID, as it does after a UI A -> B -> A switch.
        templateId: const FieldEdit.set('template-a'),
        models: [
          CustomModelChange.upsert(
            originalModelId: null,
            value: modelUpdate('fresh'),
          ),
        ],
        connections: const [
          ModelConnectionChange(modelId: 'fresh', connectionMode: 'http'),
        ],
        limits: const [ModelLimitChange(modelId: 'fresh', overrideLimit: 123)],
      ),
    );
    final call = await fixture.port.saved(0);
    final update = call.request.account;
    expect(update.templateId, 'template-a');
    expect(update.customModels.map((model) => model.modelId), ['fresh']);
    expect(_connections(update), {'fresh': 'http'});
    expect(_limits(update), {'fresh': 123});
    expect(update.accountId, 'fixture');
    expect(update.name, 'Canonical account');
    expect(update.baseUrl, 'https://fixture.invalid');
    // 普通模型编辑不回传计费类别：初始类别只随创建提交。
    expect(update.initialBillingKind, isNull);
    expect(update.secret, isA<PreserveAccountSecret>());
    await _reject(call, ticket);
  });

  test(
    'rebuild without an explicit template is rejected before any native write',
    () async {
      final fixture = await _fixture();
      expect(
        () => fixture.repository.saveAccount(accountEdit(rebuild: true)),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
      expect(fixture.port.saves, isEmpty);
    },
  );

  test('CAS recovery rebuilds the same operation from the latest full canonical account', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(
      accountEdit(
        models: [
          CustomModelChange.upsert(
            originalModelId: 'alpha',
            value: modelUpdate('renamed'),
          ),
        ],
      ),
    );
    final first = await fixture.port.saved(0);
    expect(_limits(first.request.account)['renamed'], 111);
    final latest = _account().copyWith(
      name: 'External name',
      baseUrl: 'https://new.invalid',
      modelAutoCompactLimits: const [
        ModelAutoCompact(modelId: 'alpha', overrideLimit: 321),
        ModelAutoCompact(modelId: 'beta', overrideLimit: 450),
        ModelAutoCompact(modelId: 'online-not-displayed', overrideLimit: 999),
      ],
    );
    fixture.port.snapshots[2] = latest;
    const stale = StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'The native CAS base advanced',
      retryable: true,
      correlationId: 'stale-account',
    );
    await first.native.resultRead(0);
    first.native
        .resultAt(0)
        .reply
        .completeError(const CommandDispatchFailure.rejected(failure: stale));
    final closing = await first.native.closed(0);
    expect(fixture.port.saves, hasLength(1));
    expect(
      fixture.port.feeds,
      hasLength(1),
      reason:
          'No fresh CAS source is captured before the old native call is Clean',
    );
    closing.reply.complete(
      FeedCloseReport(
        feedId: first.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final replacement = await fixture.port.opened(1);
    await replacement.listened.future;
    fixture.port.baseline(replacement, 2);
    final retried = await fixture.port.saved(1);
    expect(retried.request.operationId, first.request.operationId);
    expect(retried.native.callId, isNot(first.native.callId));
    expect(retried.request.expectedRevision, 2);
    expect(retried.request.account.name, 'External name');
    expect(retried.request.account.baseUrl, 'https://new.invalid');
    expect(_limits(retried.request.account), {
      'renamed': 321,
      'beta': 450,
      'online-not-displayed': 999,
    });
    expect(_connections(retried.request.account), {
      'beta': 'auto',
      'online-not-displayed': 'http',
    });
    expect(fixture.port.readRevisions, [1, 2]);
    await retried.native.resultRead(0);
    retried.native
        .resultAt(0)
        .reply
        .completeError(const CommandDispatchFailure.rejected(failure: stale));
    final secondClose = await retried.native.closed(0);
    secondClose.reply.complete(
      FeedCloseReport(
        feedId: retried.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    final newest = latest.copyWith(usageQueryRevision: 10);
    fixture.port.snapshots[3] = newest;
    final lastSource = await fixture.port.opened(2);
    await lastSource.listened.future;
    fixture.port.baseline(lastSource, 3);
    final last = await fixture.port.saved(2);
    expect(last.request.operationId, first.request.operationId);
    expect(last.request.expectedRevision, 3);
    expect(last.request.account.name, 'External name');
    expect(last.request.account.secret, isA<PreserveAccountSecret>());
    expect(_limits(last.request.account), {
      'renamed': 321,
      'beta': 450,
      'online-not-displayed': 999,
    });
    await last.native.resultRead(0);
    last.native
        .resultAt(0)
        .reply
        .completeError(const CommandDispatchFailure.rejected(failure: stale));
    final lastClose = await last.native.closed(0);
    lastClose.reply.complete(
      FeedCloseReport(
        feedId: last.native.callId,
        outcome: const FeedCloseOutcome.clean(),
      ),
    );
    await Future.any<void>([
      ticket.result.then<void>((_) {}),
      fixture.port.opened(3).then<void>((_) {}),
      fixture.port.saved(3).then<void>((_) {}),
    ]);
    expect(
      fixture.port.saves,
      hasLength(3),
      reason:
          'The original business intention has at most three native attempts',
    );
    expect(
      fixture.port.feeds,
      hasLength(3),
      reason: 'Exhausted CAS retry must not capture a fourth source',
    );
    final result = await ticket.result;
    expect(result, isA<RejectedCommandResult<Unit>>());
    expect((result as RejectedCommandResult<Unit>).error, stale);
    expect(await fixture.repository.loadAccount('fixture'), newest);
  });

  test('model ID collisions remain visible to native validation rather than being silently resolved', () async {
    final fixture = await _fixture();
    final ticket = fixture.repository.saveAccount(
      accountEdit(
        models: [
          CustomModelChange.upsert(
            originalModelId: 'alpha',
            value: modelUpdate('beta'),
          ),
        ],
      ),
    );
    final call = await fixture.port.saved(0);
    expect(call.request.account.customModels.map((model) => model.modelId), [
      'beta',
      'beta',
    ]);
    await _reject(call, ticket);
    expect(await fixture.repository.loadAccount('fixture'), _account());
  });
}
