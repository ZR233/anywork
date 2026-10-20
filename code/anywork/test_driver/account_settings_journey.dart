import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'driver_observation.dart';
import 'flutter_driver_session.dart';

/// Real-bridge manual journey for detail-list auto-save, not a widget test.
/// Run with cargo xtask manual-gui --scenario gui, then:
/// cargo dart test_driver/account_settings_journey.dart VM_URL OUTPUT_DIR
/// Only the isolated fixture account is edited; no system credential account
/// is created. The operator still sends the fixture prompt and `done` to the
/// harness, reviews screenshots and records the human verdict separately.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: account_settings_journey.dart VM_URL OUTPUT_DIR');
    exitCode = 64;
    return;
  }
  final output = Directory(args[1]);
  await output.create(recursive: true);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  try {
    final recorder = _Recorder(output, driver);
    final baseline = await recorder.readSnapshot();
    final fixture = _accounts(baseline)
        .where((account) => '${account['id']}'.startsWith('gui-fixture-'))
        .single;
    final id = '${fixture['id']}';
    final model = '${fixture['defaultModelId']}';
    final siblings = {
      for (final modelId in _models(fixture))
        if (modelId != model) modelId: _limit(baseline, id, modelId),
    };
    await recorder.openAccounts();
    await recorder.assertAccountListRedacted(id, model);
    await recorder.openDetails(id);
    await recorder.capture('details-defaults', await recorder.readSnapshot());
    await driver.waitForAbsent(find.byValueKey('account-save'));
    final template = _models(fixture).singleWhere((modelId) {
      final limit = _limit(baseline, id, modelId);
      return modelId != model && limit['effective'] != null;
    });
    await recorder._scrollTo(
      find.byValueKey('account-$id-model-$template-auto-compact-input'),
    );
    await recorder.capture(
      'model-template-default',
      await recorder.readSnapshot(),
    );

    await recorder.setCompactInput(id, model, '18000');
    await recorder.capture('input-pending', await recorder.readSnapshot());
    final afterInput = await recorder.waitOverride(id, model, 18000);
    await recorder.capture('input-applied-without-save', afterInput);
    const excessive = 9000000000;
    await recorder.setCompactInput(id, model, '$excessive');
    final above = await recorder.waitOverride(id, model, excessive);
    final resolved = _limit(above, id, model);
    if (resolved['adjustment'] != 'safetyLimit' ||
        resolved['effective'] is! int) {
      throw StateError('backend did not classify the adjusted override');
    }
    await recorder.capture('above-safe-clamped', above);

    await recorder.setCompactInput(id, model, 'not-a-number');
    // Negative proof: observe past the 650ms debounce, not merely one frame.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final invalid = await recorder.readSnapshot();
    if (_limit(invalid, id, model)['override'] != excessive ||
        invalid['settings']['revision'] != above['settings']['revision']) {
      throw StateError('invalid input changed canonical settings');
    }
    await recorder.capture('invalid-kept-not-persisted', invalid);

    await recorder.tapCompactReset(id, model);
    final reset = await recorder.waitOverride(id, model, null);
    if (_limit(reset, id, model)['effective'] !=
        _limit(baseline, id, model)['effective']) {
      throw StateError('reset did not restore the backend automatic value');
    }
    await recorder.capture('restored-default', await recorder.readSnapshot());

    // Rapid typing must keep the newest raw input and eventually canonicalize
    // it without a page round trip. Deterministic CAS/old-ACK races live in the
    // SDK-only Client suite, rather than being faked inside Driver.
    await recorder.setCompactInput(id, model, '19000');
    await recorder.setCompactInput(id, model, '21000');
    await driver.sendTextInputAction(TextInputAction.done);
    final latest = await recorder.waitOverride(id, model, 21000);
    await recorder.capture('latest-intent-applied', latest);
    for (final sibling in siblings.entries) {
      if (jsonEncode(_limit(latest, id, sibling.key)) !=
          jsonEncode(sibling.value)) {
        throw StateError('sibling ${sibling.key} changed');
      }
    }

    final unknown = _models(fixture)
        .where(
          (modelId) =>
              _limit(baseline, id, modelId)['unavailable'] == 'windowUnknown',
        )
        .single;
    if (_limit(baseline, id, unknown)['effective'] != null) {
      throw StateError('unknown-capacity fixture fabricated a default');
    }
    await recorder.setCompactInput(id, unknown, '17000');
    final unknownApplied = await recorder.waitOverride(id, unknown, 17000);
    if (_limit(unknownApplied, id, unknown)['effective'] != null) {
      throw StateError('unknown context enabled compaction');
    }
    await recorder.capture('unknown-capacity-stays-off', unknownApplied);
    await recorder.tapCompactReset(id, unknown);
    await recorder.waitOverride(id, unknown, null);

    // Explicit Save remains only for other account fields, with no second
    // threshold entry. Its canonical payload must preserve the thresholds.
    await driver.scrollBy(find.byValueKey('account-editor'), 3000);
    await driver.tap(find.byValueKey('account-edit'));
    await driver.waitFor(find.byValueKey('account-save'));
    await driver.waitForAbsent(
      find.byValueKey('account-$id-model-$model-auto-compact-input'),
    );
    await recorder.capture(
      'editor-without-threshold-entry',
      await recorder.readSnapshot(),
    );
    await driver.tap(find.byValueKey('account-save'));
    await driver.waitForAbsent(find.byValueKey('account-save'));
    final afterAccountSave = await recorder.waitOverride(id, model, 21000);
    if (_limit(afterAccountSave, id, unknown)['override'] != null) {
      throw StateError(
        'account field save restored a cleared sibling override',
      );
    }
    await recorder.capture(
      'account-save-preserved-overrides',
      afterAccountSave,
    );
    await recorder.openDetails(id);
    await recorder.tapCompactReset(id, model);
    await recorder.waitOverride(id, model, null);
    await File('${output.path}/account-journey-summary.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'fixtureAccountId': id, 'model': model, 'unknownModel': unknown, 'inlineAutoSave': true, 'backendPolicy': true, 'restoreDefault': true, 'invalidNotPersisted': true, 'aboveSafeClamped': true, 'latestIntent': true, 'siblingsUnchanged': true, 'secondEditorEntryAbsent': true, 'humanVerdict': 'pending'})}\n',
    );
    stdout.writeln('Account journey captured; human verdict pending.');
  } finally {
    await driver.close().timeout(const Duration(seconds: 5));
  }
}

class _Recorder {
  _Recorder(this.output, this.driver);
  final Directory output;
  final FlutterDriverSession driver;
  int _captureIndex = 0;

  Future<Map<String, dynamic>> readSnapshot() => driver.readSnapshot();

  Future<void> capture(String name, Map<String, dynamic> snapshot) async {
    final ordinal = _captureIndex++;
    await File('${output.path}/snapshot-$ordinal-$name.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
    );
    await File('${output.path}/screenshot-$ordinal-$name.png')
        .writeAsBytes(await driver.screenshot());
    await File('${output.path}/tree-$ordinal-$name.txt')
        .writeAsString(await driver.renderTree());
  }

  Future<Map<String, dynamic>> waitOverride(
    String id,
    String model,
    int? value,
  ) => waitLimit(id, model, (limit) => limit['override'] == value);

  Future<Map<String, dynamic>> waitLimit(
    String id,
    String model,
    bool Function(Map<String, dynamic>) predicate,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await readSnapshot();
      if (predicate(_limit(snapshot, id, model))) return snapshot;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('canonical threshold did not settle: $id/$model');
  }

  Future<void> assertAccountListRedacted(String id, String model) async {
    verifyAccountListRedacted(
      await readSnapshot(),
      fixtureModelId: model,
      accountId: id,
    );
    final tree = await driver.renderTree();
    if (tree.contains(model)) {
      throw StateError('account list rendered model modelId');
    }
  }

  Future<void> openAccounts() async {
    await driver.waitFor(
      find.byValueKey('settings-open'),
      timeout: const Duration(seconds: 60),
    );
    await driver.tap(find.byValueKey('settings-open'));
    await driver.waitFor(find.byValueKey('settings-page'));
    await driver.tap(find.byValueKey('settings-tab-accounts'));
    await driver.waitFor(find.byValueKey('account-add'));
  }

  Future<void> openDetails(String id) async {
    await driver.tap(find.byValueKey('account-row-$id'));
    await driver.waitFor(find.byValueKey('account-edit'));
  }

  Future<void> _scrollTo(SerializableFinder finder) async {
    // The isolated gui fixture has three model cards. Re-anchor at the top so
    // targets above a lazy ListView's cache are built before scrolling down.
    await driver.scrollBy(find.byValueKey('account-editor'), 3000);
    await driver.scrollUntilVisible(
      find.byValueKey('account-editor'),
      finder,
      dyScroll: -220,
      timeout: const Duration(seconds: 45),
    );
  }

  Future<void> setCompactInput(String id, String modelId, String value) async {
    final finder = find.byValueKey(
      'account-$id-model-$modelId-auto-compact-input',
    );
    await _scrollTo(finder);
    await driver.tap(finder);
    await driver.enterText(value);
  }

  Future<void> tapCompactReset(String id, String modelId) async {
    final finder = find.byValueKey(
      'account-$id-model-$modelId-auto-compact-reset',
    );
    await _scrollTo(finder);
    await driver.tap(finder);
  }
}

List<Map<String, dynamic>> _accounts(Map<String, dynamic> snapshot) => [
  for (final account in snapshot['settings']['accounts'] as List)
    (account as Map).cast<String, dynamic>(),
];
Map<String, dynamic> _account(Map<String, dynamic> snapshot, String id) =>
    _accounts(snapshot).singleWhere((account) => account['id'] == id);
List<String> _models(Map<String, dynamic> account) => [
  for (final model in account['models'] as List) '$model',
];
Map<String, dynamic> _limit(
  Map<String, dynamic> snapshot,
  String id,
  String modelId,
) => (_account(snapshot, id)['autoCompactLimits'] as List)
    .cast<Map>()
    .singleWhere((limit) => limit['modelId'] == modelId)
    .cast<String, dynamic>();
