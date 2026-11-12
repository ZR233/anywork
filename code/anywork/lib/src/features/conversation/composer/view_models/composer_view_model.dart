import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../domain/models/composer_primary_action.dart';
import '../../../../platform/clipboard_image_reader.dart';
import '../../../../platform/dropped_file.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../platform/file_picking.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/mode_catalog_store.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/providers/project_store.dart';
import '../../../../presentation/providers/settings_store.dart';
import '../../timeline/view_models/timeline_view_model.dart';
import '../state/composer_input_state.dart';
import '../state/composer_view_state.dart';
import 'composer_actions.dart';
import 'composer_attachment_intents.dart';
import 'composer_projections.dart';

part 'composer_view_model.g.dart';

/// One target-bound presentation owner, not a second draft or submission owner.
@riverpod
class ComposerViewModel extends _$ComposerViewModel implements ComposerActions {
  int? _queuedStopStartedAtMs;
  int? _expiredStopStartedAtMs;
  final _submissionOperations = <String>{};
  final _submissionFailures = <String, Object>{};
  Object? _actionFailure;

  AnyworkClient get _client => ref.read(anyworkClientProvider);

  @override
  FutureOr<ComposerViewState> build(ComposerTarget target) {
    final projections = ComposerProjections(ref, _queuedStopStartedAtMs);
    final now = DateTime.now().millisecondsSinceEpoch;
    ComposerViewState result;
    switch (target) {
      case ThreadComposerTarget(:final threadId):
        final thread = projections.thread(threadId);
        final route = thread.displayRoute;
        final model = route == null
            ? null
            : ModelRouteQueries.model(
                thread.accounts,
                route.accountId,
                route.modelId,
              );
        final owner = _client.drafts.existingComposer(threadId);
        final submissions = owner == null
            ? const <ComposerSubmission>[]
            : observeClient(
                ref,
                owner.submissions,
                (_) => ref.invalidateSelf(),
              );
        result = ComposerViewState(
          thread: thread,
          submissions: submissions,
          input: ComposerInputState(
            composer: thread.composer,
            enabled:
                owner != null &&
                !thread.executionClosed &&
                thread.row?.isRootRow == true &&
                thread.activeInteraction == null,
            execution: thread.execution,
            continuation: thread.continuation,
            continuationAccepted: thread.continuationAccepted,
            continuationPending: thread.continuationPending,
            blocker: thread.canonicalBlocker,
            failure: thread.operationFailure,
            stopCommand: thread.stopCommand,
            queuedStopStartedAtMs: thread.queuedStopStartedAtMs,
            targetDiagnostic: thread.targetDiagnostic,
            inputCapabilities: model?.inputCapabilities ?? const [],
            nowMs:
                _expiredStopStartedAtMs == thread.stopCommand?.startedAtMs &&
                    _expiredStopStartedAtMs != null
                ? _expiredStopStartedAtMs! +
                      ComposerInputState.stopUnconfirmedAfter.inMilliseconds
                : now,
          ),
        );
      case StartComposerTarget(:final workspaceId):
        final start = projections.start(workspaceId);
        final route = start.displayRoute(start.mode);
        final model = route == null
            ? null
            : ModelRouteQueries.model(
                start.accounts,
                route.accountId,
                route.modelId,
              );
        final submissions =
            observeClient(
              ref,
              _client.drafts.startDraft.submissions,
              (_) => ref.invalidateSelf(),
            )[workspaceId] ??
            const <ComposerSubmission>[];
        final directory = observeClient(
          ref,
          _client.directoryCommands.source,
          (_) => ref.invalidateSelf(),
        );
        result = ComposerViewState(
          start: start,
          submissions: submissions,
          projects:
              ref.watch(projectStoreProvider).projects?.values.toList() ??
              const [],
          delegation: ref.watch(settingsStoreProvider).canonical?.delegation,
          standalonePreparing: directory.standalonePreparationInProgress,
          input: ComposerInputState(
            composer: start.composer,
            draftText: start.draftText,
            enabled: start.canEdit,
            submissionLocked: start.submitting,
            targetDiagnostic: start.targetDiagnostic,
            additionalDiagnostics: [
              for (final item in start.diagnostics)
                if (item != start.targetDiagnostic) item,
            ],
            blocker: start.recoveryIssue == null
                ? null
                : ComposerRecoveryBlocker(start.recoveryIssue!),
            inputCapabilities: model?.inputCapabilities ?? const [],
            nowMs: now,
          ),
        );
    }
    final input = result.input;
    if (input.stopAwaitingReceipt && !input.stopUnconfirmed) {
      final started = input.stopCommand?.startedAtMs ?? 0;
      final remaining =
          started +
          ComposerInputState.stopUnconfirmedAfter.inMilliseconds -
          now;
      if (started != 0 && remaining > 0) {
        final timer = Timer(Duration(milliseconds: remaining), () {
          _expiredStopStartedAtMs = started;
          ref.invalidateSelf();
        });
        ref.onDispose(timer.cancel);
      }
    }
    return result.copyWith(
      modeCatalog:
          ref.watch(modeCatalogStoreProvider).value ??
          const ThreadModeCatalogView(),
      submissionOperations: Set.unmodifiable(_submissionOperations),
      submissionFailures: Map.unmodifiable(_submissionFailures),
      actionFailure: _actionFailure,
    );
  }

  ComposerViewState? get _current => ref.mounted ? state.value : null;

  Future<void> _run(
    Future<void> Function() action, {
    // Stop/continue failures are already owned and rendered by the command
    // board. Only boundary/platform failures need the local action error row.
    bool ownerReportsFailure = false,
  }) {
    if (!ref.mounted) return Future<void>.value();
    _actionFailure = null;
    // Call synchronously: Client must freeze/clear before the first await.
    try {
      final work = action();
      return work.catchError((Object error) {
        if (!ref.mounted) return;
        if (!ownerReportsFailure) {
          _actionFailure = error;
          ref.invalidateSelf();
        }
      });
    } catch (error) {
      if (!ownerReportsFailure) {
        _actionFailure = error;
        ref.invalidateSelf();
      }
      return Future<void>.value();
    }
  }

  @override
  void updateText(String text) {
    if (_current?.input.enabled != true) return;
    switch (target) {
      case ThreadComposerTarget(:final threadId):
        _client.drafts.existingComposer(threadId)?.updateDraft(text);
      case StartComposerTarget(:final workspaceId):
        _client.drafts.startDraft.updateDraft(workspaceId, text);
    }
  }

  @override
  void submit() {
    final current = _current;
    if (current == null ||
        !current.input.enabled ||
        !current.input.action.enterSubmits) {
      return;
    }
    switch (target) {
      case ThreadComposerTarget(:final threadId):
        final timeline = ref.read(timelineSessionOwnerProvider);
        final lease = timeline.lease(threadId);
        final owner = _client.drafts.existingComposer(threadId);
        if (owner == null) return;
        _run(() {
          // Hand off the input before publishing any local display intent.
          final submission = owner.submit();
          if (lease != null) {
            timeline.prepareComposerSubmissionDisplay(threadId, lease: lease);
          }
          return submission;
        });
      case StartComposerTarget(:final workspaceId):
        final owner = _client.drafts.startDraft;
        _run(() async {
          await owner.submit(workspaceId);
        });
    }
  }

  @override
  void stop(String expectedExecutionId) {
    final current = _current?.thread;
    if (target case ThreadComposerTarget(:final threadId)) {
      final commands = _client.threadCommands;
      final previous = current?.stopCommand?.startedAtMs;
      _run(() async {
        final outcome = await commands.stop(
          threadId,
          expectedExecutionId: expectedExecutionId,
        );
        if (!ref.mounted) return;
        _queuedStopStartedAtMs = outcome is StopQueued ? previous : null;
        ref.invalidateSelf();
      }, ownerReportsFailure: true);
    }
  }

  @override
  void continueConversation() {
    final thread = _current?.thread;
    if (target case ThreadComposerTarget(:final threadId)) {
      final continuation = thread?.continuation;
      final revision = thread?.modelRoute?.revision;
      if (continuation == null || revision == null) return;
      final commands = _client.threadCommands;
      _run(() async {
        await commands.continueThread(
          threadId,
          continuation,
          expectedModelRouteRevision: revision,
        );
      }, ownerReportsFailure: true);
    }
  }

  void setMode(ThreadModeId mode) {
    switch (target) {
      case ThreadComposerTarget(:final threadId):
        final commands = _client.threadCommands;
        _run(() => commands.setThreadMode(mode, threadId: threadId));
      case StartComposerTarget(:final workspaceId):
        _client.drafts.startDraft.setMode(workspaceId, mode);
    }
  }

  void setModel(String accountId, String modelId) {
    final current = _current;
    if (current == null) return;
    switch (target) {
      case ThreadComposerTarget(:final threadId):
        final thread = current.thread!;
        final effort = ModelRouteQueries.effortAfterModelSelection(
          ModelRouteQueries.model(thread.accounts, accountId, modelId),
          thread.displayRoute?.effort,
        );
        final commands = _client.threadCommands;
        _run(
          () => commands.setThreadModelRoute(
            threadId: threadId,
            accountId: accountId,
            modelId: modelId,
            effort: effort,
          ),
        );
      case StartComposerTarget():
        _client.drafts.startDraft.setModelIntent(
          current.start!.mode,
          accountId,
          modelId,
        );
    }
  }

  void setEffort(String effort) {
    final current = _current;
    if (current == null) return;
    switch (target) {
      case ThreadComposerTarget(:final threadId):
        final route = current.thread?.displayRoute;
        if (route == null) return;
        final commands = _client.threadCommands;
        _run(
          () => commands.setThreadModelRoute(
            threadId: threadId,
            accountId: route.accountId,
            modelId: route.modelId,
            effort: effort,
          ),
        );
      case StartComposerTarget():
        _client.drafts.startDraft.setEffortIntent(current.start!.mode, effort);
    }
  }

  void setWorkspaceMode(ThreadWorkspaceMode mode) {
    if (target case StartComposerTarget(:final workspaceId)) {
      _client.drafts.startDraft.setWorkspaceMode(workspaceId, mode);
    }
  }

  bool isSafeExternalLink(String raw) => safeExternalWebUrl(raw) != null;

  void openExternalLink(String raw) {
    if (!ref.mounted) return;
    final url = safeExternalWebUrl(raw);
    if (url == null) return;
    final launch = ref.read(externalUrlLauncherProvider);
    _run(() => launch(url));
  }

  void setDelegationMode(DelegationMode? mode) {
    if (target case StartComposerTarget(:final workspaceId)) {
      _client.drafts.startDraft.setDelegationModeOverride(workspaceId, mode);
    }
  }

  void setDelegationPreference(DelegationPreference? preference) {
    if (target case StartComposerTarget(:final workspaceId)) {
      _client.drafts.startDraft.setDelegationPreferenceOverride(
        workspaceId,
        preference,
      );
    }
  }

  void selectProject(StudioProject? project) {
    final commands = _client.directoryCommands;
    _run(
      () => project == null || project.isStandalone
          ? commands.beginStandaloneThread()
          : commands.beginNewThread(workspaceId: project.id),
    );
  }

  void refresh() {
    if (target case ThreadComposerTarget(:final threadId)) {
      _client.conversations.session(threadId).refresh();
    }
  }

  ComposerAttachmentIntents get _attachments => ComposerAttachmentIntents(
    target: target,
    client: _client,
    clipboard: ref.read(clipboardImageReaderProvider),
    pickPaths: ref.read(attachmentPathPickerProvider),
    input: () => _current?.input,
    mode: _current?.start?.mode,
  );
  @override
  void removeAttachment(String draftId) =>
      _run(() => _attachments.remove(draftId));
  @override
  void addUrl(String url) => _run(() => _attachments.addUrl(url));
  @override
  void pickAttachments(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  ) {
    final intents = _attachments;
    _run(() => intents.pick(capabilities, isCurrent));
  }

  @override
  Future<void> dropAttachments(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  ) {
    final intents = _attachments;
    return _run(() => intents.drop(files, isCurrent));
  }

  @override
  void paste(ComposerTextPaste textPaste) {
    final intents = _attachments;
    _run(() => intents.paste(textPaste));
  }

  void retrySubmission(String inputId) =>
      _submissionAction(inputId, retry: true);
  void removeSubmission(String inputId) =>
      _submissionAction(inputId, retry: false);

  void _submissionAction(String inputId, {required bool retry}) {
    if (!ref.mounted || !_submissionOperations.add(inputId)) return;
    final client = _client;
    _submissionFailures.remove(inputId);
    Future<void> perform() async {
      try {
        switch (target) {
          case ThreadComposerTarget(:final threadId):
            final owner = client.drafts.existingComposer(threadId);
            if (owner == null) {
              throw StateError('Composer draft is unavailable');
            }
            if (retry) {
              await owner.retrySubmission(inputId);
            } else {
              await owner.removeSubmission(inputId);
            }
          case StartComposerTarget(:final workspaceId):
            if (retry) {
              await client.drafts.startDraft.retrySubmission(
                workspaceId,
                inputId,
              );
            } else {
              await client.drafts.startDraft.removeSubmission(
                workspaceId,
                inputId,
              );
            }
        }
      } catch (error) {
        if (ref.mounted) _submissionFailures[inputId] = error;
      } finally {
        _submissionOperations.remove(inputId);
        if (ref.mounted) ref.invalidateSelf();
      }
    }

    // Register UI operation before notifying any synchronous observer.
    unawaited(perform());
    ref.invalidateSelf();
  }
}
