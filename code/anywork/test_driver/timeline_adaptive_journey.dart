// Opt-in native cold reopen, window, sidebar and composer acceptance.
// Use a retained manual-gui snapshot as the original project/thread identity.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'cold_start_navigation.dart';
import 'timeline_observation.dart';
import 'window_control.dart';
import 'key_press.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    throw ArgumentError('Expected VM_URL BASELINE_SNAPSHOT OUTPUT_DIR');
  }
  final baseline = (jsonDecode(await File(args[1]).readAsString()) as Map)
      .cast<String, dynamic>();
  final identity = readOpenedTimelineIdentity(baseline);
  if (!identity.consistent) throw StateError('Inconsistent source identity');
  final output = Directory(args[2]);
  if (await output.exists()) throw StateError('Evidence already exists');
  await output.create(recursive: true);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  final report = <String, Object?>{
    'pass': false,
    'platform': 'Linux native / Flutter Driver / real FRB',
  };
  WindowGeometry? originalWindow;
  int? guiPid;
  var heldRight = false;
  int? canonicalWidth(Map<String, dynamic> state) =>
      (state['settings'] as Map?)?['sidebarWidth'] as int?;
  bool settingsSettled(Map<String, dynamic> state) =>
      ((state['settings'] as Map)['mutations'] as List).isEmpty;
  Future<Map<String, dynamic>> until(
    String stage,
    bool Function(Map<String, dynamic>) predicate,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final state = await driver.readSnapshot();
      if (predicate(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Did not settle: $stage');
  }

  Future<Map<String, dynamic>> settled(String stage) {
    final stability = TimelineViewportStability();
    return until(stage, stability.accept);
  }

  Future<({double width, double height})> bounds(String key) async {
    final a = await driver.getTopLeft(find.byValueKey(key));
    final b = await driver.getBottomRight(find.byValueKey(key));
    return (width: b.dx - a.dx, height: b.dy - a.dy);
  }

  try {
    report['restore'] = await restoreColdStartTarget(
      ColdStartDriverSurface(
        readSnapshot: driver.readSnapshot,
        tap: (finder, timeout) => driver.rawTap(finder, timeout: timeout),
      ),
      identity: ColdStartIdentity(
        workspaceId: identity.workspaceId!,
        threadId: identity.threadId!,
      ),
      phase: 'compact-cold-reopen',
      onStage: (stage) async {
        stdout.writeln(stage);
      },
    );
    final initial = await settled('cold latest');
    final content = TimelineObservation.parse(initial);
    final scroll = TimelineScrollObservation.parse(initial);
    content.requireConsistentIds();
    if (!content.isLive ||
        content.itemCount <= 32 ||
        !scroll.atLiveEdge ||
        content.threadId != identity.threadId) {
      throw StateError('Cold compact history did not automatically fill');
    }
    report['coldReopen'] = {
      'timeline': content.summary(),
      'scroll': scroll.toJson(),
      'pass': true,
    };
    await File('${output.path}/cold-reopen-autofill.png')
        .writeAsBytes(await driver.screenshot());
    guiPid = (jsonDecode(await driver.requestData('pid')) as Map)['pid'] as int;
    final resizes = <Object?>[];
    report['resizes'] = resizes;
    for (final size in [
      (1280, 900),
      (1920, 1200),
      (900, 760),
      (1280, 900),
      (1280, 600),
      (1100, 900),
    ]) {
      final previous = TimelineObservation.parse(
        await settled('before resize'),
      );
      final before = await bounds('studio-shell');
      final result = resizeOwnedWindow(
        guiPid: guiPid,
        width: size.$1,
        height: size.$2,
      );
      if (!result.resized) {
        throw StateError('${result.reason}: ${result.diagnostics}');
      }
      originalWindow ??= result.original;
      final ratio = before.width / result.original!.width;
      final expectedWidth =
          before.width + (size.$1 - result.original!.width) * ratio;
      final expectedHeight =
          before.height + (size.$2 - result.original!.height) * ratio;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (true) {
        final actual = await bounds('studio-shell');
        if ((actual.width - expectedWidth).abs() <= 1 &&
            (actual.height - expectedHeight).abs() <= 1) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Flutter did not adopt $size');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final state = await settled('resize $size');
      final after = TimelineObservation.parse(state);
      final geometry = TimelineScrollObservation.parse(state);
      after.requireConsistentIds();
      final pass =
          after.generation == content.generation &&
          after.isLive &&
          geometry.atLiveEdge &&
          previous.itemIds.every(after.itemIds.contains);
      resizes.add({
        'size': [size.$1, size.$2],
        'beforeItems': previous.itemCount,
        'afterItems': after.itemCount,
        'scroll': geometry.toJson(),
        'pass': pass,
      });
      if (!pass) throw StateError('Resize changed display or reading position');
      await File('${output.path}/responsive-${size.$1}x${size.$2}.png')
          .writeAsBytes(await driver.screenshot());
    }
    await driver.sendCommand(const SetSemantics(true));
    final sidebar = find.byValueKey('sidebar-resize');
    final sidebarBefore = await bounds('timeline-scrollable');
    final initialSidebarWidth =
        (await driver.getTopLeft(sidebar)).dx -
        (await driver.getTopLeft(find.byValueKey('studio-shell'))).dx;
    await driver.dragBy(sidebar, dx: 80);
    final sidebarState = await settled('sidebar resized');
    final sidebarAfter = await bounds('timeline-scrollable');
    final expectedDrag = (440 - initialSidebarWidth).clamp(0.0, 80.0);
    if ((sidebarBefore.width - sidebarAfter.width - expectedDrag).abs() > 1) {
      throw StateError(
        'Sidebar drag lost part of the native pointer displacement',
      );
    }
    final sidebarContent = TimelineObservation.parse(sidebarState);
    final savedDrag = await until(
      'sidebar drag saved',
      (state) =>
          canonicalWidth(state) ==
              (initialSidebarWidth + expectedDrag).round() &&
          settingsSettled(state),
    );
    if (sidebarBefore.width - sidebarAfter.width < 1 ||
        !sidebarContent.isLive ||
        sidebarContent.generation != content.generation) {
      throw StateError('Sidebar resize did not preserve display');
    }
    report['sidebarResize'] = {
      'beforeWidth': sidebarBefore.width,
      'afterWidth': sidebarAfter.width,
      'expectedDelta': expectedDrag,
      'canonicalWidth': canonicalWidth(savedDrag),
      'pass': true,
    };
    await File('${output.path}/sidebar-resized.png')
        .writeAsBytes(await driver.screenshot());
    await driver.dragBy(sidebar, dx: -80);
    await settled('sidebar restored');
    final keyboardWidth = (await bounds('timeline-scrollable')).width;
    final sidebarWidth =
        (await driver.getTopLeft(sidebar)).dx -
        (await driver.getTopLeft(find.byValueKey('studio-shell'))).dx;
    final keyboardWidths = <Map<String, Object?>>[];
    report['sidebarKeyboard'] = {'widths': keyboardWidths, 'pass': false};
    Future<void> expectWidth(
      double expected,
      String stage, {
      bool saved = true,
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      final expectedCanonical = (keyboardWidth + sidebarWidth - expected)
          .round();
      while (DateTime.now().isBefore(deadline)) {
        final actual = (await bounds('timeline-scrollable')).width;
        final state = await driver.readSnapshot();
        final canonical = canonicalWidth(state);
        if ((actual - expected).abs() <= 1 &&
            (!saved ||
                (canonical == expectedCanonical && settingsSettled(state)))) {
          keyboardWidths.add({
            'stage': stage,
            'expected': expected,
            'actual': actual,
            'canonicalWidth': canonical,
            'saved': saved,
            'settingsSettled': settingsSettled(state),
          });
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('Sidebar keyboard width did not change: $stage');
    }

    await driver.rawTap(find.byValueKey('composer-input'));
    await driver.rawTap(sidebar);
    await driver.pressKey(0x100000303, 0x7004f);
    await expectWidth(keyboardWidth - 16, 'Right');
    await driver.pressKey(0x100000303, 0x7004f);
    await expectWidth(keyboardWidth - 32, 'Right twice');
    await driver.pressKey(0x100000302, 0x70050);
    await expectWidth(keyboardWidth - 16, 'Left');
    await driver.pressKey(0x100000303, 0x7004f);
    await driver.pressKey(0x100000302, 0x70050);
    await expectWidth(keyboardWidth - 16, 'rapid Right then Left');
    await driver.pressKey(0x100000306, 0x7004a);
    await expectWidth(
      keyboardWidth + sidebarWidth - 336,
      'Home canonical default',
    );
    await driver.sendCommand(
      KeyPress(0x100000303, 0x7004f, phase: KeyPressPhase.down),
    );
    heldRight = true;
    await expectWidth(
      keyboardWidth + sidebarWidth - 352,
      'Right held',
      saved: false,
    );
    final heldCanonical = canonicalWidth(await driver.readSnapshot());
    if (heldCanonical != 336) {
      throw StateError('Held key committed before release or focus loss');
    }
    await driver.rawTap(find.byValueKey('composer-input'));
    await expectWidth(
      keyboardWidth + sidebarWidth - 352,
      'focus loss saves held key',
    );
    await driver.sendCommand(
      KeyPress(0x100000303, 0x7004f, phase: KeyPressPhase.up),
    );
    heldRight = false;
    await driver.rawTap(sidebar);
    await driver.pressKey(0x100000306, 0x7004a);
    await expectWidth(
      keyboardWidth + sidebarWidth - 336,
      'Home after focus loss',
    );
    final keyboardState = TimelineObservation.parse(
      await settled('sidebar keyboard'),
    );
    if (!keyboardState.isLive ||
        keyboardState.generation != content.generation) {
      throw StateError('Sidebar keyboard changed reading mode');
    }
    report['sidebarKeyboard'] = {
      'arrowsAndHome': true,
      'focusLossSaved': true,
      'widths': keyboardWidths,
      'pass': true,
    };
    await File('${output.path}/sidebar-keyboard.png')
        .writeAsBytes(await driver.screenshot());
    final composerBefore = await driver.readSnapshot();
    final originalDraft =
        ((composerBefore['workspace'] as Map)['composer'] as Map)['draft']
            as String;
    final viewportBefore = TimelineScrollObservation.parse(composerBefore)
        .viewportDimension!;
    final draft = List.generate(
      14,
      (i) => 'Unsent layout check ${i + 1}',
    ).join('\n');
    await driver.tap(find.byValueKey('composer-input'));
    await driver.enterText(draft);
    final grown = await until(
      'composer grew',
      (state) =>
          ((state['workspace'] as Map?)?['composer'] as Map?)?['draft'] ==
              draft &&
          timelineViewportSettled(state) &&
          (TimelineScrollObservation.parse(state).viewportDimension ??
                  viewportBefore) <
              viewportBefore - 1,
    );
    final grownContent = TimelineObservation.parse(grown);
    if (!grownContent.isLive || grownContent.generation != content.generation) {
      throw StateError('Composer layout changed reading mode');
    }
    report['composerResize'] = {
      'beforeViewport': viewportBefore,
      'afterViewport': TimelineScrollObservation.parse(grown).viewportDimension,
      'pass': true,
    };
    await File('${output.path}/composer-grown.png')
        .writeAsBytes(await driver.screenshot());
    await driver.enterText(originalDraft);
    await until(
      'draft restored',
      (state) =>
          ((state['workspace'] as Map?)?['composer'] as Map?)?['draft'] ==
              originalDraft &&
          timelineViewportSettled(state),
    );
    report['pass'] = true;
  } catch (error) {
    report['error'] = '$error';
    await File('${output.path}/failure.png')
        .writeAsBytes(await driver.screenshot());
    rethrow;
  } finally {
    try {
      if (heldRight) {
        await driver.sendCommand(
          KeyPress(0x100000303, 0x7004f, phase: KeyPressPhase.up),
        );
      }
      if (originalWindow != null && guiPid != null) {
        resizeOwnedWindow(
          guiPid: guiPid,
          width: originalWindow.width,
          height: originalWindow.height,
        );
      }
      report['shutdown'] = jsonDecode(
        await driver.requestData(
          'shutdown',
          timeout: const Duration(seconds: 90),
        ),
      );
      await driver.requestData('request-app-exit');
    } finally {
      await File('${output.path}/report.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      await driver.close();
    }
  }
}
