import 'package:anywork_client/bots.dart';
import 'package:flutter/material.dart';

import '../widgets/bot_labels.dart';

/// One message row of the platform tools page.
///
/// Body text is a typed domain value: unsupported bodies are ordinary readable
/// history with their platform notice, never a cast failure or an attempt to
/// decode platform JSON here.
class BotMessageView extends StatelessWidget {
  const BotMessageView({required this.message, super.key});

  final BotMessage message;

  @override
  Widget build(BuildContext context) {
    final text = botMessageText(message);
    return ExpansionTile(
      key: ValueKey(('bot-message', message.messageId)),
      title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${message.senderOpenId ?? message.messageId} · '
        '${DateTime.fromMillisecondsSinceEpoch(message.createdAt * 1000).toLocal()}',
      ),
      children: [
        Padding(padding: const EdgeInsets.all(12), child: SelectableText(text)),
      ],
    );
  }
}
