import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../state/content_reference_identity.dart';

final planDocumentViewModelProvider = NotifierProvider.autoDispose
    .family<PlanDocumentViewModel, PlanDocumentState, String>(
      PlanDocumentViewModel.new,
    );

class PlanDocumentState {
  const PlanDocumentState({
    this.window,
    this.error,
    this.loading = false,
    this.canRead = false,
  });

  final ContentWindow? window;
  final Object? error;
  final bool loading;
  final bool canRead;
}

class PlanDocumentViewModel extends Notifier<PlanDocumentState> {
  PlanDocumentViewModel(this.threadId);

  final String threadId;
  late ConversationRepository _conversations;
  ConversationSession? _session;
  Observation? _sessionObservation;
  Observation? _contentObservation;
  ConversationQueryScope? _scope;
  Object? _source;
  int _generation = 0;
  int _request = 0;
  int _offset = 0;
  bool _disposed = false;

  @override
  PlanDocumentState build() {
    _conversations = ref.read(anyworkClientProvider).conversations;
    observeClient(ref, _conversations.visibleThreadId, (_) => _sync());
    ref.onDispose(() {
      _disposed = true;
      _sessionObservation?.cancel();
      _contentObservation?.cancel();
      _retire();
    });
    // Defer IO until the provider has published its initial presentation.
    scheduleMicrotask(_sync);
    return const PlanDocumentState();
  }

  Object? _currentSource() {
    final session = _conversations.existingSession(threadId);
    final content = session?.content;
    final document = session?.state.businessRefs?.plan?.document;
    if (_conversations.visibleThreadId.value != threadId ||
        session == null ||
        content == null ||
        document == null ||
        content.isClosed ||
        content.state.value is! ChatReady<bool> ||
        content.currentAttemptId == null) {
      return null;
    }
    return (
      session,
      content,
      content.currentAttemptId,
      contentReferenceIdentity(document),
    );
  }

  void _sync() {
    if (_disposed) return;
    final session = _conversations.existingSession(threadId);
    if (!identical(session, _session)) {
      _sessionObservation?.cancel();
      _contentObservation?.cancel();
      _session = session;
      _sessionObservation = session?.source
          .watchLatest((_) => _sync())
          .observation;
      _contentObservation = session?.content.state
          .watchLatest((_) => _sync())
          .observation;
    }
    final source = _currentSource();
    if (source != null && source == _source) return;
    _retire();
    _source = source;
    _offset = 0;
    if (source == null) {
      final connection = session?.content.state.value;
      final error =
          _conversations.visibleThreadId.value == threadId &&
              connection is ChatFailed<bool>
          ? connection.error
          : null;
      state = PlanDocumentState(error: error);
      return;
    }
    state = const PlanDocumentState(canRead: true);
    unawaited(_load(0));
  }

  void _retire() {
    _request++;
    _source = null;
    final scope = _scope;
    _scope = null;
    scope?.retire();
    // Failed cleanup remains owned by the original SDK content owner.
    if (scope != null) unawaited(scope.close());
  }

  Future<void> _load(int offset) async {
    final source = _source;
    if (_disposed ||
        source == null ||
        source != _currentSource() ||
        state.loading) {
      return;
    }
    final request = ++_request;
    _offset = offset;
    final content = _session!.content;
    final document = _session!.state.businessRefs!.plan!.document!;
    bool current() =>
        !_disposed &&
        request == _request &&
        source == _source &&
        source == _currentSource();
    state = PlanDocumentState(
      window: state.window,
      loading: true,
      canRead: true,
    );
    try {
      final scope = _scope ??= content.openScope(generation: ++_generation);
      final window = await scope.readContent(
        reference: document,
        range: ContentRange(offset: offset, maxBytes: 64 * 1024),
      );
      if (!current()) return;
      state = PlanDocumentState(window: window, canRead: true);
    } catch (error) {
      if (!current()) return;
      state = PlanDocumentState(
        window: state.window,
        error: error,
        canRead: true,
      );
    }
    // No shared finally: an old request cannot clear a newer request's loading.
  }

  void retry() {
    if (_disposed || state.loading || state.error == null) return;
    if (_conversations.visibleThreadId.value != threadId) return;
    final content = _session?.content;
    if (content?.state.value is ChatFailed<bool>) {
      content!.refresh();
    } else {
      unawaited(_load(_offset));
    }
  }

  void next() {
    final window = state.window;
    if (window == null ||
        window.bytes.isEmpty ||
        window.offset + window.bytes.length >= window.availableThrough) {
      return;
    }
    unawaited(_load(window.offset + window.bytes.length));
  }

  void copy() {
    final window = state.window;
    if (window == null ||
        state.loading ||
        _source == null ||
        _source != _currentSource()) {
      return;
    }
    unawaited(
      Clipboard.setData(
        ClipboardData(text: utf8.decode(window.bytes, allowMalformed: true)),
      ),
    );
  }
}
