import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork_client/models.dart';

const chatDemand = 20;

ChatItemPresentation chatPresentation(
  String id, {
  required String type,
  required Map<String, Object?> data,
  List<Map<String, Object?>> bodies = const [],
  int? sealedAt,
  String contract = 'anywork.chat/1',
}) => ChatItemPresentation.decodePayloadJson(
  id,
  jsonEncode({
    'contract': contract,
    'type': type,
    'data': data,
    'bodies': bodies,
    'sealedAt': ?sealedAt,
  }),
);

Map<String, Object?> inlineBody(String key, String text) => {
  'key': key,
  'byteLength': utf8.encode(text).length,
  'inline': utf8.encode(text),
};

ThreadWorkspace chatWorkspace(String threadId) {
  final thread = StudioThread(
    id: threadId,
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.auto,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  );
  return ThreadWorkspace(
    thread: thread,
    revision: 1,
    interactions: const [],
    runtime: const ThreadRuntimeView(
      modelId: 'model',
      contextTokens: 0,
      contextWindow: 1,
      totalTokens: 0,
      costLabel: '',
      activeSkills: [],
      activeMcpServers: [],
      activeLspServers: [],
    ),
  );
}
