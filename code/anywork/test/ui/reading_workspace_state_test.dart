import 'package:anywork/src/features/shell/reading_workspace_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('新待确认交互全宽打开，重复观察保留关闭、重开和并排选择', () {
    final state = ReadingWorkspaceState<String>();
    void observe() =>
        state.observePlan(identity: 'interaction:first', pending: true);
    observe();
    expect(state.planOpen, isTrue);
    expect(state.mode, ReadingMode.fullWidth);
    state.toggleMode();
    observe();
    expect(state.mode, ReadingMode.sideBySide);
    state.closePlan();
    observe();
    expect(state.readingOpen, isFalse);
    state.openPlan();
    observe();
    expect(state.planOpen, isTrue);
    expect(state.mode, ReadingMode.sideBySide);

    state.observePlan(identity: 'interaction:second', pending: true);
    expect(state.planOpen, isTrue);
    expect(state.mode, ReadingMode.fullWidth);
    state.closePlan();
    state.observePlan(identity: 'interaction:third', pending: true);
    expect(state.planOpen, isTrue);
    expect(state.mode, ReadingMode.fullWidth);
  });

  test('窄窗强制全宽不反向覆盖宽窗选择', () {
    final state = ReadingWorkspaceState<String>()
      ..observePlan(identity: 'interaction:first', pending: true)
      ..toggleMode();
    expect(state.fullWidth(sideBySideFeasible: true), isFalse);
    expect(state.fullWidth(sideBySideFeasible: false), isTrue);
    expect(state.fullWidth(sideBySideFeasible: true), isFalse);
    expect(state.mode, ReadingMode.sideBySide);
  });

  test('计划与文件互斥；重复计划观察不抢占文件，新交互优先', () {
    final state = ReadingWorkspaceState<String>()
      ..observePlan(identity: 'interaction:first', pending: true)
      ..toggleMode()
      ..openFile('notes.md');
    expect(state.planOpen, isFalse);
    expect(state.file, 'notes.md');
    state.observePlan(identity: 'interaction:first', pending: true);
    expect(state.file, 'notes.md');
    state.toggleMode();
    expect(state.mode, ReadingMode.fullWidth);
    state.openPlan();
    expect(state.file, isNull);
    expect(state.mode, ReadingMode.sideBySide);
    state.openFile('second.md');
    expect(state.mode, ReadingMode.sideBySide);
    state.observePlan(identity: 'interaction:second', pending: true);
    expect(state.file, isNull);
    expect(state.planOpen, isTrue);
    expect(state.mode, ReadingMode.fullWidth);
    state.closePlan();
    expect(state.readingOpen, isFalse);
    state.openFile('third.md');
    state.closeFile();
    expect(state.readingOpen, isFalse);
  });

  test('只读计划不会自动打开，身份移除或变化会退休旧阅读选择', () {
    final state = ReadingWorkspaceState<String>()
      ..observePlan(identity: 'plan:1', pending: false);
    expect(state.readingOpen, isFalse);
    state.openPlan();
    expect(state.planOpen, isTrue);
    state.observePlan(identity: 'plan:2', pending: false);
    expect(state.readingOpen, isFalse);
    state.openPlan();
    state.observePlan(identity: null, pending: false);
    state.openPlan();
    expect(state.readingOpen, isFalse);
  });
}
