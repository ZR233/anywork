import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/presentation/providers/selection_store.dart';
import 'package:anywork/src/presentation/providers/start_session_controller.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Passive metadata only: no provider reads, additional demand or frame pumps.
final class WaitSelectionTrace extends ProviderObserver {
  WaitSelectionTrace(this.graph, Map<String, Object?> report) {
    report['selectionProjectionTrace'] = _scenes;
    final selection = graph.client.selection.source.watchLatest(
      (value) => _record('sdk.selection', _value(value)),
    );
    final draft = graph.client.drafts.startDraft.source.watchLatest(
      (value) => _record('sdk.startDraft', _value(value)),
    );
    _cancel = [selection.observation.cancel, draft.observation.cancel];
    _record('sdk.selection.initial', _value(selection.value));
    _record('sdk.startDraft.initial', _value(draft.value));
  }

  final AppGraph graph;
  final _clock = Stopwatch()..start();
  final _scenes = <String, Map<String, Object?>>{};
  late final List<void Function()> _cancel;
  var _scene = 'setup';
  var _phase = 'setup';
  var _sequence = 0;
  String? _lastUi;

  void close() {
    for (final cancel in _cancel) {
      cancel();
    }
  }

  Future<void> write(String path) => File(
    path,
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(_scenes)}\n');

  Map<String, Object?> _value(Object? value) {
    if (value is SelectionStoreState) {
      return {
        'project': value.selectedProjectId,
        'thread': value.selectedThreadId,
        'needsOpen': value.needsOpen,
      };
    }
    if (value is StartSessionDraft) {
      return {'revision': value.revision, 'submitting': value.submitting};
    }
    if (value is AsyncValue) {
      final data = value.asData?.value;
      return {
        'loading': value.isLoading,
        'hasValue': value.hasValue,
        'hasError': value.hasError,
        if (data is StartPageComposerViewState) ...{
          'project': data.project?.id,
          'submitting': data.submitting,
          'canEdit': data.canEdit,
          'canSubmit': data.canSubmit,
          'revision': data.sessionDraft.revision,
          'draftLength': data.draftText.length,
          'preparation': data.preparation?.phase.name,
        },
      };
    }
    return {'kind': value.runtimeType.toString()};
  }

  String? _name(ProviderObserverContext context) {
    if (identical(context.provider, selectionStoreProvider)) return 'selection';
    if (identical(context.provider, shellSelectionProvider)) return 'shell';
    if (identical(context.provider, startSessionControllerProvider)) {
      return 'startDraft';
    }
    if (identical(context.provider, startPageComposerViewModelProvider)) {
      return 'startComposer';
    }
    return null;
  }

  void _record(String event, Map<String, Object?> value) {
    final cut = _scenes.putIfAbsent(
      _scene,
      () => {'dropped': 0, 'events': <Map<String, Object?>>[]},
    );
    final events = cut['events'] as List<Map<String, Object?>>;
    events.add({
      'seq': ++_sequence,
      'micros': _clock.elapsedMicroseconds,
      'phase': _phase,
      'event': event,
      'sdk': _value(graph.client.selection.state),
      ...value,
    });
    if (events.length > 256) {
      events.removeAt(16);
      cut['dropped'] = (cut['dropped'] as int) + 1;
    }
  }

  void snapshot(WidgetTester tester, String scene, String phase) {
    _scene = scene;
    _phase = phase;
    final panes = find.byType(AgentWorkspacePane, skipOffstage: false);
    final composers = find.byType(PromptComposerView, skipOffstage: false);
    final inputs = find.byKey(const ValueKey('composer-input'));
    final fields = tester.widgetList<TextField>(inputs).toList();
    final focused = tester.binding.focusedEditable;
    final ui = <String, Object?>{
      'panes': [
        for (final element in panes.evaluate())
          {
            'element': identityHashCode(element),
            'thread': (element.widget as AgentWorkspacePane).threadId,
          },
      ],
      'composers': [
        for (final element in composers.evaluate())
          {
            'element': identityHashCode(element),
            'creation': (element.widget as PromptComposerView).creationCard,
            'target': (element.widget as PromptComposerView).pasteTargetId,
            'controller': identityHashCode(
              (element.widget as PromptComposerView).textController,
            ),
            'locked': (element.widget as PromptComposerView).submissionLocked,
          },
      ],
      'fields': [
        for (final field in fields)
          {
            'controller': identityHashCode(field.controller),
            'length': field.controller?.text.length,
            'enabled': field.enabled,
          },
      ],
      'focusedEditable': focused == null ? null : identityHashCode(focused),
      'focusedMounted': focused?.mounted,
      'inputClient': tester.testTextInput.hasAnyClients,
    };
    final signature = jsonEncode(ui);
    if (_lastUi != signature || phase != 'pump') {
      _record('ui', ui);
      _lastUi = signature;
    }
  }

  void dump() {
    final events = _scenes[_scene]?['events'] as List<Map<String, Object?>>?;
    if (events == null) return;
    for (final event in events.skip(
      events.length > 32 ? events.length - 32 : 0,
    )) {
      debugPrintSynchronously('WAIT_SELECTION_TRACE ${jsonEncode(event)}');
    }
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final name = _name(context);
    if (name != null) _record('provider.$name.add', _value(value));
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    final name = _name(context);
    if (name != null) _record('provider.$name.update', _value(newValue));
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    final name = _name(context);
    if (name != null) _record('provider.$name.dispose', {});
  }

  @override
  void didUnmountProvider(ProviderObserverContext context) {
    final name = _name(context);
    if (name != null) _record('provider.$name.unmount', {});
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final name = _name(context);
    if (name != null) {
      _record('provider.$name.fail', {
        'errorKind': error.runtimeType.toString(),
      });
    }
  }
}
