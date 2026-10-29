import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'package:anywork/src/features/settings/accounts/state/account_view_key_values.dart';

import 'driver_observation.dart';
import 'flutter_driver_session.dart';
import 'key_press.dart';
import 'raw_tap.dart';

/// Real-bridge manual journey for explicit model threshold saves.
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
    final startup = await recorder.readSnapshot();
    final fixture = _accounts(startup)
        .where((account) => '${account['id']}'.startsWith('gui-fixture-'))
        .single;
    final id = '${fixture['id']}';
    final originalName =
        (startup['settings']['accountDomains']['accounts'] as List)
                .cast<Map>()
                .singleWhere(
                  (account) =>
                      account['kind'] == 'native' && account['id'] == id,
                )['name']
            as String;
    final model =
        (fixture['modelDetails'] as List).cast<Map>().firstWhere(
              (model) =>
                  model['enabled'] == true &&
                  model['contextWindow'] is int &&
                  (model['contextWindow'] as int) > 21000,
            )['modelId']
            as String;
    await recorder.openAccounts();
    await recorder.assertAccountListRedacted(id, model);
    await recorder.inspectListMenu(id);
    await recorder.openDetails(id);
    final baseline = await recorder.waitLimit(
      id,
      model,
      (value) =>
          value['override'] == null &&
          value['effective'] is int &&
          value['adjustment'] == null &&
          value['unavailable'] == null,
      expected: const {
        'override': null,
        'effective': 'observed int',
        'adjustment': null,
        'unavailable': null,
      },
    );
    final automatic = Map<String, dynamic>.from(_limit(baseline, id, model));
    final siblings = {
      for (final modelId in _models(fixture))
        if (modelId != model) modelId: _limit(baseline, id, modelId),
    };
    await recorder.capture('details-defaults', baseline);
    await driver.waitForAbsent(find.byValueKey('account-save'));
    final template = _models(fixture).singleWhere(
      (modelId) =>
          modelId != model &&
          _limit(baseline, id, modelId)['effective'] != null,
    );
    await recorder.revealCompact(id, template);
    await recorder.capture(
      'model-template-default',
      await recorder.readSnapshot(),
    );
    await recorder.copyThresholdReading(
      id,
      model,
      automatic['effective'] as int,
    );
    await recorder.copyAdvancedIdentity(id);

    await recorder.setCompactInput(id, model, '18000');
    await recorder.capture('input-pending', await recorder.readSnapshot());
    await recorder.capture(
      'input-draft-not-submitted',
      await recorder.observeDraftUnchanged(
        id,
        model,
        automatic,
        baseline['settings']['revision'] as int,
      ),
    );
    await recorder.visitModelDetails(id, model, expectedRaw: '18000');
    await recorder.capture(
      'model-tabs-return-draft-not-submitted',
      await recorder.observeDraftUnchanged(
        id,
        model,
        automatic,
        baseline['settings']['revision'] as int,
      ),
    );
    await recorder.tapCompactSave(id, model);
    final afterInput = await recorder.waitThreshold(id, model, {
      ...automatic,
      'override': 18000,
      'effective': 18000,
    });
    await recorder.capture('explicit-save-applied', afterInput);
    const excessive = 9000000000;
    await recorder.setCompactInput(id, model, '$excessive');
    await recorder.tapCompactSave(id, model);
    final contextWindow =
        (fixture['modelDetails'] as List).cast<Map>().singleWhere(
              (item) => item['modelId'] == model,
            )['contextWindow']
            as int;
    final above = await recorder.waitLimit(
      id,
      model,
      (value) {
        final effective = value['effective'];
        return value['override'] == excessive &&
            value['adjustment'] == 'safetyLimit' &&
            effective is int &&
            effective > 0 &&
            effective <= contextWindow &&
            effective < excessive;
      },
      expected: {
        'override': excessive,
        'adjustment': 'safetyLimit',
        'effective':
            'positive backend clamp within contextWindow=$contextWindow',
      },
    );
    // Automatic policy is not the safety cap. Observe the real normalized
    // result instead of assuming Clear and an excessive override share a value.
    final aboveExpected = Map<String, dynamic>.from(_limit(above, id, model));
    await recorder.capture('above-safe-clamped', above);

    await recorder.setCompactInput(id, model, 'not-a-number');
    // Invalid draft input must not alter either authoritative resource.
    final invalid = await recorder.observeDraftUnchanged(
      id,
      model,
      aboveExpected,
      above['settings']['revision'] as int,
    );
    await recorder.capture('invalid-kept-not-persisted', invalid);

    await recorder.tapCompactReset(id, model);
    final reset = await recorder.waitThreshold(id, model, automatic);
    await recorder.capture('restored-default', reset);

    // Rapid typing must keep the newest raw input and eventually canonicalize
    // it only after explicit Save, without a page round trip. Deterministic CAS/old-ACK races live in the
    // SDK-only Client suite, rather than being faked inside Driver.
    await recorder.setCompactInput(id, model, '19000');
    await recorder.setCompactInput(id, model, '21000');
    await driver.sendTextInputAction(TextInputAction.done);
    await recorder.tapCompactSave(id, model);
    final latestExpected = {
      ...automatic,
      'override': 21000,
      'effective': 21000,
    };
    final latest = await recorder.waitThreshold(id, model, latestExpected);
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
    final unknownAutomatic = Map<String, dynamic>.from(
      _limit(baseline, id, unknown),
    );
    if (unknownAutomatic['override'] != null) {
      throw StateError(
        'unknown-capacity fixture did not start at its automatic value',
      );
    }
    await recorder.setCompactInput(id, unknown, '17000');
    await recorder.tapCompactSave(id, unknown);
    final unknownApplied = await recorder.waitThreshold(id, unknown, {
      ...unknownAutomatic,
      'override': 17000,
    });
    await recorder.capture('unknown-capacity-stays-off', unknownApplied);
    await recorder.tapCompactReset(id, unknown);
    await recorder.waitThreshold(id, unknown, unknownAutomatic);

    // Billing is an immediate, narrow detail action. A later connection form
    // save must preserve it rather than replay a stale account card.
    final billingMenu = find.byValueKey('account-billing-menu');
    await recorder.revealDetails(id, billingMenu);
    await driver.mouseTap(billingMenu);
    await driver.mouseTap(find.byValueKey('account-billing-noCharge'));
    await recorder.capture(
      'no-charge-canonical',
      await recorder.waitBilling(id, 'noCharge', 'noCharge'),
    );
    await driver.scrollBy(await recorder.detailsScroll(id), 10000);
    await driver.mouseTap(find.byValueKey('account-edit'));
    await driver.waitFor(
      find.byValueKey('account-save'),
      timeout: FlutterDriverSession.tapDeadline,
    );
    await driver.waitForAbsent(find.byType('AccountCompactView'));
    final editorView = (await recorder
        .readSnapshot())['driverDiagnostics']['accountsPresentation']['mountedViews']['nativeEditor'];
    if (editorView == null ||
        (editorView['compactModelIds'] as List).isNotEmpty) {
      throw StateError('connection editor includes a second threshold entry');
    }
    await recorder.capture(
      'editor-without-threshold-entry',
      await recorder.readSnapshot(),
    );
    const editedName = 'Account connection edit journey';
    await recorder.setEditorName(id, editedName);
    await driver.mouseTap(find.byValueKey('account-save'));
    await driver.waitForAbsent(find.byValueKey('account-save'));
    await recorder.waitAccountName(id, editedName);
    await recorder.waitPresentation(
      (value) => _hasAccountDetails(value, 'native', id),
      'saved editor committed Native details',
    );
    final afterAccountSave = await recorder.waitThreshold(
      id,
      model,
      latestExpected,
    );
    if (_account(afterAccountSave, id)['billingKind'] != 'noCharge') {
      throw StateError(
        'ordinary connection save replayed stale billing intent',
      );
    }
    if (_limit(afterAccountSave, id, unknown)['override'] != null) {
      throw StateError(
        'account field save restored a cleared sibling override',
      );
    }
    await recorder.capture(
      'account-save-preserved-overrides',
      afterAccountSave,
    );
    await driver.waitFor(find.byValueKey('account-edit'));
    final resetBilling = find.descendant(
      of: find.byType('AccountBillingControl'),
      matching: find.text(await recorder.label('restore')),
    );
    await recorder.revealDetails(id, resetBilling);
    await driver.mouseTap(resetBilling);
    await recorder.capture(
      'no-charge-off-restores-auto',
      await recorder.waitBilling(id, '${fixture['billingKind']}', null),
    );
    await recorder.tapCompactReset(id, model);
    await recorder.waitThreshold(id, model, automatic);
    // Restore the isolated fixture's name so later journeys see the same
    // account identity/label; this is a new UI intent, not replaying Save.
    await driver.scrollBy(await recorder.detailsScroll(id), 10000);
    await driver.mouseTap(find.byValueKey('account-edit'));
    await driver.waitFor(
      find.byValueKey('account-save'),
      timeout: FlutterDriverSession.tapDeadline,
    );
    await recorder.setEditorName(id, originalName);
    await driver.mouseTap(find.byValueKey('account-save'));
    await driver.waitForAbsent(find.byValueKey('account-save'));
    await recorder.waitAccountName(id, originalName);
    await recorder.waitBilling(id, '${fixture['billingKind']}', null);
    final restored = await recorder.waitThreshold(id, model, automatic);
    if (_limit(restored, id, model)['override'] != null) {
      throw StateError(
        'restoring the connection form replayed a cleared threshold',
      );
    }
    await recorder.discardConnectionEdit(id, originalName);
    await driver.mouseTap(find.text('Back to chat'));
    await driver.waitForAbsent(find.byValueKey('settings-page'));
    await driver.waitFor(find.byValueKey('settings-open'));
    await File('${output.path}/account-journey-summary.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'fixtureAccountId': id, 'model': model, 'unknownModel': unknown, 'mouseInput': true, 'listMenuDoesNotOpenDetails': true, 'listMenuEdit': true, 'listDeleteCancellation': true, 'backToChat': true, 'selectableReadingKeyboardCopy': true, 'advancedIdentityContextMenuCopy': true, 'dirtyCancelAndDiscard': true, 'explicitSave': true, 'unsavedDraftNotPersisted': true, 'modelDetailsThreeTabsRetainDraft': true, 'backendPolicy': true, 'restoreDefault': true, 'invalidNotPersisted': true, 'aboveSafeClamped': true, 'latestIntent': true, 'siblingsUnchanged': true, 'secondEditorEntryAbsent': true, 'noChargeCanonical': true, 'connectionEditPreservesBilling': true, 'noChargeOffClearsOverride': true, 'humanVerdict': 'pending'})}\n',
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

  Future<void> inspectListMenu(String id) async {
    // The isolated gui fixture uses English localization.
    final menu = find.byValueKey(AccountViewKeyValues.rowMenu('native', id));
    await driver.mouseTap(menu);
    await driver.waitFor(find.text('Edit account'));
    if (!_hasAccountList((await usage())['presentation'] as Map)) {
      throw StateError('opening the account menu navigated to details');
    }
    await capture('list-menu-mouse', await readSnapshot());
    await driver.pressKey(0x10000001b, 0x70029);
    await driver.waitForAbsent(find.byType('MenuItemButton'));
    await driver.mouseTap(menu);
    await driver.mouseTap(find.text('Edit account'));
    await waitEditorId(id);
    await capture('list-menu-edit', await readSnapshot());
    await driver.mouseTap(find.byValueKey('account-cancel'));
    await waitPresentation(
      (value) => _hasAccountDetails(value, 'native', id),
      'clean edit returned to its typed parent details',
    );
    await driver.mouseTap(find.byValueKey('account-back'));
    await waitPresentation(_hasAccountList, 'details returned to list');
    await driver.mouseTap(menu);
    await driver.mouseTap(find.text(await label('delete')));
    await driver.waitFor(find.byType('SimpleDialog'));
    await capture('list-delete-requires-replacement', await readSnapshot());
    await driver.pressKey(0x10000001b, 0x70029);
    await driver.waitForAbsent(find.byType('SimpleDialog'));
    if (!_accounts(await readSnapshot())
        .any((account) => account['id'] == id)) {
      throw StateError('cancelled replacement removed the default account');
    }
    await waitPresentation(_hasAccountList, 'cancelled deletion kept the list');
  }

  Future<void> copyThresholdReading(
    String id,
    String model,
    int effective,
  ) async {
    final tile = await revealCompact(id, model);
    final expected = 'Effective · $effective';
    final text = find.descendant(of: tile, matching: find.text(expected));
    await revealDetails(id, text);
    await driver.mouseTap(text);
    await driver.sendCommand(
      KeyPress(0x200000100, 0x700e0, phase: KeyPressPhase.down),
    );
    try {
      await driver.pressKey(0x61, 0x70004);
      await driver.pressKey(0x63, 0x70006);
    } finally {
      await driver.sendCommand(
        KeyPress(0x200000100, 0x700e0, phase: KeyPressPhase.up),
      );
    }
    final clipboard = jsonDecode(
      await driver.requestData(
        jsonEncode({'cmd': 'clipboard-text', 'full': true}),
      ),
    ) as Map;
    if (clipboard['text'] != expected) {
      throw StateError(
        'SelectableText Copy did not reach the native clipboard',
      );
    }
    await capture('selectable-reading-copied', await readSnapshot());
  }

  Future<void> copyAdvancedIdentity(String id) async {
    final advanced = find.descendant(
      of: _detailsView,
      matching: find.text('Advanced information'),
    );
    await revealDetails(id, advanced);
    await driver.mouseTap(advanced);
    final text = find.descendant(of: _detailsView, matching: find.text(id));
    await revealDetails(id, text);
    await driver.mouseTap(text);
    await driver.sendCommand(
      KeyPress(0x200000100, 0x700e0, phase: KeyPressPhase.down),
    );
    try {
      await driver.pressKey(0x61, 0x70004);
    } finally {
      await driver.sendCommand(
        KeyPress(0x200000100, 0x700e0, phase: KeyPressPhase.up),
      );
    }
    await driver.sendCommand(
      RawTap(
        text,
        pointerKind: RawTapKind.mouse,
        button: RawTapButton.secondary,
      ),
    );
    await driver.waitFor(find.text('Copy'));
    await capture('advanced-identity-context-menu', await readSnapshot());
    await driver.mouseTap(find.text('Copy'));
    final clipboard = jsonDecode(
      await driver.requestData(
        jsonEncode({'cmd': 'clipboard-text', 'full': true}),
      ),
    ) as Map;
    if (clipboard['text'] != id) {
      throw StateError(
        'context-menu Copy did not copy the selected account ID',
      );
    }
    await capture('advanced-identity-copied', await readSnapshot());
  }

  Future<void> discardConnectionEdit(String id, String originalName) async {
    await driver.scrollBy(await detailsScroll(id), 10000);
    await driver.mouseTap(find.byValueKey('account-edit'));
    await setEditorName(id, '$originalName discarded draft');
    await driver.mouseTap(find.byValueKey('account-cancel'));
    await driver.waitFor(find.byType('AccountUnsavedChangesDialog'));
    await capture('dirty-leave-confirmation', await readSnapshot());
    await driver.mouseTap(find.text('Keep editing'));
    await driver.waitForAbsent(find.byType('AccountUnsavedChangesDialog'));
    await waitEditorId(id);
    await driver.mouseTap(find.byValueKey('account-cancel'));
    await driver.mouseTap(find.text(await label('discard')));
    await driver.waitForAbsent(find.byType('AccountUnsavedChangesDialog'));
    await waitPresentation(
      (value) => _hasAccountDetails(value, 'native', id),
      'discard returned to the original account',
    );
    await waitAccountName(id, originalName);
    await capture('dirty-draft-discarded', await readSnapshot());
  }

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

  Future<Map<String, dynamic>> waitThreshold(
    String id,
    String model,
    Map<String, dynamic> expected,
  ) => waitLimit(
    id,
    model,
    (limit) =>
        expected.entries.every((entry) => limit[entry.key] == entry.value),
    expected: expected,
  );

  Future<Map<String, dynamic>> waitBilling(
    String id,
    String kind,
    String? override,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await readSnapshot();
      final account = _account(snapshot, id);
      if (account['billingKind'] == kind &&
          account['billingKindOverride'] == override) {
        return snapshot;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'canonical billing kind did not settle: $id/$kind/$override',
    );
  }

  Future<void> waitAccountName(String id, String name) async {
    final deadline = DateTime.now().add(FlutterDriverSession.tapDeadline);
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await readSnapshot().timeout(
        deadline.difference(DateTime.now()),
      );
      final domains = snapshot['settings']['accountDomains'] as Map;
      final matches = (domains['accounts'] as List)
          .cast<Map>()
          .where(
            (account) => account['kind'] == 'native' && account['id'] == id,
          )
          .toList();
      if (domains['summaries']['loaded'] == true &&
          matches.length == 1 &&
          matches.single['name'] == name) {
        return;
      }
      final remaining = deadline.difference(DateTime.now()).inMilliseconds;
      if (remaining <= 0) break;
      await Future<void>.delayed(
        Duration(milliseconds: remaining.clamp(1, 100)),
      );
    }
    throw StateError(
      'canonical Native account name did not settle within 30 seconds: $id',
    );
  }

  Future<Map<String, dynamic>> waitLimit(
    String id,
    String model,
    bool Function(Map<String, dynamic>) predicate, {
    required Map<String, dynamic> expected,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await readSnapshot();
      last = snapshot;
      if (_thresholdResourcesReady(snapshot, id) &&
          predicate(_limit(snapshot, id, model))) {
        return snapshot;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await recordThresholdFailure(id, model, expected, last);
    throw StateError('canonical threshold did not settle: $id/$model');
  }

  Future<Map<String, dynamic>> observeDraftUnchanged(
    String id,
    String model,
    Map<String, dynamic> expected,
    int settingsRevision,
  ) async {
    // Observe beyond the removed automatic-submit timer to prove raw typing
    // (valid or invalid) never writes canonical settings before Save.
    final deadline = DateTime.now().add(const Duration(milliseconds: 1100));
    while (true) {
      final snapshot = await readSnapshot();
      final limit = _limit(snapshot, id, model);
      if (!_thresholdResourcesReady(snapshot, id) ||
          !expected.entries.every((entry) => limit[entry.key] == entry.value) ||
          snapshot['settings']['revision'] != settingsRevision) {
        await recordThresholdFailure(id, model, {
          ...expected,
          'settingsRevision': settingsRevision,
          'condition':
              'unchanged throughout the unsaved-draft observation window',
        }, snapshot);
        throw StateError('unsaved draft changed canonical settings');
      }
      final remaining = deadline.difference(DateTime.now()).inMilliseconds;
      if (remaining <= 0) return snapshot;
      await Future<void>.delayed(
        Duration(milliseconds: remaining.clamp(1, 100)),
      );
    }
  }

  Future<void> recordThresholdFailure(
    String id,
    String model,
    Map<String, dynamic> expected,
    Map<String, dynamic>? snapshot,
  ) async {
    try {
      final domains = snapshot?['settings']?['accountDomains'] as Map?;
      final account = snapshot == null
          ? null
          : _accounts(snapshot)
                .where((account) => account['id'] == id)
                .firstOrNull;
      await File(
        '${output.path}/threshold-failure-${_captureIndex++}.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'target': {'kind': 'native', 'id': id, 'modelId': model},
          'expected': expected,
          'settingsRevision': snapshot?['settings']?['revision'],
          'actualLimits': account?['autoCompactLimits'],
          'resources': {
            for (final domain in const ['catalogs', 'configurations'])
              domain: [
                for (final resource in domains?[domain] as List? ?? const [])
                  if ((resource as Map)['accountId'] == id) resource,
              ],
          },
        }),
      );
    } catch (error) {
      stderr.writeln('threshold failure capture failed: ${error.runtimeType}');
    }
  }

  Future<void> assertAccountListRedacted(String id, String model) async {
    final list = find.descendant(
      of: find.byValueKey('settings-page'),
      matching: find.byType('AccountsListView'),
    );
    final add = find.descendant(
      of: list,
      matching: find.byValueKey('account-add'),
    );
    final snapshot = await readSnapshot();
    Map<String, dynamic>? widget;
    _RenderedAccountList? rendered;
    try {
      // Official finders skip offstage routes. Tappability additionally proves
      // this is the current page, not a retained background list.
      await driver.sendCommand(
        WaitForTappable(add, timeout: const Duration(seconds: 15)),
      );
      await driver.waitFor(
        find.descendant(
          of: list,
          matching: find.byValueKey(AccountViewKeyValues.row('native', id)),
        ),
        timeout: const Duration(seconds: 15),
      );
      widget = await driver.sendCommand(
        GetDiagnosticsTree(
          list,
          DiagnosticsType.widget,
          includeProperties: false,
          timeout: const Duration(seconds: 15),
        ),
      );
      if (widget['widgetRuntimeType'] != 'AccountsListView') {
        throw StateError('the current page has no production AccountsListView');
      }
      final tree = await driver.sendCommand(
        GetDiagnosticsTree(
          list,
          DiagnosticsType.renderObject,
          subtreeDepth: 128,
          timeout: const Duration(seconds: 15),
        ),
      );
      rendered = _RenderedAccountList.read(tree);
      verifyAccountListRedacted(snapshot, fixtureModelId: model, accountId: id);
      final modelIds = {
        model,
        for (final account in driverAccountDetailsObservation(snapshot))
          for (final descriptor in account['models'] as List? ?? const [])
            if (descriptor is Map && descriptor['modelId'] is String)
              descriptor['modelId'] as String,
      };
      rendered.verify(modelIds);
    } catch (error, stack) {
      // Capture only this synthetic list scenario: never dump the entire
      // window, background chat, arbitrary diagnostic properties or text here.
      try {
        await File('${output.path}/account-list-redaction-failure.json')
            .writeAsString(
              const JsonEncoder.withIndent('  ').convert({
                'scope': 'settings-page / AccountsListView',
                'widgetRuntimeType': widget?['widgetRuntimeType'],
                'renderNodeCount': rendered?.nodeCount,
                'renderedTextCount': rendered?.texts.length,
                'canonicalList': driverAccountListObservation(snapshot),
                'fixtureAccountId': id,
                'fixtureModelId': model,
              }),
            );
        await File('${output.path}/account-list-redaction-failure.png')
            .writeAsBytes(await driver.screenshot());
      } catch (captureError) {
        stderr.writeln(
          'account list failure capture failed: ${captureError.runtimeType}',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> openAccounts() async {
    await driver.waitFor(
      find.byValueKey('settings-open'),
      timeout: const Duration(seconds: 60),
    );
    await driver.mouseTap(find.byValueKey('settings-open'));
    await driver.waitFor(find.byValueKey('settings-page'));
    await driver.mouseTap(find.byValueKey('settings-tab-accounts'));
    await driver.waitFor(find.byValueKey('account-add'));
    await waitPresentation(_hasAccountList, 'committed account list');
  }

  Future<void> openDetails(String id) async {
    final list = find.descendant(
      of: find.byValueKey('settings-page'),
      matching: find.byType('AccountsListView'),
    );
    final row = find.descendant(
      of: list,
      matching: find.byValueKey(AccountViewKeyValues.row('native', id)),
    );
    await driver.scrollUntilVisible(
      find.descendant(of: list, matching: find.byType('ListView')),
      row,
      dyScroll: -180,
      timeout: FlutterDriverSession.tapDeadline,
    );
    await driver.mouseTap(row);
    await driver.waitFor(find.byValueKey('account-edit'));
    await waitPresentation(
      (value) => _hasAccountDetails(value, 'native', id),
      'committed Native details',
    );
  }

  Future<Map<String, dynamic>> usage() async =>
      (jsonDecode(await driver.requestData('account-usage-state')) as Map)
          .cast<String, dynamic>();

  Future<String> label(String name) async =>
      ((await usage())['labels'] as Map)[name] as String;

  Future<Map> waitPresentation(
    bool Function(Map) predicate,
    String description,
  ) async {
    final deadline = DateTime.now().add(FlutterDriverSession.tapDeadline);
    while (DateTime.now().isBefore(deadline)) {
      final value = (await usage())['presentation'] as Map;
      if (predicate(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('account presentation did not settle: $description');
  }

  Future<String> waitEditorId(String id) async {
    final deadline = DateTime.now().add(FlutterDriverSession.tapDeadline);
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await readSnapshot().timeout(
        deadline.difference(DateTime.now()),
      );
      final presentation =
          snapshot['driverDiagnostics']['accountsPresentation'] as Map;
      final editor = presentation['editor'] as Map?;
      final mounted = presentation['mountedViews']?['nativeEditor'] as Map?;
      if (_hasAccountEditor(presentation) &&
          _isAccountPage(presentation, 'edit', kind: 'native', id: id) &&
          editor != null) {
        final target = editor['target'] as Map?;
        if (target?['kind'] != 'native' ||
            target?['id'] != id ||
            editor['creating'] != false) {
          throw StateError(
            'the observed editor is not the requested existing Native account: $id',
          );
        }
        final editorId = editor['editorId'];
        if (editorId is String &&
            editorId.isNotEmpty &&
            editor['stale'] == false &&
            editor['saving'] == false &&
            mounted?['editorId'] == editorId) {
          return editorId;
        }
      }
      final remaining = deadline.difference(DateTime.now()).inMilliseconds;
      if (remaining <= 0) break;
      await Future<void>.delayed(
        Duration(milliseconds: remaining.clamp(1, 100)),
      );
    }
    throw StateError(
      'the existing Native editor did not become ready within 30 seconds: $id',
    );
  }

  SerializableFinder get _detailsView => find.descendant(
    of: find.byValueKey('settings-page'),
    matching: find.byType('AccountDetailsView'),
  );

  Future<SerializableFinder> detailsScroll(String id) async {
    final presentation =
        (await readSnapshot())['driverDiagnostics']['accountsPresentation']
            as Map;
    if (!_hasAccountDetails(presentation, 'native', id)) {
      throw StateError(
        'the current details view is not the requested Native account',
      );
    }
    // PageStorageKey is intentionally not ValueKey. Keep production scroll
    // restoration and use the unique ListView inside the current details view.
    return find.descendant(of: _detailsView, matching: find.byType('ListView'));
  }

  Future<void> revealDetails(String id, SerializableFinder finder) async {
    final scroll = await detailsScroll(id);
    await driver.scrollBy(scroll, 10000);
    await driver.scrollUntilVisible(
      scroll,
      finder,
      dyScroll: -180,
      timeout: FlutterDriverSession.tapDeadline,
    );
  }

  Future<void> setEditorName(String id, String value) async {
    final deadline = DateTime.now().add(FlutterDriverSession.tapDeadline);
    Duration remaining() {
      final budget = deadline.difference(DateTime.now());
      if (budget <= Duration.zero) {
        throw StateError(
          'Native name draft did not become save-ready within 30 seconds: $id',
        );
      }
      return budget;
    }

    Duration layoutBudget() {
      final budget = remaining();
      return budget < FlutterDriverSession.geometryDeadline
          ? budget
          : FlutterDriverSession.geometryDeadline;
    }

    final editorId = await waitEditorId(id).timeout(remaining());
    final view = find.descendant(
      of: find.byValueKey('settings-page'),
      matching: find.byType('NativeAccountEditorView'),
    );
    Future<Map?> readCurrentEditor() async {
      final snapshot = await readSnapshot().timeout(remaining());
      final presentation =
          snapshot['driverDiagnostics']['accountsPresentation'] as Map;
      final editor = presentation['editor'] as Map?;
      final mounted = presentation['mountedViews']?['nativeEditor'] as Map?;
      if (editor != null &&
          (editor['editorId'] != editorId ||
              editor['target']?['kind'] != 'native' ||
              editor['target']?['id'] != id ||
              editor['creating'] != false)) {
        throw StateError(
          'Native name editor identity changed before Save: $id',
        );
      }
      if (mounted != null && mounted['editorId'] != editorId) {
        throw StateError(
          'a different Native name editor was mounted before Save: $id',
        );
      }
      return !_hasAccountEditor(presentation) ||
              !_isAccountPage(presentation, 'edit', kind: 'native', id: id)
          ? null
          : editor;
    }

    final baseline = await readCurrentEditor();
    final baselineRevision = baseline?['draftRevision'];
    if (baselineRevision is! int ||
        baseline?['saving'] != false ||
        baseline?['stale'] != false) {
      throw StateError('Native name editor has no current input baseline: $id');
    }
    bool ready(Map? editor) {
      final revision = editor?['draftRevision'];
      return revision is int &&
          revision > baselineRevision &&
          editor?['dirty'] == true &&
          editor?['canSave'] == true &&
          editor?['saving'] == false &&
          editor?['stale'] == false;
    }

    final field = find.descendant(
      of: find.descendant(
        of: view,
        matching: find.byValueKey(
          AccountViewKeyValues.editorField(editorId, 'name'),
        ),
      ),
      matching: find.byType('EditableText'),
    );
    final save = find.descendant(
      of: view,
      matching: find.byValueKey('account-save'),
    );
    await driver.mouseTap(field, timeout: remaining());
    await driver.enterText(value).timeout(remaining());
    while (true) {
      final editor = await readCurrentEditor();
      if (ready(editor) &&
          await driver.getText(field).timeout(remaining()) == value) {
        // Hit-testability alone cannot prove a button is enabled. Require the
        // current owner to authorize Save, then let its footer rebuild before
        // checking the real control. No Save is issued by this preparation.
        await driver
            .waitForNoPendingFrame(timeout: layoutBudget())
            .timeout(remaining());
        await driver.sendCommand(
          WaitForTappable(save, timeout: layoutBudget()),
        );
        if (ready(await readCurrentEditor()) &&
            await driver.getText(field).timeout(remaining()) == value) {
          return;
        }
      }
      await Future<void>.delayed(
        Duration(milliseconds: remaining().inMilliseconds.clamp(1, 100)),
      );
    }
  }

  Future<SerializableFinder> revealCompact(String id, String model) async {
    final item = find.descendant(
      of: _detailsView,
      matching: find.byValueKey(
        AccountViewKeyValues.modelItem('native', id, model),
      ),
    );
    final tile = find.descendant(
      of: item,
      matching: find.byType('ExpansionTile'),
    );
    final header = find.descendant(of: tile, matching: find.byType('ListTile'));
    final scroll = await detailsScroll(id);
    await driver.scrollBy(scroll, 10000);
    await driver.scrollUntilVisible(
      scroll,
      header,
      dyScroll: -220,
      timeout: const Duration(seconds: 45),
    );
    final input = _compactInputFinder(tile);
    // The maintained body always has an Offstage, even when collapsed. Read
    // its actual flag; a failed Driver command is never evidence of absence.
    final body = await driver.sendCommand(
      GetDiagnosticsTree(
        find.descendant(of: tile, matching: find.byType('Offstage')),
        DiagnosticsType.widget,
        timeout: const Duration(seconds: 15),
      ),
    );
    if (!_compactBodyExpanded(body)) {
      await driver.mouseTap(header);
    }
    // Expansion changes the body's heightFactor. EnsureVisible must measure
    // settled geometry, not an intermediate frame of that animation. This
    // bounded condition waits for scheduled frames, not every future cursor
    // blink or all global transient callbacks.
    await driver.waitForNoPendingFrame(
      timeout: FlutterDriverSession.geometryDeadline,
    );
    await driver.scrollUntilVisible(
      scroll,
      input,
      dyScroll: -180,
      timeout: FlutterDriverSession.tapDeadline,
    );
    await driver.sendCommand(
      WaitForTappable(input, timeout: FlutterDriverSession.geometryDeadline),
    );
    return tile;
  }

  Future<void> setCompactInput(String id, String modelId, String value) async {
    final tile = await revealCompact(id, modelId);
    final input = _compactInputFinder(tile);
    await driver.mouseTap(input);
    await driver.enterText(value);
  }

  Future<void> tapCompactSave(String id, String modelId) async {
    final tile = await revealCompact(id, modelId);
    final save = find.descendant(
      of: _compactViewFinder(tile),
      matching: find.byValueKey('account-compact-save'),
    );
    await driver.scrollUntilVisible(
      await detailsScroll(id),
      save,
      dyScroll: -180,
      timeout: FlutterDriverSession.tapDeadline,
    );
    await driver.sendCommand(
      WaitForTappable(save, timeout: FlutterDriverSession.geometryDeadline),
    );
    await driver.mouseTap(save);
  }

  Future<void> visitModelDetails(
    String id,
    String modelId, {
    required String expectedRaw,
  }) async {
    final readout = find.byValueKey(
      AccountViewKeyValues.modelReadout('native', id, modelId),
    );
    await revealDetails(id, readout);
    await driver.mouseTap(readout);
    await driver.waitFor(find.byType('AccountModelDetailsView'));
    for (final (tab, routeTab, content) in const [
      ('specs', 'specifications', 'AccountModelSpecifications'),
      ('prices', 'pricing', 'AccountModelPricing'),
      ('evaluations', 'evaluations', 'AccountEvaluationsView'),
    ]) {
      await driver.mouseTap(find.byValueKey('account-model-$tab-tab'));
      await driver.waitForNoPendingFrame(
        timeout: FlutterDriverSession.geometryDeadline,
      );
      await driver.waitFor(find.byType(content));
      await waitPresentation(
        (value) =>
            _isAccountPage(value, 'model', kind: 'native', id: id) &&
            value['navigation']?['modelId'] == modelId &&
            value['navigation']?['tab'] == routeTab &&
            value['resourceStatus']?['models'] == 'observed' &&
            value['mountedViews']?['model']?['visible'] == true &&
            value['mountedViews']?['model']?['modelId'] == modelId &&
            value['mountedViews']?['model']?['tab'] == routeTab,
        'typed model tab $routeTab',
      );
      await capture('model-details-$tab', await readSnapshot());
    }
    await driver.mouseTap(find.byValueKey('account-model-back'));
    await driver.waitForAbsent(find.byType('AccountModelDetailsView'));
    await driver.waitForNoPendingFrame(
      timeout: FlutterDriverSession.geometryDeadline,
    );
    await waitPresentation(
      (value) => _hasAccountDetails(value, 'native', id),
      'model Back committed Native details',
    );
    final tile = await revealCompact(id, modelId);
    if (await driver.getText(_compactInputFinder(tile)) != expectedRaw) {
      throw StateError('model details navigation lost the unsaved threshold');
    }
  }

  Future<void> tapCompactReset(String id, String modelId) async {
    final tile = await revealCompact(id, modelId);
    final reset = find.descendant(
      of: _compactViewFinder(tile),
      matching: find.byValueKey('account-compact-reset'),
    );
    await driver.scrollUntilVisible(
      await detailsScroll(id),
      reset,
      dyScroll: -180,
      timeout: FlutterDriverSession.tapDeadline,
    );
    await driver.mouseTap(reset);
  }
}

bool _thresholdResourcesReady(Map<String, dynamic> snapshot, String id) {
  final domains = snapshot['settings']['accountDomains'] as Map;
  if (domains['schemaVersion'] != 2 || domains['summaries']['loaded'] != true) {
    return false;
  }
  if (!(domains['accounts'] as List).cast<Map>().any(
    (account) => account['kind'] == 'native' && account['id'] == id,
  )) {
    return false;
  }
  for (final domain in const ['catalogs', 'configurations']) {
    final resources = (domains[domain] as List)
        .cast<Map>()
        .where((resource) => resource['accountId'] == id)
        .toList();
    if (resources.length != 1 ||
        resources.single['loaded'] != true ||
        resources.single['stale'] != false ||
        resources.single['hasValue'] != true) {
      return false;
    }
  }
  return true;
}

SerializableFinder _compactViewFinder(SerializableFinder tile) =>
    find.descendant(of: tile, matching: find.byType('AccountCompactView'));

SerializableFinder _compactInputFinder(SerializableFinder tile) {
  final rawField = find.descendant(
    of: _compactViewFinder(tile),
    matching: find.byType('AccountRawTextField'),
  );
  final textField = find.descendant(
    of: rawField,
    matching: find.byType('TextField'),
  );
  // SelectableText elsewhere in the model tile also owns EditableText. Only
  // the threshold's production TextField is an editable input target here.
  return find.descendant(of: textField, matching: find.byType('EditableText'));
}

bool _compactBodyExpanded(Map<String, dynamic> diagnostics) {
  if (diagnostics['truncated'] == true ||
      diagnostics['widgetRuntimeType'] != 'Offstage' ||
      diagnostics['properties'] is! List) {
    throw StateError('compact body has no Offstage diagnostics');
  }
  final flags = (diagnostics['properties'] as List)
      .whereType<Map>()
      .where((property) => property['name'] == 'offstage')
      .toList();
  if (flags.length != 1 || flags.single['value'] is! bool) {
    throw StateError('compact body has no unique observed offstage flag');
  }
  return !(flags.single['value'] as bool);
}

/// Reads only descendants of the list's actual RenderObject. Creator chains,
/// widget keys and layout properties are not visible text and are not searched.
final class _RenderedAccountList {
  final List<String> texts = [];
  int nodeCount = 0;

  void verify(Set<String> modelIds) {
    if (texts.isEmpty) {
      throw StateError('account list render diagnostics contain no text');
    }
    for (final text in texts) {
      if (modelIds.any((id) => id.isNotEmpty && text.contains(id))) {
        throw StateError('account list rendered a model ID');
      }
      if (RegExp(r'\+\s*\d+').hasMatch(text) ||
          RegExp(
            r'\b\d+\s+(?:models?|bundled)\b',
            caseSensitive: false,
          ).hasMatch(text) ||
          RegExp(r'\d+\s*(?:个模型|個模型|个内置|個內建)').hasMatch(text)) {
        throw StateError('account list rendered a model count');
      }
    }
  }

  static _RenderedAccountList read(Map<String, dynamic> root) {
    final result = _RenderedAccountList();
    void visit(Map node, [List<String>? paragraph]) {
      result.nodeCount++;
      final description = node['description'];
      final startsParagraph =
          description is String &&
          (description.startsWith('RenderParagraph') ||
              description.startsWith('RenderEditable'));
      final textParts = startsParagraph ? <String>[] : paragraph;
      final children = node['children'];
      if (node['truncated'] == true ||
          (node['hasChildren'] == true &&
              (children is! List || children.isEmpty))) {
        throw StateError('account list render diagnostics were truncated');
      }
      // RenderParagraph/RenderEditable describe their InlineSpan children.
      // These text properties are the rendered data, unlike a creator string
      // that may mention widgets above this list or offstage sibling routes.
      for (final property in node['properties'] as List? ?? const []) {
        if (property is Map &&
            property['name'] == 'text' &&
            property['value'] is String) {
          textParts?.add(property['value'] as String);
        }
      }
      if (children is List) {
        for (final child in children) {
          if (child is! Map) {
            throw StateError('invalid account list render diagnostic child');
          }
          visit(child, textParts);
        }
      }
      // InlineSpan boundaries do not separate visible words or model IDs.
      if (startsParagraph && textParts!.isNotEmpty) {
        result.texts.add(textParts.join());
      }
    }

    visit(root);
    return result;
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

// Read-only schema-v3 predicates: a missing resource is never a location ACK.
bool _isAccountPage(Map? value, String page, {String? kind, String? id}) {
  final navigation = value?['navigation'];
  return value?['schemaVersion'] == 3 &&
      navigation is Map &&
      navigation['source'] == 'goRouter' &&
      navigation['page'] == page &&
      (kind == null || navigation['account']?['kind'] == kind) &&
      (id == null || navigation['account']?['id'] == id);
}

bool _hasAccountEditor(Map? value) {
  final editor = value?['editor'];
  if (editor is! Map) return false;
  final creating = editor['creating'] == true;
  final target = editor['target'];
  if (target is! Map ||
      !const {'native', 'acp'}.contains(target['kind']) ||
      target['id'] is! String ||
      (target['id'] as String).isEmpty) {
    return false;
  }
  if (!_isAccountPage(
    value,
    creating ? 'create' : 'edit',
    kind: creating ? null : target['kind'] as String,
    id: creating ? null : target['id'] as String,
  )) {
    return false;
  }
  final entry = value?['navigation']?['entry'];
  final mounted =
      value?['mountedViews']?[target['kind'] == 'native'
          ? 'nativeEditor'
          : 'acpEditor'];
  return entry is Map &&
      entry['kind'] == (creating ? 'creating' : 'editing') &&
      entry['routeEntryId'] is String &&
      (entry['routeEntryId'] as String).isNotEmpty &&
      (creating ||
          (entry['target']?['kind'] == target['kind'] &&
              entry['target']?['id'] == target['id'])) &&
      value?['resourceStatus']?['editorSession'] == 'active' &&
      value?['resourceStatus']?['editor'] == 'observed' &&
      editor['editorId'] is String &&
      (editor['editorId'] as String).isNotEmpty &&
      mounted?['visible'] == true &&
      mounted?['editorId'] == editor['editorId'];
}

bool _hasAccountDetails(Map? value, String kind, String id) =>
    _isAccountPage(value, 'details', kind: kind, id: id) &&
    value?['resourceStatus']?['details'] == 'observed' &&
    value?['details']?['target']?['kind'] == kind &&
    value?['details']?['target']?['id'] == id &&
    value?['details']?['observed'] == true &&
    value?['details']?['stale'] == false &&
    value?['mountedViews']?['details']?['visible'] == true;

bool _hasAccountList(Map? value) =>
    _isAccountPage(value, 'list') &&
    value?['resourceStatus']?['list'] == 'observed' &&
    value?['list']?['phase'] == 'ready' &&
    value?['mountedViews']?['list']?['visible'] == true;

// Keep this manual desktop journey on the real mouse gesture path.
extension _AccountMouseInput on FlutterDriverSession {
  Future<void> mouseTap(SerializableFinder finder, {Duration? timeout}) async {
    await sendCommand(
      RawTap(finder, pointerKind: RawTapKind.mouse, timeout: timeout),
    );
  }
}
