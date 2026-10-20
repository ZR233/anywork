/// 驱动与验收脚本使用的键值字符串。
///
/// 本文件**只依赖 Dart**：宿主机侧 driver 脚本（`test_driver/*.dart`）在纯 Dart VM
/// 中编译，任何 `package:flutter` 依赖都会因为缺少 `dart:ui` 而编译失败。Flutter 侧
/// 的 `StudioDriverKeys` 从同一常量构造 `ValueKey`，因此键值只有这一份事实源；
/// driver 脚本需要新的键时，把字符串加进这里并在 `StudioDriverKeys` 中引用。
library;

import 'package:anywork_client/models.dart';

abstract final class StudioDriverKeyValues {
  static const shell = 'studio-shell';
  static const startPage = 'studio-start-page';
  static const threadPreparation = 'thread-preparation';
  static const threadPreparationDetails = 'thread-preparation-details';
  static String threadPreparationStage(ThreadPreparationStage stage) =>
      'thread-preparation-${stage.name}';
  static const newSession = 'sidebar-new-session';
  static const sidebarResize = 'sidebar-resize';
  static const settingsBack = 'settings-back';
  static const sessionMode = 'session-mode-selector';
  static const sessionModeLabel = 'session-mode-label';
  static const startPageSelectors = 'start-page-selectors';
  static const reasoningEffort = 'reasoning-effort-selector';
  static const reasoningEffortLabel = 'reasoning-effort-label';

  static String sessionModeOption(String mode) => 'session-mode-$mode';

  static String reasoningEffortOption(String effort) =>
      'reasoning-effort-$effort';

  /// Timeline 的稳定操作与详情入口（canonical item + typed field 寻址）。
  static const timelineScrollable = 'timeline-scrollable';
  static const timelineLoadingOlder = 'timeline-loading-older';
  static const timelineRetryOlder = 'timeline-retry-older';
  static const timelineReturnLive = 'timeline-return-live';
  static const timelineNewOutput = 'timeline-new-output';
  static const timelineDetailDialog = 'timeline-detail-dialog';
  static const timelineDetailText = 'timeline-detail-text';
  static const timelineDetailCopy = 'timeline-detail-copy';
  static const timelineDetailClose = 'timeline-detail-close';
  static const timelineDetailRetry = 'timeline-detail-retry';
  static const timelineDetailTerminal = 'timeline-detail-terminal';
  static const timelineConnectionNotice = 'timeline-connection-notice';
  static const timelineRetryConnection = 'timeline-retry-connection';

  static String timelineRow(String id) => 'timeline-row-$id';
  static String timelineDetailOpen(String id, String field) =>
      'timeline-detail-open-$id-$field';

  /// 一个 typed 内容字段的稳定诊断 token（design/26 §26.9）。
  ///
  /// 展示层按钮 key 与 Driver 投影共用这一个入口：不按 `record.toString()`、类型名或两份
  /// switch 镜像生成身份。同类字段靠判别分支 + 逻辑索引区分，独立解码的同值字段得到同一
  /// token；问答的 header/question/answer/option 各自独立，不折叠成同一个 `user-input-N`。
  static String timelineDetailField(ThreadContentFieldView field) =>
      switch (field) {
        ThreadTextFieldView() => 'text',
        ThreadThinkingSummaryFieldView(:final chunkIndex) =>
          'thinking-summary-$chunkIndex',
        ThreadThinkingContentFieldView(:final chunkIndex) =>
          'thinking-content-$chunkIndex',
        ThreadToolArgumentsFieldView() => 'tool-arguments',
        ThreadToolResultFieldView() => 'tool-result',
        ThreadToolOutputArtifactsFieldView() => 'tool-artifacts',
        ThreadRawPayloadFieldView(:final payloadIndex) =>
          'raw-payload-$payloadIndex',
        ThreadToolUserInputFieldView(:final questionIndex, :final part) =>
          'user-input-$questionIndex-${userInputPartToken(part)}',
      };

  /// 问答正文域的一段：与后端 `BridgeThreadUserInputFieldPart` 一一对应。
  static String userInputPartToken(ThreadUserInputFieldPartView part) =>
      switch (part) {
        ThreadUserInputHeaderFieldPartView() => 'header',
        ThreadUserInputQuestionFieldPartView() => 'question',
        ThreadUserInputAnswerFieldPartView(:final answerIndex) =>
          'answer-$answerIndex',
        ThreadUserInputOptionLabelFieldPartView(:final optionIndex) =>
          'option-label-$optionIndex',
        ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) =>
          'option-description-$optionIndex',
      };
}
