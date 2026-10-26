import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/settings/modes/state/mode_editor_state.dart';
import 'package:anywork/src/features/settings/modes/view_models/mode_editor_view_model.dart';
import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Shared test environment only; production dependencies are public domain APIs.
import '../../../anywork_client/test/support/modes_fixture.dart';

final class _Editor {
  _Editor(this.fixture, this.container) {
    subscription = container.listen(modeEditorViewModelProvider, (_, next) {
      final value = next.asData?.value;
      if (value != null) publications.add(value);
    }, fireImmediately: true);
  }
  final ModesFixture fixture;
  final ProviderContainer container;
  final publications = <ModeEditorViewState>[];
  late final ProviderSubscription<AsyncValue<ModeEditorViewState>> subscription;
  bool disposed = false;

  ModeEditorViewState get state =>
      container.read(modeEditorViewModelProvider).requireValue;
  ModeEditorViewModel get vm =>
      container.read(modeEditorViewModelProvider.notifier);

  void disposeEditor() {
    if (disposed) return;
    disposed = true;
    subscription.close();
    container.dispose();
  }

  Future<void> close() async {
    disposeEditor();
    final report = await fixture.repository.close(
      deadline: DateTime.now().add(const Duration(seconds: 3)),
    );
    expect(
      report.unresolved,
      isEmpty,
      reason: 'The actual Mode Repository joins its own work',
    );
    expect(fixture.budget.usage, isEmpty);
  }
}

Future<_Editor> _editor({
  ModeDocument? document,
  int revision = 1,
  bool open = true,
  bool readOnly = false,
}) async {
  final fixture = ModesFixture();
  final initial = document ?? modeDocument();
  fixture.port.definitions[initial.definition.id.id] = ModeDefinitionSnapshot(
    revision: revision,
    document: initial,
    readOnly: readOnly,
  );
  fixture.port.validation = ModeValidationResult(
    document: initial,
    issues: const [],
  );
  await fixture.establish(revision: revision);
  final container = ProviderContainer(
    overrides: [modesRepositoryProvider.overrideWithValue(fixture.repository)],
  );
  final editor = _Editor(fixture, container);
  addTearDown(editor.close);
  await container.read(modeEditorViewModelProvider.future);
  if (open) expect(await editor.vm.open(initial.definition.id.id), isTrue);
  return editor;
}

ThreadModeDescriptorRead _descriptor(ModeDocument document) =>
    ThreadModeDescriptorRead(
      id: document.definition.id,
      displayName: ReadText.inline(text: document.definition.displayName),
      description: ReadText.inline(text: document.definition.description),
      order: document.definition.order,
      hasWorkflow: document.definition.workflow != null,
      readOnly: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final operation in [
    'open',
    'applyJson',
    'validate',
    'preview',
    'schema',
    'reload',
  ]) {
    test(
      'disposing the editor does not drop admitted Mode $operation from Repository close',
      () async {
        final editor = await _editor(open: operation != 'open');
        final fixture = editor.fixture;
        final port = fixture.port;
        if (operation == 'applyJson') {
          editor.vm.editJson('{"id":"mode.custom"}');
        }
        final barrier = port.queryReceipt = Completer<void>();
        final entered = port.queryEntered = Completer<void>();
        Future<void> invoke() async {
          switch (operation) {
            case 'open':
              await editor.vm.open('mode.custom');
            case 'applyJson':
              await editor.vm.applyJson();
            case 'validate':
              await editor.vm.validate();
            case 'preview':
              await editor.vm.preview();
            case 'schema':
              await editor.vm.readSchema();
            case 'reload':
              await editor.vm.reload();
          }
        }

        final request = invoke();
        try {
          if (operation == 'reload') {
            final command = await port.command(0);
            expect(command.kind, 'reload');
            command.complete(revision: 2);
            port.publishChange(
              deliverySequence: 2,
              from: 1,
              to: 2,
              rows: [_descriptor(modeDocument())],
            );
            await port.feed.acknowledged(2);
          }
          await entered.future;
          final frozen = editor.state;
          final publicationCount = editor.publications.length;
          editor.disposeEditor();
          expect(
            port.feed.requestCloseCalls,
            0,
            reason:
                'VM disposal cancels its observation, not the shared catalog',
          );
          final report = await fixture.repository.close(
            deadline: DateTime.utc(2000),
          );
          expect(
            report.complete,
            isFalse,
            reason: 'The admitted query has not returned',
          );
          final queryOwner = switch (operation) {
            'open' || 'reload' => 'modes:definition',
            'applyJson' || 'validate' => 'modes:validate',
            'preview' => 'modes:preview',
            _ => 'modes:schema',
          };
          final pendingQuery = report.unresolved
              .where((owner) => owner.owner == queryOwner)
              .single;
          expect(
            pendingQuery.issues.single.recovery,
            CleanupRecovery.awaitCompletion,
          );
          expect(
            fixture.budget.usage
                .where((usage) => usage.owner == queryOwner)
                .single
                .kind,
            ResourceKind.readModel,
          );
          barrier.complete();
          await request;
          expect((await fixture.repository.retryCleanup()).complete, isTrue);
          expect(editor.publications, hasLength(publicationCount));
          expect(
            editor.publications.last,
            same(frozen),
            reason: 'No late VM state publication',
          );
          expect(fixture.budget.usage, isEmpty);
        } finally {
          if (!barrier.isCompleted) barrier.complete();
          await request;
        }
      },
    );
  }

  test('open loads canonical authoring data and a dirty graph cannot be silently replaced', () async {
    final editor = await _editor(revision: 7);
    final original = modeDocument();
    expect(editor.state.document, original);
    expect(editor.state.savedRevision, 7);
    expect(editor.state.dirty, isFalse);
    expect((jsonDecode(editor.state.jsonText) as Map)['displayName'], 'Custom');
    editor.vm.edit(const ModeEdit.prompt('edited'));
    expect(editor.state.dirty, isTrue);
    expect(editor.state.undo, isNotEmpty);
    expect(await editor.vm.open('mode.other'), isFalse);
    expect(editor.state.document!.definition.prompt, 'edited');
    expect(
      editor.state.error,
      isNotNull,
      reason: 'Rejecting replacement of a dirty draft remains visible',
    );
    expect(editor.fixture.port.definitionRequests, ['mode.custom']);
  });

  test('invalid JSON keeps raw input and the last graph; undo and redo restore both', () async {
    final editor = await _editor(revision: 3);
    final original = editor.state.document;
    editor.vm.editJson('{not json');
    editor.fixture.port.validation = const ModeValidationResult(
      document: null,
      issues: [
        ValidationIssue(
          code: 'json.invalid',
          path: r'$',
          message: 'invalid JSON',
        ),
      ],
    );
    expect(await editor.vm.applyJson(), isFalse);
    expect(editor.fixture.port.validationRequests.single, '{not json');
    expect(editor.state.jsonText, '{not json');
    expect(editor.state.document, original);
    expect(editor.state.dirty, isTrue);
    expect(editor.state.issues.single.code, 'json.invalid');
    editor.vm.undo();
    expect(editor.state.jsonText, isNot('{not json'));
    expect(editor.state.document, original);
    editor.vm.redo();
    expect(editor.state.jsonText, '{not json');
    expect(editor.state.document, original);
  });

  test('save uses the frozen draft revision and clears dirty only after real catalog observation', () async {
    final editor = await _editor(revision: 4);
    editor.vm.edit(const ModeEdit.prompt('saved'));
    final payload = editor.state.document!;
    editor.fixture.port.validation = ModeValidationResult(
      document: payload,
      issues: const [],
    );
    final saving = editor.vm.save();
    final call = await editor.fixture.port.command(0);
    expect(call.kind, 'save');
    expect(call.expectedRevision, 4);
    expect(call.document!.definition.prompt, 'saved');
    expect(editor.state.dirty, isTrue);
    expect(editor.state.busy, isTrue);
    call.complete(
      revision: 5,
      definition: ModeDefinitionSnapshot(
        revision: 5,
        document: payload,
        readOnly: false,
      ),
    );
    expect(
      editor.fixture.repository.state.value.projection.header!.revision,
      4,
      reason: 'A command reply is not a second canonical writer',
    );
    editor.fixture.port.publishChange(
      deliverySequence: 2,
      from: 4,
      to: 5,
      rows: [_descriptor(payload)],
    );
    expect(await saving, isTrue);
    expect(editor.state.dirty, isFalse);
    expect(editor.state.busy, isFalse);
    expect(editor.state.document!.definition.prompt, 'saved');
    expect(editor.state.savedRevision, 5);
    expect(
      editor.fixture.repository.state.value.projection.header!.revision,
      5,
    );
    expect(editor.state.operation!.operation!.observed, isTrue);
  });

  test(
    'a rejected save preserves the graph and exact raw JSON draft',
    () async {
      final editor = await _editor(revision: 5);
      editor.vm.edit(const ModeEdit.prompt('draft'));
      final raw = editor.state.jsonText;
      editor.fixture.port.validation = ModeValidationResult(
        document: editor.state.document,
        issues: const [],
      );
      final saving = editor.vm.save();
      final call = await editor.fixture.port.command(0);
      const failure = StudioFailure(
        code: StudioFailureCode.storage,
        message: 'disk full',
        retryable: true,
        correlationId: 'test-save',
      );
      call.reply.completeError(
        const CommandDispatchFailure.rejected(failure: failure),
      );
      expect(await saving, isFalse);
      expect(editor.state.dirty, isTrue);
      expect(editor.state.jsonText, raw);
      expect(editor.state.document!.definition.prompt, 'draft');
      expect(editor.state.error, failure);
      expect(editor.fixture.port.commands, hasLength(1));
    },
  );

  test(
    'a stale save never replays the draft against a newer definition',
    () async {
      final editor = await _editor(revision: 5);
      editor.vm.edit(const ModeEdit.prompt('my draft'));
      editor.fixture.port.validation = ModeValidationResult(
        document: editor.state.document,
        issues: const [],
      );
      final newer = modeDocument(prompt: 'someone else updated');
      editor.fixture.port.definitions['mode.custom'] = ModeDefinitionSnapshot(
        revision: 6,
        document: newer,
        readOnly: false,
      );
      final saving = editor.vm.save();
      final call = await editor.fixture.port.command(0);
      expect(call.expectedRevision, 5);
      const failure = StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'reload required',
        retryable: true,
        correlationId: 'stale-mode',
      );
      call.reply.completeError(
        const CommandDispatchFailure.rejected(failure: failure),
      );
      expect(await saving, isFalse);
      expect(editor.fixture.port.commands, hasLength(1));
      expect(editor.fixture.port.definitionRequests, ['mode.custom']);
      expect(editor.state.document!.definition.prompt, 'my draft');
      expect(editor.state.dirty, isTrue);
      expect(editor.state.savedRevision, 5);
      expect(editor.fixture.port.definitions['mode.custom']!.document, newer);
    },
  );

  test('JSON authoring and create cannot use built-in IDs to bypass read-only protection', () async {
    final editor = await _editor();
    final builtin = modeDocument(id: 'mode.task');
    editor.fixture.port.validation = ModeValidationResult(
      document: builtin,
      issues: const [],
    );
    const raw = '{"id":"mode.task"}';
    editor.vm.editJson(raw);
    expect(await editor.vm.applyJson(), isFalse);
    expect(editor.state.jsonText, raw);
    expect(editor.state.document!.definition.id, ThreadModeId('mode.custom'));
    expect(editor.state.dirty, isTrue);
    editor.vm.discard();
    expect(await editor.vm.importJson(raw), isFalse);
    expect(editor.state.document!.definition.id, ThreadModeId('mode.custom'));
    editor.vm.discard();
    editor.vm.create(modeDocument(id: 'mode.simple'));
    expect(editor.state.document!.definition.id, ThreadModeId('mode.custom'));
    expect(editor.fixture.port.commands, isEmpty);
  });

  test(
    'successful reload observes deletion without restoring a stale definition',
    () async {
      final editor = await _editor();
      final reloading = editor.vm.reload();
      final command = await editor.fixture.port.command(0);
      expect(command.expectedRevision, 1);
      editor.fixture.port.definitions.remove('mode.custom');
      command.complete(revision: 2);
      editor.fixture.port.publishChange(deliverySequence: 2, from: 1, to: 2);
      expect(await reloading, isTrue);
      expect(editor.state.document, isNull);
      expect(editor.state.dirty, isFalse);
      expect(editor.state.error, isNull);
      final mirror =
          editor.fixture.repository.state.value.modes
              as CurrentCollectionMirror<ThreadModeDescriptor>;
      expect(mirror.window.entries, isEmpty);
      expect(mirror.window.complete, isTrue);
    },
  );

  test(
    'built-in read-only definitions reject editing and never dispatch save',
    () async {
      final document = modeDocument(id: 'mode.simple');
      final editor = await _editor(
        document: document,
        revision: 2,
        readOnly: true,
      );
      editor.vm.edit(const ModeEdit.prompt('forbidden'));
      expect(editor.state.document, document);
      expect(editor.state.error, isNotNull);
      expect(await editor.vm.save(), isFalse);
      expect(editor.fixture.port.commands, isEmpty);
    },
  );

  test(
    'preview delegates the exact typed request and publishes the native result',
    () async {
      final editor = await _editor(revision: 6);
      final document = editor.state.document!;
      final preview = WorkflowPreviewSnapshot(
        accepted: true,
        message: 'ok',
        currentState: document.definition.workflow!.states.last,
        transitions: const [],
        path: const ['a', 'done'],
        terminal: true,
      );
      editor.fixture.port.previewResult = preview;
      editor.vm.setPreviewReason('check');
      await editor.vm.preview(targetStateId: 'done');
      final request = editor.fixture.port.previewRequests.single;
      expect(request.document, document);
      expect(request.path, isEmpty);
      expect(request.targetStateId, 'done');
      expect(request.reason, 'check');
      expect(editor.state.preview, preview);
      expect(editor.state.error, isNull);
    },
  );
}
