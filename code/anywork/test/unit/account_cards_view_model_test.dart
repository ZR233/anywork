import 'dart:async';

import 'package:anywork/src/features/settings/accounts/state/account_presentations.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_card_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/account_projection.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accounts_view_models_test.dart';

const _alpha = AccountDisplayKey(kind: AccountKind.acp, id: 'alpha');
const _beta = AccountDisplayKey(kind: AccountKind.acp, id: 'beta');
const _quota = AcpUsageObservationView(
  checkedAt: 12,
  state: AcpUsageReadyView(
    groups: [
      AcpQuotaGroupView(
        name: 'Gemini',
        limits: [
          AcpQuotaLimitView(
            label: 'Fast',
            remaining: AcpQuotaPercentageView(40),
          ),
        ],
      ),
    ],
  ),
);
const _failure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'Quota request failed',
  retryable: true,
  correlationId: 'card-request',
);

AccountsVmHarness _harness({int? revision = 1, bool beta = true}) {
  final h = AccountsVmHarness();
  h.acp.holdUsageRefreshRequests = true;
  _summaries(h, revision: revision, beta: beta);
  addTearDown(() {
    h.dispose();
    for (final request in h.acp.usageRefreshRequests) {
      if (!request.completion.isCompleted) {
        request.completion.complete(AcpUsageRefreshDisposition.cancelled);
      }
    }
  });
  return h;
}

void _summaries(
  AccountsVmHarness h, {
  int? revision = 1,
  bool alpha = true,
  bool beta = true,
  String owner = 'owner',
  bool stale = false,
}) => h.accounts.state.publish(
  AccountsState(
    stamp: ResourceStamp(resourceKey: 'test', ownerEpoch: owner, revision: 1),
    templates: h.accounts.state.value.templates,
    stale: stale,
    accounts: [
      vmSummary(const NativeAccountIdentity('native'), name: 'Native'),
      if (alpha)
        vmSummary(
          const AcpAccountIdentity('alpha'),
          name: 'Alpha',
          acpRevision: revision,
        ),
      if (beta) vmSummary(const AcpAccountIdentity('beta'), name: 'Beta'),
    ],
  ),
);

void _auth(
  AccountsVmHarness h, {
  String owner = 'owner',
  bool stale = false,
  List<AcpAuthAccountView> accounts = const [],
}) => h.acp.auth.publish(
  AccountResource(
    stamp: ResourceStamp(resourceKey: 'test', ownerEpoch: owner, revision: 1),
    stale: stale,
    value: AcpAuthSnapshotView(revision: 1, updatedAt: 1, accounts: accounts),
  ),
);

AcpAuthAccountView _authAccount(String id, {int revision = 1}) =>
    AcpAuthAccountView(
      accountId: id,
      connectionRevision: revision,
      state: const AcpVerifiedState(checkedAt: 1, server: null),
      usage: _quota,
    );

AccountRowPresentation _row(AccountsVmHarness h, AccountDisplayKey key) =>
    h.container.read(accountCardViewModelProvider(key)).requireValue!;

AcpUsagePresentation? _usage(AccountsVmHarness h, AccountDisplayKey key) =>
    (_row(h, key).content as AcpAccountRowContent).usage;

List<VmAcpUsageRefreshRequest> _requests(AccountsVmHarness h, String id) => h
    .acp
    .usageRefreshRequests
    .where((request) => request.identity.accountId == id)
    .toList();

void main() {
  test(
    'one account action does not publish sibling card projections',
    () async {
      final h = _harness();
      final owner = await h.listOwner();
      await h.container.pump();
      final completion = Completer<OperationState>();
      h.accounts.defaultWrite = () => completion.future;
      final alpha = _row(h, _alpha);
      final beta = _row(h, _beta);
      var alphaPublications = 0;
      var betaPublications = 0;
      var nativePublications = 0;
      h.container.listen(
        accountCardViewModelProvider(_alpha),
        (_, _) => alphaPublications++,
      );
      h.container.listen(
        accountCardViewModelProvider(_beta),
        (_, _) => betaPublications++,
      );
      h.container.listen(
        accountCardViewModelProvider(nativeKey),
        (_, _) => nativePublications++,
      );
      final action = owner.setDefault(nativeKey);
      expect(_row(h, nativeKey).actions, isEmpty);
      expect(alphaPublications, 0);
      expect(betaPublications, 0);
      expect(nativePublications, greaterThan(0));
      completion.complete(savedVmOperation('card-default'));
      expect(await action, isTrue);
      await h.container.pump();
      expect(_row(h, nativeKey).actions, contains(AccountRowAction.setDefault));
      expect(alphaPublications, 0);
      expect(betaPublications, 0);
      expect(_row(h, _alpha), alpha);
      expect(_row(h, _beta), beta);
    },
  );

  test(
    'list rebuild cancels only its retired observations and pending intents',
    () async {
      final h = _harness();
      await h.listOwner();
      await h.container.pump();
      final oldAlpha = _requests(h, 'alpha').single;
      final oldBeta = _requests(h, 'beta').single;
      h.container.invalidate(accountsViewModelProvider);
      await h.container.read(accountsViewModelProvider.future);
      h.container.read(accountsViewModelProvider.notifier).setVisible(true);
      await h.container.pump();
      expect(oldAlpha.pendingCancels, 1);
      expect(oldBeta.pendingCancels, 1);
      expect(_requests(h, 'alpha'), hasLength(2));
      expect(_requests(h, 'beta'), hasLength(2));
      final currentAlpha = _requests(h, 'alpha').last;
      final currentBeta = _requests(h, 'beta').last;
      expect(currentAlpha.pendingCancels, 0);
      expect(currentBeta.pendingCancels, 0);
      oldAlpha.completion.completeError(_failure);
      oldBeta.completion.complete(AcpUsageRefreshDisposition.cancelled);
      await h.container.pump();
      _auth(h, accounts: [_authAccount('alpha'), _authAccount('beta')]);
      expect(_row(h, _alpha).operationError, isNull);
      expect(_usage(h, _alpha)!.queried, isTrue);
      expect(_usage(h, _beta)!.queried, isTrue);
      expect(currentAlpha.pendingCancels, 0);
      expect(currentBeta.pendingCancels, 0);
      expect(h.acp.authCancels, isEmpty);
    },
  );

  test('reentrant cancellation and an old lease cannot detach the replacement scope', () async {
    final h = _harness(beta: false);
    final owner = await h.listOwner();
    await h.container.pump();
    final cancelOld = h.container
        .read(accountCardViewModelProvider(_alpha).notifier)
        .cancellationForCurrentObservation();
    final old = _requests(h, 'alpha').single;
    old.onPendingCancel = () {
      old.onPendingCancel = null;
      _summaries(h, revision: 3, beta: false);
    };
    _summaries(h, revision: 2, beta: false);
    await h.container.pump();
    expect(_requests(h, 'alpha').map((request) => request.connectionRevision), [
      1,
      3,
    ]);
    final current = _requests(h, 'alpha').last;
    expect(old.pendingCancels, 1);
    expect(current.pendingCancels, 0);
    expect(h.acp.demands.first.releases, 1);
    expect(h.acp.demands.last.releases, 0);
    cancelOld();
    cancelOld();
    _auth(h, accounts: [_authAccount('alpha', revision: 3)]);
    expect(_usage(h, _alpha)!.queried, isTrue);
    expect(current.pendingCancels, 0);
    expect(h.acp.demands.last.releases, 0);
    owner.setVisible(false);
    expect(current.pendingCancels, 1);
    expect(h.acp.demands.last.releases, 1);
    expect(h.acp.authCancels, isEmpty);
  });

  test('ACP initial registration waits for valid sources and revision, then survives filtering once', () async {
    final h = _harness(revision: null, beta: false);
    h.acp.auth.publish(const AccountResource());
    final owner = await h.listOwner();
    await h.container.pump();
    expect(h.acp.usageRefreshRequests, isEmpty);
    _auth(h);
    await h.container.pump();
    expect(h.acp.usageRefreshRequests, isEmpty);
    _summaries(h, revision: 4, beta: false);
    await h.container.pump();
    final request = h.acp.usageRefreshRequests.single;
    expect(request.connectionRevision, 4);
    final card = h.container.read(
      accountCardViewModelProvider(_alpha).notifier,
    );
    owner.search('Native');
    owner.setVisible(true);
    h.container.read(accountCardViewModelProvider(_alpha));
    _auth(h);
    await h.container.pump();
    expect(
      h.container.read(accountCardViewModelProvider(_alpha).notifier),
      same(card),
    );
    expect(h.acp.usageRefreshRequests, [request]);
    expect(request.pendingCancels, 0);
    expect(h.usage.refreshes, [const NativeAccountIdentity('native')]);
    owner.setVisible(false);
    expect(request.pendingCancels, 1);
    request.completion.complete(AcpUsageRefreshDisposition.cancelled);
    await h.container.pump();
    expect(h.acp.authCancels, isEmpty);
    expect(h.acp.usageQueries, isEmpty);
  });

  test('explicit single and all refresh register independently, including hidden ACP members', () async {
    final h = _harness();
    final nativeGate = Completer<void>();
    addTearDown(() {
      if (!nativeGate.isCompleted) nativeGate.complete();
    });
    h.usage.onRefresh = (_) => nativeGate.future;
    final owner = await h.listOwner();
    await h.container.pump();
    expect(h.acp.usageRefreshRequests, hasLength(2));
    expect(h.usage.refreshes, hasLength(1));
    final single = owner.refresh(_alpha);
    expect(_requests(h, 'alpha'), hasLength(2));
    expect(_requests(h, 'beta'), hasLength(1));
    final explicitAlpha = _requests(h, 'alpha').last;
    explicitAlpha.completion.complete(AcpUsageRefreshDisposition.joined);
    await single;
    expect(_usage(h, _alpha), isNull, reason: 'Joining is not a quota result');
    owner.search('Native');
    final all = owner.refreshAll();
    expect(_requests(h, 'alpha'), hasLength(3));
    expect(_requests(h, 'beta'), hasLength(2));
    expect(h.usage.refreshes, hasLength(2));
    final allAlpha = _requests(h, 'alpha').last;
    final allBeta = _requests(h, 'beta').last;
    allBeta.completion.complete(AcpUsageRefreshDisposition.started);
    allAlpha.completion.complete(AcpUsageRefreshDisposition.joined);
    nativeGate.complete();
    await all;
    expect(_usage(h, _beta), isNull, reason: 'Starting is not a quota result');
    owner.setVisible(false);
    expect(_requests(h, 'alpha').first.pendingCancels, 1);
    expect(_requests(h, 'beta').first.pendingCancels, 1);
    expect(explicitAlpha.pendingCancels, 0);
    expect(allAlpha.pendingCancels, 0);
    expect(allBeta.pendingCancels, 0);
    expect(h.acp.authStarts, isEmpty);
    expect(h.acp.starts, isEmpty);
  });

  test('ACP quota and request failures publish only their card, without deriving quota from dispositions', () async {
    final h = _harness();
    await h.listOwner();
    await h.container.pump();
    var listPublications = 0;
    var alphaPublications = 0;
    var betaPublications = 0;
    h.container.listen(accountsViewModelProvider, (_, _) => listPublications++);
    h.container.listen(
      accountCardViewModelProvider(_alpha),
      (_, _) => alphaPublications++,
    );
    h.container.listen(
      accountCardViewModelProvider(_beta),
      (_, _) => betaPublications++,
    );
    _requests(
      h,
      'beta',
    ).single.completion.complete(AcpUsageRefreshDisposition.started);
    await h.container.pump();
    expect(_usage(h, _beta), isNull);
    expect(betaPublications, 0);
    _auth(h, accounts: [_authAccount('beta')]);
    expect(_usage(h, _beta)!.groups.single.quotas.single.remaining, '40%');
    expect(alphaPublications, 0);
    expect(betaPublications, 1);
    expect(listPublications, 0);
    final beforeBeta = _row(h, _beta);
    _requests(h, 'alpha').single.completion.completeError(_failure);
    await h.container.pump();
    expect(_row(h, _alpha).operationError, _failure.message);
    expect(_row(h, _beta), same(beforeBeta));
    expect(betaPublications, 1);
    expect(listPublications, 0);
    expect(alphaPublications, 1);
  });

  test('auth observation retains login requirements, preparation and cleanup errors with last-good quota', () async {
    final h = _harness(beta: false);
    final owner = await h.listOwner();
    owner.setStrings(
      const AccountStrings({
        'acp.needsLogin': 'Login required',
        'acp.failed': 'Failed',
      }),
    );
    await h.container.pump();
    _requests(
      h,
      'alpha',
    ).single.completion.complete(AcpUsageRefreshDisposition.started);
    await h.container.pump();
    _auth(
      h,
      accounts: [
        const AcpAuthAccountView(
          accountId: 'alpha',
          connectionRevision: 1,
          state: AcpRequiredState(operationId: 'auth', server: null),
          usage: _quota,
        ),
      ],
    );
    expect(
      (_row(h, _alpha).content as AcpAccountRowContent).status,
      'Login required',
    );
    expect(_usage(h, _alpha)!.groups.single.quotas.single.remaining, '40%');
    for (final failure in const [
      AcpAuthFailureView(
        code: AcpAuthFailureCodeView.preparationRequired,
        stage: AcpAuthStageView.prepare,
        message: 'Preparation required',
        retryable: true,
      ),
      AcpAuthFailureView(
        code: AcpAuthFailureCodeView.cleanup,
        stage: AcpAuthStageView.cleanup,
        message: 'Cleanup failed',
        retryable: false,
      ),
    ]) {
      _auth(
        h,
        accounts: [
          AcpAuthAccountView(
            accountId: 'alpha',
            connectionRevision: 1,
            state: AcpFailedState(failure: failure),
            usage: _quota,
          ),
        ],
      );
      expect(
        (_row(h, _alpha).content as AcpAccountRowContent).status,
        'Failed',
      );
      expect(_row(h, _alpha).operationError, failure.message);
      expect(_usage(h, _alpha)!.groups.single.quotas.single.remaining, '40%');
    }
    expect(h.acp.usageRefreshRequests, hasLength(1));
    expect(h.acp.starts, isEmpty);
    expect(h.acp.authStarts, isEmpty);
    expect(h.acp.authCancels, isEmpty);
  });

  test('connection and owner replacement cancel pending intents and reject late old results and readouts', () async {
    final h = _harness();
    await h.listOwner();
    await h.container.pump();
    final oldRequest = _requests(h, 'alpha').single;
    final betaRequest = _requests(h, 'beta').single;
    final betaRow = _row(h, _beta);
    _summaries(h, revision: 2);
    await h.container.pump();
    final current = _requests(h, 'alpha').last;
    expect(_requests(h, 'alpha').map((request) => request.connectionRevision), [
      1,
      2,
    ]);
    expect(oldRequest.pendingCancels, 1);
    expect(current.pendingCancels, 0);
    expect(_requests(h, 'beta'), [betaRequest]);
    expect(betaRequest.pendingCancels, 0);
    expect(_row(h, _beta), betaRow);
    _auth(h, accounts: [_authAccount('alpha')]);
    expect(_usage(h, _alpha), isNull);
    oldRequest.completion.completeError(_failure);
    await h.container.pump();
    expect(_row(h, _alpha).operationError, isNull);
    expect(_requests(h, 'alpha').map((request) => request.connectionRevision), [
      1,
      2,
    ]);
    expect(current.pendingCancels, 0);
    expect(_requests(h, 'beta'), [betaRequest]);
    expect(betaRequest.pendingCancels, 0);
    expect(_row(h, _beta), betaRow);
    _auth(h, accounts: [_authAccount('alpha', revision: 2)]);
    expect(_usage(h, _alpha)!.queried, isTrue);
    _summaries(h, revision: 2, owner: 'replacement-owner');
    await h.container.pump();
    expect(current.pendingCancels, 1);
    expect(
      _usage(h, _alpha),
      isNull,
      reason: 'Old owner readouts are not new owner data',
    );
    expect(
      _requests(h, 'alpha'),
      hasLength(2),
      reason: 'Wait for the new auth source',
    );
    _auth(h, owner: 'replacement-owner');
    await h.container.pump();
    expect(_requests(h, 'alpha'), hasLength(3));
    expect(_requests(h, 'alpha').last.connectionRevision, 2);
    current.completion.completeError(_failure);
    await h.container.pump();
    expect(_row(h, _alpha).operationError, isNull);
    expect(h.acp.authCancels, isEmpty);
  });

  test('leaving and deletion cancel only owned pending requests; late dispositions cannot restart cards', () async {
    final h = _harness();
    final owner = await h.listOwner();
    await h.container.pump();
    final alpha = _requests(h, 'alpha').single;
    final beta = _requests(h, 'beta').single;
    _summaries(h, alpha: false);
    await h.container.pump();
    expect(alpha.pendingCancels, 1);
    expect(beta.pendingCancels, 0);
    alpha.completion.complete(AcpUsageRefreshDisposition.started);
    await h.container.pump();
    expect(_requests(h, 'alpha'), hasLength(1));
    expect(
      h.container.read(accountsViewModelProvider).requireValue.list.members,
      isNot(contains(_alpha)),
    );
    owner.setVisible(false);
    expect(beta.pendingCancels, 1);
    beta.completion.completeError(_failure);
    await h.container.pump();
    owner.setVisible(true);
    await h.container.pump();
    expect(_requests(h, 'beta'), hasLength(2));
    expect(_row(h, _beta).operationError, isNull);
    expect(h.acp.authCancels, isEmpty);
  });

  test('stale auth revokes pending registration without guessing or retrying its action', () async {
    final h = _harness(beta: false);
    final owner = await h.listOwner();
    await h.container.pump();
    final request = _requests(h, 'alpha').single;
    _auth(h, stale: true);
    expect(request.pendingCancels, 1);
    _auth(h);
    owner.search('Native');
    owner.setVisible(true);
    await h.container.pump();
    expect(_requests(h, 'alpha'), [request]);
    request.completion.complete(AcpUsageRefreshDisposition.cancelled);
    await h.container.pump();
    expect(_row(h, _alpha).operationError, isNull);
    owner.setVisible(false);
    await h.container.pump();
    owner.setVisible(true);
    await h.container.pump();
    expect(_requests(h, 'alpha'), hasLength(2));
  });

  test('reentrant source retirement cancels the handle returned after registration', () async {
    final h = _harness(beta: false);
    h.acp.onUsageRefreshRequest = (_) =>
        _summaries(h, alpha: false, beta: false);
    await h.listOwner();
    await h.container.pump();
    final request = h.acp.usageRefreshRequests.single;
    expect(request.pendingCancels, 1);
    request.completion.completeError(_failure);
    await h.container.pump();
    expect(h.rows.map((row) => row.key), [nativeKey]);
    expect(h.acp.authCancels, isEmpty);
  });
}
