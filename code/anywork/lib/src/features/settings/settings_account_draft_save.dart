/// 把编辑保存 pending 绑到一次草稿操作，避免旧 ACK/finally 锁住或清掉新草稿。
final class AccountDraftSaveSession {
  int _epoch = 0;
  bool _saving = false;

  bool get isSaving => _saving;

  int begin() {
    _saving = true;
    return ++_epoch;
  }

  bool owns(int epoch) => _saving && epoch == _epoch;

  void succeed(int epoch) {
    if (!owns(epoch)) return;
    _saving = false;
  }

  void fail(int epoch) {
    if (!owns(epoch)) return;
    _saving = false;
  }

  void abandon() {
    _epoch++;
    _saving = false;
  }
}
