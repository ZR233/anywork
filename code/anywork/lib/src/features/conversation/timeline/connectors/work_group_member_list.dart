import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/timeline_current_projection.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_models.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/display_member_controller.dart';
import 'timeline_member_atom.dart';

/// 历史工作组与实时状态栏开放工作组共用的成员列表连接器视图。
///
/// 统一处理成员控制器的加载进度条、失败重试、封存占位文案，以及尚未落入分页切片的
/// 实时 `CurrentAtom` 追加项去重叠加。
class WorkGroupMemberList extends StatelessWidget {
  const WorkGroupMemberList({
    required this.controller,
    required this.blockReference,
    required this.executionPresent,
    required this.threadId,
    required this.currentReader,
    required this.retirement,
    required this.isActive,
    required this.images,
    this.readAttachment,
    this.monotonicMicros,
    this.onContentLayout,
    this.onCurrentContentLayout,
    this.onCurrentContentUnmounted,
    this.registerMemberDisplay,
    this.extraLiveAtoms = const [],
    this.hideSealedCurrentPlaceholders = false,
    super.key,
  });

  final DisplayMemberController? controller;
  final DisplayBlockRef? blockReference;
  final bool executionPresent;
  final String threadId;
  final CurrentReader? currentReader;
  final ValueListenable<bool> retirement;
  final bool Function() isActive;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String)? readAttachment;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  final void Function(String, int)? onCurrentContentLayout;
  final void Function(String)? onCurrentContentUnmounted;
  final VoidCallback Function(TimelineMemberDisplay)? registerMemberDisplay;
  final List<CurrentAtom> extraLiveAtoms;
  final bool hideSealedCurrentPlaceholders;

  @override
  Widget build(BuildContext context) {
    final activeController = controller;
    if (activeController == null) {
      if (extraLiveAtoms.isNotEmpty) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final atom in extraLiveAtoms) _buildExtraAtom(atom)],
        );
      }
      return Text(context.l10n.liveStatusMembersUnavailable);
    }

    return ListenableBuilder(
      listenable: activeController,
      builder: (context, _) {
        final l10n = context.l10n;
        final extraAtoms = _unrepresentedLiveAtoms(activeController);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeController.error case final error?)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error.toString()),
                  TextButton(
                    onPressed: activeController.retry,
                    child: Text(l10n.liveStatusRetryAction),
                  ),
                ],
              ),
            if (activeController.loading) const LinearProgressIndicator(),
            for (final entry in activeController.entries)
              ValueListenableBuilder<DisplayMemberHead?>(
                key: ValueKey(entry.memberKey),
                valueListenable: activeController.member(entry.memberKey),
                builder: (context, value, _) {
                  if (value == null) return const SizedBox.shrink();
                  if (hideSealedCurrentPlaceholders &&
                      activeController.awaitingSealed &&
                      value.record.contentSource is CurrentAtomSource) {
                    return Text(l10n.liveStatusMembersLoading);
                  }
                  return TimelineMemberAtom(
                    key: ValueKey((
                      blockReference ?? activeController.reference,
                      entry.memberKey,
                      activeController.disclosure(entry.memberKey),
                    )),
                    record: value.record,
                    displayId: entry.memberKey,
                    disclosure: activeController.disclosure(entry.memberKey),
                    executionPresent: executionPresent,
                    threadId: threadId,
                    currentReader: currentReader,
                    retirement: retirement,
                    isActive: isActive,
                    images: images,
                    readAttachment: readAttachment,
                    monotonicMicros: monotonicMicros,
                    onContentLayout: onContentLayout,
                    onCurrentContentLayout: onCurrentContentLayout,
                    onCurrentContentUnmounted: onCurrentContentUnmounted,
                    registerDisplay: registerMemberDisplay,
                  );
                },
              ),
            for (final atom in extraAtoms) _buildExtraAtom(atom),
          ],
        );
      },
    );
  }

  List<CurrentAtom> _unrepresentedLiveAtoms(
    DisplayMemberController activeController,
  ) {
    if (extraLiveAtoms.isEmpty) return const [];
    final representedIds = <String>{};
    final representedCallIds = <String>{};
    for (final entry in activeController.entries) {
      representedIds.add(entry.record.atom.id);
      final callId = entry.record.callId ?? entry.record.atom.tool?.callId;
      if (callId != null) representedCallIds.add(callId);
    }
    return [
      for (final atom in extraLiveAtoms)
        if (!representedIds.contains(atom.id) &&
            (atom.tool?.callId == null ||
                !representedCallIds.contains(atom.tool!.callId)))
          atom,
    ];
  }

  Widget _buildExtraAtom(CurrentAtom atom) => TimelineMemberAtom(
    key: ValueKey(('live-atom', atom.id)),
    record: DisplayRecord(
      atom: TimelineCurrentProjection.toChatAtom(atom),
      contentSource: const CurrentAtomSource(),
      currentContents: atom.contents,
    ),
    displayId: atom.id,
    threadId: threadId,
    currentReader: currentReader,
    retirement: retirement,
    isActive: isActive,
    images: images,
    readAttachment: readAttachment,
    executionPresent: true,
    monotonicMicros: monotonicMicros,
    onCurrentContentLayout: onCurrentContentLayout,
    onCurrentContentUnmounted: onCurrentContentUnmounted,
  );
}
