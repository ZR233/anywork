import 'dart:async';

import 'package:anywork_client/resources.dart';

import '../state/read_material.dart';
import 'read_scope_borrow.dart';
import 'read_validation.dart';

typedef ReadPageResult<I> = ({ReadScopeIdentity scope, int offset, int total, List<I> items, int? nextOffset});

/// Shared presentation mechanics only: each instance has one concrete D1 scope
/// and one VM-owned material value. DTOs stay typed; no generic wire/value DOM.
final class ScopedReadPresenter<S, H, I> {
  ScopedReadPresenter({
    required ReadScopeBorrow<S> borrow,
    required ReadMaterial<H, I> Function() read,
    required void Function(ReadMaterial<H, I>) publish,
    required Future<H> Function(S) header,
    required ReadScopeIdentity Function(H) scopeOf,
    required Iterable<ReadText> Function(H) headerTexts,
    required Future<TextChunk> Function(S, int, int) text,
    required bool Function() current,
    int Function(H)? total,
    Future<ReadPageResult<I>> Function(S, int)? page,
    Iterable<ReadText> Function(I)? itemTexts,
    int Function(I)? indexOf,
  }) : _borrow = borrow, _read = read, _publish = publish, _header = header,
       _scopeOf = scopeOf, _headerTexts = headerTexts, _text = text, _current = current,
       _total = total, _page = page, _itemTexts = itemTexts, _indexOf = indexOf;
  final ReadScopeBorrow<S> _borrow;
  final ReadMaterial<H, I> Function() _read;
  final void Function(ReadMaterial<H, I>) _publish;
  final Future<H> Function(S) _header;
  final ReadScopeIdentity Function(H) _scopeOf;
  final Iterable<ReadText> Function(H) _headerTexts;
  final Future<TextChunk> Function(S, int, int) _text;
  final bool Function() _current;
  final int Function(H)? _total;
  final Future<ReadPageResult<I>> Function(S, int)? _page;
  final Iterable<ReadText> Function(I)? _itemTexts;
  final int Function(I)? _indexOf;
  Future<void>? _loading;
  final Map<int, Future<void>> _texts = {};
  Object? failureCause;
  StackTrace? failureTrace;
  bool get active => !_borrow.retired && _current();
  void retire() => _borrow.retire();

  /// A sibling named read borrows this exact immutable scope. It does not gain
  /// a second close/permit owner; retiring this presenter seals all such reads.
  Future<R> query<R>(Future<R> Function(S) read) async {
    if (!active) throw _retired;
    final scope = await _borrow.open();
    if (!active) throw _retired;
    return read(scope);
  }

  static const _retired = StudioFailure(code: StudioFailureCode.cancelled,
    message: 'The conversation read is retired', retryable: false,
    correlationId: 'conversation-read-retired');

  Future<void> load() {
    final running = _loading;
    if (running != null) return running;
    if (!active) return Future<void>.value();
    final done = Completer<void>();
    _loading = done.future;
    _publish(_read().copyWith(loading: true, error: null));
    Future<void>.sync(_load).then<void>((_) { _loading = null; done.complete(); },
      onError: (Object error, StackTrace stack) {
        _unexpected(error, stack); _loading = null; done.complete();
      });
    return done.future;
  }

  Future<void> _load() async {
    try {
      final scope = await _borrow.open();
      if (!active) return;
      if (_read().header == null) {
        final header = await _header(scope);
        if (!active) return;
        final count = _total?.call(header) ?? 0;
        if (count < 0) throw readProtocol('material-count');
        _publish(ReadMaterial(header: header, texts: registerReadTexts({}, _headerTexts(header)),
          nextOffset: count > 0 ? 0 : null, loading: true));
      }
      if (!active || _page == null || _read().nextOffset == null) return;
      final before = _read();
      final offset = before.nextOffset!;
      final result = await _page(scope, offset);
      if (!active) return;
      checkReadPage(expectedScope: _scopeOf(before.header as H), scope: result.scope,
        requested: offset, offset: result.offset, total: result.total,
        count: result.items.length, next: result.nextOffset,
        expectedTotal: _total?.call(before.header as H));
      if (_indexOf != null) {
        for (final (index, item) in result.items.indexed) {
          if (_indexOf(item) != offset + index) throw readProtocol('material-index');
        }
      }
      final texts = registerReadTexts(_read().texts, [
        if (_itemTexts != null) for (final item in result.items) ..._itemTexts(item),
      ]);
      _publish(_read().copyWith(items: [...before.items, ...result.items],
        nextOffset: result.nextOffset, texts: texts));
    } on StudioFailure catch (error) {
      if (active) _publish(_read().copyWith(error: error));
    } finally {
      if (active) _publish(_read().copyWith(loading: false));
    }
  }

  Future<void> loadText(int fieldId) {
    final running = _texts[fieldId];
    if (running != null) return running;
    if (!active) return Future<void>.value();
    final progress = _read().texts[fieldId];
    if (progress == null || progress.complete) return Future<void>.value();
    final done = Completer<void>();
    _texts[fieldId] = done.future;
    Future<void>(() async {
      try {
        final scope = await _borrow.open();
        if (!active) return;
        final chunk = await _text(scope, fieldId, progress.loadedUtf8Bytes);
        if (active) _publish(_read().copyWith(texts: {..._read().texts,
          fieldId: applyReadChunk(progress, chunk)}));
      } on StudioFailure catch (error) {
        if (active) _publish(_read().copyWith(error: error));
      } catch (error, stack) { _unexpected(error, stack); }
      finally { _texts.remove(fieldId); done.complete(); }
    });
    return done.future;
  }

  void _unexpected(Object error, StackTrace stack) {
    failureCause = error; failureTrace = stack;
    if (active) _publish(_read().copyWith(loading: false,
      error: const StudioFailure(code: StudioFailureCode.internal,
        message: 'The conversation detail could not be read', retryable: false,
        correlationId: 'conversation-detail-internal')));
  }
}
