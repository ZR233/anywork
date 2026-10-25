import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/configuration_start_fixture.dart';

const _model = AccountModelKey(accountId: 'start-account', modelId: 'original');
const _selected = AccountModelKey(
  accountId: 'start-account',
  modelId: 'selected',
);
const _intent = StartRouteIntent(
  mode: ThreadModeId.task,
  model: _model,
  effort: ' raw effort ',
);
const _query = StartRouteQuery.resolve(intent: _intent);
const _route = ModelSelection(model: _model, effort: ' raw effort ');
const _defaults = DelegationSettings(
  mode: DelegationMode.automatic,
  preference: DelegationPreference.economy,
);
const _unavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The original native model is unavailable',
  retryable: false,
  correlationId: 'start-known-unavailable',
);
const _cleanupCancelled = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'Release a scripted boundary after a test has finished',
  retryable: false,
  correlationId: 'start-test-cleanup',
);
const _retryIssue = FeedCloseIssue(
  diagnostic: StudioShutdownIssue(
    stage: 'native-start',
    code: 'originalJoinPending',
    message: 'The original Start pin still needs close retry',
    retryable: true,
    correlationId: 'start-native-close',
  ),
  recovery: CleanupRecovery.retryClose,
);

StartRouteRead _ready(
  ConfigurationRoleReadTarget sources,
  StartRouteQuery query,
  StartRouteIntent intent, {
  ModelSelection route = _route,
}) => StartRouteRead.ready(
  sources: sources,
  query: query,
  intent: intent,
  route: route,
  defaults: _defaults,
);

Future<ConfigurationStartFixture> _fixture(
  ConfigurationRoleReadTarget sources, {
  ResourceBudget? budget,
}) async {
  final fixture = ConfigurationStartFixture(budget: budget);
  await fixture.establish(sources);
  addTearDown(() async {
    // Failure cleanup only: these cancellation replies never count as a test's
    // successful result, and every asserted path supplies its own native reply.
    for (final opening in fixture.opens) {
      if (!opening.reply.isCompleted)
        opening.reply.completeError(_cleanupCancelled);
      final pin = opening.native;
      if (pin == null) continue;
      for (final call in pin.calls) {
        if (!call.reply.isCompleted)
          call.reply.completeError(_cleanupCancelled);
      }
      final close = pin.closeReceipt;
      if (close != null && !close.isCompleted) {
        close.complete(
          FeedCloseReport(
            feedId: pin.id,
            outcome: const FeedCloseOutcome.clean(),
          ),
        );
      }
      pin.outcome = const FeedCloseOutcome.clean();
    }
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    final reports = await Future.wait([
      fixture.repository.retryCleanup(deadline: deadline),
      fixture.owner.models.close(deadline: deadline),
    ]);
    expect(reports.expand((report) => report.unresolved), isEmpty);
    expect(fixture.budget.usage, isEmpty);
  });
  return fixture;
}

Iterable<ResourceUsage> _startUsage(ConfigurationStartFixture fixture) =>
    fixture.budget.usage.where(
      (usage) =>
          usage.kind == ResourceKind.readModel &&
          usage.owner == 'configuration:start-read',
    );

Matcher get _protocol => isA<StudioFailure>().having(
  (error) => error.code,
  'code',
  StudioFailureCode.protocol,
);
Matcher get _cancelled => isA<StudioFailure>().having(
  (error) => error.code,
  'code',
  StudioFailureCode.cancelled,
);

void main() {
  test('equal original pair/query joins only in flight and a completed read does not cache native answers', () async {
    final sources = startSources();
    final fixture = await _fixture(sources);
    final before = fixture.repository.state.value;
    final first = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    final joined = fixture.repository.readStartRoute(
      sources: sources.copyWith(),
      query: StartRouteQuery.resolve(intent: _intent.copyWith()),
    );
    expect(identical(first, joined), isTrue);
    final opening = await fixture.opened(0);
    expect(opening.sources, sources);
    expect(fixture.opens, hasLength(1));
    final pin = opening.accept();
    final call = await pin.called(0);
    expect(call.query, _query);
    final native = _ready(sources, _query, _intent);
    call.reply.complete(native);
    expect(await Future.wait([first, joined]), [native, native]);
    expect(pin.calls, hasLength(1));

    final rechecked = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    await Future.any<void>([
      rechecked.then<void>((_) {}),
      pin.called(1).then<void>((_) {}),
    ]);
    expect(
      pin.calls,
      hasLength(2),
      reason: 'A completed Future is not a permanent route/defaults cache',
    );
    final next = await pin.called(1);
    next.reply.complete(native);
    expect(await rechecked, native);
    expect(
      fixture.opens,
      hasLength(1),
      reason:
          'Only the original immutable pin, not result Futures, is reusable',
    );
    expect(
      fixture.repository.state.value,
      before,
      reason: 'Borrowed Start results are not canonical configuration edits',
    );
  });

  test('native model-selection suggestions may normalize or clear effort without SDK policy', () async {
    final sources = startSources();
    final fixture = await _fixture(sources);
    const query = StartRouteQuery.selectModel(
      intent: _intent,
      selected: _selected,
    );
    final normalizedIntent = _intent.copyWith(
      model: _selected,
      effort: 'canonical-effort',
    );
    final normalized = StartRouteRead.ready(
      sources: sources,
      query: query,
      intent: normalizedIntent,
      route: const ModelSelection(model: _selected, effort: 'canonical-effort'),
      defaults: _defaults,
    );
    final reading = fixture.repository.readStartRoute(
      sources: sources,
      query: query,
    );
    final pin = (await fixture.opened(0)).accept();
    final call = await pin.called(0);
    expect(call.query, query);
    call.reply.complete(normalized);
    expect(await reading, normalized);

    final clearedIntent = _intent.copyWith(model: _selected, effort: null);
    final cleared = StartRouteRead.unavailable(
      sources: sources,
      query: query,
      intent: clearedIntent,
      desired: const ModelSelection(model: _selected, effort: null),
      defaults: _defaults,
      error: _unavailable,
    );
    final rereading = fixture.repository.readStartRoute(
      sources: sources,
      query: query,
    );
    final next = await pin.called(1);
    next.reply.complete(cleared);
    expect(
      await rereading,
      cleared,
      reason: 'A genuine native Unavailable and cleared effort remain business results, not SDK-invented policy',
    );
    expect(fixture.opens, hasLength(1));
  });

  test('different in-flight queries and original pairs never borrow one another\'s answer', () async {
    final original = startSources();
    final fixture = await _fixture(original);
    final first = fixture.repository.readStartRoute(
      sources: original,
      query: _query,
    );
    final firstPin = (await fixture.opened(0)).accept();
    final firstCall = await firstPin.called(0);
    final otherIntent = _intent.copyWith(effort: 'independent query');
    final otherQuery = StartRouteQuery.resolve(intent: otherIntent);
    final independent = fixture.repository.readStartRoute(
      sources: original,
      query: otherQuery,
    );
    final otherCall = await firstPin.called(1);
    final current = startSources(pairRevision: 8, catalogRevision: 41);
    await fixture.owner.port.publishPair(current);
    final replacement = fixture.repository.readStartRoute(
      sources: current,
      query: _query,
    );
    final nextPin = (await fixture.opened(1)).accept();
    final nextCall = await nextPin.called(0);
    final newer = _ready(current, _query, _intent);
    nextCall.reply.complete(newer);
    expect(await replacement, newer);
    expect(
      firstPin.closeCalls,
      0,
      reason: 'Original admitted queries are still waiting, not abandoned with the old source',
    );
    final older = _ready(original, _query, _intent);
    final other = _ready(
      original,
      otherQuery,
      otherIntent,
      route: const ModelSelection(model: _model, effort: 'independent query'),
    );
    firstCall.reply.complete(older);
    otherCall.reply.complete(other);
    expect(await first, older);
    expect(await independent, other);
    await firstPin.closeStarted.future;
    expect(firstPin.calls.map((call) => call.query), [_query, otherQuery]);
    expect(fixture.opens, hasLength(2));
    expect(fixture.repository.state.value.projection.header?.roleRead, current);
  });

  test('a wrong native header is rejected before resolve and does not poison a correct reread', () async {
    final sources = startSources();
    final fixture = await _fixture(sources);
    final before = fixture.repository.state.value;
    final reading = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    final rejected = expectLater(reading, throwsA(_protocol));
    final bad = (await fixture.opened(0))
        .accept(header: startSources(pairRevision: 8));
    await Future.any<void>([rejected, bad.called(0).then<void>((_) {})]);
    expect(
      bad.calls,
      isEmpty,
      reason: 'Do not query a scope that returned a foreign original pair',
    );
    await rejected;
    await bad.closeStarted.future;
    expect(fixture.repository.state.value, before);

    final corrected = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    final good = (await fixture.opened(1)).accept();
    final call = await good.called(0);
    final native = _ready(sources, _query, _intent);
    call.reply.complete(native);
    expect(await corrected, native);
    expect(bad.closeCalls, 1);
    expect(fixture.opens, hasLength(2));
  });

  final sources = startSources();
  final foreignPairs = <({String name, ConfigurationRoleReadTarget value})>[
    (
      name: 'pair reference',
      value: sources.copyWith(
        reference: const ConfigurationRoleReadRef(entry: 51, revision: 7),
      ),
    ),
    (
      name: 'configuration target',
      value: sources.copyWith(
        configuration: sources.configuration.copyWith(
          reference: const ConfigurationReadRef(entry: 2, revision: 1),
        ),
      ),
    ),
    (
      name: 'configuration origin',
      value: sources.copyWith(
        configuration: sources.configuration.copyWith(
          origin: const ProductReadOrigin(
            ownerEpoch: 'other-config-owner',
            incarnation: 1,
          ),
        ),
      ),
    ),
    (
      name: 'catalog target',
      value: sources.copyWith(
        catalog: sources.catalog.copyWith(
          reference: const ModelCatalogReadRef(entry: 9, revision: 40),
        ),
      ),
    ),
    (
      name: 'catalog origin',
      value: sources.copyWith(
        catalog: sources.catalog.copyWith(
          origin: const ProductReadOrigin(
            ownerEpoch: 'other-catalog-owner',
            incarnation: 3,
          ),
        ),
      ),
    ),
    (
      name: 'settings clock',
      value: sources.copyWith(
        stamp: sources.stamp.copyWith(settingsRevision: 2),
      ),
    ),
    (
      name: 'catalog clock',
      value: sources.copyWith(
        stamp: sources.stamp.copyWith(modelCatalogRevision: 141),
      ),
    ),
  ];
  final correctResolve = _ready(sources, _query, _intent);
  const selectQuery = StartRouteQuery.selectModel(
    intent: _intent,
    selected: _selected,
  );
  final correctSelection = _ready(
    sources,
    selectQuery,
    _intent.copyWith(model: _selected, effort: null),
    route: const ModelSelection(model: _selected, effort: null),
  );
  final corruptions =
      <({String name, StartRouteRead result, StartRouteRead correct})>[
        for (final pair in foreignPairs)
          (
            name: pair.name,
            result: _ready(pair.value, _query, _intent),
            correct: correctResolve,
          ),
        (
          name: 'query echo',
          correct: correctResolve,
          result: _ready(
            sources,
            StartRouteQuery.resolve(
              intent: _intent.copyWith(effort: 'foreign'),
            ),
            _intent,
          ),
        ),
        (
          name: 'resolve editing intent',
          correct: correctResolve,
          result: _ready(
            sources,
            _query,
            _intent.copyWith(effort: 'silently-normalized'),
          ),
        ),
        (
          name: 'selected model',
          correct: correctSelection,
          result: _ready(sources, selectQuery, _intent),
        ),
        (
          name: 'selection mode',
          correct: correctSelection,
          result: _ready(
            sources,
            selectQuery,
            _intent.copyWith(mode: ThreadModeId.simple, model: _selected),
            route: const ModelSelection(
              model: _selected,
              effort: ' raw effort ',
            ),
          ),
        ),
        (
          name: 'ready explicit route',
          correct: correctResolve,
          result: _ready(
            sources,
            _query,
            _intent,
            route: const ModelSelection(model: _selected, effort: 'foreign'),
          ),
        ),
        (
          name: 'unavailable explicit desired route',
          correct: correctResolve,
          result: StartRouteRead.unavailable(
            sources: sources,
            query: _query,
            intent: _intent,
            desired: const ModelSelection(model: _selected, effort: null),
            defaults: _defaults,
            error: _unavailable,
          ),
        ),
      ];
  for (final corruption in corruptions) {
    test(
      '${corruption.name} mismatch fails without canonical pollution or a permanent failed Future',
      () async {
        final fixture = await _fixture(sources);
        final before = fixture.repository.state.value;
        final reading = fixture.repository.readStartRoute(
          sources: sources,
          query: corruption.correct.query,
        );
        final rejected = expectLater(reading, throwsA(_protocol));
        final bad = (await fixture.opened(0)).accept();
        final call = await bad.called(0);
        call.reply.complete(corruption.result);
        await rejected;
        await bad.closeStarted.future;
        expect(fixture.repository.state.value, before);

        final corrected = fixture.repository.readStartRoute(
          sources: sources,
          query: corruption.correct.query,
        );
        final good = (await fixture.opened(1)).accept();
        final retry = await good.called(0);
        final native = corruption.correct;
        retry.reply.complete(native);
        expect(await corrected, native);
        expect(fixture.opens, hasLength(2));
        expect(bad.closeCalls, 1);
        expect(bad.calls, hasLength(1));
        expect(fixture.repository.state.value, before);
      },
    );
  }

  test('invalid pairing credentials and Closing fail before opening a native scope', () async {
    final fixture = await _fixture(sources);
    final before = fixture.repository.state.value;
    final malformed = sources.copyWith(
      reference: const ConfigurationRoleReadRef(entry: -1, revision: 7),
    );
    expect(
      () =>
          fixture.repository.readStartRoute(sources: malformed, query: _query),
      throwsA(_protocol),
    );
    final closing = sources.copyWith(
      stamp: sources.stamp.copyWith(closing: true),
    );
    expect(
      () => fixture.repository.readStartRoute(sources: closing, query: _query),
      throwsA(_cancelled),
    );
    expect(fixture.opens, isEmpty);
    expect(_startUsage(fixture), isEmpty);
    expect(fixture.repository.state.value, before);
  });

  for (final code in [
    StudioFailureCode.storage,
    StudioFailureCode.protocol,
    StudioFailureCode.cancelled,
  ]) {
    test(
      'native ${code.name} remains the original failure and a new explicit query can succeed',
      () async {
        final fixture = await _fixture(sources);
        final before = fixture.repository.state.value;
        final failure = StudioFailure(
          code: code,
          message: 'Original native ${code.name}',
          retryable: true,
          correlationId: 'start-native-${code.name}',
        );
        final reading = fixture.repository.readStartRoute(
          sources: sources,
          query: _query,
        );
        final rejected = expectLater(reading, throwsA(same(failure)));
        final opening = await fixture.opened(0);
        if (code == StudioFailureCode.storage) {
          opening.reply.completeError(failure);
        } else {
          final pin = opening.accept();
          final call = await pin.called(0);
          call.reply.completeError(failure);
          await pin.closeStarted.future;
        }
        await rejected;
        expect(fixture.repository.state.value, before);
        final intent = _intent.copyWith(effort: 'explicit retry');
        final query = StartRouteQuery.resolve(intent: intent);
        final retrying = fixture.repository.readStartRoute(
          sources: sources,
          query: query,
        );
        final pin = (await fixture.opened(1)).accept();
        final call = await pin.called(0);
        final native = _ready(
          sources,
          query,
          intent,
          route: const ModelSelection(model: _model, effort: 'explicit retry'),
        );
        call.reply.complete(native);
        expect(await retrying, native);
        expect(fixture.opens, hasLength(2));
      },
    );
  }

  test('a retired late open remains owned through close and the original native close barrier', () async {
    final fixture = await _fixture(sources);
    final reading = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    final cancelled = expectLater(reading, throwsA(_cancelled));
    final opening = await fixture.opened(
      0,
    ); // The real owner has entered port.openStartRead.
    await fixture.owner.port.publishPair(
      startSources(pairRevision: 8, catalogRevision: 41),
    );
    final pending = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(pending.complete, isFalse);
    final original = pending.unresolved.singleWhere(
      (item) =>
          item.owner == 'configuration:start-read' &&
          item.issues.any((issue) => issue.diagnostic.code == 'readPending'),
    );
    expect(_startUsage(fixture).single.phase, ResourcePhase.retiring);
    final receipt = Completer<FeedCloseReport>();
    final pin = opening.accept(closeReceipt: receipt);
    await pin.closeStarted.future;
    await cancelled;
    expect(
      pin.calls,
      isEmpty,
      reason: 'A late original open after seal must be handed off for close, not queried',
    );
    expect(pin.headerEntered.isCompleted, isFalse);
    final stillPending = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    expect(
      stillPending.unresolved.any(
        (item) =>
            item.owner == original.owner &&
            item.attemptId == original.attemptId,
      ),
      isTrue,
    );
    expect(_startUsage(fixture), hasLength(1));
    final joining = fixture.repository.retryCleanup();
    receipt.complete(
      FeedCloseReport(feedId: pin.id, outcome: const FeedCloseOutcome.clean()),
    );
    expect((await joining).complete, isTrue);
    expect(pin.closeCalls, 1);
    expect(
      pin.retryCloseCalls,
      0,
      reason: 'A retry while the original close is pending joins it, not a second native close',
    );
    expect(fixture.opens, hasLength(1));
    expect(fixture.budget.usage, isEmpty);
  });

  test('source retirement and native Clean cannot release a Start pin before its real admitted query settles', () async {
    final fixture = await _fixture(sources);
    final reading = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    final cancelled = expectLater(reading, throwsA(_cancelled));
    final pin = (await fixture.opened(0)).accept();
    final call = await pin.called(
      0,
    ); // Resolve has really entered its reply wait.
    await fixture.owner.port.publishPair(
      startSources(pairRevision: 8, catalogRevision: 41),
    );
    expect(
      pin.requestCloseCalls,
      0,
      reason:
          'Retiring a source lets the admitted original-version query finish',
    );
    expect(pin.closeCalls, 0);
    final pending = await fixture.repository.close(
      deadline: DateTime.utc(2000),
    );
    await pin.closeStarted.future; // Native already returned Clean, but the query has not returned.
    expect(pending.complete, isFalse);
    expect(
      pending.unresolved.any(
        (item) => item.owner == 'configuration:start-route',
      ),
      isTrue,
    );
    expect(_startUsage(fixture), hasLength(1));
    call.reply.complete(_ready(sources, _query, _intent));
    await cancelled;
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(pin.closeCalls, 1);
    expect(pin.retryCloseCalls, 0);
    expect(fixture.opens, hasLength(1));
    expect(fixture.budget.usage, isEmpty);
  });

  test('an Unresolved retired pin retains the shared budget and retryCleanup uses that same native scope', () async {
    final budget = ResourceBudget(
      capacities: {
        ResourceKind.readModel: 2,
        ResourceKind.observer: 16,
        ResourceKind.pendingOperation: 64,
      },
    );
    final fixture = await _fixture(sources, budget: budget);
    final reading = fixture.repository.readStartRoute(
      sources: sources,
      query: _query,
    );
    final opening = await fixture.opened(0);
    final pin = opening.accept();
    final call = await pin.called(0);
    final native = _ready(sources, _query, _intent);
    call.reply.complete(native);
    expect(await reading, native);
    pin.outcome = FeedCloseOutcome.unresolved(issues: [_retryIssue]);
    final current = startSources(pairRevision: 8, catalogRevision: 41);
    await fixture.owner.port.publishPair(current);
    await pin.closeStarted.future;
    final blocked = fixture.repository.readStartRoute(
      sources: current,
      query: _query,
    );
    final rejected = expectLater(
      blocked,
      throwsA(
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.overloaded,
        ),
      ),
    );
    await Future.any<void>([rejected, fixture.opened(1).then<void>((_) {})]);
    expect(
      fixture.opens,
      hasLength(1),
      reason:
          'The original unresolved pin still consumes the shared read permit',
    );
    await rejected;
    final unresolved = await fixture.repository.close();
    expect(unresolved.unresolved, hasLength(1));
    final original = unresolved.unresolved.single;
    expect(original.owner, 'configuration:start-read');
    expect(original.issues, [_retryIssue]);
    expect(_startUsage(fixture).single.phase, ResourcePhase.unresolved);
    expect(budget.used(ResourceKind.readModel), 1);
    pin.outcome = const FeedCloseOutcome.clean();
    expect((await fixture.repository.retryCleanup()).complete, isTrue);
    expect(pin.retryCloseCalls, 1);
    expect(identical(opening.native, pin), isTrue);
    expect(fixture.opens, hasLength(1));
    expect(original.issues, [
      _retryIssue,
    ], reason: 'A captured close report is not rewritten by a later Clean');
    expect(budget.usage, isEmpty);
  });
}
