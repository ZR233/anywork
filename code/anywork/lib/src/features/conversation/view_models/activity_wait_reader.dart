import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../state/read_material.dart';
import 'read_validation.dart';

/// A named child page of the already borrowed Activity scope. The parent
/// presenter, not this page reader, owns that scope's actual close obligation.
final class ActivityWaitReader {
  ActivityWaitReader({required this.scope, required this.total,
    required this.read, required this.publish, required this.current,
    required this.page, required this.text});

  final ReadScopeIdentity scope;
  final int total;
  final ReadMaterial<WaitReadValue, WaitTargetReadItem> Function() read;
  final void Function(ReadMaterial<WaitReadValue, WaitTargetReadItem>) publish;
  final bool Function() current;
  final Future<WaitTargetPage> Function(int offset) page;
  final Future<TextChunk> Function(int field, int offset) text;
  Future<void>? _loading;
  final Map<int, Future<void>> _texts = {};
  bool _retired = false;
  bool get active => !_retired && current();
  void retire() => _retired = true;

  Future<void> load() {
    if (_loading case final running?) return running;
    if (!active || read().nextOffset == null) return Future<void>.value();
    final done = Completer<void>();
    _loading = done.future;
    publish(read().copyWith(loading: true, error: null));
    Future<void>(() async {
      try {
        final before = read();
        final offset = before.nextOffset!;
        final result = await page(offset);
        if (!active) return;
        checkReadPage(expectedScope: scope, scope: result.scope,
          requested: offset, offset: result.offset, total: result.total,
          count: result.items.length, next: result.nextOffset, expectedTotal: total);
        for (final (index, target) in result.items.indexed) {
          if (target.index != offset + index) throw readProtocol('wait-target-index');
        }
        publish(read().copyWith(items: [...before.items, ...result.items],
          nextOffset: result.nextOffset, texts: registerReadTexts(read().texts, [
            for (final target in result.items) ...[
              target.taskId, ?target.toolName, ?target.summary,
            ],
          ])));
      } on StudioFailure catch (error) {
        if (active) publish(read().copyWith(error: error));
      } catch (_) {
        _unexpected();
      } finally {
        if (active) publish(read().copyWith(loading: false));
        _loading = null;
        done.complete();
      }
    });
    return done.future;
  }

  Future<void> loadText(int fieldId) {
    if (_texts[fieldId] case final running?) return running;
    if (!active) return Future<void>.value();
    final progress = read().texts[fieldId];
    if (progress == null || progress.complete) return Future<void>.value();
    final done = Completer<void>();
    _texts[fieldId] = done.future;
    Future<void>(() async {
      try {
        final chunk = await text(fieldId, progress.loadedUtf8Bytes);
        if (active) publish(read().copyWith(texts: {...read().texts,
          fieldId: applyReadChunk(progress, chunk)}));
      } on StudioFailure catch (error) {
        if (active) publish(read().copyWith(error: error));
      } catch (_) {
        _unexpected();
      } finally {
        _texts.remove(fieldId);
        done.complete();
      }
    });
    return done.future;
  }

  void _unexpected() {
    if (active) publish(read().copyWith(error: const StudioFailure(
      code: StudioFailureCode.internal, message: 'The wait targets could not be read',
      retryable: false, correlationId: 'conversation-wait-targets-internal')));
  }
}
