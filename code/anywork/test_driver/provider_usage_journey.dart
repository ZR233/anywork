// Explicit native observation, not a widget/integration gate. All mutations use
// the real UI; requestData only observes typed Client state or shuts it down.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'realtime_journey.dart'
    show isDurableSettled, timelineRows, turnId, turnStatus;

typedef _Json = Map<String, dynamic>;

Future<void> main(List<String> args) async {
  if (args.length < 7 || args.length > 8) {
    stderr.writeln(
      'usage: provider_usage_journey VM PROJECT OUTPUT FIXTURE PREFIX PLAN_LABEL ORDINARY_LABEL [first|restart]',
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
      await probe.fixture('/__provider_usage/release', {
        'quota': true,
        'mcp': true,
      });
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
  await probe.write('provider-usage-summary-${probe.phase}.json', {
    'status': failure == null ? 'complete' : 'failed',
    'shutdown': shutdown,
    'phase': probe.phase,
    'stages': probe.stages,
    'providers': probe.savedProviders,
    'fixture': probe.finalFixture,
    'error': failure?.toString(),
    'realProviderCompatibility': 'not-exercised',
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
  List<dynamic> savedProviders = [];
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
      (jsonDecode(await driver.requestData('provider-usage-state')) as Map)
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
    await write(
      '$phase-$name-fixture.json',
      await fixture('/__provider_usage/state'),
    );
    await write('$phase-$name-snapshot.json', await driver.readSnapshot());
    await File('${args[2]}/$phase-$name.png')
        .writeAsBytes(await driver.screenshot());
    await File('${args[2]}/$phase-$name-tree.txt')
        .writeAsString(await driver.renderTree());
  }

  _Json? provider(_Json state, String id) => (state['providers'] as List)
      .whereType<Map>()
      .where((value) => value['id'] == id)
      .firstOrNull
      ?.cast<String, dynamic>();
  _Json? record(_Json state, String id) => (state['usages'] as List)
      .whereType<Map>()
      .where((value) => value['id'] == id)
      .firstOrNull
      ?.cast<String, dynamic>();
  bool pending(_Json state, String id) =>
      (state['loadingProviderIds'] as List).contains(id);
  Set<String> ids(_Json state) => {
    for (final value in state['providers'] as List)
      (value as Map)['id'] as String,
  };

  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> requireCounts(
    int fastCount,
    int deniedCount, {
    int slowCount = 1,
  }) async {
    final state = await fixture('/__provider_usage/state');
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
    await tap('settings-tab-providers');
    await driver.waitFor(find.byValueKey('provider-add'));
  }

  Future<void> scrollRow(String id) async {
    final row = find.byValueKey('provider-row-$id');
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

  Future<void> rowMenu(String id, String labelKey) async {
    await scrollRow(id);
    final labels = (await usage())['labels'] as Map;
    await driver.rawTap(
      find.descendant(
        of: find.byValueKey('provider-row-$id'),
        matching: find.byType('IconButton'),
      ),
    );
    await driver.rawTap(find.text(labels[labelKey] as String));
  }

  Future<void> changeName(String value) async {
    final label = ((await usage())['labels'] as Map)['displayName'] as String;
    await driver.rawTap(
      find.ancestor(
        of: find.text(label),
        matching: find.byType('SettingsTextEdit'),
        firstMatchOnly: true,
      ),
    );
    await driver.enterText(value);
  }

  Future<void> save() async {
    await tap('provider-save');
    await driver.waitForAbsent(
      find.byValueKey('provider-save'),
      timeout: const Duration(seconds: 8),
    );
    await driver.waitFor(
      find.byValueKey('provider-add'),
      timeout: const Duration(seconds: 3),
    );
  }

  Future<String> addProvider(String label, String preset) async {
    final before = ids(await usage());
    await tap('provider-add');
    await tap('provider-preset');
    final option = find.text(label);
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
    await tap('provider-base-url');
    await driver.enterText(args[3]);
    final stopwatch = Stopwatch()..start();
    await save();
    final state = await waitForState(
      usage,
      (state) => ids(state).difference(before).length == 1,
      'new canonical provider',
    );
    final id = ids(state).difference(before).single;
    final current = provider(state, id)!;
    require(
      current['preset'] == preset &&
          current['hasBearerToken'] == false &&
          (current['usageQueryRevision'] as int) > 0,
      'new provider did not cross typed canonical bridge: $current',
    );
    await waitForState(
      usage,
      (state) =>
          !pending(state, id) &&
          record(state, id)?['kind'] ==
              (preset == 'zhipu-coding-plan'
                  ? 'missingCredential'
                  : 'unsupported'),
      'new provider automatic usage',
    );
    stages.add({
      'stage': 'save-$preset',
      'providerId': id,
      'elapsedMillis': stopwatch.elapsedMilliseconds,
    });
    await tap('provider-add');
    await tap('provider-cancel');
    await driver.waitForAbsent(find.byValueKey('provider-save'));
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
      () => fixture('/__provider_usage/state'),
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
      (await fixture('/__provider_usage/state'))['mcpReleased'] == false,
      'MCP gate was released before Thread completed',
    );
    stages.add({
      'stage': 'thread-before-mcp-ready',
      'elapsedMillis': stopwatch.elapsedMilliseconds,
    });
    await capture('thread-before-mcp-ready');

    await openSettings(); // No refresh button is pressed before this evidence.
    await waitForState(
      () => fixture('/__provider_usage/state'),
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
          record(state, fast)?['kind'] == 'ready' &&
          record(state, denied)?['kind'] == 'failed',
      'per-card ready/failed before slow completes',
    );
    require(
      (record(parallel, fast)!['balances'] as List).contains('88.00'),
      'fast result payload was not mapped',
    );
    await capture('parallel-quota');
    stages.add({
      'stage': 'automatic-parallel-quota',
      'slowPending': true,
      'fastBalance': '88.00',
      'deniedKind': 'failed',
    });

    final oldRevision = provider(parallel, fast)!['usageQueryRevision'];
    await scrollRow(fast);
    await tap('provider-row-$fast');
    await tap('provider-edit');
    await changeName('Usage fast renamed');
    await save();
    final renamed = await waitForState(
      usage,
      (state) => provider(state, fast)?['name'] == 'Usage fast renamed',
      'canonical rename',
    );
    require(
      provider(renamed, fast)!['usageQueryRevision'] == oldRevision &&
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
      (state) => provider(state, slow) == null,
      'delete canonical publication',
    );
    await fixture('/__provider_usage/release', {'quota': true});
    await waitForState(
      usage,
      (state) =>
          !pending(state, slow) &&
          record(state, slow) == null &&
          record(state, fast)?['kind'] == 'ready',
      'deleted in-flight usage discarded',
    );
    await tap('provider-add');
    await tap('provider-cancel');
    await tap('settings-tab-general');
    await tap('settings-tab-providers');
    await requireCounts(1, 1);
    await rowMenu(fast, 'setDefault');
    await requireCounts(1, 1);
    stages.add({
      'stage': 'save-and-delete-before-release',
      'nameRevisionUnchanged': true,
      'retainedTabsNoRepeat': true,
      'deletedResultAbsent': true,
    });

    await addProvider(args[6], 'zhipu');
    final addedPlan = await addProvider(args[5], 'zhipu-coding-plan');
    await scrollRow(addedPlan);
    await tap('provider-row-$addedPlan');
    await tap('provider-edit');
    await tap('provider-cancel');
    await requireCounts(1, 1);
    require(
      (await fixture('/__provider_usage/state'))['mcpReleased'] == false,
      'provider saves waited until MCP release',
    );
    await capture('saved-before-mcp-ready');
    await fixture('/__provider_usage/release', {'mcp': true});
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
      provider(completed, slow) == null && record(completed, slow) == null,
      'late deleted-provider response revived a usage record',
    );
    savedProviders = completed['providers'] as List;
    finalFixture = await fixture('/__provider_usage/state');
    await capture('complete');
  }

  Future<void> restart() async {
    final first = (jsonDecode(
      await File('${args[2]}/provider-usage-summary-first.json').readAsString(),
    ) as Map).cast<String, dynamic>();
    final previous = first['fixture'] as Map;
    await openSettings();
    await waitForState(
      () => fixture('/__provider_usage/state'),
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
          record(state, fast)?['kind'] == 'ready' &&
          record(state, denied)?['kind'] == 'failed',
      'restart typed usage',
    );
    final expected = {
      for (final provider in first['providers'] as List)
        (provider as Map)['id'] as String,
    };
    require(
      ids(state).containsAll(expected) && !ids(state).contains(slow),
      'canonical providers did not survive restart',
    );
    require(
      provider(state, fast)?['name'] == 'Usage fast renamed',
      'canonical edited name did not survive restart',
    );
    await requireCounts(
      (previous['fastQuotaStarted'] as int) + 1,
      (previous['deniedQuotaStarted'] as int) + 1,
    );
    savedProviders = state['providers'] as List;
    finalFixture = await fixture('/__provider_usage/state');
    stages.add({
      'stage': 'restart-canonical-and-new-page-demand',
      'providerIds': expected.toList(),
    });
    await capture('complete');
  }
}
