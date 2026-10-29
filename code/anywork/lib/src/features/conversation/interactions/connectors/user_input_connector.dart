import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/thread_session_store.dart';
import '../state/interaction_payload.dart';
import '../view_models/interaction_command_view_model.dart';
import '../views/user_input_view.dart';
import 'hosted_child_interaction_connector.dart';

class UserInputConnector extends ConsumerWidget {
  const UserInputConnector({
    required this.threadId,
    required this.interactionId,
    required this.expectedRevision,
    required this.payload,
    required this.enabled,
    this.hostedChild,
    this.trailing,
    super.key,
  });

  final String threadId;
  final String interactionId;
  final int expectedRevision;
  final InteractionPayloadSnapshot payload;
  final bool enabled;
  final HostedChildInteraction? hostedChild;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interactionId = this.interactionId;
    final threadId = this.threadId;
    final hostedChild = this.hostedChild;
    final command = ref
        .watch(interactionCommandViewModelProvider(threadId))
        .value
        ?.status(interactionId);
    final active =
        hostedChild != null ||
        pendingInteractionIsActive(
          ref.watch(threadSessionStoreProvider(threadId)).interactions,
          interactionId,
        );
    return UserInputView(
      key: ValueKey('user-input-view-$threadId-$interactionId'),
      payload: payload,
      enabled:
          enabled &&
          active &&
          !(command?.pending ?? false) &&
          !(command?.accepted ?? false) &&
          !(command?.blocked ?? false),
      error: hostedChild == null ? command?.error : null,
      trailing: trailing,
      onSubmit: (resolution) {
        if (hostedChild != null) {
          submitHostedChildDecision(ref, threadId, hostedChild, resolution);
        } else {
          unawaited(
            ref
                .read(interactionCommandViewModelProvider(threadId).notifier)
                .resolveActive(
                  threadId,
                  interactionId,
                  expectedRevision,
                  resolution,
                )
                .then<void>((_) {}, onError: (Object _) {}),
          );
        }
      },
    );
  }
}
