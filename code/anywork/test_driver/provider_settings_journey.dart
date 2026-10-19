import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'driver_observation.dart';
import 'flutter_driver_session.dart';

/// Real-bridge manual journey for detail-list auto-save, not a widget test.
/// Run with cargo xtask manual-gui --scenario gui, then:
/// cargo dart test_driver/provider_settings_journey.dart VM_URL OUTPUT_DIR
/// Only the isolated fixture provider is edited; no system credential account
/// is created. The operator still sends the fixture prompt and `done` to the
/// harness, reviews screenshots and records the human verdict separately.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: provider_settings_journey.dart VM_URL OUTPUT_DIR');
    exitCode = 64;
    return;
  }
  final output = Directory(args[1]);
  await output.create(recursive: true);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  try {
    final recorder = _Recorder(output, driver);
    final baseline = await recorder.readSnapshot();
    final fixture = _providers(baseline)
        .where((provider) => '${provider['id']}'.startsWith('gui-fixture-'))
        .single;
    final id = '${fixture['id']}';
    final model = '${fixture['defaultModel']}';
    final siblings = {
      for (final modelId in _models(fixture))
        if (modelId != model) modelId: _limit(baseline, id, modelId),
    };
    await recorder.openProviders();
    await recorder.assertProviderListRedacted(id, model);
    await recorder.openDetails(id);
    await recorder.capture('details-defaults', await recorder.readSnapshot());
    await driver.waitForAbsent(find.byValueKey('provider-save'));
    final preset = _models(fixture).singleWhere((modelId) {
      final limit = _limit(baseline, id, modelId);
      return limit['safe'] != null && limit['default'] != limit['safe'];
    });
    await recorder._scrollTo(
      find.byValueKey('provider-$id-model-$preset-auto-compact-input'),
    );
    await recorder.capture(
      'model-preset-default',
      await recorder.readSnapshot(),
    );

    await recorder.setCompactInput(id, model, '18000');
    await recorder.capture('input-pending', await recorder.readSnapshot());
    final afterInput = await recorder.waitOverride(id, model, 18000);
    await recorder.capture('input-applied-without-save', afterInput);
    final safe = _limit(afterInput, id, model)['safe'];
    if (safe is! int || safe <= 0) {
      throw StateError('fixture capacity is missing');
    }
    await recorder.setCompactInput(id, model, '${safe + 10000}');
    final above = await recorder.waitOverride(id, model, safe + 10000);
    if (_limit(above, id, model)['effective'] != safe) {
      throw StateError('above-safe override was not clamped');
    }
    await recorder.capture('above-safe-clamped', above);

    await recorder.setCompactInput(id, model, 'not-a-number');
    // Negative proof: observe past the 650ms debounce, not merely one frame.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final invalid = await recorder.readSnapshot();
    if (_limit(invalid, id, model)['override'] != safe + 10000 ||
        invalid['settings']['revision'] != above['settings']['revision']) {
      throw StateError('invalid input changed canonical settings');
    }
    await recorder.capture('invalid-kept-not-persisted', invalid);

    await recorder.moveCompactSlider(id, model);
    final slider = await recorder.waitLimit(
      id,
      model,
      (limit) => limit['override'] is int && (limit['override'] as int) <= safe,
    );
    await recorder.capture('slider-applied', slider);
    await recorder.tapCompactReset(id, model);
    await recorder.waitOverride(id, model, null);
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
        .where((modelId) => _limit(baseline, id, modelId)['safe'] == null)
        .single;
    if (_limit(baseline, id, unknown)['default'] != null) {
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

    // Explicit Save remains only for other provider fields, with no second
    // threshold entry. Its canonical payload must preserve the thresholds.
    await driver.scrollBy(find.byValueKey('provider-editor'), 3000);
    await driver.tap(find.byValueKey('provider-edit'));
    await driver.waitFor(find.byValueKey('provider-save'));
    await driver.waitForAbsent(
      find.byValueKey('provider-$id-model-$model-auto-compact-input'),
    );
    await recorder.capture(
      'editor-without-threshold-entry',
      await recorder.readSnapshot(),
    );
    await driver.tap(find.byValueKey('provider-save'));
    await driver.waitForAbsent(find.byValueKey('provider-save'));
    final afterProviderSave = await recorder.waitOverride(id, model, 21000);
    if (_limit(afterProviderSave, id, unknown)['override'] != null) {
      throw StateError(
        'provider field save restored a cleared sibling override',
      );
    }
    await recorder.capture(
      'provider-save-preserved-overrides',
      afterProviderSave,
    );
    await recorder.openDetails(id);
    await recorder.tapCompactReset(id, model);
    await recorder.waitOverride(id, model, null);
    await File('${output.path}/provider-journey-summary.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'fixtureProviderId': id, 'model': model, 'unknownModel': unknown, 'inlineAutoSave': true, 'slider': true, 'restoreDefault': true, 'invalidNotPersisted': true, 'aboveSafeClamped': true, 'latestIntent': true, 'siblingsUnchanged': true, 'secondEditorEntryAbsent': true, 'humanVerdict': 'pending'})}\n',
    );
    stdout.writeln('Provider journey captured; human verdict pending.');
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

  Future<void> assertProviderListRedacted(String id, String model) async {
    verifyProviderListRedacted(
      await readSnapshot(),
      fixtureModelId: model,
      providerId: id,
    );
    final tree = await driver.renderTree();
    if (tree.contains(model)) {
      throw StateError('provider list rendered model modelId');
    }
  }

  Future<void> openProviders() async {
    await driver.waitFor(
      find.byValueKey('settings-open'),
      timeout: const Duration(seconds: 60),
    );
    await driver.tap(find.byValueKey('settings-open'));
    await driver.waitFor(find.byValueKey('settings-page'));
    await driver.tap(find.byValueKey('settings-tab-providers'));
    await driver.waitFor(find.byValueKey('provider-add'));
  }

  Future<void> openDetails(String id) async {
    await driver.tap(find.byValueKey('provider-row-$id'));
    await driver.waitFor(find.byValueKey('provider-edit'));
  }

  Future<void> _scrollTo(SerializableFinder finder) async {
    // The isolated gui fixture has three model cards. Re-anchor at the top so
    // targets above a lazy ListView's cache are built before scrolling down.
    await driver.scrollBy(find.byValueKey('provider-editor'), 3000);
    await driver.scrollUntilVisible(
      find.byValueKey('provider-editor'),
      finder,
      dyScroll: -220,
      timeout: const Duration(seconds: 45),
    );
  }

  Future<void> setCompactInput(String id, String modelId, String value) async {
    final finder = find.byValueKey(
      'provider-$id-model-$modelId-auto-compact-input',
    );
    await _scrollTo(finder);
    await driver.tap(finder);
    await driver.enterText(value);
  }

  Future<void> moveCompactSlider(String id, String modelId) async {
    final finder = find.byValueKey(
      'provider-$id-model-$modelId-auto-compact-slider',
    );
    await _scrollTo(finder);
    await driver.rawTap(finder);
  }

  Future<void> tapCompactReset(String id, String modelId) async {
    final finder = find.byValueKey(
      'provider-$id-model-$modelId-auto-compact-reset',
    );
    await _scrollTo(finder);
    await driver.tap(finder);
  }
}

List<Map<String, dynamic>> _providers(Map<String, dynamic> snapshot) => [
  for (final provider in snapshot['settings']['providers'] as List)
    (provider as Map).cast<String, dynamic>(),
];
Map<String, dynamic> _provider(Map<String, dynamic> snapshot, String id) =>
    _providers(snapshot).singleWhere((provider) => provider['id'] == id);
List<String> _models(Map<String, dynamic> provider) => [
  for (final model in provider['models'] as List) '$model',
];
Map<String, dynamic> _limit(
  Map<String, dynamic> snapshot,
  String id,
  String modelId,
) => (_provider(snapshot, id)['autoCompactLimits'] as List)
    .cast<Map>()
    .singleWhere((limit) => limit['modelId'] == modelId)
    .cast<String, dynamic>();
