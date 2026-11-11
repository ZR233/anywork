import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../state/acp_view_state.dart';
import 'acp_session_view_model.dart';

part 'acp_composer_view_model.g.dart';

AcpComposerBlocker? _computeBlocker({
  required bool hasState,
  required bool disconnected,
  required bool observationEnded,
  required bool openPending,
  required bool ready,
  required bool configPending,
  required Object? configError,
  required bool sendPending,
  required bool isRunning,
}) {
  if (!hasState) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.opening);
  }
  if (disconnected) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.disconnected);
  }
  if (observationEnded) {
    return const AcpComposerBlocker(
      kind: AcpComposerBlockerKind.observationEnded,
    );
  }
  if (openPending) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.initializing);
  }
  if (!ready) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.notReady);
  }
  if (configPending) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.configPending);
  }
  if (configError != null) {
    return AcpComposerBlocker(
      kind: AcpComposerBlockerKind.configError,
      detail: formatAcpError(configError),
    );
  }
  if (sendPending) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.sending);
  }
  if (isRunning) {
    return const AcpComposerBlocker(kind: AcpComposerBlockerKind.running);
  }
  return null;
}

@riverpod
class AcpComposerViewModel extends _$AcpComposerViewModel {
  @override
  AcpComposerViewState build(String threadId) {
    final client = ref.watch(anyworkClientProvider);
    final draftOwner = client.drafts.composer(threadId);
    final draft = observeClient(
      ref,
      draftOwner.source,
      (_) => ref.invalidateSelf(),
    );
    final asyncState = ref.watch(acpConversationStateProvider(threadId));
    final state = asyncState.value;
    final caps = state?.capabilities;
    final session = (
      hasState: state != null,
      disconnected: state?.disconnected ?? false,
      observationEnded: state?.observationEnded ?? false,
      openPending: state?.openPending ?? false,
      ready: state?.ready ?? false,
      configPending: state?.configPending ?? false,
      configError: state?.configError,
      sendPending: state?.sendPending ?? false,
      isRunning: state?.activeRun != null,
      imageCap: caps?.image ?? false,
      embeddedCap: caps?.embeddedContext ?? false,
    );

    final blocker = _computeBlocker(
      hasState: session.hasState,
      disconnected: session.disconnected,
      observationEnded: session.observationEnded,
      openPending: session.openPending,
      ready: session.ready,
      configPending: session.configPending,
      configError: session.configError,
      sendPending: session.sendPending,
      isRunning: session.isRunning,
    );
    final canAttach =
        session.ready &&
        !session.disconnected &&
        !session.observationEnded &&
        (session.imageCap || session.embeddedCap);

    final localCapabilities = <ModelInputCapabilityView>[
      if (canAttach && session.imageCap)
        const ModelInputCapabilityView(
          modality: ModelModalityView.image,
          sources: [ModelInputSourceView.local],
        ),
      if (canAttach && session.embeddedCap)
        const ModelInputCapabilityView(
          modality: ModelModalityView.file,
          sources: [ModelInputSourceView.local],
        ),
    ];
    final remoteCapabilities = <ModelInputCapabilityView>[
      if (canAttach && session.embeddedCap)
        const ModelInputCapabilityView(
          modality: ModelModalityView.file,
          sources: [ModelInputSourceView.remoteUrl],
        ),
    ];

    return AcpComposerViewState(
      threadId: threadId,
      draftText: draft.draft,
      attachments: draft.attachments,
      localCapabilities: localCapabilities,
      remoteCapabilities: remoteCapabilities,
      supportsImagePaste: canAttach && session.imageCap,
      canSend: blocker == null && !draft.isSubmissionPending,
      isRunning: session.isRunning,
      canInterrupt:
          session.isRunning &&
          !session.disconnected &&
          !session.observationEnded,
      canAttach: canAttach && !draft.isSubmissionPending,
      submitting: draft.isSubmissionPending,
      blocker: blocker,
      draftError: draft.error,
    );
  }

  void updateDraft(String text) {
    ref.read(anyworkClientProvider).drafts.composer(threadId).updateDraft(text);
  }

  void reportFailure(Object error) {
    ref
        .read(anyworkClientProvider)
        .drafts
        .composer(threadId)
        .reportFailure(error);
  }

  Future<void> submit() async {
    final draft = ref.read(anyworkClientProvider).drafts.composer(threadId);
    try {
      await draft.submit();
    } catch (error) {
      draft.reportFailure(error);
    }
  }

  Future<void> interrupt() => coordinateAcpSessionCommand(
    ref.read(anyworkClientProvider),
    threadId,
    (owner) => owner.interrupt(),
  );

  Future<void> pickLocalAttachments(
    Future<List<String>> Function() choosePaths,
  ) async {
    // Bind to the originating thread's draft owner synchronously before
    // awaiting the picker so later thread switches cannot misattribute files
    // or failures.
    final original = ref.read(anyworkClientProvider).drafts.composer(threadId);
    try {
      final paths = await choosePaths();
      if (paths.isNotEmpty) {
        await original.addLocalAttachments(paths);
      }
    } catch (error) {
      original.reportFailure(error);
    }
  }

  Future<void> addLocalAttachments(List<String> paths) async {
    if (paths.isEmpty) return;
    final original = ref.read(anyworkClientProvider).drafts.composer(threadId);
    try {
      await original.addLocalAttachments(paths);
    } catch (error) {
      original.reportFailure(error);
    }
  }

  Future<void> addRemoteAttachment(String url) async {
    final original = ref.read(anyworkClientProvider).drafts.composer(threadId);
    try {
      await original.addRemoteAttachment(url);
    } catch (error) {
      original.reportFailure(error);
    }
  }

  Future<void> removeAttachment(String draftId) async {
    final original = ref.read(anyworkClientProvider).drafts.composer(threadId);
    try {
      await original.removeAttachment(draftId);
    } catch (error) {
      original.reportFailure(error);
    }
  }

  Future<void> pasteImage(Uint8List pngBytes) async {
    final original = ref.read(anyworkClientProvider).drafts.composer(threadId);
    try {
      await original.addClipboardImage(pngBytes);
    } catch (error) {
      original.reportFailure(error);
    }
  }
}
