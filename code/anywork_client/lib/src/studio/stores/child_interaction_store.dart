import '../../../anywork_client.dart' show ReadModel;
import '../../../models.dart';
import '../../models/collection_equality.dart';

/// 主会话可见的子任务待决交互的只读镜像。
///
/// 投影本身没有后端 revision：它由显式读取刷新，因此这里只维护「哪一次读取发布了
/// 当前内容」的本地序号，最新意图胜出；迟到的读取不能覆盖更新的宿主或更新的结果。
final class ChildInteractionStore extends ReadModel<ChildInteractionsState> {
  ChildInteractionStore() : super(const ChildInteractionsState());

  int _sequence = 0;

  /// 捕获一次读取的意图序号；结果必须带上它才能发布。
  int beginRead() => ++_sequence;

  /// 发布一次宿主会话的子交互投影。
  bool apply(
    String hostThreadId,
    List<ChildInteractionSummary> items, {
    required int sequence,
  }) {
    if (sequence < state.sequence) return false;
    final List<ChildInteractionSummary> frozen = List.unmodifiable(items);
    if (state.loaded &&
        state.hostThreadId == hostThreadId &&
        state.sequence == sequence &&
        listEquals(state.items, frozen)) {
      return false;
    }
    state = ChildInteractionsState(
      hostThreadId: hostThreadId,
      items: frozen,
      sequence: sequence,
      loaded: true,
    );
    return true;
  }
}

/// 一个宿主会话当前的子任务待决交互投影。
final class ChildInteractionsState {
  const ChildInteractionsState({
    this.hostThreadId,
    this.items = const [],
    this.sequence = 0,
    this.loaded = false,
  });

  /// 该投影属于哪个主会话；为空表示尚未读取。
  final String? hostThreadId;
  final List<ChildInteractionSummary> items;
  final int sequence;
  final bool loaded;

  /// 一条子任务决议是否已经在原交互事实上生效。
  ///
  /// 只有同一宿主、同一子会话与同一交互编号才有判断资格：交互已消失，或它的
  /// revision 已越过调用方冻结的版本，都说明它不再等待这次决议。
  bool confirmsDecision({
    required String hostThreadId,
    required String childThreadId,
    required String interactionId,
    required int revision,
  }) {
    if (!loaded || this.hostThreadId != hostThreadId) return false;
    for (final item in items) {
      if (item.childThreadId != childThreadId) continue;
      if (item.interactionId != interactionId) continue;
      return item.revision > revision;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChildInteractionsState &&
          hostThreadId == other.hostThreadId &&
          sequence == other.sequence &&
          loaded == other.loaded &&
          listEquals(items, other.items);

  @override
  int get hashCode =>
      Object.hash(hostThreadId, sequence, loaded, Object.hashAll(items));
}
