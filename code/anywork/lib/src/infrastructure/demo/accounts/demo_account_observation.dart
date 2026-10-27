import 'dart:async';

import 'package:anywork_client/accounts_ports.dart';

/// One bounded pull observation over the demo backend's canonical facts.
final class DemoAccountObservation implements AccountDomainObservation {
  DemoAccountObservation({required this.read, required this.onClosed});
  final AccountDomainFrame Function() read;
  final void Function() onClosed;
  bool _dirty = true;
  bool _closed = false;
  bool _settled = false;
  Completer<void>? _changed;
  Future<AccountDomainFrame?>? _inFlight;
  Future<void>? _closing;

  void notify() {
    if (_closed) return;
    _dirty = true;
    final changed = _changed;
    _changed = null;
    changed?.complete();
  }

  @override
  Future<AccountDomainFrame?> next() {
    if (_inFlight != null) {
      return Future.error(StateError('Account next is already in flight'));
    }
    if (_closed) return Future.value(null);
    final work = () async {
      while (!_closed && !_dirty) {
        await (_changed ??= Completer<void>()).future;
      }
      if (_closed) return null;
      _dirty = false;
      return read();
    }();
    _inFlight = work;
    unawaited(
      work.then<void>(
        (_) {
          _inFlight = null;
        },
        onError: (Object _, StackTrace _) {
          _inFlight = null;
        },
      ),
    );
    return work;
  }

  @override
  void requestClose() {
    _closed = true;
    final changed = _changed;
    _changed = null;
    changed?.complete();
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    requestClose();
    final pending = _inFlight;
    if (pending != null) {
      await pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    }
    if (!_settled) {
      _settled = true;
      onClosed();
    }
  }
}
