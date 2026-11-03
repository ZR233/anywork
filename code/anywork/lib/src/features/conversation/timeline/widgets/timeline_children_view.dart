import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:anywork_client/conversation.dart';

import '../state/chat_item_presentation.dart';
import 'chat_item_view.dart';

/// Pure nested timeline view over the existing Children controller.
///
/// The connector owns opening, paging and retirement. The public Chat builder
/// slot composes a standard shrink-wrapped ListView over that same controller;
/// this view neither copies messages nor applies chat operations itself.
class TimelineChildrenView extends StatefulWidget {
  const TimelineChildrenView({
    super.key,
    required this.controller,
    required this.generation,
    required this.contentRangeBuilder,
    required this.isDisplayActive,
    this.onLoadOlder,
    this.attachmentBuilder,
    this.atomBuilder,
  });

  final InMemoryChatController controller;
  final int generation;
  final Future<void> Function()? onLoadOlder;
  final ChatContentRangeBuilder contentRangeBuilder;
  final Widget Function(ChatItemPresentation item)? attachmentBuilder;
  final Widget Function(ChatAtom atom)? atomBuilder;
  final bool Function() isDisplayActive;

  @override
  State<TimelineChildrenView> createState() => _TimelineChildrenViewState();
}

class _TimelineChildrenViewState extends State<TimelineChildrenView> {
  Future<void>? _loadingOlder;

  void _loadOlder() {
    final action = widget.onLoadOlder;
    if (action == null || _loadingOlder != null) return;
    setState(() {
      _loadingOlder = Future<void>.sync(action).whenComplete(() {
        if (mounted) setState(() => _loadingOlder = null);
      });
    });
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 320),
    child: Chat(
      backgroundColor: Colors.transparent,
      currentUserId: 'user',
      resolveUser: (id) async => User(id: id),
      chatController: widget.controller,
      builders: Builders(
        composerBuilder: (_) => const SizedBox.shrink(),
        customMessageBuilder:
            (
              context,
              message,
              index, {
              required bool isSentByMe,
              MessageGroupStatus? groupStatus,
            }) {
              final presentation = chatItemPresentationOf(message)!;
              final atom = presentation.atom;
              if (atom != null && widget.atomBuilder != null) {
                return widget.atomBuilder!(atom);
              }
              return ChatItemView(
              key: ValueKey((widget.generation, message.id)),
              item: chatItemPresentationOf(message)!,
              isDisplayActive: widget.isDisplayActive,
              contentRangeBuilder: widget.contentRangeBuilder,
              attachmentBuilder: widget.attachmentBuilder,
              );
            },
        chatAnimatedListBuilder: (context, itemBuilder) =>
            StreamBuilder<ChatOperation>(
              stream: widget.controller.operationsStream,
              builder: (context, _) {
                final messages = widget.controller.messages;
                final hasOlder = widget.onLoadOlder != null;
                return ListView.builder(
                  key: ValueKey(('timeline-children-list', widget.generation)),
                  shrinkWrap: true,
                  primary: false,
                  padding: EdgeInsets.zero,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final index = messages.indexWhere(
                      (message) => message.id == key.value,
                    );
                    return index < 0 ? null : index + (hasOlder ? 1 : 0);
                  },
                  itemCount: messages.length + (hasOlder ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasOlder && index == 0) {
                      return FutureBuilder<void>(
                        future: _loadingOlder,
                        builder: (context, snapshot) => Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const ValueKey('timeline-children-load-older'),
                            onPressed: _loadingOlder == null
                                ? _loadOlder
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
                        ),
                      );
                    }
                    final messageIndex = index - (hasOlder ? 1 : 0);
                    final message = messages[messageIndex];
                    return KeyedSubtree(
                      key: ValueKey(message.id),
                      child: KeyedSubtree(
                        key: ObjectKey(message),
                        child: itemBuilder(
                          context,
                          message,
                          messageIndex,
                          const AlwaysStoppedAnimation<double>(1),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      ),
    ),
  );
}
