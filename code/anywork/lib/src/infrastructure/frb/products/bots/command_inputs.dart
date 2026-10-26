import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/resources.dart' show OperationId;

import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/exact_numbers.dart';

String botOperationToBridge(OperationId value) {
  if (value.value.trim().isEmpty) {
    throw adapterProtocol('bots-command-operation');
  }
  return value.value;
}

native.BridgeSaveBotRequest saveBotToBridge(SaveBotRequest value) =>
    native.BridgeSaveBotRequest(
      operationId: botOperationToBridge(value.operationId),
      botId: value.botId,
      expectedConfigRevision: nativeU64(
        value.expectedConfigRevision,
        'bot expected configuration revision',
      ),
      name: value.name,
      projectId: value.projectId,
      appId: value.appId,
      secret: switch (value.secret) {
        BotSecretPreserve() => const native.BridgeBotSecretUpdate.preserve(),
        BotSecretReplace(:final value) => native.BridgeBotSecretUpdate.replace(
          value: value,
        ),
        BotSecretClear() => const native.BridgeBotSecretUpdate.clear(),
      },
      enabled: value.enabled,
      toolsEnabled: value.toolsEnabled,
      modelRoute: value.modelRoute == null
          ? null
          : native.BridgeBotModelRoute(
              accountId: value.modelRoute!.accountId,
              modelId: value.modelRoute!.modelId,
              effort: value.modelRoute!.effort,
            ),
    );

native.BridgeSetBotEnabledRequest setBotEnabledToBridge(
  SetBotEnabledRequest value,
) => native.BridgeSetBotEnabledRequest(
  operationId: botOperationToBridge(value.operationId),
  botId: value.botId,
  expectedConfigRevision: nativeU64(
    value.expectedConfigRevision,
    'bot expected configuration revision',
  ),
  enabled: value.enabled,
);

native.BridgeRetryBotConnectionRequest retryBotConnectionToBridge(
  RetryBotConnectionRequest value,
) => native.BridgeRetryBotConnectionRequest(
  operationId: botOperationToBridge(value.operationId),
  botId: value.botId,
);

native.BridgeStartBotRegistrationRequest startBotRegistrationToBridge(
  StartBotRegistrationRequest value,
) => native.BridgeStartBotRegistrationRequest(
  operationId: botOperationToBridge(value.operationId),
  name: value.name,
  projectId: value.projectId,
);

native.BridgeCancelBotRegistrationRequest cancelBotRegistrationToBridge(
  CancelBotRegistrationRequest value,
) => native.BridgeCancelBotRegistrationRequest(
  operationId: botOperationToBridge(value.operationId),
  attemptId: value.attemptId,
);

native.BridgeSetBotTrustedUserRequest setBotTrustedUserToBridge(
  SetBotTrustedUserRequest value,
) => native.BridgeSetBotTrustedUserRequest(
  operationId: botOperationToBridge(value.operationId),
  botId: value.botId,
  expectedConfigRevision: nativeU64(
    value.expectedConfigRevision,
    'bot expected configuration revision',
  ),
  openId: value.openId,
  trusted: value.trusted,
);

native.BridgeSetBotTrustedChatRequest setBotTrustedChatToBridge(
  SetBotTrustedChatRequest value,
) => native.BridgeSetBotTrustedChatRequest(
  operationId: botOperationToBridge(value.operationId),
  botId: value.botId,
  expectedConfigRevision: nativeU64(
    value.expectedConfigRevision,
    'bot expected configuration revision',
  ),
  chatId: value.chatId,
  trusted: value.trusted,
);

native.BridgeCreateBotConversationThreadRequest createBotThreadToBridge(
  CreateBotConversationThreadRequest value,
) => native.BridgeCreateBotConversationThreadRequest(
  operationId: botOperationToBridge(value.operationId),
  botId: value.botId,
  chatId: value.chatId,
  expectedConfigRevision: nativeU64(
    value.expectedConfigRevision,
    'bot expected configuration revision',
  ),
  expectedBindingRevision: nativeU64(
    value.expectedBindingRevision,
    'bot expected binding revision',
  ),
);

native.BridgeListBotConversationsRequest listBotConversationsToBridge(
  ListBotConversationsRequest value,
) {
  final limit = value.limit;
  // u32 representability only: BotRuntime, not Dart, owns default/clamping semantics.
  if (limit != null && (limit < 0 || limit > 0xffffffff)) {
    throw adapterProtocol('bots-conversations-limit');
  }
  return native.BridgeListBotConversationsRequest(
    botId: value.botId,
    cursor: value.cursor,
    limit: limit,
  );
}

native.BridgeReadBotMessagesRequest readBotMessagesToBridge(
  BotMessageQuery value,
) {
  final limit = value.limit;
  if (limit != null && (limit < 0 || limit > 0xffffffff)) {
    throw adapterProtocol('bots-messages-limit');
  }
  return native.BridgeReadBotMessagesRequest(
    botId: value.botId,
    chatId: value.chatId,
    startTime: value.startTime == null
        ? null
        : exactI64(
            BigInt.from(value.startTime!),
            'bot message start Unix seconds',
          ),
    endTime: value.endTime == null
        ? null
        : exactI64(BigInt.from(value.endTime!), 'bot message end Unix seconds'),
    cursor: value.cursor,
    limit: limit,
  );
}

native.BridgeSendBotMessageRequest sendBotMessageToBridge(
  SendBotMessageRequest value,
) => native.BridgeSendBotMessageRequest(
  operationId: botOperationToBridge(value.operationId),
  botId: value.botId,
  chatId: value.chatId,
  text: value.text,
);
