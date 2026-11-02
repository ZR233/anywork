import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../state/chat_item_presentation.dart';
import 'chat_item_view.dart';

/// Pure nested timeline view over the existing Children controller.
///
/// The connector owns opening, paging and retirement. This view does not retain
/// another item collection.
class TimelineChildrenView extends StatelessWidget {
  const TimelineChildrenView({
    super.key,
    required this.controller,
    required this.generation,
    required this.contentRangeBuilder,
    required this.isDisplayActive,
    this.onLoadOlder,
    this.attachmentBuilder,
  });

  final InMemoryChatController controller;
  final int generation;
  final Future<void> Function()? onLoadOlder;
  final ChatContentRangeBuilder contentRangeBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final bool Function() isDisplayActive;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 320,
    child: Chat(
      currentUserId: 'user',
      resolveUser: (id) async => User(id: id),
      chatController: controller,
      builders: Builders(
        composerBuilder: (_) => const SizedBox.shrink(),
        customMessageBuilder:
            (
              context,
              message,
              index, {
              required bool isSentByMe,
              MessageGroupStatus? groupStatus,
            }) => ChatItemView(
              key: ValueKey((generation, message.id)),
              item: chatItemPresentationOf(message)!,
              isDisplayActive: isDisplayActive,
              contentRangeBuilder: contentRangeBuilder,
              attachmentBuilder: attachmentBuilder,
            ),
        chatAnimatedListBuilder: (context, itemBuilder) =>
            ChatAnimatedListReversed(
              itemBuilder:
                  (
                    context,
                    message,
                    index,
                    animation, {
                    messagesGroupingMode,
                    messageGroupingTimeoutInSeconds,
                    isRemoved,
                  }) => KeyedSubtree(
                    key: ValueKey(message.id),
                    child: KeyedSubtree(
                      key: ObjectKey(message),
                      child: itemBuilder(
                        context,
                        message,
                        index,
                        animation,
                        messagesGroupingMode: messagesGroupingMode,
                        messageGroupingTimeoutInSeconds:
                            messageGroupingTimeoutInSeconds,
                        isRemoved: isRemoved,
                      ),
                    ),
                  ),
              handleSafeArea: false,
              onEndReached: onLoadOlder,
              insertAnimationDuration: Duration.zero,
              removeAnimationDuration: Duration.zero,
            ),
      ),
    ),
  );
}
