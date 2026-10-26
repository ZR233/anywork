import 'dart:async';
import 'dart:io';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/conversation/connectors/composer_connector.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/view_models/composer_attachment_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/views/composer_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/clipboard_image_reader.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:cross_file_io/cross_file_io.dart';
import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/drafts_native_fixture.dart';
import 'support/pump_client_future.dart';
import 'support/selector_environment.dart';

void main() {
  setUp(() {
    final previous = CrossFilePlatform.instance;
    // Registered before body cleanups: restore only after staging and the
    // original Repository owners have completed their teardown.
    addTearDown(() {
      CrossFilePlatform.instance = previous;
    });
    CrossFileIO.registerWith();
  });

  testWidgets(
    'current non-text sources control menus, exact picker filters and local drop admission',
    (tester) async {
      final env = SelectorEnvironment();
      await pumpClientFuture(
        tester,
        env.establish(catalog: false),
        'composer fixture sources ready',
      );
      await pumpClientFuture(
        tester,
        env.selectStart(),
        'composer Start route ready',
      );
      final descriptor = await pumpClientFuture(
        tester,
        env.models.loadModel('account-0', 'text'),
        'declared descriptor',
      );
      final models = _ControlledModels(env.models);
      final container = _container(env, models);
      const target = ComposerKey.start(projectId: 'project');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await pumpClientFuture(tester, env.close(), 'composer owners close');
      });
      final pickerFilters = <List<Object?>>[];
      const channel = MethodChannel('io.github.zr233.anywork/file_dialogs');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'pickFiles');
        pickerFilters.add(List<Object?>.from(call.arguments as List));
        return <String>[];
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        _harness(container, const ComposerConnector(target: target)),
      );
      final first = await pumpClientFuture(
        tester,
        models.calls.at(0),
        'initial capability read',
      );
      expect(_entry(tester).onPressed, isNull);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ComposerView)),
      );
      expect(_entry(tester).tooltip, l10n.composerAttachmentUnsupportedTooltip);
      expect(
        tester.widget<DropTarget>(find.byType(DropTarget)).enabled,
        isFalse,
      );

      final scenarios = [
        (
          input: <ModelInputCapability>[],
          local: false,
          remote: false,
          extensions: <String>[],
        ),
        (
          input: [
            _input(ModelModality.text, ModelInputSource.local),
            _input(ModelModality.text, ModelInputSource.remoteUrl),
          ],
          local: false,
          remote: false,
          extensions: <String>[],
        ),
        (
          input: [_input(ModelModality.image, ModelInputSource.local)],
          local: true,
          remote: false,
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
        ),
        (
          input: [_input(ModelModality.video, ModelInputSource.remoteUrl)],
          local: false,
          remote: true,
          extensions: <String>[],
        ),
        (
          input: [
            _input(ModelModality.image, ModelInputSource.local),
            _input(ModelModality.video, ModelInputSource.local),
            _input(ModelModality.image, ModelInputSource.remoteUrl),
          ],
          local: true,
          remote: true,
          extensions: [
            'png',
            'jpg',
            'jpeg',
            'gif',
            'webp',
            'mp4',
            'mov',
            'webm',
            'mkv',
          ],
        ),
        (
          input: [_input(ModelModality.file, ModelInputSource.local)],
          local: true,
          remote: false,
          extensions: <String>[],
        ),
      ];
      for (var index = 0; index < scenarios.length; index++) {
        final scenario = scenarios[index];
        if (index != 0) {
          await pumpClientFuture(
            tester,
            env.modelsPort.base.advanceCatalog(),
            'catalog revision',
          );
        }
        final call = index == 0
            ? first
            : await pumpClientFuture(
                tester,
                models.calls.at(index),
                'updated capability read',
              );
        call.reply.complete(
          descriptor.copyWith(
            capabilities: descriptor.capabilities.copyWith(
              input: scenario.input,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final drop = tester.widget<DropTarget>(find.byType(DropTarget));
        expect(drop.enabled, scenario.local);
        if (!scenario.local) {
          await pumpClientFuture(
            tester,
            Future<void>.sync(() => drop.onDrop(_drop())),
            'rejected local drop',
          );
          expect(env.attachments.begins.values, isEmpty);
        }
        expect(
          _entry(tester).onPressed != null,
          scenario.local || scenario.remote,
        );
        if (!scenario.local && !scenario.remote) continue;
        await tester.tap(_entryFinder());
        await tester.pumpAndSettle();
        expect(
          find.byKey(StudioDriverKeys.attachmentLocal),
          scenario.local ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(StudioDriverKeys.attachmentUrl),
          scenario.remote ? findsOneWidget : findsNothing,
        );
        if (scenario.local) {
          await tester.tap(find.byKey(StudioDriverKeys.attachmentLocal));
          await tester.pumpAndSettle();
          expect(pickerFilters.last, scenario.extensions);
        } else {
          await tester.tap(_entryFinder());
          await tester.pumpAndSettle();
        }
      }

      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'keep this draft',
      );
      final dropping = Future<void>.sync(
        () =>
            tester.widget<DropTarget>(find.byType(DropTarget)).onDrop(_drop()),
      );
      final begin = await pumpClientFuture(
        tester,
        env.attachments.begins.at(0),
        'local admission',
      );
      expect(begin.sources, const [
        AttachmentDraftSource.localFile('/declared/attachment.txt'),
      ]);
      final job = DraftAdmissionJob(begin.id);
      begin.reply.complete(job);
      final result = await pumpClientFuture(
        tester,
        job.reads.at(0),
        'original admission result',
      );
      const attachment = AttachmentMetadata(
        id: 'kept',
        modality: AttachmentModality.file,
        mediaType: 'text/plain',
        filename: 'attachment.txt',
        byteSize: 8,
      );
      result.complete([attachment]);
      final close = await pumpClientFuture(
        tester,
        job.closes.at(0),
        'admission cleanup',
      );
      close.reply.complete(
        FeedCloseReport(
          feedId: job.id.value,
          outcome: const FeedCloseOutcome.clean(),
        ),
      );
      await pumpClientFuture(tester, dropping, 'complete local drop callback');
      await tester.pumpAndSettle();
      expect(env.drafts.start('project').state.value.attachments, [attachment]);

      await pumpClientFuture(
        tester,
        env.modelsPort.base.advanceCatalog(),
        'failing catalog revision',
      );
      final failed = await pumpClientFuture(
        tester,
        models.calls.at(scenarios.length),
        'failing exact read',
      );
      failed.reply.completeError(_failure);
      await tester.pumpAndSettle();
      expect(_entry(tester).onPressed, isNull);
      expect(find.text(_failure.message), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.attachmentDraft('kept')),
        findsOneWidget,
      );
      expect(env.drafts.start('project').state.value.text, 'keep this draft');
      expect(env.drafts.start('project').state.value.attachments, [attachment]);
      final view = tester.widget<ComposerView>(find.byType(ComposerView));
      expect(
        await pumpClientFuture(
          tester,
          view.onPaste!(),
          'text clipboard fallback',
        ),
        ' pasted text',
      );

      final remove = env.drafts.start('project').removeAttachment('kept');
      final removal = await pumpClientFuture(
        tester,
        env.attachments.removals.at(0),
        'explicit attachment removal',
      );
      removal.reply.complete(true);
      await pumpClientFuture(
        tester,
        remove.result,
        'attachment removal result',
      );
    },
  );

  testWidgets(
    'late route A cannot enable B, and catalog replacement retires the old capability result',
    (tester) async {
      final env = SelectorEnvironment();
      await pumpClientFuture(
        tester,
        env.establish(catalog: false),
        'composer route fixture sources ready',
      );
      await pumpClientFuture(
        tester,
        env.selectThread('thread-main'),
        'composer Thread selected',
      );
      final descriptor = await pumpClientFuture(
        tester,
        env.models.loadModel('account-0', 'text'),
        'declared descriptor',
      );
      final models = _ControlledModels(env.models);
      final container = _container(env, models);
      const target = ComposerKey.thread(threadId: 'thread-main');
      final provider = composerAttachmentViewModelProvider(target);
      final observation = container.listen(provider, (_, _) {});
      addTearDown(() async {
        observation.close();
        container.dispose();
        await pumpClientFuture(tester, env.close(), 'route owners close');
      });
      final a = await pumpClientFuture(
        tester,
        models.calls.at(0),
        'route A capability read',
      );
      expect(a.accountId, 'account-0');
      await pumpClientFuture(
        tester,
        env.conversationPort.publishRoute(
          const ThreadModelRoute(
            botId: null,
            accountId: 'account-1',
            modelId: 'text',
            effort: 'high',
            revision: 9,
            available: true,
            unavailableReason: null,
          ),
        ),
        'route B publication',
      );
      final b = await pumpClientFuture(
        tester,
        models.calls.at(1),
        'route B capability read',
      );
      expect(b.accountId, 'account-1');
      a.reply.complete(
        descriptor.copyWith(
          capabilities: descriptor.capabilities.copyWith(
            input: [_input(ModelModality.file, ModelInputSource.local)],
          ),
        ),
      );
      await tester.pump();
      expect(container.read(provider).requireValue.local, isEmpty);
      expect(
        container
            .read(provider.notifier)
            .allowsLocal(container.read(provider).value),
        isFalse,
      );
      b.reply.complete(
        descriptor.copyWith(
          capabilities: descriptor.capabilities.copyWith(
            input: [_input(ModelModality.image, ModelInputSource.remoteUrl)],
          ),
        ),
      );
      await pumpClientUntil(
        tester,
        () => container.read(provider).value?.remote.isNotEmpty == true,
        'current route B capability',
      );
      expect(container.read(provider).requireValue.local, isEmpty);
      final shownB = container.read(provider).requireValue;
      expect(container.read(provider.notifier).allowsRemote(shownB), isTrue);

      await pumpClientFuture(
        tester,
        env.modelsPort.base.advanceCatalog(),
        'catalog source replacement',
      );
      final c = await pumpClientFuture(
        tester,
        models.calls.at(2),
        'catalog C read',
      );
      expect(container.read(provider).requireValue.remote, isEmpty);
      expect(container.read(provider.notifier).allowsRemote(shownB), isFalse);
      await pumpClientFuture(
        tester,
        env.modelsPort.base.advanceCatalog(),
        'newer catalog source',
      );
      final d = await pumpClientFuture(
        tester,
        models.calls.at(3),
        'catalog D read',
      );
      c.reply.complete(
        descriptor.copyWith(
          capabilities: descriptor.capabilities.copyWith(
            input: [_input(ModelModality.file, ModelInputSource.local)],
          ),
        ),
      );
      await tester.pump();
      expect(
        container
            .read(provider.notifier)
            .allowsLocal(container.read(provider).value),
        isFalse,
      );
      d.reply.completeError(_failure);
      await pumpClientUntil(
        tester,
        () => container.read(provider).value?.error == _failure,
        'current catalog failure',
      );
      expect(
        container
            .read(provider.notifier)
            .allowsRemote(container.read(provider).value),
        isFalse,
      );
      expect(
        env.conversationPort.reads,
        hasLength(2),
        reason: 'Only the existing status reader opens each original configuration once',
      );
    },
  );

  testWidgets(
    'a picker only admits to its original draft while the shown catalog capability is still current',
    (tester) async {
      final fixture = await _attachmentCase(tester);
      const target = ComposerKey.start(projectId: 'project');
      const channel = MethodChannel('io.github.zr233.anywork/file_dialogs');
      for (final replaceCatalog in [false, true]) {
        final entered = Completer<void>();
        final paths = Completer<List<String>>();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) {
            expect(call.method, 'pickFiles');
            entered.complete();
            return paths.future;
          },
        );
        addTearDown(() {
          if (!paths.isCompleted) paths.complete(const []);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });
        final before = fixture.env.drafts.start('project').state.value;
        final admissions = fixture.env.attachments.begins.values.length;
        await tester.tap(_entryFinder());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(StudioDriverKeys.attachmentLocal));
        await pumpClientFuture(
          tester,
          entered.future,
          'original picker waiting',
        );
        if (replaceCatalog) await _replaceCatalog(tester, fixture);
        paths.complete(['/declared/picker.txt']);
        if (!replaceCatalog) {
          final admitted = await _completeAdmission(
            tester,
            fixture.env,
            admissions,
            'picker',
          );
          expect(admitted.sources, const [
            AttachmentDraftSource.localFile('/declared/picker.txt'),
          ]);
        }
        await pumpClientUntil(
          tester,
          () =>
              fixture.container
                  .read(composerViewModelProvider(target))
                  .value
                  ?.platformPending ==
              false,
          'picker callback settled',
        );
        final after = fixture.env.drafts.start('project').state.value;
        expect(after.text, before.text);
        if (replaceCatalog) {
          expect(fixture.env.attachments.begins.values, hasLength(admissions));
          expect(after.attachments, before.attachments);
        } else {
          expect(after.attachments, [
            ...before.attachments,
            _declaredFile('picker'),
          ]);
        }
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'a provider-backed drop rechecks the shown capability after staging and releases the original staging directory',
    (tester) async {
      final fixture = await _attachmentCase(tester);
      final staging = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('composer-drop-test-'),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await staging.exists()) await staging.delete(recursive: true);
        });
      });
      for (final replaceCatalog in [false, true]) {
        final before = fixture.env.drafts.start('project').state.value;
        final admissions = fixture.env.attachments.begins.values.length;
        final drop = tester.widget<DropTarget>(find.byType(DropTarget));
        // Both source barriers and the IO continuation are born in this real
        // zone. Wait only for entered, while release remains test-controlled.
        final transfer = (await tester.runAsync(() async {
          final source = _GatedDropFile('/declared/promised.txt');
          final dropping = IOOverrides.runWithIOOverrides(
            () => Future<void>.sync(
              () => drop.onDrop(
                DropDetails(
                  items: [
                    DropFileItem(
                      file: XFile.fileSystem(path: source.path),
                      name: 'promised.txt',
                    ),
                  ],
                  localPosition: Offset.zero,
                  globalPosition: Offset.zero,
                  operation: DropOperation.copy,
                ),
              ),
            ),
            _DropOverrides(source, staging),
          );
          final event =
              await Future.any<
                ({bool sourceEntered, DraftAdmissionBegin? premature})
              >([
                source.entered.future.then(
                  (_) => (sourceEntered: true, premature: null),
                ),
                dropping.then((_) => (sourceEntered: false, premature: null)),
                fixture.env.attachments.begins
                    .at(admissions)
                    .then((begin) => (sourceEntered: false, premature: begin)),
              ]);
          if (event.premature != null) {
            source.release.complete();
            event.premature!.reply.completeError(
              const RejectedCommandDispatchFailure(failure: _failure),
            );
            await dropping;
            throw StateError('Admission began before the source read gate.');
          }
          if (!event.sourceEntered) {
            const target = ComposerKey.start(projectId: 'project');
            final state = fixture.container
                .read(composerViewModelProvider(target))
                .value;
            throw StateError(
              'Drop ended before its source read: ${state?.platformError}',
            );
          }
          return (source: source, dropping: dropping);
        }))!;
        final source = transfer.source;
        final dropping = transfer.dropping;
        addTearDown(() {
          if (!source.release.isCompleted) source.release.complete();
        });
        await pumpClientFuture(
          tester,
          source.entered.future,
          'original promised file read entered',
        );
        expect(fixture.env.attachments.begins.values, hasLength(admissions));
        expect(
          await tester.runAsync(() => staging.list().isEmpty),
          isFalse,
          reason: 'The production drop helper has already opened its staging destination',
        );
        if (replaceCatalog) await _replaceCatalog(tester, fixture);
        // Cross the remaining OS write/close work, but never wait here for a
        // native result/close reply that the fake-zone test must still supply.
        final boundary = (await tester.runAsync(() async {
          source.release.complete();
          final begin = await Future.any<DraftAdmissionBegin?>([
            fixture.env.attachments.begins.at(admissions),
            dropping.then<DraftAdmissionBegin?>((_) => null),
          ]);
          return (begin: begin);
        }))!;
        if (replaceCatalog && boundary.begin != null) {
          // This path always fails. Reject this unexpected native call solely
          // to release its original owner before reporting the admission bug.
          boundary.begin!.reply.completeError(
            const RejectedCommandDispatchFailure(failure: _failure),
          );
          await tester.runAsync(() => dropping);
          fail('A replaced capability dispatched an unexpected admission.');
        }
        if (!replaceCatalog) {
          expect(
            boundary.begin,
            isNotNull,
            reason: 'The valid original drop must reach its native admission',
          );
          final admitted = await _completeAdmission(
            tester,
            fixture.env,
            admissions,
            'dropped',
          );
          expect(admitted, same(boundary.begin));
          final path =
              (admitted.sources.single as LocalFileAttachmentDraftSource).path;
          expect(path, startsWith(staging.path));
        }
        // Source, native result and native close gates are all fulfilled now.
        // Only the real production cleanup tail remains before assertions.
        await tester.runAsync(() => dropping);
        await pumpClientFuture(
          tester,
          dropping,
          'original drop callback and cleanup',
        );
        expect(await tester.runAsync(() => staging.list().isEmpty), isTrue);
        final after = fixture.env.drafts.start('project').state.value;
        expect(after.text, before.text);
        if (replaceCatalog) {
          expect(fixture.env.attachments.begins.values, hasLength(admissions));
          expect(after.attachments, before.attachments);
        } else {
          expect(after.attachments, [
            ...before.attachments,
            _declaredFile('dropped'),
          ]);
        }
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'URL confirmation uses the original connector validator and never borrows a same-key replacement composer',
    (tester) async {
      final fixture = await _attachmentCase(tester);
      const target = ComposerKey.start(projectId: 'project');
      for (final replacement in ['none', 'catalog', 'composer']) {
        final before = fixture.env.drafts.start('project').state.value;
        final admissions = fixture.env.attachments.begins.values.length;
        await tester.tap(_entryFinder());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(StudioDriverKeys.attachmentUrl));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'https://declared.invalid/original.txt',
        );
        await tester.pump();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        );
        final submit = find.widgetWithText(
          TextButton,
          l10n.composerAddUrlConfirm,
        );
        final originalSubmit = tester.widget<TextButton>(submit).onPressed!;
        if (replacement == 'catalog') {
          await _replaceCatalog(tester, fixture);
        } else if (replacement == 'composer') {
          fixture.container.invalidate(composerViewModelProvider(target));
          await pumpClientFuture(
            tester,
            fixture.container.read(composerViewModelProvider(target).future),
            'same-key replacement composer',
          );
          await tester.pumpAndSettle();
        }
        // Invoke the originally enabled callback as well as observing the now
        // disabled button: admission must reject stale callbacks before D1.
        originalSubmit();
        if (replacement == 'none') {
          final admitted = await _completeAdmission(
            tester,
            fixture.env,
            admissions,
            'url',
          );
          expect(admitted.sources, const [
            AttachmentDraftSource.remoteUrl(
              'https://declared.invalid/original.txt',
            ),
          ]);
        } else {
          await tester.pump();
          expect(tester.widget<TextButton>(submit).onPressed, isNull);
          expect(fixture.env.attachments.begins.values, hasLength(admissions));
          expect(
            fixture.env.drafts.start('project').state.value.attachments,
            before.attachments,
          );
          final input = tester.widget<TextField>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
          );
          expect(
            input.controller!.text,
            'https://declared.invalid/original.txt',
          );
        }
        expect(
          fixture.env.drafts.start('project').state.value.text,
          before.text,
        );
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        await tester.pumpAndSettle();
      }
    },
  );
}

const _failure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The exact model could not be read.',
  retryable: true,
  correlationId: 'composer-capabilities-test',
);

ModelInputCapability _input(ModelModality modality, ModelInputSource source) =>
    ModelInputCapability(
      modality: modality,
      sources: [source],
      maxCount: null,
      maxBytes: null,
      maxTotalBytes: null,
      maxWidth: null,
      maxHeight: null,
      mediaTypes: const [],
    );

DropDetails _drop() => DropDetails(
  items: [DropFileItem.fromPath('/declared/attachment.txt')],
  localPosition: Offset.zero,
  globalPosition: Offset.zero,
  operation: DropOperation.copy,
);

ProviderContainer _container(
  SelectorEnvironment env,
  ModelsRepository models,
) => ProviderContainer(
  retry: (_, _) => null,
  overrides: [
    draftsRepositoryProvider.overrideWithValue(env.drafts),
    conversationRepositoryProvider.overrideWithValue(env.conversations),
    modelsRepositoryProvider.overrideWithValue(models),
    clipboardImageReaderProvider.overrideWithValue(_TextClipboard()),
  ],
);

Widget _harness(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SizedBox(width: 760, child: child)),
        ),
      ),
    );

Finder _entryFinder() => find.descendant(
  of: find.byKey(StudioDriverKeys.attachmentEntry),
  matching: find.byType(IconButton),
);
IconButton _entry(WidgetTester tester) =>
    tester.widget<IconButton>(_entryFinder());

final class _ModelCall {
  _ModelCall(this.accountId, this.modelId);
  final String accountId, modelId;
  final reply = Completer<ModelDescriptor>();
}

/// Only the query result/timing is controlled. The production VM performs all
/// non-text/source selection, invalidation and picker presentation rules.
final class _ControlledModels implements ModelsRepository {
  _ControlledModels(this.base);
  final ModelsRepository base;
  final calls = DraftCalls<_ModelCall>();
  @override
  ReadonlyLatestValue<ModelsState> get state => base.state;
  @override
  Future<ModelDescriptor> loadModel(String accountId, String modelId) {
    final call = _ModelCall(accountId, modelId);
    calls.add(call);
    return call.reply.future;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted capability query: ${invocation.memberName}',
  );
}

final class _TextClipboard implements ClipboardImageReader {
  @override
  Future<Uint8List?> readImage() async => null;
  @override
  Future<String?> readText() async => ' pasted text';
}

typedef _AttachmentCase = ({
  SelectorEnvironment env,
  _ControlledModels models,
  ProviderContainer container,
  ModelDescriptor descriptor,
});

Future<_AttachmentCase> _attachmentCase(WidgetTester tester) async {
  final env = SelectorEnvironment();
  await pumpClientFuture(
    tester,
    env.establish(catalog: false),
    'attachment fixture sources ready',
  );
  await pumpClientFuture(
    tester,
    env.selectStart(),
    'attachment Start route ready',
  );
  final descriptor = await pumpClientFuture(
    tester,
    env.models.loadModel('account-0', 'text'),
    'declared attachment descriptor',
  );
  final models = _ControlledModels(env.models);
  final container = _container(env, models);
  addTearDown(() async {
    if (find.byType(ComposerView).evaluate().isNotEmpty) {
      Navigator.of(tester.element(find.byType(ComposerView)))
          .popUntil((route) => route.isFirst);
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    for (final call in models.calls.values) {
      if (!call.reply.isCompleted) call.reply.completeError(_failure);
    }
    final draft = env.drafts.start('project');
    final attachments = draft.state.value.attachments;
    final offset = env.attachments.removals.values.length;
    final discard = draft.discard();
    for (var index = 0; index < attachments.length; index++) {
      final removal = await pumpClientFuture(
        tester,
        env.attachments.removals.at(offset + index),
        'original draft cleanup',
      );
      removal.reply.complete(true);
    }
    await pumpClientFuture(tester, discard.result, 'draft cleanup result');
    await pumpClientFuture(tester, env.close(), 'attachment case owners close');
  });
  const target = ComposerKey.start(projectId: 'project');
  await tester.pumpWidget(
    _harness(container, const ComposerConnector(target: target)),
  );
  final first = await pumpClientFuture(
    tester,
    models.calls.at(0),
    'initial attachment capabilities',
  );
  first.reply.complete(_attachmentDescriptor(descriptor));
  await tester.pumpAndSettle();
  final draft = env.drafts.start('project');
  draft.setText('preserve the original text');
  final seed = draft.addLocalFiles(['/declared/seed.txt']);
  await _completeAdmission(tester, env, 0, 'seed');
  await pumpClientFuture(tester, seed.result, 'original declared attachment');
  await tester.pumpAndSettle();
  return (
    env: env,
    models: models,
    container: container,
    descriptor: descriptor,
  );
}

ModelDescriptor _attachmentDescriptor(ModelDescriptor descriptor) =>
    descriptor.copyWith(
      capabilities: descriptor.capabilities.copyWith(
        input: [
          _input(ModelModality.file, ModelInputSource.local),
          _input(ModelModality.file, ModelInputSource.remoteUrl),
        ],
      ),
    );

Future<void> _replaceCatalog(
  WidgetTester tester,
  _AttachmentCase fixture,
) async {
  final index = fixture.models.calls.values.length;
  await pumpClientFuture(
    tester,
    fixture.env.modelsPort.base.advanceCatalog(),
    'replace shown catalog',
  );
  final call = await pumpClientFuture(
    tester,
    fixture.models.calls.at(index),
    'replacement exact capabilities',
  );
  call.reply.complete(_attachmentDescriptor(fixture.descriptor));
  await tester.pumpAndSettle();
}

AttachmentMetadata _declaredFile(String id) => AttachmentMetadata(
  id: id,
  modality: AttachmentModality.file,
  mediaType: 'text/plain',
  filename: '$id.txt',
  byteSize: 8,
);

Future<DraftAdmissionBegin> _completeAdmission(
  WidgetTester tester,
  SelectorEnvironment env,
  int index,
  String id,
) async {
  final begin = await pumpClientFuture(
    tester,
    env.attachments.begins.at(index),
    'original attachment admission',
  );
  final job = DraftAdmissionJob(begin.id);
  begin.reply.complete(job);
  final read = await pumpClientFuture(
    tester,
    job.reads.at(0),
    'original attachment result',
  );
  read.complete([_declaredFile(id)]);
  final closing = await pumpClientFuture(
    tester,
    job.closes.at(0),
    'original attachment close',
  );
  closing.reply.complete(
    FeedCloseReport(
      feedId: job.id.value,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
  return begin;
}

/// Only the OS source stream is held. Production staging, its destination IO,
/// connector validation, D1 admission and finally cleanup are not replaced.
final class _GatedDropFile implements File {
  _GatedDropFile(this.path);
  @override
  final String path;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    entered.complete();
    await release.future;
    yield Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted drop source IO: ${invocation.memberName}',
  );
}

final class _DropOverrides extends IOOverrides {
  _DropOverrides(this.source, this.staging);
  final _GatedDropFile source;
  final Directory staging;
  @override
  File createFile(String path) =>
      path == source.path ? source : super.createFile(path);
  @override
  Directory getSystemTempDirectory() => staging;
}
