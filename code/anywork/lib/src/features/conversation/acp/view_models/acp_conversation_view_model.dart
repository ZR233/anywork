import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';

/// Admits through the application's exact directory identity. Re-entering a
/// page borrows the existing Client owner; Ref never closes business membership.
final acpConversationOwnerProvider = FutureProvider.autoDispose
    .family<AcpConversationSession, String>((ref, threadId) {
      final client = ref.watch(anyworkClientProvider);
      final existing = client.acpSessions.conversationForThread(threadId);
      return existing == null
          ? client.openAcpConversation(threadId)
          : Future.value(existing);
    });

final acpConversationViewModelProvider = Provider.autoDispose
    .family<AsyncValue<AcpConversationState>, String>((ref, threadId) {
      final owner = ref.watch(acpConversationOwnerProvider(threadId));
      return owner.whenData(
        (owner) =>
            observeClient(ref, owner.source, (_) => ref.invalidateSelf()),
      );
    });

final acpContentCountProvider = Provider.autoDispose.family<int, String>(
  (ref, threadId) => ref.watch(
    acpConversationViewModelProvider(threadId)
        .select((state) => state.value?.content.length ?? 0),
  ),
);

final acpContentItemProvider = Provider.autoDispose
    .family<AcpConversationContentItem?, (String, int)>((ref, identity) {
      final (threadId, index) = identity;
      return ref.watch(
        acpConversationViewModelProvider(threadId).select((state) {
          final content = state.value?.content;
          return content != null && index < content.length
              ? content[index]
              : null;
        }),
      );
    });

final acpPlanProvider = Provider.autoDispose.family<AcpPlanView?, String>(
  (ref, threadId) => ref.watch(
    acpConversationViewModelProvider(threadId)
        .select((state) => state.value?.plan),
  ),
);

final acpPermissionsProvider = Provider.autoDispose
    .family<List<AcpPermissionEventView>, String>(
      (ref, threadId) => ref.watch(
        acpConversationViewModelProvider(threadId)
            .select((state) => state.value?.pendingPermissions ?? const []),
      ),
    );

typedef AcpConfigurationState = ({
  List<AcpSessionConfigOptionView>? options,
  AcpSessionModeStateView? modes,
  bool pending,
  bool enabled,
  Object? error,
});

final acpConfigurationViewModelProvider = Provider.autoDispose
    .family<AcpConfigurationState, String>(
      (ref, threadId) => ref.watch(
        acpConversationViewModelProvider(threadId).select((value) {
          final state = value.value;
          return (
            options: state?.configOptions,
            modes: state?.modes,
            pending: state?.configPending ?? false,
            enabled:
                state != null &&
                state.ready &&
                !state.openPending &&
                !state.disconnected &&
                !state.observationEnded,
            error: state?.configError,
          );
        }),
      ),
    );

typedef AcpComposerReadiness = ({
  bool canSend,
  bool active,
  bool canAttach,
  String? reason,
});

AcpComposerReadiness acpComposerReadiness(AcpConversationState? state) {
  final reason = switch (state) {
    null => '正在打开 ACP 会话',
    AcpConversationState(disconnected: true) => 'ACP 连接已断开',
    AcpConversationState(observationEnded: true) => 'ACP 观察已结束',
    AcpConversationState(openPending: true) => '正在初始化 ACP 会话',
    AcpConversationState(ready: false) => 'ACP 会话尚未就绪',
    AcpConversationState(configPending: true) => '正在应用配置',
    AcpConversationState(configError: final error?) => '配置失败：$error',
    AcpConversationState(sendPending: true) => '正在发送',
    AcpConversationState(activeRun: final run?) => '运行 ${run.sequence} 进行中',
    _ => null,
  };
  final capabilities = state?.capabilities;
  return (
    canSend: reason == null,
    active: state?.activeRun != null,
    canAttach:
        state?.ready == true &&
        state?.disconnected == false &&
        (capabilities?.image == true || capabilities?.embeddedContext == true),
    reason: reason,
  );
}

final acpComposerReadinessProvider = Provider.autoDispose
    .family<AcpComposerReadiness, String>(
      (ref, threadId) => ref.watch(
        acpConversationViewModelProvider(threadId)
            .select((state) => acpComposerReadiness(state.value)),
      ),
    );

final acpDraftViewModelProvider = Provider.autoDispose
    .family<ComposerThreadState, String>((ref, threadId) {
      final owner = ref.watch(anyworkClientProvider).drafts.composer(threadId);
      return observeClient(ref, owner.source, (_) => ref.invalidateSelf());
    });

final acpConversationActionsProvider = Provider.autoDispose
    .family<AcpConversationActions, String>(
      (ref, threadId) =>
          AcpConversationActions(ref.watch(anyworkClientProvider), threadId),
    );

final class AcpConversationActions {
  AcpConversationActions(this.client, this.threadId);

  final AnyworkClient client;
  final String threadId;

  ComposerDraftOwner get draft => client.drafts.composer(threadId);

  AcpConversationSession get owner =>
      client.acpSessions.conversationForThread(threadId) ??
      (throw StateError('ACP 会话尚未打开'));

  void updateDraft(String text) => draft.updateDraft(text);
  void reportFailure(Object error) => draft.reportFailure(error);

  Future<void> submit() => _coordinate(() => draft.submit());

  Future<void> configure(AcpConfigId id, AcpSessionConfigValueView value) =>
      _coordinate(() => owner.configure(id, value));
  Future<void> setMode(AcpModeId mode) =>
      _coordinate(() => owner.setMode(mode));
  Future<void> interrupt() => _coordinate(() => owner.interrupt());
  Future<void> answerPermission(
    AcpPermissionIdView permission,
    AcpPermissionOptionId? option,
  ) => _coordinate(() => owner.answerPermission(permission, option));

  Future<void> pickLocalAttachments(
    Future<List<String>> Function() choosePaths,
  ) {
    // The asynchronous picker stays bound to this thread's original draft.
    final original = draft;
    return _coordinate(() async {
      final paths = await choosePaths();
      if (paths.isNotEmpty) await original.addLocalAttachments(paths);
    });
  }

  Future<void> addRemoteAttachment(String url) =>
      _coordinate(() => draft.addRemoteAttachment(url));
  Future<void> removeAttachment(String id) =>
      _coordinate(() => draft.removeAttachment(id));

  Future<void> _coordinate(Future<void> Function() operation) async {
    final original = draft;
    try {
      await operation();
    } catch (error) {
      original.reportFailure(error);
    }
  }
}

/// Adjacent text chunks form one Markdown document without retaining a second
/// mutable message list or changing the original Client chunks.
List<AcpContentBlockView> acpMessageBlocks(AcpConversationMessageItem item) {
  final blocks = <AcpContentBlockView>[];
  var text = StringBuffer();
  void flush() {
    if (text.isEmpty) return;
    blocks.add(AcpTextContentView(text: text.toString()));
    text = StringBuffer();
  }

  for (final chunk in item.chunks) {
    if (chunk.content case AcpTextContentView(text: final value)) {
      text.write(value);
    } else {
      flush();
      blocks.add(chunk.content);
    }
  }
  flush();
  return blocks;
}

typedef AcpStatusState = ({
  bool loading,
  bool ready,
  bool disconnected,
  bool ended,
  AcpConversationHistory? history,
  AcpObservationGapView? gap,
  Object? error,
  AcpRunIdView? run,
  AcpCompletedRunView? completed,
});

final acpStatusViewModelProvider = Provider.autoDispose
    .family<AcpStatusState, String>(
      (ref, threadId) => ref.watch(
        acpConversationViewModelProvider(threadId).select((value) {
          final state = value.value;
          return (
            loading: value.isLoading || state?.openPending == true,
            ready: state?.ready ?? false,
            disconnected: state?.disconnected ?? false,
            ended: state?.observationEnded ?? false,
            history: state?.history,
            gap: state?.observationGap,
            error: value.error ?? state?.error,
            run: state?.activeRun,
            completed: state?.lastCompleted,
          );
        }),
      ),
    );

String acpUpdateSummary(AcpSessionUpdateView update) => switch (update) {
  AcpNoticeView(:final title, :final description) =>
    '$title${description == null ? '' : '\n$description'}',
  AcpUsageUpdateView(:final used, :final size, :final cost) =>
    '上下文 $used / $size${cost == null ? '' : ' · ${cost.amount} ${cost.currency}'}',
  AcpCompactionUpdateView(:final status, :final error) =>
    '上下文压缩 · ${status.other ?? status.kind.name}${error is AcpFieldValue<String> ? '\n${error.value}' : ''}',
  AcpAvailableCommandsUpdateView(:final commands) =>
    commands
        .map((command) => '/${command.name} · ${command.description}')
        .join('\n'),
  AcpSessionInfoUpdateView() => '会话信息已更新',
  _ => 'ACP 会话状态已更新',
};
