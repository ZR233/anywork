/// Actual detail subtrees register distinct presentation demands. A late unmount
/// cannot hide a replacement subtree's demand or start/cancel a domain command.
final class DetailDemand {
  DetailDemand(this._changed);
  final void Function(bool) _changed;
  final Set<Object> _tokens = {};
  bool _sealed = false;
  void Function() begin() {
    if (_sealed) return () {};
    final token = Object();
    final wasEmpty = _tokens.isEmpty;
    _tokens.add(token);
    if (wasEmpty) _changed(true);
    return () {
      if (!_tokens.remove(token)) return;
      if (_tokens.isEmpty && !_sealed) _changed(false);
    };
  }
  void seal() { _sealed = true; _tokens.clear(); }
}
