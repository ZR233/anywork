import 'package:anywork_client/acp_sessions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../timeline/state/patch_presentation.dart';
import '../state/acp_view_state.dart';
import 'acp_content_view_model.dart';
import 'acp_session_view_model.dart';

part 'acp_permission_view_model.g.dart';

String _permissionIdKey(AcpPermissionIdView id) =>
    '${id.instance}:${id.sequence}';

AcpPermissionOptionTone _mapOptionTone(
  AcpPermissionOptionKindView kind,
) => switch (kind) {
  AcpPermissionOptionKindView.allowAlways =>
    AcpPermissionOptionTone.allowAlways,
  AcpPermissionOptionKindView.allowOnce => AcpPermissionOptionTone.allowOnce,
  AcpPermissionOptionKindView.rejectOnce => AcpPermissionOptionTone.rejectOnce,
  AcpPermissionOptionKindView.rejectAlways =>
    AcpPermissionOptionTone.rejectAlways,
};

AcpPermissionRequestPresentation _mapPermissionRequest(
  AcpPermissionEventView event, {
  required bool submitting,
}) {
  final idKey = _permissionIdKey(event.id);
  final toolCall = event.request.toolCall;
  final fields = toolCall.fields;
  final title = (fields.title != null && fields.title!.trim().isNotEmpty)
      ? fields.title!
      : (fields.name != null && fields.name!.trim().isNotEmpty)
      ? fields.name!
      : toolCall.toolCallId.value;
  final locations = <String>[
    for (final loc in fields.locations ?? const <AcpToolCallLocationView>[])
      '${loc.path}${loc.line == null ? '' : ':${loc.line}'}',
  ];
  final diffs = <TimelinePatchDocument>[
    for (final item in fields.content ?? const <AcpToolCallContentView>[])
      if (item case final AcpToolDiffView diff) mapAcpDiffPresentation(diff),
  ];
  final rawInput = formatAcpJsonText(fields.rawInput).trim();
  return AcpPermissionRequestPresentation(
    id: idKey,
    title: title,
    kindLabel: fields.kind?.name,
    locations: locations,
    argumentsPreview: rawInput.isEmpty ? null : rawInput,
    diffs: diffs,
    options: [
      for (final option in event.request.options)
        AcpPermissionOptionPresentation(
          optionId: option.optionId.value,
          name: option.name,
          tone: _mapOptionTone(option.kind),
        ),
    ],
    submitting: submitting,
  );
}

@riverpod
class AcpPermissionViewModel extends _$AcpPermissionViewModel {
  AcpPermissionEventView? _activeRequest;
  Object? _decision;
  String? _errorMessage;

  @override
  AcpPermissionDockViewState build(String threadId) {
    final permissions =
        ref
            .watch(acpConversationStateProvider(threadId))
            .value
            ?.pendingPermissions ??
        const <AcpPermissionEventView>[];
    final active = permissions.firstOrNull;
    if (!identical(active, _activeRequest)) {
      _activeRequest = active;
      _decision = null;
      _errorMessage = null;
    }
    if (active == null) {
      return const AcpPermissionDockViewState();
    }
    return AcpPermissionDockViewState(
      pendingCount: permissions.length,
      activeRequest: _mapPermissionRequest(
        active,
        submitting: _decision != null,
      ),
      errorMessage: _errorMessage,
    );
  }

  Future<void> answer(String permissionId, String optionId) =>
      _decide(permissionId, AcpPermissionOptionId(optionId));

  Future<void> cancel(String permissionId) => _decide(permissionId, null);

  Future<void> _decide(
    String permissionId,
    AcpPermissionOptionId? option,
  ) async {
    if (!ref.mounted) return;
    final currentState = ref
        .read(acpConversationStateProvider(threadId))
        .asData
        ?.value;
    final target = currentState?.pendingPermissions.firstOrNull;
    if (target == null || _permissionIdKey(target.id) != permissionId) return;
    if (identical(target, _activeRequest) && _decision != null) return;

    final owner = ref
        .read(acpConversationOwnerProvider(threadId))
        .asData
        ?.value;
    final decision = Object();
    _activeRequest = target;
    _decision = decision;
    _errorMessage = null;
    ref.invalidateSelf();

    void finish(String? error) {
      if (!ref.mounted || !identical(_decision, decision)) return;
      final currentOwner = ref
          .read(acpConversationOwnerProvider(threadId))
          .asData
          ?.value;
      if (!identical(currentOwner, owner)) return;
      final currentRequest = owner != null
          ? owner.state.pendingPermissions.firstOrNull
          : ref
                .read(acpConversationStateProvider(threadId))
                .asData
                ?.value
                .pendingPermissions
                .firstOrNull;
      // An old boundary reply still settles its Future, but only the current
      // request's current action may change this dock's pending/error state.
      if (!identical(currentRequest, target)) return;
      _decision = null;
      _errorMessage = error;
      ref.invalidateSelf();
    }

    if (owner == null) {
      finish('ACP 会话尚未打开');
      return;
    }
    try {
      await owner.answerPermission(target.id, option);
      finish(null);
    } catch (error) {
      finish(formatAcpError(error));
    }
  }
}
