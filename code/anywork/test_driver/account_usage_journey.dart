// Explicit native observation, not a widget/integration gate. All mutations use
// the real UI; requestData only observes typed Client state or shuts it down.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';

import 'flutter_driver_session.dart';
import 'realtime_journey.dart'
    show isDurableSettled, timelineRows, turnId, turnStatus;

typedef _Json = Map<String, dynamic>;

/// `pl-provider-fixture` 注册的真实 HTTP 控制路径。
///
/// 这是外部 fixture 的既有 wire 契约（`src/provider_usage.rs` 的
/// `STATE_PATH` / `RELEASE_PATH`），与产品侧 `account-usage-state` requestData
/// 快照是两个不同接口；旅程只读取/驱动 fixture，不新增兼容别名。
const _fixtureStatePath = '/__provider_usage/state';
const _fixtureReleasePath = '/__provider_usage/release';
const _fixtureControlPath = '/__provider_usage/control';

Future<void> main(List<String> args) async {
  if (args.length < 7 || args.length > 8) {
    stderr.writeln(
      'usage: account_usage_journey VM PROJECT OUTPUT FIXTURE PREFIX PLAN_LABEL ORDINARY_LABEL [first|restart]',
    );
    exitCode = 64;
    return;
  }
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  final probe = _Probe(driver, args);
  Object? failure;
  StackTrace? failureStack;
  var shutdown = 'failed';
  try {
    await probe.run();
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
    try {
      await probe.capture('failure');
    } catch (captureError) {
      stderr.writeln('failure capture: $captureError');
    }
  } finally {
    // A failed assertion must not leave an intentionally gated request pinning
    // the Client's real close/join. This is fixture control, never a product API.
    try {
      await probe.fixture(_fixtureReleasePath, {'quota': true, 'mcp': true});
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    try {
      final reply = jsonDecode(
        await driver.requestData(
          'shutdown',
          timeout: const Duration(seconds: 60),
        ),
      );
      if (reply is! Map || reply['shutdown'] != 'completed') {
        throw StateError('native shutdown did not complete: $reply');
      }
      shutdown = 'completed';
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    } finally {
      probe.http.close(force: true);
      try {
        await driver.close().timeout(const Duration(seconds: 5));
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
  }
  await probe.write('account-usage-summary-${probe.phase}.json', {
    'status': failure == null ? 'complete' : 'failed',
    'shutdown': shutdown,
    'phase': probe.phase,
    'stages': probe.stages,
    'accounts': probe.savedAccounts,
    'fixture': probe.finalFixture,
    'error': failure?.toString(),
    'realAccountCompatibility': 'not-exercised',
  });
  if (failure != null) {
    stderr.writeln('$failure\n$failureStack');
    exitCode = 1;
  }
}

class _Probe {
  _Probe(this.driver, this.args);

  final FlutterDriverSession driver;
  final List<String> args;
  final HttpClient http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  final List<_Json> stages = [];
  List<dynamic> savedAccounts = [];
  _Json finalFixture = {};
  String get phase => args.length == 8 ? args[7] : 'first';
  String get slow => '${args[4]}-slow';
  String get fast => '${args[4]}-fast';
  String get denied => '${args[4]}-denied';

  Future<_Json> fixture(String path, [_Json? body]) async {
    final url = Uri.parse(args[3]).replace(path: path, query: '', fragment: '');
    final request = await http
        .openUrl(body == null ? 'GET' : 'POST', url)
        .timeout(const Duration(seconds: 5));
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 5));
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw StateError('fixture control $path: ${response.statusCode}');
    }
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  Future<_Json> usage() async =>
      (jsonDecode(await driver.requestData('account-usage-state')) as Map)
          .cast<String, dynamic>();

  Future<_Json> waitForState(
    Future<_Json> Function() read,
    bool Function(_Json) predicate,
    String label, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    _Json last = {};
    while (DateTime.now().isBefore(deadline)) {
      last = await read();
      if (predicate(last)) return last;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('$label timed out: ${jsonEncode(last)}');
  }

  Future<void> tap(String key) =>
      driver.rawTap(find.byValueKey(key), timeout: const Duration(seconds: 15));

  Future<void> write(String name, Object value) =>
      File('${args[2]}/$name')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(value));

  Future<void> capture(String name) async {
    await write('$phase-$name-usage.json', await usage());
    await write('$phase-$name-fixture.json', await fixture(_fixtureStatePath));
    await write('$phase-$name-snapshot.json', await driver.readSnapshot());
    await File('${args[2]}/$phase-$name.png')
        .writeAsBytes(await driver.screenshot());
    await File('${args[2]}/$phase-$name-tree.txt')
        .writeAsString(await driver.renderTree());
  }

  _Json? account(_Json state, String id) => (state['accounts'] as List)
      .whereType<Map>()
      .where((value) => value['kind'] == 'native' && value['id'] == id)
      .firstOrNull
      ?.cast<String, dynamic>();
  _Json? record(_Json state, String id) => (state['usage']['accounts'] as List)
      .whereType<Map>()
      .where((value) => value['accountId'] == id)
      .firstOrNull
      ?.cast<String, dynamic>();
  bool pending(_Json state, String id) =>
      record(state, id)?['phase'] == 'querying';
  Set<String> ids(_Json state) => {
    for (final value in state['accounts'] as List)
      if ((value as Map)['kind'] == 'native') value['id'] as String,
  };

  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> requireCounts(
    int fastCount,
    int deniedCount, {
    int slowCount = 1,
  }) async {
    final state = await fixture(_fixtureStatePath);
    require(
      state['fastQuotaStarted'] == fastCount &&
          state['deniedQuotaStarted'] == deniedCount &&
          state['slowQuotaStarted'] == slowCount,
      'unrelated or repeated usage query: $state',
    );
  }

  void requireFastBalance(_Json state, {required bool recovered}) {
    final lastGood = record(state, fast)?['lastGood'] as Map?;
    final value = lastGood?['value'] as Map?;
    require(
      lastGood?['checkedAt'] is int &&
          value?['kind'] == 'balance' &&
          value?['available'] == true,
      'fast canonical balance is unavailable: $lastGood',
    );
    final balances = (value!['balances'] as List).cast<Map>();
    require(
      balances.length == 2,
      'fast must retain both currencies: $balances',
    );
    for (final (currency, total, granted, toppedUp) in [
      (
        'USD',
        recovered ? '89.00' : '88.00',
        recovered ? '9.00' : '8.00',
        '80.00',
      ),
      (
        'CNY',
        '0.000000000000000001',
        '0.000000000000000001',
        '0.000000000000000000',
      ),
    ]) {
      final matches = balances
          .where((balance) => balance['currency'] == currency)
          .toList();
      require(
        matches.length == 1 &&
            (
                  matches.single['total'],
                  matches.single['granted'],
                  matches.single['toppedUp'],
                ) ==
                (total, granted, toppedUp),
        'fast $currency precision or components changed: $balances',
      );
    }
  }

  void requirePlanQuota(_Json state, String id) {
    final observation = record(state, id);
    final value = observation?['lastGood']?['value'] as Map?;
    require(
      observation?['phase'] == 'succeeded' &&
          !pending(state, id) &&
          observation?['failure'] == null &&
          value?['kind'] == 'subscription' &&
          value?['level'] == 'fixture-plan',
      'Plan canonical quota did not succeed: $observation',
    );
    final quotas = (value!['quotas'] as List).cast<Map>();
    require(quotas.length == 2, 'Plan must retain both quota windows: $quotas');
    for (final (window, used, remaining, percentage, resetAt) in const [
      ('fiveHour', 95, 5, 95, 1700000000),
      ('weekly', 10, 90, 10, 1700086400),
    ]) {
      final matches = quotas
          .where((quota) => quota['window'] == window)
          .toList();
      require(
        matches.length == 1 &&
            (
                  matches.single['used'],
                  matches.single['total'],
                  matches.single['remaining'],
                  matches.single['percentage'],
                  matches.single['resetAt'],
                ) ==
                (used, 100, remaining, percentage, resetAt),
        'Plan $window quota or Unix-second reset was not mapped: $quotas',
      );
    }
  }

  void requireFixtureDelta(
    _Json state,
    Map baseline, {
    required int fastIncrement,
    int planIncrement = 0,
    int failedIncrement = 0,
    bool armed = false,
  }) {
    require(
      state['fastQuotaStarted'] ==
              (baseline['fastQuotaStarted'] as int) + fastIncrement &&
          state['deniedQuotaStarted'] == baseline['deniedQuotaStarted'] &&
          state['planQuotaStarted'] ==
              (baseline['planQuotaStarted'] as int) + planIncrement &&
          state['fastQuotaFailed'] ==
              (baseline['fastQuotaFailed'] as int) + failedIncrement &&
          state['fastQuotaFailureArmed'] == armed &&
          state['slowQuotaStarted'] == baseline['slowQuotaStarted'] &&
          state['mcpStarted'] == baseline['mcpStarted'] &&
          state['mcpReleased'] == baseline['mcpReleased'] &&
          state['slowQuotaReleased'] == baseline['slowQuotaReleased'],
      'unexpected quota/MCP admission or control state: baseline=$baseline current=$state',
    );
  }

  Future<void> revealDetails(SerializableFinder target) async {
    await driver.waitFor(target, timeout: const Duration(seconds: 15));
    await driver.scrollUntilVisible(
      find.ancestor(
        of: target,
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      target,
      dyScroll: -180,
      timeout: const Duration(seconds: 15),
    );
  }

  SerializableFinder get detailsUsage => find.descendant(
    of: find.byType('AccountDetailsView'),
    matching: find.byType('AccountUsageView'),
  );

  Future<void> openSettings() async {
    await tap('settings-open');
    await driver.waitFor(find.byValueKey('settings-page'));
    await tap('settings-tab-accounts');
    await driver.waitFor(find.byValueKey('account-add'));
  }

  Future<void> scrollRow(String id) async {
    final row = find.byValueKey(AccountViewKeyValues.row('native', id));
    await driver.scrollUntilVisible(
      find.ancestor(
        of: row,
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      row,
      dyScroll: -180,
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> returnToList() async {
    final presentation = (await usage())['presentation'] as Map;
    if (presentation['selected'] != null) {
      final list = find.descendant(
        of: find.byType('AccountDetailsView'),
        matching: find.byType('ListView'),
      );
      await driver.waitFor(list, timeout: const Duration(seconds: 15));
      await driver.scrollUntilVisible(
        list,
        find.byValueKey('account-back'),
        dyScroll: 180,
        timeout: const Duration(seconds: 15),
      );
      await tap('account-back');
    }
    await driver.waitFor(find.byValueKey('account-add'));
  }

  Future<void> rowMenu(String id, String labelKey) async {
    await returnToList();
    await scrollRow(id);
    final state = await usage();
    final labels = state['labels'] as Map;
    await tap(AccountViewKeyValues.rowMenu('native', id));
    await driver.rawTap(find.text(labels[labelKey] as String));
    if (labelKey == 'delete') {
      if (account(state, id)?['isDefault'] == true) {
        final replacement = (state['accounts'] as List).cast<Map>().firstWhere(
          (value) => value['kind'] == 'native' && value['id'] != id,
        );
        await driver.rawTap(
          find.descendant(
            of: find.byType('SimpleDialog'),
            matching: find.text(replacement['name'] as String),
          ),
        );
      }
      await driver.waitFor(find.byType('AccountDeleteDialog'));
      await driver.rawTap(
        find.descendant(
          of: find.byType('AccountDeleteDialog'),
          matching: find.byType('FilledButton'),
        ),
      );
      await driver.waitForAbsent(find.byType('AccountDeleteDialog'));
    }
  }

  Future<String> editorId() async =>
      (await usage())['presentation']['editor']['editorId'] as String;

  Future<void> editField(String field, String value) async {
    final finder = find.descendant(
      of: find.byValueKey(
        AccountViewKeyValues.editorField(await editorId(), field),
      ),
      matching: find.byType('EditableText'),
    );
    await driver.rawTap(finder);
    await driver.enterText(value);
  }

  Future<void> changeName(String value) => editField('name', value);

  Future<void> _tapEditorFooter(String key) async {
    final target = find.byValueKey(key);
    await driver.waitFor(target, timeout: const Duration(seconds: 15));
    await driver.scrollUntilVisible(
      find.ancestor(
        of: target,
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      target,
      dyScroll: -180,
      timeout: const Duration(seconds: 15),
    );
    await tap(key);
  }

  Future<void> save() async {
    await _tapEditorFooter('account-save');
    await driver.waitForAbsent(
      find.byValueKey('account-save'),
      timeout: const Duration(seconds: 8),
    );
    await driver.waitFor(
      find.byValueKey('account-edit'),
      timeout: const Duration(seconds: 8),
    );
  }

  Future<String> addAccount(String label, String template) async {
    final before = ids(await usage());
    await tap('account-add');
    final opened = await waitForState(
      usage,
      (state) =>
          state['presentation']?['editor']?['creating'] == true &&
          state['presentation']?['editor']?['stale'] == false,
      'default account editor',
    );
    final original = opened['presentation']['editor'] as Map;
    final templates =
        (await driver.readSnapshot())['settings']['nativeTemplates'] as List;
    require(
      templates.isNotEmpty && original['target']?['kind'] == 'native',
      'usage creation requires the real default Native editor',
    );
    final switching = templates.first != template;
    final selector = find.byValueKey('account-template-selector');
    await driver.waitFor(selector, timeout: const Duration(seconds: 15));
    await driver.rawTap(
      find.descendant(of: selector, matching: find.byType('IconButton')),
      timeout: const Duration(seconds: 15),
    );
    final option = find.byValueKey(
      AccountViewKeyValues.template('native', template),
    );
    await driver.scrollUntilVisible(
      find.ancestor(
        of: option,
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      option,
      dyScroll: -120,
      timeout: const Duration(seconds: 15),
    );
    await driver.rawTap(option);
    if (switching) {
      await discardDialog();
      await waitForState(
        usage,
        (state) =>
            state['presentation']?['editor']?['editorId'] !=
                original['editorId'] &&
            state['presentation']?['editor']?['target']?['kind'] == 'native' &&
            state['presentation']?['editor']?['creating'] == true &&
            state['presentation']?['editor']?['stale'] == false,
        'new template editor identity',
      );
    }
    await editField('endpoint', args[3]);
    final stopwatch = Stopwatch()..start();
    await save();
    final state = await waitForState(
      usage,
      (state) =>
          ids(state).difference(before).length == 1 &&
          account(state, ids(state).difference(before).single)?['templateId'] ==
              template,
      'new canonical account',
    );
    final id = ids(state).difference(before).single;
    final current = account(state, id)!;
    require(
      current['templateId'] == template &&
          current['hasBearerToken'] == false &&
          (current['usageQueryRevision'] as int) > 0,
      'new account did not cross typed canonical bridge: $current',
    );
    await waitForState(
      usage,
      (state) =>
          !pending(state, id) &&
          record(state, id)?['phase'] ==
              (template == 'zhipu-coding-plan'
                  ? 'missingCredential'
                  : 'unsupported'),
      'new account automatic usage',
    );
    stages.add({
      'stage': 'save-$template',
      'accountId': id,
      'elapsedMillis': stopwatch.elapsedMilliseconds,
    });
    await returnToList();
    await tap('account-add');
    await discardNewEditor();
    return id;
  }

  Future<void> discardDialog() async {
    final dialog = find.byType('AccountUnsavedChangesDialog');
    await driver.waitFor(dialog);
    final label = (await usage())['labels']['discard'] as String;
    await driver.rawTap(
      find.descendant(of: dialog, matching: find.text(label)),
    );
    await driver.waitForAbsent(dialog);
  }

  Future<void> discardNewEditor() async {
    final snapshot = await waitForState(
      usage,
      (state) =>
          state['presentation']?['editor']?['creating'] == true &&
          state['presentation']?['editor']?['saving'] == false,
      'new editor before discard',
    );
    require(
      snapshot['presentation']['editor']['dirty'] == true,
      'new editor unexpectedly has no creation draft',
    );
    await _tapEditorFooter('account-cancel');
    await discardDialog();
    await driver.waitForAbsent(find.byValueKey('account-save'));
  }

  Future<void> run() async {
    await waitForState(
      usage,
      (state) => ids(state).isNotEmpty,
      'canonical startup',
    );
    if (phase == 'restart') {
      await restart();
      return;
    }
    require(phase == 'first', 'unknown phase $phase');
    await waitForState(
      () => fixture(_fixtureStatePath),
      (state) =>
          (state['mcpStarted'] as int) > 0 && state['mcpReleased'] == false,
      'blocked MCP initialization',
    );
    await tap('sidebar-open-project');
    await tap('add-project-local');
    await driver.waitFor(
      find.byValueKey('add-project-continue-ready'),
      timeout: const Duration(seconds: 30),
    );
    await tap('add-project-continue-ready');
    await tap('project-path-input');
    await driver.enterText(args[1]);
    await tap('project-path-submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
    final beforeTurn = turnId(await driver.readSnapshot());
    await tap('composer-input');
    await driver.enterText('Reply with exactly: fixture ready');
    final stopwatch = Stopwatch()..start();
    await tap('composer-submit');
    await waitForState(
      driver.readSnapshot,
      (state) =>
          turnId(state) != beforeTurn &&
          turnStatus(state) == 'completed' &&
          isDurableSettled(state) &&
          timelineRows(state).any(
            (row) =>
                row['type'] == 'finalAnswer' &&
                jsonEncode(row).contains('fixture ready'),
          ),
      'new Thread while MCP handshake is gated',
      timeout: const Duration(seconds: 12),
    );
    require(
      (await fixture(_fixtureStatePath))['mcpReleased'] == false,
      'MCP gate was released before Thread completed',
    );
    stages.add({
      'stage': 'thread-before-mcp-ready',
      'elapsedMillis': stopwatch.elapsedMilliseconds,
    });
    await capture('thread-before-mcp-ready');

    await openSettings(); // No refresh button is pressed before this evidence.
    await waitForState(
      () => fixture(_fixtureStatePath),
      (state) =>
          state['slowQuotaStarted'] == 1 &&
          state['fastQuotaStarted'] == 1 &&
          state['deniedQuotaStarted'] == 1,
      'automatic parallel quota admission',
    );
    final parallel = await waitForState(
      usage,
      (state) =>
          pending(state, slow) &&
          !pending(state, fast) &&
          record(state, fast)?['phase'] == 'succeeded' &&
          record(state, denied)?['phase'] == 'failed',
      'per-card ready/failed before slow completes',
    );
    requireFastBalance(parallel, recovered: false);
    await capture('parallel-quota');
    stages.add({
      'stage': 'automatic-parallel-quota',
      'slowPending': true,
      'fastBalance': '88.00',
      'deniedKind': 'failed',
    });

    final oldRevision = account(parallel, fast)!['usageQueryRevision'];
    await scrollRow(fast);
    await tap(AccountViewKeyValues.row('native', fast));
    await tap('account-edit');
    await changeName('Usage fast renamed');
    await save();
    final renamed = await waitForState(
      usage,
      (state) => account(state, fast)?['name'] == 'Usage fast renamed',
      'canonical rename',
    );
    require(
      account(renamed, fast)!['usageQueryRevision'] == oldRevision &&
          pending(renamed, slow),
      'name edit invalidated usage or waited for slow query',
    );
    require(
      pending(await usage(), slow),
      'slow request ended before deletion evidence',
    );
    await rowMenu(slow, 'delete');
    await waitForState(
      usage,
      (state) => account(state, slow) == null,
      'delete canonical publication',
    );
    await fixture(_fixtureReleasePath, {'quota': true});
    await waitForState(
      usage,
      (state) =>
          !pending(state, slow) &&
          record(state, slow) == null &&
          record(state, fast)?['phase'] == 'succeeded',
      'deleted in-flight usage discarded',
    );
    await tap('account-add');
    await discardNewEditor();
    await tap('settings-tab-general');
    await tap('settings-tab-accounts');
    await requireCounts(1, 1);
    await rowMenu(fast, 'setDefault');
    await requireCounts(1, 1);
    stages.add({
      'stage': 'save-and-delete-before-release',
      'nameRevisionUnchanged': true,
      'retainedTabsNoRepeat': true,
      'deletedResultAbsent': true,
    });

    final addedOrdinary = await addAccount(args[6], 'zhipu');
    final addedPlan = await addAccount(args[5], 'zhipu-coding-plan');
    await scrollRow(addedPlan);
    await tap(AccountViewKeyValues.row('native', addedPlan));
    await tap('account-edit');
    await _tapEditorFooter('account-cancel');
    await returnToList();
    await requireCounts(1, 1);
    require(
      (await fixture(_fixtureStatePath))['mcpReleased'] == false,
      'account saves waited until MCP release',
    );
    await capture('saved-before-mcp-ready');
    await fixture(_fixtureReleasePath, {'mcp': true});
    await waitForState(
      () async =>
          (jsonDecode(await driver.requestData('search-mcp-state')) as Map)
              .cast<String, dynamic>(),
      (state) => (state['servers'] as List? ?? []).whereType<Map>().any(
        (server) =>
            server['id'] == 'fixture_usage_mcp' &&
            (server['state'] as Map)['kind'] == 'available',
      ),
      'generic MCP ready after release',
    );
    await returnToList();
    await scrollRow(fast);
    await tap(AccountViewKeyValues.row('native', fast));
    final beforeRefresh = await waitForState(
      usage,
      (state) =>
          state['presentation']?['selected']?['kind'] == 'native' &&
          state['presentation']?['selected']?['id'] == fast &&
          state['presentation']?['editor'] == null &&
          record(state, fast)?['phase'] == 'succeeded' &&
          !pending(state, fast),
      'fast detail before controlled refresh',
    );
    requireFastBalance(beforeRefresh, recovered: false);
    final oldLastGood = jsonEncode(record(beforeRefresh, fast)!['lastGood']);
    final baseline = await fixture(_fixtureStatePath);
    await requireCounts(1, 1);
    require(
      baseline['fastQuotaStarted'] == 1 &&
          baseline['deniedQuotaStarted'] == 1 &&
          baseline['slowQuotaStarted'] == 1 &&
          baseline['planQuotaStarted'] == 0 &&
          baseline['fastQuotaFailed'] == 0 &&
          baseline['fastQuotaFailureArmed'] == false &&
          baseline['mcpReleased'] == true,
      'unexpected baseline before new quota intents: $baseline',
    );
    await revealDetails(detailsUsage);
    await capture('fast-multi-currency');
    final armed = await fixture(_fixtureControlPath, {
      'action': 'failNextFastQuota',
    });
    requireFixtureDelta(armed, baseline, fastIncrement: 0, armed: true);
    final refresh = find.byValueKey('account-usage-check');
    await revealDetails(refresh);
    await tap('account-usage-check');
    final failed = await waitForState(
      usage,
      (state) =>
          record(state, fast)?['phase'] == 'failed' &&
          !pending(state, fast) &&
          record(state, fast)?['failure']?['retryable'] == true,
      'fast controlled failure with retained last-good',
    );
    require(
      jsonEncode(record(failed, fast)!['lastGood']) == oldLastGood,
      'failed refresh changed last-good timestamp or complete value',
    );
    requireFastBalance(failed, recovered: false);
    final afterFailure = await fixture(_fixtureStatePath);
    requireFixtureDelta(
      afterFailure,
      baseline,
      fastIncrement: 1,
      failedIncrement: 1,
    );
    await revealDetails(detailsUsage);
    await capture('fast-last-good-failure');
    final retry = find.descendant(
      of: detailsUsage,
      matching: find.byType('TextButton'),
    );
    await revealDetails(retry);
    await driver.rawTap(retry, timeout: const Duration(seconds: 15));
    final recovered = await waitForState(
      usage,
      (state) =>
          record(state, fast)?['phase'] == 'succeeded' &&
          record(state, fast)?['failure'] == null &&
          !pending(state, fast) &&
          jsonEncode(record(state, fast)?['lastGood']) != oldLastGood,
      'fast real Retry recovery',
    );
    requireFastBalance(recovered, recovered: true);
    require(
      jsonEncode(record(recovered, fast)!['lastGood']) != oldLastGood,
      'Retry did not replace the old last-good value',
    );
    final afterRetry = await fixture(_fixtureStatePath);
    requireFixtureDelta(
      afterRetry,
      baseline,
      fastIncrement: 2,
      failedIncrement: 1,
    );
    await revealDetails(detailsUsage);
    await capture('fast-retry-recovered');
    stages.add({
      'stage': 'fast-multi-currency-last-good-retry',
      'accountId': fast,
      'lastGoodRetained': record(failed, fast)!['lastGood'],
      'lastGoodRecovered': record(recovered, fast)!['lastGood'],
      'failedOperationId': record(failed, fast)!['operationId'],
      'recoveredOperationId': record(recovered, fast)!['operationId'],
      'fixtureAfterFailure': afterFailure,
      'fixtureAfterRetry': afterRetry,
    });

    await returnToList();
    await scrollRow(addedPlan);
    await tap(AccountViewKeyValues.row('native', addedPlan));
    final planBefore = await waitForState(
      usage,
      (state) =>
          state['presentation']?['selected']?['kind'] == 'native' &&
          state['presentation']?['selected']?['id'] == addedPlan &&
          state['presentation']?['editor'] == null &&
          account(state, addedPlan)?['details']?['loaded'] == true &&
          account(state, addedPlan)?['details']?['stale'] == false &&
          account(state, addedPlan)?['hasBearerToken'] == false,
      'observed Plan details before credential edit',
    );
    final planRevision = account(planBefore, addedPlan)!['usageQueryRevision'];
    require(
      planRevision is int,
      'Plan has no canonical usage revision before credential Save',
    );
    final idsBeforeCredential = ids(planBefore);
    await tap('account-edit');
    await editField('credential', 'fixture-usage-plan');
    await save();
    final planSaved = await waitForState(
      usage,
      (state) =>
          account(state, addedPlan)?['credentialReady'] == true &&
          account(state, addedPlan)?['hasBearerToken'] == true &&
          account(state, addedPlan)?['usageQueryRevision'] is int &&
          account(state, addedPlan)?['usageQueryRevision'] != planRevision &&
          record(state, addedPlan)?['phase'] == 'succeeded' &&
          !pending(state, addedPlan),
      'same Plan canonical credential and automatic quota',
    );
    require(
      ids(planSaved).length == idsBeforeCredential.length &&
          ids(planSaved).containsAll(idsBeforeCredential),
      'credential Save created another account',
    );
    requirePlanQuota(planSaved, addedPlan);
    final afterPlan = await fixture(_fixtureStatePath);
    requireFixtureDelta(
      afterPlan,
      baseline,
      fastIncrement: 2,
      planIncrement: 1,
      failedIncrement: 1,
    );
    await revealDetails(detailsUsage);
    await capture('plan-quota-low');
    stages.add({
      'stage': 'plan-credential-and-dual-quota',
      'accountId': addedPlan,
      'previousUsageRevision': planRevision,
      'usageQueryRevision': account(
        planSaved,
        addedPlan,
      )!['usageQueryRevision'],
      'credentialReady': account(planSaved, addedPlan)!['credentialReady'],
      'hasBearerToken': account(planSaved, addedPlan)!['hasBearerToken'],
      'lastGood': record(planSaved, addedPlan)!['lastGood'],
      'accountIds': ids(planSaved).toList(),
      'fixtureAfterCredentialSave': afterPlan,
    });
    await returnToList();
    final completed = await usage();
    require(
      account(completed, slow) == null && record(completed, slow) == null,
      'late deleted-account response revived a usage record',
    );
    require(
      record(completed, denied)?['phase'] == 'failed',
      'denied record lost its original failure',
    );
    require(
      record(completed, fast)?['phase'] == 'succeeded' &&
          !pending(completed, fast),
      'fast recovery was lost',
    );
    requireFastBalance(completed, recovered: true);
    requirePlanQuota(completed, addedPlan);
    final expectedIds = {...ids(parallel)}
      ..remove(slow)
      ..addAll([addedOrdinary, addedPlan]);
    require(
      ids(completed).length == expectedIds.length &&
          ids(completed).containsAll(expectedIds),
      'rename/credential saves or creation produced unexpected account identities',
    );
    savedAccounts = (completed['accounts'] as List)
        .where((value) => (value as Map)['kind'] == 'native')
        .toList();
    finalFixture = await fixture(_fixtureStatePath);
    requireFixtureDelta(
      finalFixture,
      baseline,
      fastIncrement: 2,
      planIncrement: 1,
      failedIncrement: 1,
    );
    await capture('complete');
  }

  Future<void> restart() async {
    final first = (jsonDecode(
      await File('${args[2]}/account-usage-summary-first.json').readAsString(),
    ) as Map).cast<String, dynamic>();
    final previous = first['fixture'] as Map;
    final planStage = (first['stages'] as List).cast<Map>().singleWhere(
      (stage) => stage['stage'] == 'save-zhipu-coding-plan',
    );
    final addedPlan = planStage['accountId'] as String;
    await openSettings();
    final admitted = await waitForState(
      () => fixture(_fixtureStatePath),
      (state) =>
          state['fastQuotaStarted'] ==
              (previous['fastQuotaStarted'] as int) + 1 &&
          state['deniedQuotaStarted'] ==
              (previous['deniedQuotaStarted'] as int) + 1 &&
          state['planQuotaStarted'] ==
              (previous['planQuotaStarted'] as int) + 1,
      'new page lifecycle automatic quota load',
    );
    final state = await waitForState(
      usage,
      (state) =>
          !pending(state, fast) &&
          record(state, fast)?['phase'] == 'succeeded' &&
          record(state, denied)?['phase'] == 'failed' &&
          record(state, addedPlan)?['phase'] == 'succeeded' &&
          !pending(state, addedPlan),
      'restart typed usage',
    );
    final expected = {
      for (final account in first['accounts'] as List)
        (account as Map)['id'] as String,
    };
    require(
      ids(state).containsAll(expected) && !ids(state).contains(slow),
      'canonical accounts did not survive restart',
    );
    require(
      account(state, fast)?['name'] == 'Usage fast renamed',
      'canonical edited name did not survive restart',
    );
    require(
      record(state, slow) == null,
      'deleted slow usage record revived after restart',
    );
    requireFastBalance(state, recovered: true);
    requirePlanQuota(state, addedPlan);
    require(
      admitted['fastQuotaFailed'] == previous['fastQuotaFailed'] &&
          admitted['fastQuotaFailed'] == 1 &&
          admitted['fastQuotaFailureArmed'] == false,
      'restart replayed the controlled failure or rearmed it: $admitted',
    );
    await requireCounts(
      (previous['fastQuotaStarted'] as int) + 1,
      (previous['deniedQuotaStarted'] as int) + 1,
    );
    await scrollRow(addedPlan);
    await tap(AccountViewKeyValues.row('native', addedPlan));
    final observedPlan = await waitForState(
      usage,
      (state) =>
          state['presentation']?['selected']?['kind'] == 'native' &&
          state['presentation']?['selected']?['id'] == addedPlan &&
          state['presentation']?['editor'] == null &&
          account(state, addedPlan)?['details']?['loaded'] == true &&
          account(state, addedPlan)?['details']?['stale'] == false &&
          account(state, addedPlan)?['credentialReady'] == true &&
          account(state, addedPlan)?['hasBearerToken'] == true,
      'restart observed same Plan credential',
    );
    requirePlanQuota(observedPlan, addedPlan);
    await revealDetails(detailsUsage);
    await capture('plan-quota-low');
    await returnToList();
    final completed = await usage();
    requirePlanQuota(completed, addedPlan);
    requireFastBalance(completed, recovered: true);
    require(
      record(completed, denied)?['phase'] == 'failed' &&
          account(completed, slow) == null &&
          record(completed, slow) == null,
      'restart detail observation changed independent account results',
    );
    savedAccounts = (completed['accounts'] as List)
        .where((value) => (value as Map)['kind'] == 'native')
        .toList();
    finalFixture = await fixture(_fixtureStatePath);
    require(
      finalFixture['fastQuotaStarted'] == admitted['fastQuotaStarted'] &&
          finalFixture['deniedQuotaStarted'] ==
              admitted['deniedQuotaStarted'] &&
          finalFixture['planQuotaStarted'] == admitted['planQuotaStarted'] &&
          finalFixture['slowQuotaStarted'] == previous['slowQuotaStarted'] &&
          finalFixture['fastQuotaFailed'] == admitted['fastQuotaFailed'] &&
          finalFixture['fastQuotaFailureArmed'] == false,
      'restart details caused extra quota requests or replayed the fault: $finalFixture',
    );
    stages.add({
      'stage': 'restart-canonical-and-new-page-demand',
      'accountIds': expected.toList(),
      'planAccountId': addedPlan,
      'planCredentialReady': account(
        observedPlan,
        addedPlan,
      )!['credentialReady'],
      'planHasBearerToken': account(observedPlan, addedPlan)!['hasBearerToken'],
      'planLastGood': record(completed, addedPlan)!['lastGood'],
      'fastLastGood': record(completed, fast)!['lastGood'],
      'fixtureAfterDemand': admitted,
    });
    await capture('complete');
  }
}
