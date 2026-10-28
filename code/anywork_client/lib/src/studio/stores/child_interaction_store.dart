import '../../../anywork_client.dart' show ReadModel, ValueObservation;
import '../../../models.dart';
import '../../models/collection_equality.dart';

/// 主会话可见的子任务待决交互的只读镜像。
///
/// 投影本身没有后端 revision：它由显式读取刷新，因此这里只维护「哪一次读取发布了
/// 当前内容」的本地序号，最新意图胜出；迟到的读取不能覆盖更新的宿主或更新的结果。
abstract interface class ChildInteractionsView {
  ChildInteractionsState get state;
  ValueObservation<ChildInteractionsState> get source;
}

final class ChildInteractionStore extends ReadModel<ChildInteractionsState>
    implements ChildInteractionsView {
  ChildInteractionStore() : super(const ChildInteractionsState());

  int _sequence = 0;

  /// 只撤销展示资格；导航不是 canonical 查询结果或决议观察事实。
  void setVisibleHostThread(String? threadId) {
    final current = state;
    if (current.visibleHostThreadId == threadId) return;
    state = ChildInteractionsState(
      hostThreadId: current.hostThreadId,
      items: current.items,
      sequence: current.sequence,
      loaded: current.loaded,
      visibleHostThreadId: threadId,
      displayGeneration: current.displayGeneration + 1,
      readDisplayGeneration: current.readDisplayGeneration,
    );
  }

  /// 在任何异步派发前捕获读取意图和展示代次。
  ({int sequence, int displayGeneration}) beginRead() =>
      (sequence: ++_sequence, displayGeneration: state.displayGeneration);

  /// 发布一次宿主会话的子交互投影。
  bool apply(
    String hostThreadId,
    List<ChildInteractionSummary> items, {
    required int sequence,
    required int readDisplayGeneration,
  }) {
    if (sequence != _sequence) return false;
    final List<ChildInteractionSummary> frozen = List.unmodifiable(items);
    if (state.loaded &&
        state.hostThreadId == hostThreadId &&
        state.sequence == sequence &&
        state.readDisplayGeneration == readDisplayGeneration &&
        listEquals(state.items, frozen)) {
      return false;
    }
    state = ChildInteractionsState(
      hostThreadId: hostThreadId,
      items: frozen,
      sequence: sequence,
      loaded: true,
      visibleHostThreadId: state.visibleHostThreadId,
      displayGeneration: state.displayGeneration,
      readDisplayGeneration: readDisplayGeneration,
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
    this.visibleHostThreadId,
    this.displayGeneration = 0,
    this.readDisplayGeneration,
  });

  /// 该投影属于哪个主会话；为空表示尚未读取。
  final String? hostThreadId;
  final List<ChildInteractionSummary> items;
  final int sequence;
  final bool loaded;
  final String? visibleHostThreadId;
  final int displayGeneration;
  final int? readDisplayGeneration;

  /// 只有当前可见宿主、当前展示代次的真实查询结果才可呈现。
  List<ChildInteractionSummary> get visibleItems =>
      loaded &&
          hostThreadId == visibleHostThreadId &&
          readDisplayGeneration == displayGeneration
      ? items
      : const [];

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
          visibleHostThreadId == other.visibleHostThreadId &&
          displayGeneration == other.displayGeneration &&
          readDisplayGeneration == other.readDisplayGeneration &&
          listEquals(items, other.items);

  @override
  int get hashCode => Object.hash(
    hostThreadId,
    sequence,
    loaded,
    visibleHostThreadId,
    displayGeneration,
    readDisplayGeneration,
    Object.hashAll(items),
  );
}
