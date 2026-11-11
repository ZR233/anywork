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
  String? _submittingId;
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
    if (active == null) {
      _submittingId = null;
      _errorMessage = null;
      return const AcpPermissionDockViewState();
    }
    final activeKey = _permissionIdKey(active.id);
    if (_submittingId != null && _submittingId != activeKey) {
      _submittingId = null;
      _errorMessage = null;
    }
    return AcpPermissionDockViewState(
      pendingCount: permissions.length,
      activeRequest: _mapPermissionRequest(
        active,
        submitting: _submittingId == activeKey,
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
    if (_submittingId == permissionId) return;
    final currentState = ref
        .read(acpConversationStateProvider(threadId))
        .asData
        ?.value;
    final target = currentState?.pendingPermissions
        .where((item) => _permissionIdKey(item.id) == permissionId)
        .firstOrNull;
    if (target == null) return;

    _submittingId = permissionId;
    _errorMessage = null;
    ref.invalidateSelf();

    final client = ref.read(acpConversationOwnerProvider(threadId)).asData;
    final owner = client?.value;
    if (owner == null) {
      _submittingId = null;
      _errorMessage = 'ACP 会话尚未打开';
      if (ref.mounted) ref.invalidateSelf();
      return;
    }
    try {
      await owner.answerPermission(target.id, option);
      if (!ref.mounted) return;
      _submittingId = null;
      _errorMessage = null;
      ref.invalidateSelf();
    } catch (error) {
      if (!ref.mounted) return;
      _submittingId = null;
      _errorMessage = formatAcpError(error);
      ref.invalidateSelf();
    }
  }
}
