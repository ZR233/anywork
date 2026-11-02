import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'timeline_observation.dart';
import 'timeline_scope_driver.dart';
import 'timeline_group_observation.dart';

/// Real-provider journey for the asynchronous image tools.
///
/// The acceptance harness only runs isolated fixture providers, so this script
/// drives the ordinary application graph (the user configuration) and proves
/// the end-to-end chain:
///
///     generate_image (background task) -> wait -> show_image -> image card
///
///     dart run test_driver/image_generation_journey.dart \
///       VM_URL PROJECT_DIR PROMPT OUTPUT_DIR [--keep-open] [--mode=mode.task] \
///       [--model=provider:model] [--capture-only] [--capture-existing]
///
/// It never prints provider credentials and only records tool identity, status
/// and attachment metadata in the evidence file.
Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
      'usage: image_generation_journey.dart VM_URL PROJECT_DIR PROMPT OUTPUT_DIR '
      '[--keep-open] [--mode=mode.task] [--model=provider:model] '
      '[--capture-only] [--capture-existing]',
    );
    exitCode = 64;
    return;
  }
  final keepOpen = args.contains('--keep-open');
  final captureOnly = args.contains('--capture-only');
  final captureExisting = args.contains('--capture-existing');
  String? modeSpec;
  String? modelSpec;
  for (final arg in args) {
    if (arg.startsWith('--mode=')) {
      modeSpec = arg.substring('--mode='.length);
    }
    if (arg.startsWith('--model=')) {
      modelSpec = arg.substring('--model='.length);
    }
  }
  final output = Directory(args[3]);
  await output.create(recursive: true);
  Future<void> stage(String value) =>
      File('${output.path}/journey-stage.txt').writeAsString(value);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  try {
    await stage('connected');
    if (captureOnly) {
      await _writeJson(
        '${output.path}/snapshot.json',
        await driver.readSnapshot(),
      );
      await File('${output.path}/screenshot.png').writeAsBytes(
        await driver.screenshot().timeout(const Duration(seconds: 15)),
      );
      await stage('capture_completed');
      return;
    }
    if (captureExisting) {
      final snapshot = await TimelineScopeDriver.session(driver).openLatest();
      final generated = _generatedFromSnapshot(snapshot);
      final card = _cardFromSnapshot(snapshot);
      if (generated == null || card == null) {
        throw StateError('no completed image card in the current thread');
      }
      await _captureCard(driver, output, generated, card);
      await stage('capture_completed');
      return;
    }
    await _openProject(driver, args[1], output);
    await stage('project_ready');
    await _startNewSession(driver);
    await driver
        .waitFor(
          find.byValueKey('composer-input'),
          timeout: const Duration(seconds: 90),
        )
        .timeout(const Duration(seconds: 90));
    if (modeSpec != null) {
      await _selectMode(driver, modeSpec);
    }
    if (modelSpec != null) {
      await _selectModel(driver, modelSpec);
    }
    if (modeSpec != null || modelSpec != null) await stage('route_selected');
    await driver.tap(find.byValueKey('composer-input'));
    await driver.enterText(args[2]);
    await driver
        .waitFor(
          find.byValueKey('composer-submit'),
          timeout: const Duration(seconds: 15),
        )
        .timeout(const Duration(seconds: 15));
    await driver.tap(find.byValueKey('composer-submit'));
    await stage('prompt_submitted');
    final generated = await _waitForGeneratedImage(driver, output);
    await stage('tool_succeeded');
    final card = await _waitForCard(driver, output);
    await stage('card_ready');
    await _captureCard(driver, output, generated, card);
    await stage('screenshot_captured');
    if (!keepOpen) {
      final shutdown = jsonDecode(
        await driver
            .requestData('shutdown', timeout: const Duration(seconds: 90))
            .timeout(const Duration(seconds: 95)),
      );
      final status = shutdown is Map ? shutdown['shutdown'] : null;
      // `completed` is a clean exit; `degraded` still exits while reporting a
      // cleanup degradation, which the run must record rather than hide.
      if (status == 'completed' || status == 'degraded') {
        await stage('shutdown_$status');
      } else {
        await stage('shutdown_rejected');
        throw StateError('native GUI shutdown did not complete');
      }
    }
    stdout.writeln('Image generation and card evidence captured.');
  } finally {
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // A completed shutdown must not keep the journey process open.
    }
  }
}

Future<void> _openProject(
  FlutterDriverSession driver,
  String projectPath,
  Directory output,
) async {
  final openProject = find.byValueKey('sidebar-open-project');
  // A later run of the same profile may already have an active project; the
  // onboarding path must stay untouched in that case.
  try {
    await driver
        .waitFor(openProject, timeout: const Duration(seconds: 20))
        .timeout(const Duration(seconds: 20));
  } on Object {
    return;
  }
  await driver.tap(openProject);
  await driver.tap(find.byValueKey('add-project-local'));
  await driver
      .waitFor(
        find.byValueKey('add-project-continue-ready'),
        timeout: const Duration(seconds: 20),
      )
      .timeout(const Duration(seconds: 20));
  await driver.tap(find.byValueKey('add-project-continue-ready'));
  await driver
      .waitFor(
        find.byValueKey('project-path-input'),
        timeout: const Duration(seconds: 60),
      )
      .timeout(const Duration(seconds: 60));
  await File('${output.path}/project-dialog.png').writeAsBytes(
    await driver.screenshot().timeout(const Duration(seconds: 10)),
  );
  await driver.tap(find.byValueKey('project-path-input'));
  await driver.enterText(projectPath);
  await driver
      .waitFor(
        find.byValueKey('project-path-submit'),
        timeout: const Duration(seconds: 15),
      )
      .timeout(const Duration(seconds: 15));
  await driver.tap(find.byValueKey('project-path-submit'));
}

Future<void> _startNewSession(FlutterDriverSession driver) async {
  // A restored project may reopen its last thread, which can be faulted from an
  // unrelated run; a fresh thread keeps the evidence scoped to this prompt.
  final newSession = find.byValueKey('sidebar-new-session');
  try {
    await driver
        .waitFor(newSession, timeout: const Duration(seconds: 15))
        .timeout(const Duration(seconds: 15));
    await driver.tap(newSession);
  } on Object {
    return;
  }
}

Future<void> _selectMode(FlutterDriverSession driver, String mode) async {
  await driver
      .waitFor(
        find.byValueKey('session-mode-selector'),
        timeout: const Duration(seconds: 20),
      )
      .timeout(const Duration(seconds: 20));
  await driver.tap(find.byValueKey('session-mode-selector'));
  final option = find.byValueKey('session-mode-$mode');
  await driver
      .waitFor(option, timeout: const Duration(seconds: 20))
      .timeout(const Duration(seconds: 20));
  await driver.tap(option);
}

Future<void> _selectModel(FlutterDriverSession driver, String modelSpec) async {
  final separator = modelSpec.indexOf(':');
  if (separator <= 0) {
    throw ArgumentError('Expected --model=provider:model');
  }
  final providerId = modelSpec.substring(0, separator);
  final model = modelSpec.substring(separator + 1);
  await driver
      .waitFor(
        find.byValueKey('model-selector'),
        timeout: const Duration(seconds: 20),
      )
      .timeout(const Duration(seconds: 20));
  await driver.tap(find.byValueKey('model-selector'));
  final option = find.byValueKey(
    'model-${jsonEncode(<String>[providerId, model])}',
  );
  await driver
      .waitFor(option, timeout: const Duration(seconds: 20))
      .timeout(const Duration(seconds: 20));
  // Switching the model rebuilds the thread route and can keep scheduling
  // frames; the frame-waiting tap cannot acknowledge that, so send the pointer
  // event directly and let the following waits observe the result.
  await driver.rawTap(option);
}

Future<_GeneratedImage> _waitForGeneratedImage(
  FlutterDriverSession driver,
  Directory output,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 8));
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    var snapshot = await driver.readSnapshot();
    last = snapshot;
    if (_workspaceIdle(snapshot)) {
      await for (final evidence in _imageEvidence(driver, snapshot)) {
        final generated = _generatedFromSnapshot(evidence);
        if (generated != null) {
          await _writeJson('${output.path}/snapshot.json', evidence);
          return generated;
        }
      }
    }
    final generated = _generatedFromSnapshot(snapshot);
    if (generated != null && _workspaceIdle(snapshot)) {
      await _writeJson('${output.path}/snapshot.json', snapshot);
      return generated;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (last != null) {
    await _writeJson('${output.path}/incomplete-snapshot.json', last);
  }
  throw StateError('generate_image did not complete before the deadline');
}

Future<_ImageCard> _waitForCard(
  FlutterDriverSession driver,
  Directory output,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 8));
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    var snapshot = await driver.readSnapshot();
    last = snapshot;
    if (_workspaceIdle(snapshot)) {
      await for (final evidence in _imageEvidence(driver, snapshot)) {
        final card = _cardFromSnapshot(evidence);
        if (card != null) {
          await _writeJson('${output.path}/card-snapshot.json', evidence);
          return card;
        }
      }
    }
    final card = _cardFromSnapshot(snapshot);
    if (card != null && _workspaceIdle(snapshot)) {
      await _writeJson('${output.path}/card-snapshot.json', snapshot);
      return card;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (last != null) {
    await _writeJson('${output.path}/incomplete-card-snapshot.json', last);
  }
  throw StateError('show_image did not produce a timeline card');
}

bool _workspaceIdle(Map<String, dynamic> snapshot) {
  final workspace = snapshot['workspace'];
  final persistence = snapshot['persistence'];
  final persistenceDetails = persistence is Map ? persistence : const {};
  if (workspace is! Map) return false;
  return workspace['isBusy'] == false &&
      persistenceDetails['kind'] == 'ready' &&
      persistenceDetails['pendingCommits'] == 0;
}

_GeneratedImage? _generatedFromSnapshot(Map<String, dynamic> snapshot) {
  for (final item in _timelineItems(snapshot)) {
    final tool = item['tool'];
    if (tool is! Map || tool['name'] != 'generate_image') continue;
    final attachments = item['attachments'];
    if (tool['status'] != 'succeeded' ||
        attachments is! List ||
        attachments.isEmpty) {
      continue;
    }
    return _GeneratedImage(
      itemId: '${item['id']}',
      tool: tool,
      attachments: attachments,
    );
  }
  return null;
}

_ImageCard? _cardFromSnapshot(Map<String, dynamic> snapshot) {
  for (final item in _timelineItems(snapshot)) {
    final tool = item['tool'];
    // `tool` exists only when the current renderer decoded the actual marker.
    if (tool is! Map || tool['name'] != 'show_image') continue;
    final attachments = item['attachments'];
    if (tool['status'] != 'succeeded' ||
        attachments is! List ||
        attachments.isEmpty) {
      continue;
    }
    return _ImageCard(
      itemId: item['id'] as String,
      tool: tool,
      attachments: attachments,
    );
  }
  return null;
}

/// Only Main receipts and mounted ordinary atomic windows; never Turn Children.
Iterable<Map<dynamic, dynamic>> _timelineItems(Map<String, dynamic> snapshot) =>
    timelineDisplayedAtoms(snapshot);

/// Fresh-thread journey: inspect loaded work records in source/display order,
/// including G1 before text and G2 after text. Each action reads one ordinary
/// bounded page. Unread prefixes are an explicit incomplete-evidence failure.
Stream<Map<String, dynamic>> _imageEvidence(
  FlutterDriverSession driver,
  Map<String, dynamic> initial,
) async* {
  yield initial;
  final timeline = TimelineObservation.parse(initial);
  if (timeline.hasOlder) {
    throw StateError(
      'Image evidence is incomplete: Main has an unloaded atomic prefix',
    );
  }
  final actions = TimelineScopeDriver.session(driver);
  for (final unit in timeline.items.where((item) => item.kind == 'workGroup')) {
    var snapshot = await actions.setGroupExpanded(unit.id, true);
    yield snapshot;
    final raw = ((snapshot['timeline'] as Map)['items'] as List)
        .cast<Map>()
        .singleWhere((item) => item['id'] == unit.id);
    final atomic = raw['atomic'];
    if (atomic is! Map || atomic['loadedCount'] is! int) {
      throw StateError('Image group lacks actual loaded atomic metadata');
    }
    for (var page = 0; page < 32; page++) {
      final display = timelineGroupDisplays(snapshot)
          .singleWhere((group) => group['unitId'] == unit.id);
      final hasWindow = display['completionAnchor'] != null;
      final missingProps =
          (atomic['loadedCount'] as int) > (display['items'] as List).length;
      if (hasWindow && display['before'] == null) break;
      if (!hasWindow && !missingProps) break;
      snapshot = await actions.loadGroupEarlier(unit.id);
      yield snapshot;
      if (page == 31 &&
          timelineGroupDisplays(
                snapshot,
              ).singleWhere((group) => group['unitId'] == unit.id)['before'] !=
              null) {
        throw StateError(
          'Image evidence budget exhausted with an unread ordinary prefix',
        );
      }
    }
  }
}

Future<void> _captureCard(
  FlutterDriverSession driver,
  Directory output,
  _GeneratedImage generated,
  _ImageCard card,
) async {
  final attachments = card.attachments;
  final first = attachments.first as Map;
  final callId = card.tool['callId'];
  final attachmentId = '${first['id']}';
  await TimelineScopeDriver.session(driver).revealItem(card.itemId);
  // The actual connector binds the item identity and the attachment identity.
  final entryId = '${card.itemId}:$attachmentId';
  final cardKey = find.byValueKey('chat-item:${card.itemId}');
  final imageKey = find.byValueKey('view-image-thumbnail-$entryId');
  await driver.waitFor(imageKey, timeout: const Duration(seconds: 20));
  final cardMounted = await _isMounted(driver, cardKey);
  // The timeline follows the newest content; nudge it up so the screenshot also
  // shows the card header and its status pill.
  try {
    await driver.scrollBy(find.byValueKey('timeline-scrollable'), 110);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  } on Object {
    // A card whose header is already visible is still valid evidence.
  }
  await _screenshot(driver, '${output.path}/card.png');
  // The card can be taller than the timeline viewport on a short window; a
  // second frame scrolled slightly further records the caption band too.
  try {
    await driver.scrollBy(find.byValueKey('timeline-scrollable'), -70);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _screenshot(driver, '${output.path}/card-caption.png');
  } on Object {
    // The primary card screenshot already records the image and header.
  }
  await driver.rawTap(imageKey);
  await driver.waitFor(
    find.byValueKey('view-image-dialog-$entryId'),
    timeout: const Duration(seconds: 20),
  );
  await _screenshot(driver, '${output.path}/card-dialog.png');
  await driver.tap(find.byValueKey('timeline-image-close'));
  await _writeJson('${output.path}/evidence.json', {
    'generateTool': '${generated.tool['name']}',
    'generateCallId': generated.tool['callId'],
    'generateItemId': generated.itemId,
    'cardTool': '${card.tool['name']}',
    'cardCallId': callId,
    'cardItemId': card.itemId,
    'status': card.tool['status'],
    'attachments': attachments,
    'caption': _arguments(card.tool['arguments'])?['caption'],
    'cardMounted': cardMounted,
    'dialogOpened': true,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
  });
}

/// Tool arguments reach the driver snapshot either decoded or as their JSON text.
Map<dynamic, dynamic>? _arguments(Object? raw) {
  if (raw is Map) return raw;
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded;
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// Captures one full-window frame, tolerating a rasterizer that is still busy.
///
/// A screenshot request can be rejected while the engine is decoding the freshly
/// mounted image, so the capture retries instead of failing the evidence run.
Future<void> _screenshot(FlutterDriverSession driver, String path) async {
  Object? lastError;
  for (var attempt = 0; attempt < 4; attempt++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      final bytes = await driver.screenshot().timeout(
        const Duration(seconds: 20),
      );
      await File(path).writeAsBytes(bytes);
      return;
    } on Object catch (error) {
      lastError = error;
    }
  }
  throw StateError('screenshot did not complete: $lastError');
}

Future<bool> _isMounted(
  FlutterDriverSession driver,
  SerializableFinder finder, {
  int timeout = 3,
}) async {
  final deadline = Duration(seconds: timeout);
  try {
    await driver.waitFor(finder, timeout: deadline).timeout(deadline);
    return true;
  } on Object {
    return false;
  }
}

Future<void> _writeJson(String path, Object value) => File(path)
    .writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');

class _GeneratedImage {
  const _GeneratedImage({
    required this.itemId,
    required this.tool,
    required this.attachments,
  });

  final String itemId;
  final Map<dynamic, dynamic> tool;
  final List<dynamic> attachments;
}

class _ImageCard {
  const _ImageCard({
    required this.itemId,
    required this.tool,
    required this.attachments,
  });

  final String itemId;
  final Map<dynamic, dynamic> tool;
  final List<dynamic> attachments;
}
