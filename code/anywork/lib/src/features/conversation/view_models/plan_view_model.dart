import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/plan_view_state.dart';
import 'read_scope_borrow.dart';
import 'read_validation.dart';
import 'session_facet_observer.dart';

part 'plan_view_model.g.dart';

/// Reading and expansion only. Decisions/feedback never live in this VM.
@riverpod
class PlanViewModel extends _$PlanViewModel {
  late SessionFacetObserver<ThreadAuthoringState> _observer;
  ReadScopeBorrow<PlanDocumentReadScope>? _borrow;
  int _binding = 0;

  @override
  FutureOr<PlanViewState> build(String threadId) {
    _observer = SessionFacetObserver<ThreadAuthoringState>(
      repository: ref.read(conversationRepositoryProvider), threadId: threadId,
      source: (session) => session.authoring, onValue: _changed);
    _binding = _observer.generation;
    ref.onDispose(() { _observer.cancel(); _borrow?.retire(); });
    return PlanViewState(threadId: threadId, origin: _observer.value?.stamp,
      plan: _observer.value?.value?.plan);
  }

  void _changed(ThreadAuthoringState source) {
    if (!ref.mounted || !state.hasValue) return;
    final before = state.requireValue;
    final plan = source.value?.plan;
    final replaced = _binding != _observer.generation;
    _binding = _observer.generation;
    final documentChanged = replaced || before.plan?.document != plan?.document;
    if (before.plan == plan && !replaced) return;
    if (documentChanged) { _borrow?.retire(); _borrow = null; }
    state = AsyncData(before.copyWith(plan: plan, origin: source.stamp,
      document: documentChanged ? null : before.document,
      loading: documentChanged ? false : before.loading,
      error: documentChanged ? null : before.error,
      latestIntent: documentChanged ? before.latestIntent + 1 : before.latestIntent));
    if (documentChanged && state.requireValue.expanded) loadDocument();
  }

  void setExpanded(bool expanded) {
    state = AsyncData(state.requireValue.copyWith(expanded: expanded));
    if (expanded && state.requireValue.document == null) loadDocument();
  }
  void toggle() => setExpanded(!state.requireValue.expanded);

  Future<void> loadDocument() async {
    final before = state.requireValue;
    final session = _observer.session;
    final reference = before.plan?.document;
    final origin = before.origin;
    if (!before.expanded || before.loading || reference == null || session == null || origin == null) return;
    final intent = before.latestIntent + 1;
    final binding = _observer.generation;
    final borrow = ReadScopeBorrow<PlanDocumentReadScope>(
      open: () => session.openPlanDocument(reference, origin: origin),
      requestClose: (scope) => scope.requestClose(), close: (scope) => scope.close(),
      retryCleanup: (scope) => scope.retryCleanup());
    _borrow?.retire(); _borrow = borrow;
    state = AsyncData(before.copyWith(loading: true, error: null, latestIntent: intent));
    bool current() => ref.mounted && binding == _observer.generation &&
        identical(session, _observer.session) && state.requireValue.latestIntent == intent &&
        state.requireValue.plan?.document == reference;
    try {
      final scope = await borrow.open();
      final header = await scope.header();
      if (header.version != reference.version || header.contentHash != reference.contentHash ||
          header.scope.runtimeEpoch != origin.runtimeEpoch || header.scope.incarnation != origin.incarnation) {
        throw readProtocol('plan-identity');
      }
      final document = await scope.document();
      if (document.scope != header.scope || document.version != reference.version ||
          document.contentHash != reference.contentHash) throw readProtocol('plan-document');
      if (current()) state = AsyncData(state.requireValue.copyWith(document: document));
    } on StudioFailure catch (error) {
      if (current()) state = AsyncData(state.requireValue.copyWith(error: error));
    } finally {
      borrow.retire();
      if (current()) state = AsyncData(state.requireValue.copyWith(loading: false));
    }
  }
}
