import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../state/chat_item_presentation.dart';
import 'chat_item_view.dart';

/// Pure nested timeline view over the existing Children controller.
///
/// The connector owns opening, paging and retirement. The public Chat builder
/// slot composes a standard shrink-wrapped ListView over that same controller;
/// this view neither copies messages nor applies chat operations itself.
/// The surrounding live body or main timeline owns scrolling and height.
class TimelineChildrenView extends StatefulWidget {
  const TimelineChildrenView({
    super.key,
    required this.controller,
    required this.generation,
    required this.isDisplayActive,
    this.onLoadOlder,
    this.onLoadNewer,
    this.attachmentBuilder,
    this.atomBuilder,
  });

  final InMemoryChatController controller;
  final int generation;
  final Future<void> Function()? onLoadOlder;
  final Future<void> Function()? onLoadNewer;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final Widget Function(ChatItemPresentation item)? atomBuilder;
  final bool Function() isDisplayActive;

  @override
  State<TimelineChildrenView> createState() => _TimelineChildrenViewState();
}

class _TimelineChildrenViewState extends State<TimelineChildrenView> {
  Future<void>? _loadingPage;

  void _load(Future<void> Function()? action) {
    if (action == null || _loadingPage != null) return;
    setState(() {
      _loadingPage = Future<void>.sync(action).whenComplete(() {
        if (mounted) setState(() => _loadingPage = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) => Chat(
    backgroundColor: Colors.transparent,
    currentUserId: 'user',
    resolveUser: (id) async => User(id: id),
    chatController: widget.controller,
    builders: Builders(
      composerBuilder: (_) => const SizedBox.shrink(),
      // 组导轨与活动行已拥有缩进和行高。成员只借用 Chat 的
      // 消息分发，不再嵌套顶层 ChatMessage 的留白与对齐外壳。
      chatMessageBuilder: (
        context,
        message,
        index,
        animation,
        child, {
        bool? isRemoved,
        required bool isSentByMe,
        MessageGroupStatus? groupStatus,
      }) => isRemoved == true ? const SizedBox.shrink() : child,
      customMessageBuilder:
          (
            context,
            message,
            index, {
            required bool isSentByMe,
            MessageGroupStatus? groupStatus,
          }) {
            final presentation = chatItemPresentationOf(message)!;
            if (presentation.atom != null && widget.atomBuilder != null) {
              return widget.atomBuilder!(presentation);
            }
            return ChatItemView(
              key: ValueKey((widget.generation, message.id)),
              item: chatItemPresentationOf(message)!,
              isDisplayActive: widget.isDisplayActive,
              attachmentBuilder: widget.attachmentBuilder,
            );
          },
      chatAnimatedListBuilder: (context, itemBuilder) =>
          StreamBuilder<ChatOperation>(
            stream: widget.controller.operationsStream,
            builder: (context, _) {
              final messages = widget.controller.messages;
              final hasOlder = widget.onLoadOlder != null;
              final hasNewer = widget.onLoadNewer != null;
              final hasPageControl = hasOlder || hasNewer;
              return ListView.builder(
                key: ValueKey(('timeline-children-list', widget.generation)),
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  final index = messages.indexWhere(
                    (message) => message.id == key.value,
                  );
                  return index < 0 ? null : index + (hasPageControl ? 1 : 0);
                },
                itemCount: messages.length + (hasPageControl ? 1 : 0),
                itemBuilder: (context, index) {
                  if (hasPageControl && index == 0) {
                    return FutureBuilder<void>(
                      future: _loadingPage,
                      builder: (context, snapshot) => Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (hasNewer)
                              TextButton.icon(
                                key: const ValueKey(
                                  'timeline-children-load-newer',
                                ),
                                onPressed: _loadingPage == null
                                    ? () => _load(widget.onLoadNewer)
                                    : null,
                                icon: const Icon(Icons.update, size: 15),
                                label: const Text('加载较新记录'),
                              ),
                            if (hasOlder)
                              TextButton.icon(
                                key: const ValueKey(
                                  'timeline-children-load-older',
                                ),
                                onPressed: _loadingPage == null
                                    ? () => _load(widget.onLoadOlder)
                                    : null,
                                icon:
                                    snapshot.connectionState ==
                                        ConnectionState.waiting
                                    ? const SizedBox.square(
                                        dimension: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.history, size: 15),
                                label: const Text('加载更早记录'),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  final messageIndex = index - (hasPageControl ? 1 : 0);
                  final message = messages[messageIndex];
                  return KeyedSubtree(
                    key: ValueKey(message.id),
                    child: itemBuilder(
                      context,
                      message,
                      messageIndex,
                      const AlwaysStoppedAnimation<double>(1),
                    ),
                  );
                },
              );
            },
          ),
    ),
  );
}
