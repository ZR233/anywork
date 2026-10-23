import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/editor_keys.dart';
import '../state/interaction_view_state.dart';
import 'interaction_reader.dart';
import 'interaction_validation.dart';

part 'interaction_view_model.g.dart';

@riverpod
class InteractionViewModel extends _$InteractionViewModel {
  late ConversationSession _session;
  late InteractionReader _reader;
  Observation? _execution;
  Observation? _selection;
  Observation? _interactionIndex;
  InteractionIndexRef? _index;
  int _readGeneration = 0;
  KeepAliveLink? _editing;
  bool _enabled = true;
  int _editRevision = 0;
  int get editRevision => _editRevision;

  @override
  FutureOr<InteractionViewState> build(InteractionEditorKey key) {
    final repository = ref.read(conversationRepositoryProvider);
    _session = repository.existingSession(key.threadId) ?? repository.session(key.threadId);
    final initial = InteractionViewState(key: key, enabled: _enabled);
    _createReader(initial);
    final execution = _session.execution.watchLatest(_executionChanged);
    _execution = execution.observation;
    _index = execution.value.value?.interactions.reference;
    final selection = repository.active.watchLatest((session) {
      if (session?.threadId == key.threadId && !identical(session, _session)) _sourceChanged();
    });
    _selection = selection.observation;
    final index = _session.interactions.watchLatest((value) {
      if (ref.mounted && state.hasValue) _publish(state.requireValue);
    });
    _interactionIndex = index.observation;
    ref.onDispose(() {
      _execution?.cancel(); _execution = null;
      _selection?.cancel(); _selection = null;
      _interactionIndex?.cancel(); _interactionIndex = null;
      _reader.retire();
      // This ends only the editing read/observation, never D1's frozen operation.
    });
    scheduleMicrotask(() {
      if (ref.mounted) { _reader.open(); loadInteractionIndex(); }
    });
    return initial;
  }

  void _createReader(InteractionViewState initial) {
    final generation = ++_readGeneration;
    _reader = InteractionReader(session: _session,
      read: () => state.value ?? initial,
      publish: _publish,
      canPublish: () => ref.mounted && _readGeneration == generation);
  }

  void _publish(InteractionViewState value) {
    if (!ref.mounted) return;
    final next = value.copyWith(sourceCurrent: _sourceEligible(value));
    state = AsyncData(next.copyWith(submitBlock: interactionSubmitBlock(next)));
  }

  bool _sourceEligible(InteractionViewState value) {
    if (_reader.active == false || value.closing) return false;
    final index = _session.interactions.value;
    final current = index.current;
    final header = value.header;
    final execution = _session.execution.value;
    if (index.error != null || current == null || header == null ||
        execution.sync.phase != FacetSyncPhase.ready ||
        execution.stamp?.runtimeEpoch != current.origin.runtimeEpoch ||
        execution.stamp?.incarnation != current.origin.incarnation ||
        execution.value?.interactions.reference != current.index.reference ||
        current.origin.incarnation != value.key.incarnation ||
        header.scope.runtimeEpoch != current.origin.runtimeEpoch) return false;
    return current.items.any((item) => item.interactionId == value.key.interactionId &&
      item.revision == value.key.revision && item.status == InteractionStatus.pending);
  }

  Future<void> loadInteractionIndex() async {
    try { await _session.loadInteractionsPage(); } on StudioFailure catch (error) {
      if (ref.mounted && state.hasValue) _publish(state.requireValue.copyWith(readIssues: [
        ...state.requireValue.readIssues,
        InteractionReadIssue(section: InteractionReadSection.header, error: error)]));
    }
  }

  void _executionChanged(ThreadExecutionState execution) {
    if (!ref.mounted || !state.hasValue) return;
    final index = execution.value?.interactions.reference;
    if (execution.stamp?.incarnation != state.requireValue.key.incarnation ||
        (_index != null && index != _index)) {
      // A pinned Pending header is not proof that the current interaction is
      // still Pending. Current index/materialized admission is supplied by D1.
      _publish(state.requireValue.copyWith(sourceCurrent: false));
    }
    _index = index;
    // Sync/closing and other admission facts can change without a new index.
    _publish(state.requireValue);
  }

  void _sourceChanged() {
    if (!ref.mounted || !state.hasValue) return;
    _reader.retire();
    _publish(state.requireValue.copyWith(sourceCurrent: false));
  }

  void _edit(InteractionViewState Function(InteractionViewState) change) {
    final value = state.requireValue;
    if (value.closing || !value.enabled || !value.sourceCurrent || value.header?.state is! PendingInteractionRead) return;
    final next = change(value);
    if (next == value) return;
    _editRevision++;
    if (next.hasDraftEdits) { _editing ??= ref.keepAlive(); }
    else { _editing?.close(); _editing = null; }
    _publish(next);
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (state.hasValue) _publish(state.requireValue.copyWith(enabled: value));
  }
  void setQuestionText(int index, String raw) {
    if (!state.requireValue.questions.containsKey(index)) return;
    _edit((s) => s.copyWith(answers: {...s.answers,
      index: (s.answers[index] ?? const QuestionAnswerDraft()).copyWith(text: raw)}));
  }
  void setOptionSelected(int index, String label, bool selected) {
    final value = state.requireValue;
    final question = value.questions[index];
    if (question == null || !question.options.any((option) => value.textOf(option.label) == label)) return;
    _edit((s) {
      final answer = s.answers[index] ?? const QuestionAnswerDraft();
      final labels = [...answer.selectedLabels];
      if (selected) { if (!labels.contains(label)) labels.add(label); } else { labels.remove(label); }
      return s.copyWith(answers: {...s.answers, index: answer.copyWith(selectedLabels: labels)});
    });
  }
  void setFallbackText(String raw) => _edit((s) => s.copyWith(fallbackText: raw));
  void setApprovalReason(String raw) => _edit((s) => s.copyWith(approvalReason: raw));
  void setPlanFeedback(String raw) => _edit((s) => s.copyWith(planFeedback: raw));

  Future<void> showQuestion(int index) async {
    if (!state.requireValue.questions.containsKey(index)) return;
    _publish(state.requireValue.copyWith(currentQuestionIndex: index));
  }
  Future<void> loadNextQuestions() => _reader.questions();
  Future<void> loadNextOptions(int index) => _reader.options(index);
  Future<void> loadNextAnswerEntries() => _reader.answerEntries();
  Future<void> loadNextAnswerValues(int index) => _reader.answerValues(index);
  Future<void> loadText(int fieldId) => _reader.text(fieldId);
  Future<void> completeRead() => _reader.completeRead();

  Future<void> retryRead() {
    final value = state.requireValue;
    if (value.readIssues.any((issue) => issue.error.code == StudioFailureCode.superseded)) {
      _publish(value.copyWith(sourceCurrent: false, submitBlock: InteractionSubmitBlock.sourceChanged));
      return Future<void>.value();
    }
    _reader.retire();
    final next = value.copyWith(scope: null, header: null, questions: {}, texts: {},
      readIssues: [], questionPageLoading: false, completingRead: false);
    _publish(next);
    _createReader(next);
    return _reader.open();
  }

  /// Called for a confirmed terminal editor or explicit discard, not from Widget
  /// dispose/Settings navigation. Accepted/unknown payload remains with D1.
  bool endEditing({required int expectedEditRevision, bool discardDraft = false}) {
    final value = state.requireValue;
    if (!value.canCloseEditor || expectedEditRevision != _editRevision ||
        (value.hasDraftEdits && !discardDraft)) return false;
    _reader.retire();
    _publish(value.copyWith(closing: true,
      answers: const {}, fallbackText: '', approvalReason: '', planFeedback: ''));
    _editing?.close(); _editing = null;
    return true;
  }
}
