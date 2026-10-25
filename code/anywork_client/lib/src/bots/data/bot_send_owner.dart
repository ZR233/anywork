import 'dart:async';

import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../domain/bot_message_values.dart';
import 'bot_message_requests.dart';
import 'bots_port.dart';

/// One immutable operation and exactly one invocation. Unknown external
/// delivery remains protected in the registry, independently of local receipts.
final class BotSendOwner implements ResourceOwner {
  BotSendOwner({
    required this.port,
    required this.lifetime,
    required this.operations,
    required this.writer,
    required SendBotMessageRequest request,
    required this.record,
  }) : _request = request,
       attempt = lifetime.nextAttempt();

  final BotsPort port;
  final ResourceLifetime lifetime;
  final OperationRecorder operations;
  final OperationWriter<BotSendResult> writer;
  final void Function(BotSendResult) record;
  SendBotMessageRequest? _request;
  @override
  final int attempt;
  @override
  String get owner => 'bots:send:${writer.ticket.id.value}';
  final Completer<void> _settled = Completer<void>();
  final List<(Object, StackTrace)> _causes = [];
  bool _dispatched = false;
  bool _confirmed = false;
  bool _unknown = false;
  CommitReceipt? _receipt;
  StudioFailure? _failure;
  BotSendResult? _value;

  void start(Future<void> previous, void Function() release) {
    unawaited(
      lifetime.accepted<void>(this, () async {
        try {
          await previous;
          lifetime.admit();
          final request = _request!;
          _dispatched = true;
          final result = await port.sendMessage(request);
          _confirmed = true;
          _confirmReceipt(result.receipt, request);
          if (result.operationId != request.operationId ||
              result.botId != request.botId ||
              result.chatId != request.chatId) {
            throw resourceProtocol(
              'The bot send result belongs to another frozen operation or target.',
            );
          }
          _value = result;
          record(result);
          if (result.status == BotSendStatus.unknown ||
              result.status == BotSendStatus.partial) {
            _unknown = true;
            _failure = StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'Bot send finished with ${result.status.name}.',
              retryable: false,
              correlationId: request.operationId.value,
            );
            // This receipt proves local ledger acceptance, not external delivery.
            // accepted() followed by unknownOutcome() contradicts the registry's
            // success contract. Keep the full receipt in the typed result mirror,
            // and settle this original ticket as Unknown without automatic replay.
            writer.unknownOutcome(_failure!);
          } else {
            writer.accepted(result, result.receipt);
            for (final target in result.receipt.targets) {
              operations.observe(target);
            }
            writer.identityObserved();
          }
        } catch (error, stack) {
          _fail(error, stack);
        } finally {
          // No completed/unknown operation retains a second copy of message text.
          _request = null;
          _settled.complete();
          release();
        }
      }),
    );
  }

  void _confirmReceipt(CommitReceipt receipt, SendBotMessageRequest request) {
    if (receipt.operationId != request.operationId ||
        receipt.targets.length != 1 ||
        receipt.requiresIdentityObservation ||
        receipt.targets.single is! ResourceStamp) {
      throw resourceProtocol(
        'The bot send receipt has another operation or observation contract.',
      );
    }
    final target = receipt.targets.single as ResourceStamp;
    if (target.resourceKey != 'bot:${request.botId}' ||
        target.ownerEpoch.isEmpty ||
        target.revision < 0) {
      throw resourceProtocol(
        'The bot send receipt belongs to another resource.',
      );
    }
    _receipt = receipt;
  }

  void notStarted(Object error, StackTrace stack) {
    _remember(error, stack);
    _request = null;
    writer.rejected(_failure!);
    if (!_settled.isCompleted) _settled.complete();
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
          _confirmed = true;
          try {
            _confirmReceipt(receipt, _request!);
          } catch (mismatch, mismatchStack) {
            _remember(mismatch, mismatchStack);
          }
        case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
          _confirmed = true;
        case RejectedCommandDispatchFailure():
          break;
        default:
          _unknown = _dispatched;
      }
    }
    if (writer.ticket.state.value.observed) {
      writer.evidenceFailed(_failure!);
    } else if (_unknown) {
      writer.unknownOutcome(_failure!);
    } else if (_confirmed) {
      final receipt = _receipt;
      if (receipt == null) {
        writer.acknowledgedSynchronizationFailed(_failure!, value: _value);
      } else {
        writer.synchronizationFailed(
          _failure!,
          value: _value,
          receipt: receipt,
        );
      }
      writer.evidenceFailed(_failure!);
    } else {
      writer.rejected(_failure!);
    }
  }

  @override
  bool get released =>
      _settled.isCompleted &&
      !_unknown &&
      (!_confirmed || writer.ticket.state.value.observed);
  @override
  void requestClose() {
    // Repository seal rejects unsent slots. A dispatched external write is only
    // joined, never cancelled or retried by a read observer/cleanup operation.
  }
  @override
  Future<void> cleanup({required bool retry}) async {
    await _settled.future;
  }

  @override
  List<FeedCloseIssue> get issues {
    if (!_settled.isCompleted) return [resourcePendingIssue('botSendPending')];
    if (released) return const [];
    return [
      resourceCleanupIssue(
        _failure ??
            const StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The original bot send has unresolved outcome or receipt evidence.',
              retryable: false,
              correlationId: 'bots',
            ),
        CleanupRecovery.terminal,
      ),
    ];
  }
}
