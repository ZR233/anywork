import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';

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
      final snapshot = await driver.readSnapshot();
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
      if (shutdown is! Map || shutdown['shutdown'] != 'completed') {
        await stage('shutdown_rejected');
        throw StateError('native GUI shutdown did not complete');
      }
      await stage('shutdown_completed');
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
    final snapshot = await driver.readSnapshot();
    last = snapshot;
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
    final snapshot = await driver.readSnapshot();
    last = snapshot;
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
  final workspace = snapshot['workspace'];
  if (workspace is! Map) return null;
  final rows = workspace['timeline'];
  if (rows is! List) return null;
  for (final row in rows) {
    if (row is! Map || row['type'] != 'activityGroup') continue;
    final tools = row['tools'];
    if (tools is! List) continue;
    for (final tool in tools) {
      if (tool is! Map || tool['name'] != 'generate_image') continue;
      final attachments = tool['attachments'];
      if (tool['status'] != 'succeeded' ||
          attachments is! List ||
          attachments.isEmpty) {
        continue;
      }
      return _GeneratedImage(groupId: '${row['id']}', tool: tool);
    }
  }
  return null;
}

_ImageCard? _cardFromSnapshot(Map<String, dynamic> snapshot) {
  final workspace = snapshot['workspace'];
  if (workspace is! Map) return null;
  final rows = workspace['timeline'];
  if (rows is! List) return null;
  for (final row in rows) {
    if (row is! Map || row['type'] != 'imageCard') continue;
    final tools = row['tools'];
    if (tools is! List) continue;
    for (final tool in tools) {
      if (tool is! Map || tool['name'] != 'show_image') continue;
      final attachments = tool['attachments'];
      if (tool['status'] != 'succeeded' ||
          attachments is! List ||
          attachments.isEmpty) {
        continue;
      }
      return _ImageCard(rowId: '${row['id']}', tool: tool);
    }
  }
  return null;
}

Future<void> _captureCard(
  FlutterDriverSession driver,
  Directory output,
  _GeneratedImage generated,
  _ImageCard card,
) async {
  final attachments = card.tool['attachments'] as List;
  final first = attachments.first as Map;
  final callId = card.tool['callId'] ?? card.tool['toolCallId'];
  final attachmentId = '${first['id']}';
  // Both keys use the documented entry identity: owning call id plus the
  // content-addressed attachment id.
  final entryId = '$callId:$attachmentId';
  final cardKey = find.byValueKey('image-card-$entryId');
  final imageKey = find.byValueKey('image-card-image-$entryId');
  var cardMounted = await _isMounted(driver, cardKey);
  if (!cardMounted) {
    await driver
        .waitFor(imageKey, timeout: const Duration(seconds: 20))
        .timeout(const Duration(seconds: 20));
    cardMounted = await _isMounted(driver, cardKey);
  }
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
  var dialogOpened = false;
  try {
    await driver.rawTap(imageKey);
    await driver
        .waitFor(
          find.byValueKey('timeline-image-dialog-$attachmentId'),
          timeout: const Duration(seconds: 20),
        )
        .timeout(const Duration(seconds: 20));
    dialogOpened = true;
    await _screenshot(driver, '${output.path}/card-dialog.png');
    await driver.tap(find.byValueKey('timeline-image-close'));
  } on Object {
    // The dialog is supplementary; the card screenshot already proves the
    // generated image reached the timeline.
  }
  await _writeJson('${output.path}/evidence.json', {
    'generateTool': '${generated.tool['name']}',
    'generateCallId': generated.tool['callId'],
    'cardTool': '${card.tool['name']}',
    'cardCallId': callId,
    'cardRowId': card.rowId,
    'status': card.tool['status'],
    'attachments': attachments,
    'caption': _arguments(card.tool['arguments'])?['caption'],
    'cardMounted': cardMounted,
    'dialogOpened': dialogOpened,
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
  const _GeneratedImage({required this.groupId, required this.tool});

  final String groupId;
  final Map<dynamic, dynamic> tool;
}

class _ImageCard {
  const _ImageCard({required this.rowId, required this.tool});

  final String rowId;
  final Map<dynamic, dynamic> tool;
}
