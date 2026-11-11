import 'dart:async';

import '../../observation/latest_value.dart';
import '../domain/acp_business_models.dart';
import '../domain/acp_business_port.dart';
import '../domain/acp_content.dart';
import '../domain/acp_session_payloads.dart';
import '../domain/acp_updates.dart';
import '../domain/acp_values.dart';

part 'acp_conversation_session.dart';

/// Application-owned ACP commands and borrowed observation lifetimes.
///
/// Raw [open] preserves original frames. [openConversation] additionally owns
/// the member's temporary display state and continuously consumes that open.
/// Application shutdown releases observations, not business membership.
final class AcpSessionClient {
  AcpSessionClient({required AcpBusinessPort port}) : _port = port;

  final AcpBusinessPort _port;
  final Set<AcpSessionObservation> _observations = {};
  final Set<Future<void>> _opening = {};
  final Map<String, AcpConversationSession> _conversations = {};
  final Map<String, Future<AcpConversationSession>> _conversationOpening = {};
  final Set<AcpConversationSession> _owners = {};
  bool _disposed = false;
  Future<void>? _disposing;

  void _requireOpen() {
    if (_disposed) throw const AcpObservationDisposed();
  }

  AcpConversationSession? conversationForThread(String threadId) =>
      _conversations[threadId];

  /// Reuses a member's owner, sharing concurrent admission by existing thread.
  ///
  /// Returns after Accepted, without waiting for load replay or Settled.
  /// Creation without a thread remains qualified by the caller's draft gate.
  Future<AcpConversationSession> openConversation(
    OpenAcpSessionRequestView request,
  ) {
    _requireOpen();
    final threadId = request.threadId;
    if (threadId != null) {
      final owner = _conversations[threadId];
      if (owner != null) return Future.value(owner);
      final opening = _conversationOpening[threadId];
      if (opening != null) return opening;
    }
    final future = _openConversation(request);
    if (threadId != null) _conversationOpening[threadId] = future;
    return future;
  }

  Future<AcpConversationSession> _openConversation(
    OpenAcpSessionRequestView request,
  ) async {
    final admission = Completer<void>();
    _opening.add(admission.future);
    try {
      final observation = await open(request);
      _requireOpen();
      final owner = AcpConversationSession._(this, observation, request.intent);
      _owners.add(owner);
      await owner._start();
      _requireOpen();
      final target = owner.state.target!;
      final existing = _conversations[target.threadId];
      if (existing != null && !identical(existing, owner)) {
        await owner._dispose();
        _owners.remove(owner);
        return existing;
      }
      _conversations[target.threadId] = owner;
      return owner;
    } finally {
      if (request.threadId != null) {
        _conversationOpening.removeWhere((key, _) => key == request.threadId);
      }
      _opening.remove(admission.future);
      admission.complete();
    }
  }

  /// Returns the same open's pull resource without awaiting its Settled frame.
  ///
  /// An in-flight admission is not cancellable by abandoning its Dart Future.
  /// If disposed before it returns, disposal owns release of its late resource
  /// and this method fails with [AcpObservationDisposed]; business may proceed.
  Future<AcpSessionObservation> open(OpenAcpSessionRequestView request) async {
    _requireOpen();
    final admission = Completer<void>();
    _opening.add(admission.future);
    try {
      final source = await _port.open(request);
      final observation = AcpSessionObservation._(source, _observations.remove);
      _observations.add(observation);
      if (_disposed) {
        throw const AcpObservationDisposed();
      }
      return observation;
    } finally {
      _opening.remove(admission.future);
      admission.complete();
    }
  }

  Future<AcpRunIdView> prompt(AcpPromptRequestView request) {
    _requireOpen();
    return _port.prompt(request);
  }

  Future<AcpRunIdView> replace(AcpReplaceRequestView request) {
    _requireOpen();
    return _port.replace(request);
  }

  Future<void> interrupt(AcpInterruptRequestView request) {
    _requireOpen();
    return _port.interrupt(request);
  }

  Future<void> configure(AcpConfigureRequestView request) {
    _requireOpen();
    return _port.configure(request);
  }

  Future<void> setMode(AcpSetModeRequestView request) {
    _requireOpen();
    return _port.setMode(request);
  }

  Future<void> answerPermission(AcpPermissionAnswerRequestView request) {
    _requireOpen();
    return _port.answerPermission(request);
  }

  Future<AcpListSessionsResponseView> list(AcpListRequestView request) {
    _requireOpen();
    return _port.list(request);
  }

  Future<AcpBusinessSnapshotView> snapshot(AcpSessionTargetView target) {
    _requireOpen();
    return _port.snapshot(target);
  }

  /// Explicitly closes a business member, preserving every partial-close fact.
  ///
  /// This is independent of releasing a page observation or disposing a Client.
  Future<AcpBusinessCloseView> closeMember(AcpSessionTargetView target) {
    _requireOpen();
    return _port.closeMember(target);
  }

  /// Seals new calls and joins release of this application's observations.
  ///
  /// In-flight commands remain their original Futures and are not cancelled or
  /// resent. Pending opens are joined so late observation resources cannot leak.
  /// Failed resource cleanup is retained and a subsequent dispose retries it.
  Future<void> dispose() {
    final existing = _disposing;
    if (existing != null) return existing;
    _disposed = true;
    final completion = Completer<void>();
    _disposing = completion.future;
    completion.complete(_dispose().whenComplete(() => _disposing = null));
    return completion.future;
  }

  Future<void> _dispose() async {
    final initial = _observations.toSet();
    final owners = _owners.toSet();
    final releases = [
      for (final owner in owners) _releaseOwner(owner),
      for (final observation in initial) observation.close(),
    ];
    try {
      // Admissions register late resources before their joins settle.
      await Future.wait<void>([...releases, ..._opening.toList()]);
    } finally {
      // Even if an initial release failed, release every late resource once.
      // Failed initial resources remain owned for an explicit cleanup retry.
      await Future.wait<void>([
        for (final observation in _observations.toList())
          if (!initial.contains(observation)) observation.close(),
      ]);
    }
  }

  Future<void> _releaseOwner(AcpConversationSession owner) async {
    await owner._dispose();
    _owners.remove(owner);
    final threadId = owner.state.target?.threadId;
    if (identical(_conversations[threadId], owner)) {
      _conversations.remove(threadId);
    }
  }
}

/// A page-borrowed pull observation with no local event buffer.
///
/// [next] preserves the port's frame identity and order. A gap, source error or
/// EOF is never interpreted as prompt completion and never closes a member.
final class AcpSessionObservation {
  AcpSessionObservation._(this._source, this._released);

  final AcpSessionObservationPort _source;
  final void Function(AcpSessionObservation) _released;
  bool _closing = false;
  bool _closed = false;
  Completer<void>? _reading;
  Future<void>? _release;

  /// Pulls one frame; concurrent pulls fail Busy without entering another queue.
  ///
  /// Dart Futures have no cancellation operation. Ignoring a pending Future
  /// leaves this read active until the source settles or [close] releases it.
  Future<AcpSessionFrameView?> next() async {
    if (_closing) return null;
    if (_reading != null) {
      throw AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.busy,
        message: 'An ACP observation read is already pending',
      );
    }
    final reading = Completer<void>();
    _reading = reading;
    try {
      final frame = await _source.next();
      return _closing ? null : frame;
    } finally {
      _reading = null;
      reading.complete();
    }
  }

  /// Signals observation-only release without cancelling a business operation.
  void requestClose() {
    if (_closing) return;
    _closing = true;
    _source.requestClose();
  }

  /// Joins this observation's release and outstanding read, retaining failures.
  ///
  /// Calling again after a cleanup failure retries the same resource, not open.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    final existing = _release;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _release = completion.future;
    completion.complete(_close().whenComplete(() => _release = null));
    return completion.future;
  }

  Future<void> _close() async {
    requestClose();
    await _source.close();
    await _reading?.future;
    _closed = true;
    _released(this);
  }
}
