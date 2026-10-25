import 'package:anywork_client/bots.dart';

import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../shared/exact_numbers.dart';
import 'bot_values.dart';

BotConversationThreadBinding botBindingFromBridge(
  native.BridgeBotConversationThreadBinding value,
) => BotConversationThreadBinding(
  botId: value.botId,
  chatId: value.chatId,
  projectId: value.projectId,
  threadId: value.threadId,
  revision: exactU64(value.revision, 'bot conversation binding revision'),
  state: switch (value.state) {
    native.BridgeBotConversationThreadState.creating =>
      BotConversationThreadState.creating,
    native.BridgeBotConversationThreadState.bound =>
      BotConversationThreadState.bound,
    native.BridgeBotConversationThreadState.needsAttention =>
      BotConversationThreadState.needsAttention,
  },
  diagnostic: value.diagnostic == null
      ? null
      : botDiagnosticFromBridge(value.diagnostic!),
);

BotConversationPage botConversationPageFromBridge(
  native.BridgeBotConversationPage value,
) => BotConversationPage(
  botId: value.botId,
  nextCursor: value.nextCursor,
  conversations: List.unmodifiable([
    for (final conversation in value.conversations)
      BotConversation(
        chatId: conversation.chatId,
        kind: switch (conversation.kind) {
          native.BridgeBotConversationKind.group => BotConversationKind.group,
          native.BridgeBotConversationKind.direct => BotConversationKind.direct,
        },
        source: switch (conversation.source) {
          native.BridgeBotConversationSource.remoteGroup =>
            BotConversationSource.remoteGroup,
          native.BridgeBotConversationSource.observedDirect =>
            BotConversationSource.observedDirect,
        },
        name: conversation.name,
        lastObservedAt: conversation.lastObservedAt == null
            ? null
            : exactI64(
                BigInt.from(conversation.lastObservedAt!),
                'bot conversation observed Unix seconds',
              ),
        threadBinding: conversation.threadBinding == null
            ? null
            : botBindingFromBridge(conversation.threadBinding!),
      ),
  ]),
);
