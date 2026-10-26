import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../../../rust/api/studio/types/command.dart' as command;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/receipt_converters.dart';
import 'bot_values.dart';
import 'conversation_values.dart';
import 'registration_values.dart';

StudioFailure botsCallFailure(Object error) {
  if (error case CommandDispatchFailure(:final failure)) return failure;
  try {
    return bridgeFailure(error);
  } on Object catch (mappingError) {
    return adapterFailure(mappingError, operation: 'bots-call-error');
  }
}

/// Only a failure before invoking native proves no dispatch. An ordinary BridgeError from an
/// invoked Bots command carries no rejection guarantee and must remain UnknownOutcome.
T prepareBotsCommand<T>(T Function() prepare) {
  try {
    return prepare();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.rejected(failure: botsCallFailure(error)),
      stack,
    );
  }
}

Future<T> invokeBotsCommand<N, T>(
  Future<N> Function() invoke,
  T Function(N) convert,
) async {
  final N value;
  try {
    value = await invoke();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(
      CommandDispatchFailure.unknownOutcome(failure: botsCallFailure(error)),
      stack,
    );
  }
  // Conversion keeps the stronger native returned/committed evidence below. Do not wrap this
  // phase in the invocation catch or turn a malformed result back into an unknown commit.
  return convert(value);
}

CommitReceipt _receipt(
  command.BridgeStudioCommandReceipt value,
  OperationId operation,
  String key,
) {
  try {
    if (value.operationId != operation.value ||
        value.operationId.trim().isEmpty) {
      throw adapterProtocol('bots-command-operation');
    }
    final receipt = commitReceiptFromBridge(value);
    if (receipt.targets.length != 1 ||
        receipt.requiresIdentityObservation ||
        receipt.targets.single is! ResourceStamp) {
      throw adapterProtocol('bots-command-receipt');
    }
    final target = receipt.targets.single as ResourceStamp;
    if (target.resourceKey != key || target.ownerEpoch.isEmpty) {
      throw adapterProtocol('bots-command-target');
    }
    return receipt;
  } on Object catch (error) {
    throw CommandDispatchFailure.confirmedWithoutUsableReceipt(
      failure: botsCallFailure(error),
    );
  }
}

BotsCommandReply botsReplyFromBridge(
  native.BridgeBotsCommandReply value,
  OperationId operation,
  void Function(BotsCommandReply) validate,
) {
  final receipt = _receipt(value.receipt, operation, 'bots');
  try {
    final stamp = value.stamp;
    final reply = BotsCommandReply(
      receipt: receipt,
      stamp: stamp == null
          ? null
          : ResourceStamp(
              resourceKey: stamp.resourceKey,
              ownerEpoch: stamp.ownerEpoch,
              revision: exactU64(stamp.revision, 'bots command stamp revision'),
            ),
      bot: value.bot == null ? null : botSnapshotFromBridge(value.bot!),
      registration: value.registration == null
          ? null
          : botRegistrationFromBridge(value.registration!),
    );
    if (reply.stamp != null && reply.stamp != receipt.targets.single) {
      throw adapterProtocol('bots-command-stamp');
    }
    validate(reply);
    return reply;
  } on Object catch (error) {
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: receipt,
      failure: botsCallFailure(error),
    );
  }
}

void requireBotResult(
  BotsCommandReply value,
  String? botId, {
  int? expectedRevision,
}) {
  final bot = value.bot;
  if (bot == null ||
      bot.id.isEmpty ||
      botId != null && bot.id != botId ||
      expectedRevision != null && bot.configRevision < expectedRevision ||
      value.registration != null) {
    throw adapterProtocol('bots-command-bot-binding');
  }
  for (final pairing in bot.pairing) {
    if (pairing.botId != bot.id) {
      throw adapterProtocol('bots-command-pairing-binding');
    }
  }
}

void requireRegistrationResult(
  BotsCommandReply value, {
  String? attemptId,
  String? name,
  String? projectId,
}) {
  final registration = value.registration;
  if (registration == null ||
      registration.attemptId.isEmpty ||
      attemptId != null && registration.attemptId != attemptId ||
      name != null && registration.name != name.trim() ||
      projectId != null && registration.projectId != projectId.trim() ||
      value.bot != null && registration.completedBotId != value.bot!.id) {
    throw adapterProtocol('bots-command-registration-binding');
  }
  final statusAttempt = switch (registration.status) {
    BotRegistrationIdle() => null,
    BotRegistrationPreparing(:final attemptId) => attemptId,
    BotRegistrationWaiting(:final attemptId) => attemptId,
    BotRegistrationSlowDown(:final attemptId) => attemptId,
    BotRegistrationCompleted(:final attemptId) => attemptId,
    BotRegistrationCommitting(:final attemptId) => attemptId,
    BotRegistrationDenied(:final attemptId) => attemptId,
    BotRegistrationExpired(:final attemptId) => attemptId,
    BotRegistrationCancelled(:final attemptId) => attemptId,
    BotRegistrationFailed(:final attemptId) => attemptId,
  };
  if (statusAttempt != null && statusAttempt != registration.attemptId) {
    throw adapterProtocol('bots-command-registration-status');
  }
}

BotConversationThreadReply botThreadReplyFromBridge(
  native.BridgeBotConversationThreadReply value,
  CreateBotConversationThreadRequest request,
) {
  final receipt = _receipt(
    value.receipt,
    request.operationId,
    'bot:${request.botId}:chat:${request.chatId}',
  );
  try {
    final binding = botBindingFromBridge(value.binding);
    final target = receipt.targets.single as ResourceStamp;
    if (binding.botId != request.botId ||
        binding.chatId != request.chatId ||
        binding.projectId.isEmpty ||
        binding.revision < request.expectedBindingRevision ||
        binding.revision != target.revision ||
        binding.state == BotConversationThreadState.bound &&
            (binding.threadId == null || binding.threadId!.isEmpty)) {
      throw adapterProtocol('bots-command-thread-binding');
    }
    return BotConversationThreadReply(binding: binding, receipt: receipt);
  } on Object catch (error) {
    throw CommandDispatchFailure.committedButUnobserved(
      receipt: receipt,
      failure: botsCallFailure(error),
    );
  }
}
