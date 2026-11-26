import 'package:anywork_client/studio_client.dart';

TimelineAssistantText feedAssistant(
  String id,
  int seq,
  String text, {
  BodyRef? bodyRef,
  String? turnId,
}) => TimelineAssistantText(
  id: id,
  seq: seq,
  text: text,
  bodyRef: bodyRef,
  turnId: turnId,
  channel: 'assistant',
  isFinalTurnDelivery: true,
  outcome: 'completed',
);

TimelineUserMessage feedUser(
  String id,
  int seq,
  String text, {
  String? inputId,
}) => TimelineUserMessage(
  id: id,
  seq: seq,
  channel: 'user',
  text: text,
  inputId: inputId,
  attachments: const [],
);
