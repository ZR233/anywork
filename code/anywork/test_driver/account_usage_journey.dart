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
    if (presentation['selected'] != null) await tap('account-back');
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

  Future<void> save() async {
    await tap('account-save');
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
    await driver.rawTap(
      find.descendant(
        of: find.byType('AccountTemplatePickerView'),
        matching: find.byType('OutlinedButton'),
      ),
    );
    await driver.waitForAbsent(find.byValueKey('account-save'));
    return id;
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
    require(
      (record(parallel, fast)!['lastGood']['value']['balances'] as List)
          .cast<Map>()
          .any(
            (balance) =>
                balance['total'] == '88.00' && balance['currency'] is String,
          ),
      'fast result payload was not mapped',
    );
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
    await driver.rawTap(
      find.descendant(
        of: find.byType('AccountTemplatePickerView'),
        matching: find.byType('OutlinedButton'),
      ),
    );
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

    await addAccount(args[6], 'zhipu');
    final addedPlan = await addAccount(args[5], 'zhipu-coding-plan');
    await scrollRow(addedPlan);
    await tap(AccountViewKeyValues.row('native', addedPlan));
    await tap('account-edit');
    await tap('account-cancel');
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
    final completed = await usage();
    require(
      account(completed, slow) == null && record(completed, slow) == null,
      'late deleted-account response revived a usage record',
    );
    savedAccounts = (completed['accounts'] as List)
        .where((value) => (value as Map)['kind'] == 'native')
        .toList();
    finalFixture = await fixture(_fixtureStatePath);
    await capture('complete');
  }

  Future<void> restart() async {
    final first = (jsonDecode(
      await File('${args[2]}/account-usage-summary-first.json').readAsString(),
    ) as Map).cast<String, dynamic>();
    final previous = first['fixture'] as Map;
    await openSettings();
    await waitForState(
      () => fixture(_fixtureStatePath),
      (state) =>
          state['fastQuotaStarted'] ==
              (previous['fastQuotaStarted'] as int) + 1 &&
          state['deniedQuotaStarted'] ==
              (previous['deniedQuotaStarted'] as int) + 1,
      'new page lifecycle automatic quota load',
    );
    final state = await waitForState(
      usage,
      (state) =>
          !pending(state, fast) &&
          record(state, fast)?['phase'] == 'succeeded' &&
          record(state, denied)?['phase'] == 'failed',
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
    await requireCounts(
      (previous['fastQuotaStarted'] as int) + 1,
      (previous['deniedQuotaStarted'] as int) + 1,
    );
    savedAccounts = (state['accounts'] as List)
        .where((value) => (value as Map)['kind'] == 'native')
        .toList();
    finalFixture = await fixture(_fixtureStatePath);
    stages.add({
      'stage': 'restart-canonical-and-new-page-demand',
      'accountIds': expected.toList(),
    });
    await capture('complete');
  }
}
