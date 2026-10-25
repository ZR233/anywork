import 'dart:async';

import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../domain/bot_edit.dart';
import '../domain/bot_values.dart';
import '../domain/bot_conversation_values.dart';
import 'bot_conversation_scope_owner.dart' show validateBotBinding;
import 'bots_commands_values.dart';
import 'bots_mirror.dart';
import 'bots_port.dart';

/// Domain-private action dispatch. The supplied registry remains the only
/// operation evidence store; these owners retain actual in-flight work/causes.
final class BotsActions {
  BotsActions(this.port, this.mirror, this.lifetime, this.operations);
  final BotsPort port;
  final BotsMirror mirror;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;

  OperationTicket<BotSnapshot> saveBot(BotEdit intent) =>
      _run<BotSnapshot>('bots:save:${intent.botId}', (action) async {
        _revision(intent.expectedConfigRevision);
        final request = SaveBotRequest(
          operationId: action.id,
          botId: intent.botId,
          expectedConfigRevision: intent.expectedConfigRevision,
          name: intent.name,
          projectId: intent.projectId,
          appId: intent.appId,
          secret: intent.secret,
          enabled: intent.enabled,
          toolsEnabled: intent.toolsEnabled,
          modelRoute: intent.modelRoute,
        );
        final reply = await action.invoke(() => port.saveBot(request));
        action.confirmBots(reply);
        final bot = _bot(reply, intent.botId, intent.expectedConfigRevision);
        if (intent.projectId.isNotEmpty && bot.projectId != intent.projectId ||
            bot.appId != intent.appId) {
          throw resourceProtocol(
            'The saved bot reply belongs to another application or project.',
          );
        }
        await action.observeBots(bot);
      });

  OperationTicket<BotSnapshot> setEnabled({
    required String botId,
    required int expectedConfigRevision,
    required bool enabled,
  }) => _run<BotSnapshot>('bots:enabled:$botId', (action) async {
    _revision(expectedConfigRevision);
    final request = SetBotEnabledRequest(
      operationId: action.id,
      botId: botId,
      expectedConfigRevision: expectedConfigRevision,
      enabled: enabled,
    );
    final reply = await action.invoke(() => port.setBotEnabled(request));
    action.confirmBots(reply);
    final bot = _bot(reply, botId, expectedConfigRevision);
    if (bot.enabled != enabled)
      throw resourceProtocol('The bot enable reply has another desired state.');
    await action.observeBots(bot);
  });

  OperationTicket<BotSnapshot> retryConnection({required String botId}) =>
      _run<BotSnapshot>('bots:retry:$botId', (action) async {
        final request = RetryBotConnectionRequest(
          operationId: action.id,
          botId: botId,
        );
        final reply = await action.invoke(
          () => port.retryBotConnection(request),
        );
        action.confirmBots(reply);
        // A retry acknowledgement is not proof of a connected socket.
        await action.observeBots(_bot(reply, botId, null));
      });

  OperationTicket<BotRegistrationAttempt> startRegistration({
    required String name,
    required String projectId,
  }) => _run<BotRegistrationAttempt>('bots:registration:start', (action) async {
    final request = StartBotRegistrationRequest(
      operationId: action.id,
      name: name,
      projectId: projectId,
    );
    final reply = await action.invoke(() => port.startBotRegistration(request));
    action.confirmBots(reply);
    final registration = _registration(reply);
    if (registration.projectId != projectId.trim() ||
        registration.name != name.trim()) {
      throw resourceProtocol(
        'The registration reply belongs to another project.',
      );
    }
    // Preserve Preparing/Waiting/Failed/Committing exactly as native returned.
    await action.observeBots(registration);
  });

  OperationTicket<BotRegistrationAttempt> cancelRegistration({
    required String attemptId,
  }) => _run<BotRegistrationAttempt>('bots:registration:cancel:$attemptId', (
    action,
  ) async {
    final request = CancelBotRegistrationRequest(
      operationId: action.id,
      attemptId: attemptId,
    );
    final reply = await action.invoke(
      () => port.cancelBotRegistration(request),
    );
    action.confirmBots(reply);
    final registration = _registration(reply);
    if (registration.attemptId != attemptId) {
      throw resourceProtocol(
        'The cancellation reply belongs to another registration attempt.',
      );
    }
    // Native may return a real terminal NoChange value; never manufacture
    // Cancelled or Completed from the fact that this RPC returned success.
    await action.observeBots(registration);
  });

  OperationTicket<BotSnapshot> setTrustedUser({
    required String botId,
    required int expectedConfigRevision,
    required String openId,
    required bool trusted,
  }) => _run<BotSnapshot>('bots:trusted-user:$botId:$openId', (action) async {
    _revision(expectedConfigRevision);
    final request = SetBotTrustedUserRequest(
      operationId: action.id,
      botId: botId,
      expectedConfigRevision: expectedConfigRevision,
      openId: openId,
      trusted: trusted,
    );
    final reply = await action.invoke(() => port.setBotTrustedUser(request));
    action.confirmBots(reply);
    final bot = _bot(reply, botId, expectedConfigRevision);
    if (bot.trustedOpenIds.contains(openId) != trusted) {
      throw resourceProtocol(
        'The trusted-user reply has another authorization target.',
      );
    }
    await action.observeBots(bot);
  });

  OperationTicket<BotSnapshot> setTrustedChat({
    required String botId,
    required int expectedConfigRevision,
    required String chatId,
    required bool trusted,
  }) => _run<BotSnapshot>('bots:trusted-chat:$botId:$chatId', (action) async {
    _revision(expectedConfigRevision);
    final request = SetBotTrustedChatRequest(
      operationId: action.id,
      botId: botId,
      expectedConfigRevision: expectedConfigRevision,
      chatId: chatId,
      trusted: trusted,
    );
    final reply = await action.invoke(() => port.setBotTrustedChat(request));
    action.confirmBots(reply);
    final bot = _bot(reply, botId, expectedConfigRevision);
    if (bot.trustedChatIds.contains(chatId) != trusted) {
      throw resourceProtocol(
        'The trusted-chat reply has another authorization target.',
      );
    }
    await action.observeBots(bot);
  });

  OperationTicket<BotConversationThreadBinding> createConversationThread({
    required String botId,
    required String chatId,
    required int expectedConfigRevision,
    required int expectedBindingRevision,
  }) => _run<BotConversationThreadBinding>('bots:thread:$botId:$chatId', (
    action,
  ) async {
    _revision(expectedConfigRevision);
    _revision(expectedBindingRevision);
    final request = CreateBotConversationThreadRequest(
      operationId: action.id,
      botId: botId,
      chatId: chatId,
      expectedConfigRevision: expectedConfigRevision,
      expectedBindingRevision: expectedBindingRevision,
    );
    action.bindingTarget(botId, chatId);
    final reply = await action.invoke(
      () => port.createBotConversationThread(request),
    );
    action.confirmReceipt(reply.receipt, 'bot:$botId:chat:$chatId');
    validateBotBinding(reply.binding, botId, chatId);
    final target = reply.receipt.targets.single as ResourceStamp;
    if (reply.binding.revision < expectedBindingRevision ||
        target.revision != reply.binding.revision) {
      throw resourceProtocol(
        'The bot thread receipt does not cover its original binding.',
      );
    }
    action.observeBinding(reply.binding, target);
  });

  OperationTicket<T> _run<T>(
    String target,
    Future<void> Function(_BotsAction<T>) action,
  ) {
    lifetime.admit();
    // Bots receipts use their native whole-domain/binding ResourceStamp, not
    // a fabricated additional identity-observation obligation. Later recovery
    // can therefore settle this same original receipt through the registry.
    final writer = operations.begin<T>(target: target);
    final owner = _BotsAction<T>(lifetime, mirror, operations, writer, action);
    try {
      lifetime.register(owner);
      owner.start();
    } catch (error, stack) {
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      // No native invocation can exist before start has entered its work.
      owner.notStarted(error, stack);
    }
    return writer.ticket;
  }
}

void _revision(int value) {
  if (value < 0) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'The bot expected revision cannot be negative.',
      retryable: false,
      correlationId: 'bots',
    );
  }
}

BotSnapshot _bot(BotsCommandReply reply, String? botId, int? revision) {
  final bot = reply.bot;
  if (bot == null ||
      botId != null && bot.id != botId ||
      bot.configRevision < 0 ||
      revision != null && bot.configRevision < revision) {
    throw resourceProtocol(
      'The bot command reply changed its frozen bot identity or version.',
    );
  }
  return bot;
}

BotRegistrationAttempt _registration(BotsCommandReply reply) {
  final registration = reply.registration;
  if (registration == null)
    throw resourceProtocol('The registration reply has no original attempt.');
  validateBotRegistration(registration);
  return registration;
}

/// One action owns the actual invocation and its feed observation. It cannot
/// be restarted, and cleanup only joins this work; it never calls the command.
final class _BotsAction<T> implements ResourceOwner {
  _BotsAction(
    this.lifetime,
    this.mirror,
    this.operations,
    this.writer,
    this.action,
  ) : attempt = lifetime.nextAttempt();

  final ResourceLifetime lifetime;
  final BotsMirror mirror;
  final OperationRecorder operations;
  final OperationWriter<T> writer;
  Future<void> Function(_BotsAction<T>)? action;
  @override
  final int attempt;
  OperationId get id => writer.ticket.id;
  @override
  String get owner => 'bots:action:${id.value}';
  final Completer<void> _settled = Completer<void>();
  final List<(Object, StackTrace)> _causes = [];
  ProductReadOrigin? _origin;
  bool _dispatched = false;
  bool _confirmed = false;
  bool _unknown = false;
  bool _observed = false;
  bool _released = false;
  bool _closing = false;
  CommitReceipt? _receipt;
  StudioFailure? _failure;
  T? _value;

  void start() {
    unawaited(
      lifetime.accepted<void>(this, () async {
        try {
          final original = await mirror.ready();
          lifetime.admit();
          if (original.projection.header?.botsRevision == null) {
            throw const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The Bots source has no current business value.',
              retryable: true,
              correlationId: 'bots',
            );
          }
          _origin = original.projection.stamp!.origin;
          await action!(this);
        } catch (error, stack) {
          _fail(error, stack);
        } finally {
          // In particular, no secret-bearing request/intent remains retained by
          // a completed action, even when its evidence outcome is unresolved.
          action = null;
          _settled.complete();
          _released = !_unknown && (!_confirmed || _observed);
        }
      }),
    );
  }

  void notStarted(Object error, StackTrace stack) {
    _remember(error, stack);
    action = null;
    writer.rejected(_failure!);
    _released = true;
    if (!_settled.isCompleted) _settled.complete();
  }

  Future<R> invoke<R>(Future<R> Function() send) {
    lifetime.admit();
    if (_closing) throw resourceCancelled;
    _dispatched = true;
    return Future<R>.sync(send);
  }

  void confirmReceipt(CommitReceipt receipt, String key) {
    if (receipt.operationId != id ||
        receipt.targets.length != 1 ||
        receipt.targets.single is! ResourceStamp ||
        receipt.requiresIdentityObservation) {
      throw resourceProtocol(
        'The Bots reply has another operation or observation contract.',
      );
    }
    final target = receipt.targets.single as ResourceStamp;
    if (target.resourceKey != key ||
        target.ownerEpoch != _origin?.ownerEpoch ||
        target.revision < 0) {
      throw resourceProtocol(
        'The Bots receipt belongs to another frozen resource owner.',
      );
    }
    _receipt = receipt;
    _confirmed = true;
  }

  void confirmBots(BotsCommandReply reply) {
    confirmReceipt(reply.receipt, 'bots');
    if (reply.stamp case final stamp?) {
      if (stamp != reply.receipt.targets.single) {
        throw resourceProtocol(
          'The Bots reply stamp disagrees with its native receipt.',
        );
      }
    }
  }

  Future<void> observeBots(T value) async {
    _value = value;
    writer.accepted(value, _receipt!);
    await mirror.observe(_receipt!);
    // Evidence and effect are not inferred from connection, registration or
    // credential availability. Only real receipt flags carry those stages.
    writer.identityObserved();
    _observed = true;
  }

  void observeBinding(T value, ResourceStamp target) {
    _value = value;
    writer.accepted(value, _receipt!);
    // The returned binding is itself the original authoritative read, with a
    // verified bot/chat/revision. There is no synthetic directory observation.
    operations.observe(target);
    writer.identityObserved();
    _observed = true;
  }

  void _remember(Object error, StackTrace stack) {
    _causes.add((error, stack));
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
    _failure ??= error is CommandDispatchFailure
        ? error.failure
        : resourceFailure(error);
  }

  void _fail(Object error, StackTrace stack) {
    _remember(error, stack);
    if (!_confirmed) {
      switch (error) {
        case CommittedButUnobservedCommandDispatchFailure(:final receipt):
          // This path also validates the source/OperationId. A malformed
          // committed reply remains confirmed, but cannot acquire that receipt.
          try {
            confirmReceipt(receipt, _bindingKey ?? 'bots');
          } catch (mismatch, mismatchStack) {
            _remember(mismatch, mismatchStack);
            // The adapter independently confirmed this invocation, but a
            // foreign receipt must never be attached to the original ID.
            _confirmed = true;
          }
        case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
          _confirmed = true;
        case RejectedCommandDispatchFailure():
          break;
        case UnknownOutcomeCommandDispatchFailure():
          _unknown = _dispatched;
        default:
          _unknown = _dispatched;
      }
    }
    final failure = _failure!;
    if (writer.ticket.state.value.observed) {
      writer.evidenceFailed(failure);
      _observed = true;
    } else if (_confirmed) {
      final receipt = _receipt;
      if (receipt == null) {
        writer.acknowledgedSynchronizationFailed(failure, value: _value);
      } else {
        writer.synchronizationFailed(failure, value: _value, receipt: receipt);
      }
      writer.evidenceFailed(failure);
    } else if (_unknown) {
      writer.unknownOutcome(failure);
    } else {
      writer.rejected(failure);
    }
  }

  // Binding commands set this before invoke so typed committed failures can
  // validate the same target even if no ordinary reply was convertible.
  String? _bindingKey;

  void bindingTarget(String botId, String chatId) {
    _bindingKey = 'bot:$botId:chat:$chatId';
  }

  @override
  bool get released =>
      _released ||
      _settled.isCompleted &&
          !_unknown &&
          _confirmed &&
          writer.ticket.state.value.observed;
  @override
  void requestClose() {
    // Closing observations is not cancellation of an accepted native action.
    // The shared source seal ends the wait, while this invocation is joined.
    _closing = true;
  }

  @override
  Future<void> cleanup({required bool retry}) async {
    await _settled.future;
  }

  @override
  List<FeedCloseIssue> get issues {
    if (!_settled.isCompleted)
      return [resourcePendingIssue('botActionPending')];
    if (released) return const [];
    return [
      resourceCleanupIssue(
        _failure ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The original bot action has unresolved outcome or observation evidence.',
              retryable: false,
              correlationId: 'bots',
            ),
        CleanupRecovery.terminal,
      ),
    ];
  }
}
