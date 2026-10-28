import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../state/interaction_view_state.dart';
import 'interaction_validation.dart';
import 'read_scope_borrow.dart';
import 'read_validation.dart';

/// Typed reading only. The VM remains the sole owner of raw answers and intent;
/// all canonical identity lookup/CAS/native query supervision remains in D1.
final class InteractionReader {
  InteractionReader({
    required ConversationSession session,
    required InteractionViewState Function() read,
    required this._publish,
    required this._canPublish,
  }) : _read = read {
    final key = read().key;
    _borrow = ReadScopeBorrow<InteractionReadScope>(
      open: () => key.isHosted
          ? session.openHostedInteraction(
              origin: key.hostedOrigin!,
              reference: key.hostedReference!,
              targetThreadId: key.target,
            )
          : session.openInteraction(
              interactionId: key.interactionId,
              expectedRevision: key.revision,
              expectedIncarnation: key.incarnation,
            ),
      requestClose: (scope) => scope.requestClose(),
      close: (scope) => scope.close(),
      retryCleanup: (scope) => scope.retryCleanup(),
    );
  }
  final InteractionViewState Function() _read;
  final void Function(InteractionViewState) _publish;
  final bool Function() _canPublish;
  late final ReadScopeBorrow<InteractionReadScope> _borrow;
  final Map<(InteractionReadSection, int?, int?), Future<void>> _requests = {};
  Object? readCause;
  StackTrace? readTrace;
  bool get active => !_borrow.retired && _canPublish();
  void retire() => _borrow.retire();

  void _update(InteractionViewState Function(InteractionViewState) edit) {
    if (active) _publish(edit(_read()));
  }

  Future<void> open() => _request(InteractionReadSection.header, (scope) async {
    final header = await scope.header();
    if (!active) return;
    final key = _read().key;
    if (header.scope.runtimeEpoch != key.runtimeEpoch ||
        header.scope.incarnation != key.incarnation ||
        header.revision != key.revision) {
      throw readProtocol('interaction-key');
    }
    final content = header.content;
    final terminal = header.state;
    var next = _read().copyWith(
      scope: header.scope,
      header: header,
      questions: {},
      nextQuestionOffset:
          content is UserInputContentRead && content.questionCount > 0
          ? 0
          : null,
      answerEntries: [],
      answerValues: {},
      nextAnswerValueOffsets: {},
      texts: {},
      nextAnswerEntryOffset:
          terminal is ResolvedUserInputRead && terminal.answerEntryCount > 0
          ? 0
          : null,
      readIssues: [],
    );
    next = next.copyWith(
      texts: registerReadTexts(next.texts, requiredInteractionTexts(next)),
    );
    _publish(next);
  });

  Future<void> questions() {
    final value = _read();
    final offset = value.nextQuestionOffset;
    final content = value.header?.content;
    if (offset == null || content is! UserInputContentRead) {
      return Future<void>.value();
    }
    _update((s) => s.copyWith(questionPageLoading: true));
    return _request(InteractionReadSection.questions, (scope) async {
      final page = await scope.questions(offset: offset, limit: 32);
      if (!active) return;
      checkReadPage(
        expectedScope: _read().scope!,
        scope: page.scope,
        requested: offset,
        offset: page.offset,
        total: page.total,
        count: page.items.length,
        next: page.nextOffset,
        expectedTotal: content.questionCount,
      );
      final next = Map<int, QuestionReadProgress>.of(_read().questions);
      for (final (position, item) in page.items.indexed) {
        if (item.index != offset + position || next.containsKey(item.index)) {
          throw readProtocol('question-index');
        }
        next[item.index] = QuestionReadProgress(
          question: item,
          nextOptionOffset: (item.optionsCount ?? 0) > 0 ? 0 : null,
        );
      }
      _update((s) {
        final changed = s.copyWith(
          questions: next,
          nextQuestionOffset: page.nextOffset,
        );
        return changed.copyWith(
          texts: registerReadTexts(
            changed.texts,
            requiredInteractionTexts(changed),
          ),
        );
      });
    }).whenComplete(
      () => _update((s) => s.copyWith(questionPageLoading: false)),
    );
  }

  Future<void> options(int index) {
    final progress = _read().questions[index];
    final offset = progress?.nextOptionOffset;
    if (progress == null || offset == null || progress.optionsLoading) {
      return Future<void>.value();
    }
    _update(
      (s) => s.copyWith(
        questions: {
          ...s.questions,
          index: progress.copyWith(optionsLoading: true, optionsError: null),
        },
      ),
    );
    return _request(InteractionReadSection.options, (scope) async {
      final page = await scope.options(index, offset: offset, limit: 32);
      if (!active) return;
      checkReadPage(
        expectedScope: _read().scope!,
        scope: page.scope,
        requested: offset,
        offset: page.offset,
        total: page.total,
        count: page.items.length,
        next: page.nextOffset,
        expectedTotal: progress.question.optionsCount,
      );
      for (final (position, item) in page.items.indexed) {
        if (item.index != offset + position) throw readProtocol('option-index');
      }
      _update((s) {
        final old = s.questions[index]!;
        final changed = s.copyWith(
          questions: {
            ...s.questions,
            index: old.copyWith(
              options: [...old.options, ...page.items],
              nextOptionOffset: page.nextOffset,
            ),
          },
        );
        return changed.copyWith(
          texts: registerReadTexts(
            changed.texts,
            requiredInteractionTexts(changed),
          ),
        );
      });
    }, index: index).whenComplete(
      () => _update(
        (s) => s.copyWith(
          questions: {
            ...s.questions,
            index: s.questions[index]!.copyWith(optionsLoading: false),
          },
        ),
      ),
    );
  }

  Future<void> answerEntries() {
    final value = _read();
    final offset = value.nextAnswerEntryOffset;
    if (offset == null || value.answerEntriesLoading) {
      return Future<void>.value();
    }
    _update((s) => s.copyWith(answerEntriesLoading: true));
    return _request(InteractionReadSection.answerEntries, (scope) async {
      final page = await scope.answerEntries(offset: offset, limit: 32);
      if (!active) return;
      final headerState = _read().header!.state as ResolvedUserInputRead;
      checkReadPage(
        expectedScope: _read().scope!,
        scope: page.scope,
        requested: offset,
        offset: page.offset,
        total: page.total,
        count: page.items.length,
        next: page.nextOffset,
        expectedTotal: headerState.answerEntryCount,
      );
      final offsets = Map<int, int?>.of(_read().nextAnswerValueOffsets);
      for (final (position, item) in page.items.indexed) {
        if (item.index != offset + position) {
          throw readProtocol('answer-entry-index');
        }
        offsets[item.index] = item.answerCount > 0 ? 0 : null;
      }
      _update(
        (s) => s.copyWith(
          answerEntries: [...s.answerEntries, ...page.items],
          nextAnswerEntryOffset: page.nextOffset,
          nextAnswerValueOffsets: offsets,
          texts: registerReadTexts(
            s.texts,
            page.items.map((item) => item.questionId),
          ),
        ),
      );
    }).whenComplete(
      () => _update((s) => s.copyWith(answerEntriesLoading: false)),
    );
  }

  Future<void> answerValues(int index) {
    final value = _read();
    if (value.answerValueLoading.contains(index)) return Future<void>.value();
    final entry = value.answerEntries
        .where((entry) => entry.index == index)
        .firstOrNull;
    final offset = value.nextAnswerValueOffsets[index];
    if (entry == null || offset == null) return Future<void>.value();
    _update(
      (s) => s.copyWith(answerValueLoading: {...s.answerValueLoading, index}),
    );
    return _request(InteractionReadSection.answerValues, (scope) async {
      final page = await scope.answerValues(index, offset: offset, limit: 32);
      if (!active) return;
      checkReadPage(
        expectedScope: _read().scope!,
        scope: page.scope,
        requested: offset,
        offset: page.offset,
        total: page.total,
        count: page.items.length,
        next: page.nextOffset,
        expectedTotal: entry.answerCount,
      );
      for (final (position, item) in page.items.indexed) {
        if (item.index != offset + position) {
          throw readProtocol('answer-value-index');
        }
      }
      _update(
        (s) => s.copyWith(
          answerValues: {
            ...s.answerValues,
            index: [...?s.answerValues[index], ...page.items],
          },
          nextAnswerValueOffsets: {
            ...s.nextAnswerValueOffsets,
            index: page.nextOffset,
          },
          texts: registerReadTexts(
            s.texts,
            page.items.map((item) => item.value),
          ),
        ),
      );
    }, index: index).whenComplete(
      () => _update(
        (s) => s.copyWith(
          answerValueLoading: {...s.answerValueLoading}..remove(index),
        ),
      ),
    );
  }

  Future<void> text(int fieldId) {
    final progress = _read().texts[fieldId];
    if (progress == null || progress.complete || progress.loading) {
      return Future<void>.value();
    }
    _update(
      (s) => s.copyWith(
        texts: {
          ...s.texts,
          fieldId: progress.copyWith(loading: true, error: null),
        },
      ),
    );
    return _request(InteractionReadSection.text, (scope) async {
      final chunk = await scope.text(
        fieldId,
        offset: progress.loadedUtf8Bytes,
        maxBytes: 65536,
      );
      _update(
        (s) => s.copyWith(
          texts: {...s.texts, fieldId: applyReadChunk(progress, chunk)},
        ),
      );
    }, fieldId: fieldId).whenComplete(
      () => _update(
        (s) => s.copyWith(
          texts: {
            ...s.texts,
            fieldId: s.texts[fieldId]!.copyWith(loading: false),
          },
        ),
      ),
    );
  }

  /// 挂载后的一次性读取准备：HEAD 的 plan/tool dock 直接由 pending 数据驱动，
  /// 用户不必先点“加载”；现役读取是分页的，这里补齐首屏问题、选项与全部身份
  /// 文本，使 dock 的渲染与提交不再被 `readIncomplete` 长期禁用。应答记录
  /// （answer entries）仍按需读取，因为它只在终态结算视图出现。
  /// 每层都带进度守卫，读不到新数据即停止，不排帧、不空转。
  Future<void> readMountData() async {
    if (!active) return;
    if (_read().header == null) await open();
    if (!active) return;
    while (active && _read().nextQuestionOffset != null) {
      final before = _read().nextQuestionOffset;
      await questions();
      if (!active || _read().nextQuestionOffset == before) break;
    }
    for (final index in _read().questions.keys.toList()..sort()) {
      if (!active) return;
      while (active && _read().questions[index]!.nextOptionOffset != null) {
        final before = _read().questions[index]!.nextOptionOffset;
        await options(index);
        if (!active || _read().questions[index]!.nextOptionOffset == before) {
          break;
        }
      }
    }
    for (final fieldId in _read().texts.keys.toList()..sort()) {
      if (!active) return;
      while (active && !_read().texts[fieldId]!.complete) {
        final before = _read().texts[fieldId]!.loadedUtf8Bytes;
        await text(fieldId);
        if (!active ||
            _read().texts[fieldId]!.error != null ||
            (!_read().texts[fieldId]!.complete &&
                _read().texts[fieldId]!.loadedUtf8Bytes == before)) {
          return;
        }
      }
    }
  }

  Future<void> completeRead() async {
    if (!active || _read().completingRead) return;
    _update((s) => s.copyWith(completingRead: true));
    try {
      if (_read().header == null) await open();
      while (active && _read().nextQuestionOffset != null) {
        final before = _read().nextQuestionOffset;
        await questions();
        if (!active || _read().nextQuestionOffset == before) return;
      }
      if (!active) return;
      for (final index in _read().questions.keys.toList()..sort()) {
        while (active && _read().questions[index]!.nextOptionOffset != null) {
          final before = _read().questions[index]!.nextOptionOffset;
          await options(index);
          if (!active || _read().questions[index]!.nextOptionOffset == before) {
            return;
          }
        }
      }
      if (!active) return;
      for (final fieldId in _read().texts.keys.toList()) {
        while (active && !_read().texts[fieldId]!.complete) {
          final before = _read().texts[fieldId]!.loadedUtf8Bytes;
          await text(fieldId);
          if (!active ||
              _read().texts[fieldId]!.error != null ||
              (!_read().texts[fieldId]!.complete &&
                  _read().texts[fieldId]!.loadedUtf8Bytes == before)) {
            return;
          }
        }
      }
    } finally {
      _update((s) => s.copyWith(completingRead: false));
    }
  }

  Future<void> _request(
    InteractionReadSection section,
    Future<void> Function(InteractionReadScope) action, {
    int? index,
    int? fieldId,
  }) {
    if (!active) return Future<void>.value();
    final identity = (section, index, fieldId);
    final running = _requests[identity];
    if (running != null) return running;
    final done = Completer<void>();
    _requests[identity] = done.future;
    _update(
      (s) => s.copyWith(
        readIssues: [
          for (final issue in s.readIssues)
            if ((issue.section, issue.index, issue.fieldId) != identity) issue,
        ],
      ),
    );
    Future<void>(() async {
      try {
        final scope = await _borrow.open();
        if (active) await action(scope);
      } on StudioFailure catch (error) {
        _failed(section, index, fieldId, error);
      } catch (error, stack) {
        readCause = error;
        readTrace = stack;
        _failed(
          section,
          index,
          fieldId,
          const StudioFailure(
            code: StudioFailureCode.internal,
            message: 'The interaction could not be read',
            retryable: false,
            correlationId: 'interaction-read-internal',
          ),
        );
      } finally {
        _requests.remove(identity);
        done.complete();
      }
    });
    return done.future;
  }

  void _failed(
    InteractionReadSection section,
    int? index,
    int? fieldId,
    StudioFailure error,
  ) {
    _update((s) {
      final progress = fieldId == null ? null : s.texts[fieldId];
      final question = section == InteractionReadSection.options
          ? s.questions[index]
          : null;
      return s.copyWith(
        readIssues: [
          ...s.readIssues,
          InteractionReadIssue(
            section: section,
            index: index,
            fieldId: fieldId,
            error: error,
          ),
        ],
        texts: progress == null
            ? s.texts
            : {...s.texts, fieldId!: progress.copyWith(error: error)},
        questions: question == null
            ? s.questions
            : {...s.questions, index!: question.copyWith(optionsError: error)},
        sourceCurrent: error.code == StudioFailureCode.superseded
            ? false
            : s.sourceCurrent,
      );
    });
  }
}
