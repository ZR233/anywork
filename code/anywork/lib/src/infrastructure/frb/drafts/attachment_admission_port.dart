import 'dart:async';

import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/draft_commands/commands.dart' as commands;
import '../../../rust/api/studio/draft_commands/handles.dart' as native;
import '../../../rust/api/studio/draft_commands/types.dart' as wire;
import '../../../rust/api/studio/handlers/attachment.dart' as attachment;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/resource_owner.dart';
import 'draft_command_failures.dart';
import 'draft_command_values.dart';

/// Production registration/recovery only. Native owns admission and the SDK
/// ledger owns successful entries; closing an observer never removes drafts.
final class FrbAttachmentAdmissionPort implements AttachmentAdmissionPort {
  const FrbAttachmentAdmissionPort();

  @override
  Future<AttachmentAdmissionJob> begin(
    OperationId id,
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  ) {
    final Future<native.BridgeAttachmentAdmission> Function() invoke;
    try {
      final frozenContext = admissionContextToBridge(context);
      final frozenSources = admissionSourcesToBridge(sources);
      invoke = () => commands.beginAttachmentAdmission(
        operationId: id.value,
        context: frozenContext,
        sources: frozenSources,
      );
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: draftCommandFailure(error)),
        stack,
      );
    }
    final job = _FrbAttachmentAdmission(id, invoke, isBegin: true);
    return job.opened.then((_) => job);
  }

  @override
  Future<AttachmentAdmissionJob?> find(OperationId id) {
    final job = _FrbAttachmentAdmission(
      id,
      () => commands.findAttachmentAdmission(operationId: id.value),
    );
    return job.opened.then((found) => found ? job : null);
  }

  @override
  Future<bool> remove(String draftId) =>
      bridgeQuery(() => attachment.removeAttachmentDraft(draftId: draftId));
}

final class _FrbAttachmentAdmission implements AttachmentAdmissionJob {
  _FrbAttachmentAdmission(
    this._expected,
    Future<native.BridgeAttachmentAdmission?> Function() open, {
    bool isBegin = false,
  }) {
    _opening.future.ignore();
    _owner = AdapterResourceOwner(
      resource: 'attachment-admission',
      requestNativeClose: () {
        _handle?.requestClose();
      },
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: draftCommandFailure,
      expectedIdentity: () => _operationId?.value ?? '',
    );
    final finish = _owner.registerOpening();
    Future<native.BridgeAttachmentAdmission?>.sync(open)
        .then<void>(
          (handle) {
            _handle = handle;
            if (handle != null) {
              try {
                _rememberIdentity(handle);
              } on Object catch (error, stack) {
                _descriptorFailure = (
                  failure: _owner.failure(error, stack, source: 'identity'),
                  stack: stack,
                );
              }
              if (_owner.isClosing) {
                try {
                  handle.requestClose();
                } on Object catch (error, stack) {
                  _owner.failure(error, stack, source: 'late-open-close');
                }
              }
            }
            _opening.complete(handle);
          },
          onError: (Object error, StackTrace stack) {
            _owner.failure(error, stack, source: 'open');
            _opening.completeError(
              isBegin ? draftBeginFailure(error) : draftCommandFailure(error),
              stack,
            );
          },
        )
        .whenComplete(finish)
        .ignore();
  }

  final OperationId _expected;
  final _opening = Completer<native.BridgeAttachmentAdmission?>();
  late final AdapterResourceOwner _owner;
  native.BridgeAttachmentAdmission? _handle;
  OperationId? _operationId;
  ({StudioFailure failure, StackTrace stack})? _descriptorFailure;
  wire.BridgeAttachmentAdmissionOutcome? _outcome;
  Future<wire.BridgeAttachmentAdmissionOutcome>? _resultQuery;
  bool _resultSealed = false;

  Future<bool> get opened => _opening.future.then((handle) => handle != null);

  void _rememberIdentity(native.BridgeAttachmentAdmission handle) {
    final id = handle.identity().operationId;
    if (id.isEmpty || _operationId != null && id != _operationId!.value) {
      throw adapterProtocol('attachment-admission-identity');
    }
    _operationId ??= OperationId(id);
  }

  @override
  OperationId get operationId {
    if (_operationId case final id?) return id;
    if (_descriptorFailure case final failure?) {
      Error.throwWithStackTrace(failure.failure, failure.stack);
    }
    throw adapterProtocol('attachment-admission-identity-unavailable');
  }

  /// A result is an observation of an already accepted command, not a new
  /// query admission. Install its one in-flight responsibility synchronously;
  /// the real closer below joins it before permitting opaque disposal.
  Future<wire.BridgeAttachmentAdmissionOutcome> _rawResult() {
    if (_outcome case final outcome?) return Future.value(outcome);
    if (_resultQuery case final pending?) return pending;
    if (_resultSealed || _owner.isDisposed) {
      throw adapterCancelled('attachment-admission-result');
    }
    final completion = Completer<wire.BridgeAttachmentAdmissionOutcome>();
    final pending = _resultQuery = completion.future;
    pending.ignore(); // Cleanup may join this after the independent close RPC.
    unawaited(
      Future<wire.BridgeAttachmentAdmissionOutcome>.sync(() async {
            final handle = await _opening.future;
            if (handle == null) {
              throw adapterProtocol('attachment-admission-missing');
            }
            final outcome = await handle.result();
            _outcome = outcome; // Keep actual Returned evidence even if conversion fails.
            return outcome;
          })
          .then<void>(
            completion.complete,
            onError: (Object error, StackTrace stack) {
              _owner.failure(error, stack, source: 'result');
              completion.completeError(
                CommandDispatchFailure.unknownOutcome(
                  failure: draftCommandFailure(error),
                ),
                stack,
              );
            },
          )
          .whenComplete(() {
            if (identical(_resultQuery, pending)) _resultQuery = null;
          }),
    );
    return pending;
  }

  @override
  Future<List<AttachmentMetadata>> result() async {
    final outcome = await _rawResult();
    switch (outcome) {
      case wire.BridgeAttachmentAdmissionOutcome_Returned(:final drafts):
        try {
          if (operationId != _expected) {
            throw adapterProtocol('attachment-admission-operation');
          }
          return List<AttachmentMetadata>.unmodifiable(
            drafts.map(admittedAttachmentFromBridge),
          );
        } on Object catch (error, stack) {
          final failure = _owner.failure(
            error,
            stack,
            source: 'returned-conversion',
          );
          // Local mapping failure after a REAL Returned, not a fictitious
          // native fourth outcome or a synthesized generic CommitReceipt.
          Error.throwWithStackTrace(
            CommandDispatchFailure.confirmedWithoutUsableReceipt(
              failure: failure,
            ),
            stack,
          );
        }
      case wire.BridgeAttachmentAdmissionOutcome_Rejected(:final error):
        throw CommandDispatchFailure.rejected(
          failure: draftCommandFailure(error),
        );
      case wire.BridgeAttachmentAdmissionOutcome_UnknownOutcome(:final error):
        throw CommandDispatchFailure.unknownOutcome(
          failure: draftCommandFailure(error),
        );
    }
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.future;
    if (handle == null) throw adapterProtocol('attachment-admission-missing');
    if (_operationId == null) {
      try {
        _rememberIdentity(handle);
      } on Object catch (error, stack) {
        _owner.failure(error, stack, source: 'close-identity');
      }
    }
    Future<wire.BridgeAttachmentAdmissionOutcome>? resultQuery;
    try {
      resultQuery = _rawResult();
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'result-join');
    }
    FeedCloseReport? report;
    Object? closeError;
    StackTrace? closeStack;
    try {
      report = feedCloseReportFromBridge(
        await (retry ? handle.retryClose() : handle.close()),
      );
    } on Object catch (error, stack) {
      closeError = error;
      closeStack = stack;
    }
    if (_operationId != null &&
        report?.feedId == _operationId!.value &&
        report?.outcome is CleanFeedCloseOutcome) {
      // No new result RPC after this real native Clean; calls already entered
      // while closing must still settle before the opaque can be disposed.
      _resultSealed = true;
    }
    try {
      await resultQuery;
    } on Object catch (error, stack) {
      _owner.failure(error, stack, source: 'result-join');
    }
    // Even a failed close RPC does not abandon the original result call. The
    // shared owner retains the close error/real ID and permits explicit retry.
    if (closeError != null) Error.throwWithStackTrace(closeError, closeStack!);
    return report!;
  }

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
