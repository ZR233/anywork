import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _ModeTransport implements StudioTransport {
  ModeDefinitionSnapshot? snapshot;
  ModeValidationResult validation = const ModeValidationResult();
  WorkflowPreviewSnapshot preview = const WorkflowPreviewSnapshot(
    accepted: true,
    message: 'ok',
    terminal: false,
  );
  Object? saveError;
  final List<ModeDocument> saved = [];
  int catalogRevision = 1;
  int saveAttempts = 0;
  Completer<void>? queryBarrier;
  Completer<void>? queryStarted;
  bool retainModeOnReload = false;

  Future<void> _holdQuery() async {
    queryStarted?.complete();
    await queryBarrier?.future;
  }

  @override
  Future<ModeDefinitionSnapshot> readThreadModeDefinition(String modeId) async {
    await _holdQuery();
    final value = snapshot;
    if (value == null) throw StateError('No definition for $modeId');
    return value;
  }

  @override
  Future<ModeDefinitionCommandReply> saveThreadModeDefinition(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    saveAttempts += 1;
    final failure = saveError;
    if (failure != null) throw failure;
    saved.add(document);
    catalogRevision += 1;
    return ModeDefinitionCommandReply(
      catalog: ThreadModeCatalogView(
        revision: catalogRevision,
        modes: [
          ThreadModeDescriptorView(
            id: document.definition.id,
            displayName: document.definition.displayName,
            description: document.definition.description,
            order: document.definition.order,
            hasWorkflow: document.definition.workflow != null,
          ),
        ],
      ),
      definition: ModeDefinitionSnapshot(
        revision: catalogRevision,
        document: document,
        readOnly: false,
      ),
      receipt: _receipt(operationId),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> deleteThreadModeDefinition(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    catalogRevision += 1;
    return ModeDefinitionCommandReply(
      catalog: ThreadModeCatalogView(revision: catalogRevision),
      receipt: _receipt(operationId),
    );
  }

  @override
  Future<ModeDefinitionCommandReply> reloadThreadModeDefinitions({
    required int expectedRevision,
    required OperationId operationId,
  }) async {
    catalogRevision += 1;
    return ModeDefinitionCommandReply(
      catalog: ThreadModeCatalogView(
        revision: catalogRevision,
        modes: retainModeOnReload
            ? [
                ThreadModeDescriptorView(
                  id: snapshot!.document.definition.id,
                  displayName: 'Custom',
                  description: '',
                  order: 0,
                  hasWorkflow: false,
                ),
              ]
            : const [],
      ),
      receipt: _receipt(operationId),
    );
  }

  @override
  Future<ModeValidationResult> validateThreadModeDefinition(String json) async {
    await _holdQuery();
    return validation;
  }

  @override
  Future<String> threadModeDefinitionSchema() async {
    await _holdQuery();
    return '{}';
  }

  @override
  Future<WorkflowPreviewSnapshot> previewThreadModeWorkflow(
    WorkflowPreviewRequest request,
  ) async {
    await _holdQuery();
    return preview;
  }

  StudioCommandReceipt _receipt(OperationId operationId) =>
      StudioCommandReceipt(
        operationId: operationId,
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'thread-mode-catalog',
            ownerEpoch: 'test',
            revision: catalogRevision,
          ),
        ],
        effect: EffectPoint.nextTurn,
        effective: false,
        durable: false,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

ModeDocument _document({String id = 'mode.custom', String prompt = 'first'}) =>
    ModeDocument(
      definition: ModeDefinition(
        id: id,
        displayName: 'Custom',
        description: 'Custom mode',
        order: 3,
        prompt: prompt,
      ),
      editor: const ModeEditorLayout(
        nodes: [WorkflowNodePosition(stateId: 'a', x: 12, y: 34)],
      ),
    );

void main() {
  late _ModeTransport transport;
  late AnyworkClient client;

  setUp(() {
    transport = _ModeTransport();
    client = AnyworkClient(transport: transport, clientId: 'mode-editor');
  });

  tearDown(() async {
    await client.close();
  });

  for (final operation in [
    'open',
    'applyJson',
    'validate',
    'preview',
    'schema',
    'reload',
  ]) {
    test(
      'Client close joins admitted Mode $operation before releasing its permit',
      () async {
        final document = _document();
        transport.snapshot = ModeDefinitionSnapshot(
          revision: 1,
          document: document,
          readOnly: false,
        );
        if (operation != 'open') {
          await client.modeEditor.open(document.definition.id);
        }
        if (operation == 'applyJson') {
          client.modeEditor.editJson('{"id":"mode.custom"}');
          transport.validation = ModeValidationResult(document: document);
        }
        transport.retainModeOnReload = operation == 'reload';
        final barrier = transport.queryBarrier = Completer<void>();
        final started = transport.queryStarted = Completer<void>();
        final Future<Object?> request = switch (operation) {
          'open' => client.modeEditor.open(document.definition.id),
          'applyJson' => client.modeEditor.applyJson(),
          'validate' => client.modeEditor.validate(),
          'preview' => client.modeEditor.preview(),
          'schema' => client.modeEditor.schema(),
          _ => client.modeEditor.reload(),
        };
        await started.future;
        if (operation == 'reload') {
          // This fixture has no bootstrap topic/epoch. Deliver the resource
          // stamp for the catalog already applied from the command reply.
          expect(client.modeCatalog.state.revision, transport.catalogRevision);
          client.mutations.observe(
            ResourceStamp(
              resourceKey: 'thread-mode-catalog',
              ownerEpoch: 'test',
              revision: transport.catalogRevision,
            ),
          );
        }
        final frozen = client.modeEditor.state;
        var ownerClosed = false;
        final closing = client.close();
        final ownerClosing = client.modeEditor.close().then(
          (_) => ownerClosed = true,
        );
        try {
          await Future<void>.delayed(Duration.zero);
          expect(
            ownerClosed,
            isFalse,
            reason: 'The real query has not returned',
          );
          expect(client.budget.used(ResourceKind.draft), 1);
        } finally {
          barrier.complete();
          await request;
          await ownerClosing;
          final report = await closing;
          expect(
            report.unresolved.map((value) => '${value.owner}: ${value.reason}'),
            isEmpty,
          );
        }
        expect(
          client.modeEditor.state,
          same(frozen),
          reason: 'No late state publication',
        );
        expect(client.budget.used(ResourceKind.draft), 0);
      },
    );
  }

  test(
    'open loads the canonical document and create refuses to drop a draft',
    () async {
      final document = _document();
      transport.snapshot = ModeDefinitionSnapshot(
        revision: 7,
        document: document,
        readOnly: false,
      );

      expect(await client.modeEditor.open('mode.custom'), isTrue);
      expect(client.modeEditor.state.document, document);
      expect(client.modeEditor.state.dirty, isFalse);
      expect(
        jsonDecode(client.modeEditor.state.jsonText)['displayName'],
        'Custom',
      );

      client.modeEditor.replace(
        document.copyWith(
          definition: document.definition.copyWith(prompt: 'edited'),
        ),
      );
      expect(client.modeEditor.state.dirty, isTrue);
      expect(client.modeEditor.state.canUndo, isTrue);
      expect(await client.modeEditor.open('mode.other'), isFalse);
      expect(
        client.modeEditor.state.document!.definition.prompt,
        'edited',
        reason: 'a dirty draft must not be silently replaced',
      );
      expect(client.modeEditor.state.error, isNotNull);
    },
  );

  test(
    'invalid JSON keeps the raw text and last graph, then undo restores both',
    () async {
      final document = _document();
      transport.snapshot = ModeDefinitionSnapshot(
        revision: 3,
        document: document,
        readOnly: false,
      );
      await client.modeEditor.open('mode.custom');

      client.modeEditor.editJson('{not json');
      transport.validation = const ModeValidationResult(
        issues: [
          ModeValidationIssue(
            code: 'json.invalid',
            path: r'$',
            message: 'invalid JSON',
          ),
        ],
      );
      expect(await client.modeEditor.applyJson(), isFalse);
      expect(client.modeEditor.state.jsonText, '{not json');
      expect(client.modeEditor.state.document, document);
      expect(client.modeEditor.state.dirty, isTrue);
      expect(client.modeEditor.state.issues.single.code, 'json.invalid');

      client.modeEditor.undo();
      expect(client.modeEditor.state.jsonText, isNot('{not json'));
      expect(client.modeEditor.state.document, document);
      client.modeEditor.redo();
      expect(client.modeEditor.state.jsonText, '{not json');
    },
  );

  test('save applies the typed catalog reply and clears dirty state', () async {
    final document = _document();
    transport.snapshot = ModeDefinitionSnapshot(
      revision: 4,
      document: document,
      readOnly: false,
    );
    await client.modeEditor.open('mode.custom');
    client.modeEditor.replace(
      document.copyWith(
        definition: document.definition.copyWith(prompt: 'saved'),
      ),
    );

    expect(await client.modeEditor.save(), isTrue);
    expect(client.modeEditor.state.dirty, isFalse);
    expect(client.modeEditor.state.busy, isFalse);
    expect(transport.saved.single.definition.prompt, 'saved');
    expect(client.modeCatalog.state.revision, transport.catalogRevision);
  });

  test('save failure retains the graph and raw JSON draft', () async {
    final document = _document();
    transport.snapshot = ModeDefinitionSnapshot(
      revision: 5,
      document: document,
      readOnly: false,
    );
    await client.modeEditor.open('mode.custom');
    client.modeEditor.replace(
      document.copyWith(
        definition: document.definition.copyWith(prompt: 'draft'),
      ),
    );
    final raw = client.modeEditor.state.jsonText;
    transport.saveError = const StudioFailure(
      code: StudioFailureCode.storage,
      message: 'disk full',
      retryable: true,
      correlationId: 'test-save',
    );

    expect(await client.modeEditor.save(), isFalse);
    expect(client.modeEditor.state.dirty, isTrue);
    expect(client.modeEditor.state.jsonText, raw);
    expect(client.modeEditor.state.document!.definition.prompt, 'draft');
    expect(client.modeEditor.state.error, contains('disk full'));
  });

  test('a stale save preserves the draft without replaying it against a newer definition', () async {
    final document = _document();
    transport.snapshot = ModeDefinitionSnapshot(
      revision: 5,
      document: document,
      readOnly: false,
    );
    await client.modeEditor.open('mode.custom');
    client.modeEditor.replace(
      document.copyWith(
        definition: document.definition.copyWith(prompt: 'my draft'),
      ),
    );
    transport.snapshot = ModeDefinitionSnapshot(
      revision: 6,
      document: document.copyWith(
        definition: document.definition.copyWith(
          prompt: 'someone else updated',
        ),
      ),
      readOnly: false,
    );
    transport.saveError = const StudioFailure(
      code: StudioFailureCode.staleRevision,
      message: 'reload required',
      retryable: true,
      correlationId: 'stale-mode',
    );
    expect(await client.modeEditor.save(), isFalse);
    expect(transport.saveAttempts, 1);
    expect(client.modeEditor.state.document!.definition.prompt, 'my draft');
    expect(client.modeEditor.state.dirty, isTrue);
    expect(
      transport.snapshot!.document.definition.prompt,
      'someone else updated',
    );
  });

  test(
    'JSON authoring cannot use a built-in ID to bypass read-only protection',
    () async {
      final draft = _document();
      transport.snapshot = ModeDefinitionSnapshot(
        revision: 1,
        document: draft,
        readOnly: false,
      );
      await client.modeEditor.open('mode.custom');
      final builtin = _document(id: 'mode.task');
      transport.validation = ModeValidationResult(document: builtin);
      const raw = '{"id":"mode.task"}';
      client.modeEditor.editJson(raw);
      expect(await client.modeEditor.applyJson(), isFalse);
      expect(client.modeEditor.state.jsonText, raw);
      expect(client.modeEditor.state.document!.definition.id, 'mode.custom');
      expect(client.modeEditor.state.dirty, isTrue);
      client.modeEditor.discard();
      client.modeEditor.replace(builtin);
      expect(client.modeEditor.state.document!.definition.id, 'mode.custom');
      client.modeEditor.create(id: 'mode.simple', displayName: 'overwrite');
      expect(client.modeEditor.state.document!.definition.id, 'mode.custom');
      expect(transport.saved, isEmpty);
    },
  );

  test('successful reload observes external deletion without restoring a stale definition', () async {
    transport.snapshot = ModeDefinitionSnapshot(
      revision: 1,
      document: _document(),
      readOnly: false,
    );
    await client.modeEditor.open('mode.custom');
    expect(await client.modeEditor.reload(), isTrue);
    expect(client.modeEditor.state.document, isNull);
    expect(client.modeEditor.state.dirty, isFalse);
    expect(client.modeEditor.state.error, isNull);
    expect(client.modeCatalog.state.value!.modes, isEmpty);
  });

  test('built-in read-only definitions reject edits in the owner', () async {
    final document = _document(id: 'mode.simple');
    transport.snapshot = ModeDefinitionSnapshot(
      revision: 2,
      document: document,
      readOnly: true,
    );
    await client.modeEditor.open('mode.simple');

    client.modeEditor.replace(
      document.copyWith(
        definition: document.definition.copyWith(prompt: 'forbidden'),
      ),
    );
    expect(client.modeEditor.state.document, document);
    expect(client.modeEditor.state.error, isNotNull);
    expect(await client.modeEditor.save(), isFalse);
    expect(transport.saved, isEmpty);
  });

  test(
    'preview delegates the typed request and publishes the Rust result',
    () async {
      final document = _document();
      transport.snapshot = ModeDefinitionSnapshot(
        revision: 6,
        document: document,
        readOnly: false,
      );
      await client.modeEditor.open('mode.custom');

      await client.modeEditor.preview(targetStateId: 'done', reason: 'check');
      expect(client.modeEditor.state.preview, transport.preview);
      expect(client.modeEditor.state.error, isNull);
    },
  );
}
