import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationWriter;
import '../../../resources.dart';
import '../../../resources_ports.dart' show ResourcePermit;
import 'configuration_command_owner.dart';
import 'configuration_read_fields.dart';
import 'configuration_write_context.dart';

/// Runtime owners, not domain values: each typed job retains both its immutable
/// user intent and the exact last dispatched request until evidence settles it.
abstract class ConfigurationWriteJobBase {
  ConfigurationWriteJobBase(this.writer, this.attempt);
  final OperationWriter<Unit> writer;
  final AttemptId attempt;
  Observation? observation;
  ResourcePermit? evidencePermit;
  bool finished = false;
  final List<ConfigurationCallOwner> calls = [];
  ConfigurationCallOwner? currentCall;

  bool get releasable =>
      finished &&
      proven &&
      calls.every((call) => call.released && call.issues.isEmpty);

  void observe(OperationState state) => currentCall?.observe(state);

  bool get dispatched;
  Future<ConfigurationWriteReply> dispatch();
  void nextAttempt();

  bool get proven {
    final state = writer.ticket.state.value;
    return state.failurePhase == OperationFailurePhase.rejected ||
        state.receipt != null && state.observed ||
        state.acknowledged && state.observed;
  }

  void retainUnresolved() {
    final permit = evidencePermit;
    if (permit != null && !permit.isReleased)
      permit.mark(ResourcePhase.unresolved);
  }

  void releaseObservation() {
    observation?.cancel();
    observation = null;
    evidencePermit?.release();
    evidencePermit = null;
  }
}

final class ConfigurationWriteJob<T, P> extends ConfigurationWriteJobBase {
  ConfigurationWriteJob({
    required OperationWriter<Unit> writer,
    required AttemptId attempt,
    required this.intent,
    required this.send,
  }) : super(writer, attempt);
  final T intent;
  final Future<ConfigurationWriteReply> Function(
    T,
    OperationId,
    void Function(P, ProductReadOrigin),
  )
  send;
  P? _prepared;
  ProductReadOrigin? _firstOrigin;

  @override
  bool get dispatched => _prepared != null;
  @override
  void nextAttempt() {
    if (currentCall case final call?) {
      if (!call.released || call.issues.isNotEmpty)
        throw StateError(
          'The original Configuration call has not clean-closed.',
        );
    }
    currentCall = null;
    _prepared = null;
  }

  @override
  Future<ConfigurationWriteReply> dispatch() =>
      send(intent, writer.ticket.id, (request, origin) {
        if (_firstOrigin != null && _firstOrigin != origin)
          throw configurationSuperseded;
        _firstOrigin ??= origin;
        _prepared = request;
      });
}
