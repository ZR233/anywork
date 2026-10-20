// Native Mode editor acceptance: every edit and command uses visible product controls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'pointer_drag.dart' show PointerDragKind;
import 'realtime_journey.dart';
import 'sidebar_navigation.dart';
import 'window_control.dart';

const _modeId = 'mode.editor-evidence';
const _prompts = [
  'Workflow editor first turn',
  'Workflow editor graph update',
  'Workflow editor prompt update',
  'Workflow editor delete while running',
  'Workflow editor restored snapshot',
];

Future<void> main(List<String> args) async {
  if (args.length != 6) {
    throw ArgumentError('PHASE VM_URL PROJECT OUTPUT COORD HOME required');
  }
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[1]);
  final journey = ModeEditorJourney(driver, args);
  Object? failure;
  StackTrace? failureStack;
  var shutdown = 'failed';
  try {
    await journey.run();
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
    try {
      await journey.capture('failure');
    } catch (_) {
      /* retain original error */
    }
  }
  try {
    final result = jsonDecode(
      await driver.requestData(
        'shutdown',
        timeout: const Duration(seconds: 60),
      ),
    );
    if (result is! Map || result['shutdown'] != 'completed') {
      throw StateError('native shutdown did not complete: $result');
    }
    shutdown = 'completed';
  } catch (error, stack) {
    failure ??= error;
    failureStack ??= stack;
  } finally {
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      /* native shutdown may close its connection */
    }
  }
  await File('${args[3]}/${args[0]}-summary.json').writeAsString(
    jsonEncode({
      'phase': args[0],
      'status': failure == null ? 'complete' : 'failed',
      'shutdown': shutdown,
      'threadId': journey.threadId,
      'error': failure?.toString(),
      'checks': journey.checks,
      'humanVerdict': 'pending',
    }),
  );
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}

class ModeEditorJourney {
  ModeEditorJourney(this.driver, List<String> args)
    : phase = args[0],
      project = args[2],
      output = args[3],
      coord = args[4],
      home = args[5];
  final FlutterDriverSession driver;
  final String phase, project, output, coord, home;
  final Map<String, Object?> checks = {};
  String? threadId;

  Future<void> tap(String key) async {
    stdout.writeln('$phase: tap $key');
    final finder = find.byValueKey(key);
    await driver.waitFor(finder, timeout: const Duration(seconds: 45));
    await driver.rawTap(finder);
  }

  Future<void> text(String key, String value) async {
    await tap(key);
    await driver.enterText(value);
  }

  Future<Map<String, dynamic>> editor() async =>
      (jsonDecode(await driver.requestData('mode-editor-state')) as Map)
          .cast<String, dynamic>();
  Future<Map<String, dynamic>> waitEditor(
    bool Function(Map<String, dynamic>) predicate,
    String label,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    Map<String, dynamic> last = {};
    while (DateTime.now().isBefore(deadline)) {
      last = await editor();
      if (predicate(last)) return last;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('$phase/$label timed out: ${jsonEncode(last)}');
  }

  Future<Map<String, dynamic>> waitSnapshot(
    bool Function(Map<String, dynamic>) predicate,
    String label,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    Map<String, dynamic> last = {};
    while (DateTime.now().isBefore(deadline)) {
      last = await driver.readSnapshot();
      if (predicate(last)) return last;
      final status = turnStatus(last);
      if (const ['failed', 'cancelled', 'budgetLimited'].contains(status)) {
        throw StateError('$label ended with $status: ${jsonEncode(last)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('$phase/$label timed out: ${jsonEncode(last)}');
  }

  bool settled(Map<String, dynamic> snapshot) {
    final workspace = workspaceOf(snapshot);
    final persistence = snapshot['persistence'];
    return workspace != null &&
        workspace['isBusy'] == false &&
        persistence is Map &&
        persistence['pendingCommits'] == 0;
  }

  Future<void> capture(String label) async {
    try {
      await driver.waitUntilNoTransientCallbacks(
        timeout: const Duration(seconds: 5),
      );
      await driver.waitForNoPendingFrame(timeout: const Duration(seconds: 5));
    } catch (_) {
      if (label != 'failure') rethrow;
    }
    await File('$output/$phase-$label.png')
        .writeAsBytes(await driver.screenshot());
    await File('$output/$phase-$label-tree.txt')
        .writeAsString(await driver.renderTree());
    await File('$output/$phase-$label-state.json')
        .writeAsString(jsonEncode(await editor()));
  }

  void require(bool condition, String check) {
    checks[check] = condition;
    if (!condition) throw StateError('Mode editor acceptance failed: $check');
  }

  Future<void> checkpointStage(String stage) async {
    await File('$coord/observed.json')
        .writeAsString(jsonEncode({'threadId': threadId}));
    await File('$coord/$stage').writeAsString('ready');
    final verified = File('$coord/$stage-verified');
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!await verified.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('checkpoint coordinator did not verify $stage');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> openEditor() async {
    await tap('settings-open');
    await tap('settings-tab-workModes');
    await waitEditor(
      (state) => state['document'] != null && state['busy'] == false,
      'editor ready',
    );
  }

  Future<void> jsonDraft(Map<String, dynamic> document) async {
    await tap('mode-editor-tab-json');
    await text(
      'mode-editor-json-editor',
      const JsonEncoder.withIndent('  ').convert(document),
    );
    await tap('mode-editor-apply-json');
    final state = await waitEditor(
      (state) =>
          state['busy'] == false &&
          (state['document'] as Map?)?['prompt'] == document['prompt'],
      'JSON applied',
    );
    require((state['issues'] as List).isEmpty, 'valid JSON accepted');
  }

  Future<void> save() async {
    await tap('mode-editor-save');
    final state = await waitEditor(
      (state) =>
          state['busy'] == false &&
          (state['dirty'] == false || state['error'] != null),
      'save',
    );
    require(
      state['dirty'] == false && state['error'] == null,
      'canonical save acknowledged',
    );
  }

  Future<void> submit(int index, {bool wait = true}) async {
    await text('composer-input', _prompts[index]);
    await tap('composer-submit');
    final snapshot = await waitSnapshot(
      (snapshot) => workspaceOf(snapshot)?['threadId'] is String,
      'Thread admitted',
    );
    threadId = workspaceOf(snapshot)!['threadId'] as String;
    await File('$coord/observed.json')
        .writeAsString(jsonEncode({'threadId': threadId}));
    if (wait) {
      await waitSnapshot(
        (snapshot) => settled(snapshot) && turnStatus(snapshot) == 'completed',
        'Turn $index completed',
      );
    } else {
      await waitSnapshot(
        (snapshot) => workspaceOf(snapshot)?['isBusy'] == true,
        'Turn $index running',
      );
      await waitEditor(
        (state) => state['run'] != null,
        'workflow snapshot frozen',
      );
    }
  }

  Map<String, dynamic> documentOf(Map<String, dynamic> state) =>
      jsonDecode(jsonEncode(state['document'])) as Map<String, dynamic>;
  Future<void> connect(String source, String target) async {
    await driver.waitUntilNoTransientCallbacks(
      timeout: const Duration(seconds: 15),
    );
    await driver.waitForNoPendingFrame(timeout: const Duration(seconds: 15));
    final from = find.byValueKey('mode-editor-port-$source-out');
    final to = find.byValueKey('mode-editor-port-$target-in');
    await driver.waitFor(from);
    await driver.waitFor(to);
    final a = await driver.getTopLeft(from),
        b = await driver.getBottomRight(from);
    final c = await driver.getTopLeft(to), d = await driver.getBottomRight(to);
    stdout.writeln('$phase: connect $source -> $target, $a/$b -> $c/$d');
    await driver.dragBy(
      from,
      pointerKind: PointerDragKind.mouse,
      dx: (c.dx + d.dx - a.dx - b.dx) / 2,
      dy: (c.dy + d.dy - a.dy - b.dy) / 2,
    );
    await waitEditor(
      (state) =>
          ((state['document'] as Map)['workflow']['transitions'] as List).any(
            (edge) =>
                edge['sourceStateId'] == source &&
                edge['targetStateId'] == target,
          ),
      'connection $source -> $target',
    );
    await tap('mode-editor-close-inspector');
    await tap('mode-editor-fit-view');
  }

  Future<void> first() async {
    await tap('sidebar-open-project');
    await tap('add-project-local');
    await tap('add-project-continue-ready');
    await text('project-path-input', project);
    await tap('project-path-submit');
    await openEditor();
    await tap('mode-editor-catalog-mode.task');
    final builtin = await waitEditor(
      (state) =>
          state['readOnly'] == true &&
          (state['document'] as Map?)?['id'] == 'mode.task',
      'builtin',
    );
    await tap('mode-editor-fit-view');
    await capture('builtin-read-only');
    final original = jsonEncode(builtin['document']);
    await driver.dragBy(
      find.byValueKey('mode-editor-node-planning'),
      dx: 35,
      dy: 20,
    );
    require(
      jsonEncode((await editor())['document']) == original,
      'builtin layout is read only',
    );
    await tap('mode-editor-copy');
    await waitEditor(
      (state) => state['dirty'] == true && state['readOnly'] == false,
      'copy draft',
    );
    final document = <String, dynamic>{
      'id': _modeId,
      'displayName': '研发验证流程',
      'description': '原生工作流编辑、校验与快照验收',
      'order': 30,
      'prompt': 'mode-editor-original\n按工作流推进，汇报可复现证据。',
      'workflow': {
        'title': '研发验证流程',
        'goal': '从需求规划到交付，允许循环返工与多后继。',
        'initialStateId': 'planning',
        'states': [
          {
            'id': 'planning',
            'title': '规划需求',
            'instructions': '确认需求与实施步骤。',
            'completionCriteria': ['需求与实施边界已明确'],
            'kind': 'atomic',
          },
          {
            'id': 'working',
            'title': '实施验证',
            'instructions': '完成实现并验证行为。',
            'completionCriteria': ['变更已验证且有证据'],
            'kind': 'atomic',
          },
          {
            'id': 'completed',
            'title': '完成交付',
            'instructions': '',
            'completionCriteria': [],
            'kind': 'final',
          },
        ],
        'transitions': [
          {
            'sourceStateId': 'planning',
            'targetStateId': 'working',
            'guard': '需求已明确，可以开始实施。',
          },
          {
            'sourceStateId': 'working',
            'targetStateId': 'completed',
            'guard': '验证通过且交付证据完整。',
          },
        ],
      },
      'editor': {
        'nodes': [
          {'stateId': 'planning', 'x': 40.0, 'y': 100.0},
          {'stateId': 'working', 'x': 350.0, 'y': 100.0},
          {'stateId': 'completed', 'x': 660.0, 'y': 100.0},
        ],
      },
    };
    await jsonDraft(document);
    await tap('mode-editor-tab-graph');
    await tap('mode-editor-fit-view');
    final before = jsonEncode((await editor())['document']);
    await driver.dragBy(
      find.byValueKey('mode-editor-node-working'),
      dx: 16,
      dy: 40,
    );
    await waitEditor(
      (state) => jsonEncode(state['document']) != before,
      'node moved',
    );
    await tap('mode-editor-undo');
    require(
      jsonEncode((await editor())['document']) == before,
      'node drag undo',
    );
    await tap('mode-editor-redo');
    require(
      jsonEncode((await editor())['document']) != before,
      'node drag redo',
    );
    await connect('working', 'planning');
    await connect('planning', 'completed');
    await connect('planning', 'planning');
    final connected = await waitEditor(
      (state) =>
          ((state['document'] as Map)['workflow']['transitions'] as List)
              .length ==
          5,
      'canvas connections',
    );
    require(
      ((connected['document'] as Map)['workflow']['transitions'] as List)
              .length ==
          5,
      'cycle self loop and multiple successors',
    );
    await tap('mode-editor-add-state');
    await waitEditor(
      (state) =>
          ((state['document'] as Map)['workflow']['states'] as List).length ==
          4,
      'stage created',
    );
    await text('mode-editor-inspector-state-title', '临时验证阶段 A');
    await driver.waitUntilNoTransientCallbacks(
      timeout: const Duration(seconds: 10),
    );
    // A second input without refocusing proves graph projection keeps the
    // property field's text-input connection alive.
    await driver.enterText('临时验证阶段');
    require(
      ((await editor())['document']['workflow']['states'] as List).any(
        (state) => state['id'] == 'stage1' && state['title'] == '临时验证阶段',
      ),
      'stage title edited',
    );
    // Scroll the inspector itself. ensureVisible also scrolls the surrounding
    // settings PageView and can move this retained tab out of view.
    await driver.scrollBy(
      find.byValueKey('mode-editor-inspector-scroll'),
      -320,
      mouseWheel: true,
      timeout: const Duration(seconds: 15),
    );
    await capture('stage-before-delete');
    await tap('mode-editor-delete-state');
    await tap('mode-editor-remove-state-confirm');
    await waitEditor(
      (state) =>
          ((state['document'] as Map)['workflow']['states'] as List).length ==
              3 &&
          ((state['document'] as Map)['workflow']['states'] as List).any(
            (stage) => stage['id'] == 'working',
          ) &&
          !((state['document'] as Map)['workflow']['states'] as List).any(
            (stage) => stage['id'] == 'stage1',
          ),
      'stage deleted',
    );
    await tap('mode-editor-close-inspector');
    await save();
    await tap('mode-editor-tab-graph');
    await tap('mode-editor-node-working');
    await tap('mode-editor-toggle-inspector');
    await tap('mode-editor-fit-view');
    await capture('custom-graph-editor');
    await tap('mode-editor-close-inspector');
    // A malformed graph is rejected without publishing or losing the authored JSON.
    final valid = documentOf(await editor());
    final invalid = jsonDecode(jsonEncode(valid)) as Map<String, dynamic>;
    invalid['workflow']['transitions'].add({
      'sourceStateId': 'completed',
      'targetStateId': 'planning',
      'guard': 'invalid terminal outgoing',
    });
    await tap('mode-editor-tab-json');
    final raw = const JsonEncoder.withIndent('  ').convert(invalid);
    await text('mode-editor-json-editor', raw);
    await tap('mode-editor-validate');
    final rejected = await waitEditor(
      (state) => state['busy'] == false && (state['issues'] as List).isNotEmpty,
      'invalid graph rejected',
    );
    require(
      rejected['jsonText'] == raw && rejected['dirty'] == true,
      'invalid graph retains authored JSON',
    );
    await capture('json-validation');
    await tap('settings-back');
    await tap('mode-editor-unsaved-cancel');
    require(
      (await editor())['jsonText'] == raw,
      'cancel navigation retains draft',
    );
    await tap('settings-back');
    await tap('mode-editor-unsaved-discard');
    await openEditor();
    await tap('mode-editor-catalog-$_modeId');
    await waitEditor(
      (state) =>
          state['busy'] == false &&
          state['dirty'] == false &&
          (state['document'] as Map?)?['id'] == _modeId,
      'discard restored canonical',
    );
    checks['unsaved discard restored canonical'] = true;
    await tap('mode-editor-tab-preview');
    await tap('mode-editor-preview-start');
    await waitEditor(
      (state) =>
          (state['preview'] as Map?)?['currentState']?['id'] == 'planning',
      'preview started',
    );
    await tap('mode-editor-preview-target-working');
    await waitEditor(
      (state) =>
          (state['preview'] as Map?)?['currentState']?['id'] == 'working',
      'preview step',
    );
    await capture('workflow-preview');
    await tap('mode-editor-preview-target-completed');
    await waitEditor(
      (state) => (state['preview'] as Map?)?['terminal'] == true,
      'preview final',
    );
    require(
      (await driver.readSnapshot())['workspace'] == null,
      'preview creates no Thread',
    );
    // Native resize: retain the draft through the catalog/inspector fallback and return.
    final pidReply = jsonDecode(await driver.requestData('pid')) as Map;
    final pid = pidReply['pid'] as int;
    final resized = resizeOwnedWindow(guiPid: pid, width: 760, height: 860);
    require(resized.resized, 'native resize applied');
    await tap('mode-editor-tab-graph');
    await tap('mode-editor-node-working');
    await tap('mode-editor-toggle-inspector');
    final property = find.byValueKey('mode-editor-close-inspector');
    final beforeScroll = await driver.getTopLeft(property);
    await driver.scrollBy(
      find.byValueKey('mode-editor-close-inspector'),
      -180,
      mouseWheel: true,
    );
    final afterScroll = await driver.getTopLeft(property);
    require(
      afterScroll.dy < beforeScroll.dy - 20,
      'native wheel scrolls narrow properties',
    );
    await capture('narrow-inspector');
    final restored = resizeOwnedWindow(guiPid: pid, width: 1440, height: 1000);
    require(restored.resized, 'native resize restored');
    await tap('mode-editor-toggle-inspector');
    // Explicit external reload must retain the last valid published catalog on failure.
    final file = File('$home/modes/$_modeId.json');
    final bytes = await file.readAsBytes();
    final catalogBefore = (await editor())['catalogRevision'];
    await file.writeAsString('{ invalid external document');
    await tap('mode-editor-reload');
    await waitEditor(
      (state) => state['busy'] == false && state['error'] != null,
      'reload rejected',
    );
    require(
      (await editor())['catalogRevision'] == catalogBefore,
      'failed reload keeps published catalog',
    );
    await file.writeAsBytes(bytes);
    await tap('mode-editor-reload');
    await waitEditor(
      (state) => state['busy'] == false && state['error'] == null,
      'valid reload',
    );
    await tap('settings-back');
    await tap('session-mode-selector');
    await tap('session-mode-mode.editor-evidence');
    await submit(0, wait: false);
    await openEditor();
    await tap('mode-editor-catalog-$_modeId');
    var update = documentOf(await editor());
    update['prompt'] = 'mode-editor-graph-updated\n使用更新后的工作流与提示。';
    (update['workflow']['states'] as List).firstWhere(
      (state) => state['id'] == 'planning',
    )['title'] = '规划与设计';
    await jsonDraft(update);
    await save();
    await checkpointStage('first-updated-during-turn');
    await tap('settings-back');
    await waitSnapshot(
      (snapshot) => settled(snapshot) && turnStatus(snapshot) == 'completed',
      'original Turn completed',
    );
    await submit(1);
    await checkpointStage('graph-updated');
    await openEditor();
    update = documentOf(await editor());
    update['prompt'] = 'mode-editor-prompt-only\n仅更新提示词，保留工作流进度。';
    await jsonDraft(update);
    await save();
    await tap('settings-back');
    await submit(2);
    await checkpointStage('prompt-updated');
    await submit(3, wait: false);
    await openEditor();
    await tap('mode-editor-delete');
    await tap('mode-editor-delete-confirm');
    final deleted = await waitEditor(
      (state) =>
          state['busy'] == false &&
          !(state['catalog'] as List).any((mode) => mode['id'] == _modeId),
      'mode deleted',
    );
    require(
      !(deleted['catalog'] as List).any((mode) => mode['id'] == _modeId),
      'deleted Mode removed from catalog',
    );
    await checkpointStage('deleted-running');
    await tap('settings-back');
    await waitSnapshot(
      (snapshot) => settled(snapshot) && turnStatus(snapshot) == 'completed',
      'deleted in flight Turn completed',
    );
    await capture('deleted-mode-snapshot');
  }

  Future<void> recovered() async {
    final saved =
        jsonDecode(await File('$coord/observed.json').readAsString()) as Map;
    threadId = saved['threadId'] as String;
    await revealSidebarThread(driver, threadId!);
    await tap('thread-row-$threadId');
    await clearSidebarSearch(driver);
    await waitSnapshot(
      (snapshot) =>
          workspaceOf(snapshot)?['threadId'] == threadId && settled(snapshot),
      'cold restored Thread',
    );
    final state = await editor();
    require(
      !(state['catalog'] as List).any((mode) => mode['id'] == _modeId),
      'snapshot absent from global catalog',
    );
    require(
      (state['run'] as Map?)?['modeDisplayName'] == '研发验证流程',
      'snapshot display name restored',
    );
    await checkpointStage(
      phase == 'restart' ? 'restart-opened' : 'recheck-opened',
    );
    if (phase == 'restart') {
      await submit(4);
      await tap('thread-menu-$threadId');
      await tap('thread-menu-archive-$threadId');
      await tap('thread-archive-confirm');
      await driver.waitForAbsent(
        find.byValueKey('thread-row-$threadId'),
        timeout: const Duration(seconds: 60),
      );
      await tap('sidebar-archived');
      await tap('thread-restore-$threadId');
      await tap('sidebar-archived');
      await revealSidebarThread(driver, threadId!);
      await tap('thread-row-$threadId');
      await clearSidebarSearch(driver);
      await waitSnapshot(
        (snapshot) =>
            workspaceOf(snapshot)?['threadId'] == threadId && settled(snapshot),
        'archived Mode snapshot restored',
      );
      require(
        (await editor())['run']?['modeDisplayName'] == '研发验证流程',
        'archived Thread restores deleted Mode snapshot',
      );
    }
    await capture('restored-snapshot');
  }

  Future<void> run() async {
    await driver.waitFor(
      find.byValueKey('settings-open'),
      timeout: const Duration(seconds: 90),
    );
    final owner = jsonDecode(await driver.requestData('pid')) as Map;
    require(
      resizeOwnedWindow(
        guiPid: owner['pid'] as int,
        width: 1440,
        height: 1000,
      ).resized,
      'initial native window geometry',
    );
    if (phase == 'first') {
      await first();
    } else {
      await recovered();
    }
  }
}
