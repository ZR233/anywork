import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_models.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/display_member_controller.dart';
import 'timeline_member_atom.dart';

/// 历史工作组与实时状态栏开放工作组共用的成员列表连接器视图。
///
/// 统一处理加载进度、读取失败重试和封存占位文案，成员由各自的监听入口刷新。
class WorkGroupMemberList extends StatelessWidget {
  const WorkGroupMemberList({
    required this.controller,
    required this.showLoadingIndicator,
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
    this.hideSealedCurrentPlaceholders = false,
    super.key,
  });

  final DisplayMemberController? controller;
  final bool showLoadingIndicator;
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
  final bool hideSealedCurrentPlaceholders;

  @override
  Widget build(BuildContext context) {
    final activeController = controller;
    if (activeController == null) {
      return Text(context.l10n.liveStatusMembersUnavailable);
    }

    return ListenableBuilder(
      listenable: activeController,
      builder: (context, _) {
        final l10n = context.l10n;
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
            if (showLoadingIndicator && activeController.loading)
              const LinearProgressIndicator(),
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
                      blockReference,
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
          ],
        );
      },
    );
  }
}
