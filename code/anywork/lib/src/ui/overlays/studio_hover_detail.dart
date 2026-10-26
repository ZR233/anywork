import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';

/// 状态栏共用的详情悬浮表面。
///
/// 内容由官方 [Tooltip.richMessage] 承载：悬停打开、跟随所属控件的 canonical 重建刷新、长内容在
/// 浮层内滚动，并被限制在窗口安全区域内。这里没有第二套菜单状态：点击、长按和键盘激活都不打开、
/// 固定或切换详情，输入焦点始终留在原处；可访问性读数由触发控件的 [Semantics] 提供。
///
/// 富详情沿用官方命中测试：浮层可被指针命中，因此移入浮层后仍保持展开并可滚动长内容，离开触发
/// 控件与浮层都收起。详情可以承载明确的操作按钮；按钮只处理自身操作，浮层开合仍由官方悬停生命周期管理。
class StudioHoverDetail extends StatelessWidget {
  const StudioHoverDetail({
    required this.child,
    required this.detailBuilder,
    this.maxWidth = 356,
    this.semanticsLabel,
    this.semanticsValue,
    super.key,
  });

  /// 触发悬浮的只读读数；不得是需要点击或持有焦点的控件。
  final Widget child;

  /// 详情内容，在浮层内按可用宽度与高度布局。
  final WidgetBuilder detailBuilder;

  /// 详情卡片可见宽度上限（含内边距与边框，不含透明外边距）；窄窗口下按安全边距收窄。
  final double maxWidth;

  final String? semanticsLabel;
  final String? semanticsValue;

  /// 详情卡片与窗口边缘之间的安全距离，也是本组件的显式布局令牌。
  static const _safeMargin = 24.0;

  static const _sidePadding = 14.0;
  static const _paddingTop = 12.0;
  static const _paddingBottom = 14.0;
  static const _contentPadding = EdgeInsets.fromLTRB(
    _sidePadding,
    _paddingTop,
    _sidePadding,
    _paddingBottom,
  );

  /// 卡片细边框宽度；Tooltip 的 decoration border 与这里同源。
  static const _borderWidth = 1.0;

  /// 卡片与窗口边缘之间的透明外边距，由 Tooltip 官方定位在此范围内避让。
  static const _horizontalMargin = 24.0;
  static const _verticalMargin = 12.0;

  /// 内容之外的整份 chrome：上下内边距、上下外边距与上下边框。
  static const _verticalChrome =
      _paddingTop + _paddingBottom + _verticalMargin * 2 + _borderWidth * 2;
  static const _horizontalChrome = _sidePadding * 2 + _borderWidth * 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final viewport = media.size;
    // 可见卡片宽 = 内容 + 内边距 + 边框；Tooltip 的 margin 也计入它的约束，所以外层约束要连同
    // 这份 chrome 与安全距一起留给窗口，内容才不会被压窄。
    final cardWidth = math.max(
      0.0,
      math.min(maxWidth, viewport.width - _horizontalMargin * 2),
    );
    final contentWidth = math.max(0.0, cardWidth - _horizontalChrome);
    final outerWidth = contentWidth + _horizontalChrome + _horizontalMargin * 2;
    // 内容最大高度只扣本组件已声明的 chrome 与安全距：普通 1280×720 窗口一次看完整分区，
    // 更矮的窗口或放大文字由浮层内部有界滚动，不使用任何按窗口高度反推的经验比例。
    final availableHeight = math.max(
      0.0,
      viewport.height - _verticalChrome - _safeMargin * 2,
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      value: semanticsValue,
      // 外层 Text.rich 会按 textScaler 二次放大 WidgetSpan 的几何尺寸，而触发读数与详情文本都应
      // 只按用户设置缩放一次。这里关掉外层富文本的几何缩放，并在两棵子树里各自恢复原始
      // MediaQuery，尺寸预算因此就是真实逻辑像素。
      child: MediaQuery.withNoTextScaling(
        child: Tooltip(
          richMessage: WidgetSpan(
            child: MediaQuery(
              data: media,
              child: Builder(
                builder: (context) => ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: contentWidth,
                    maxWidth: contentWidth,
                    maxHeight: availableHeight,
                  ),
                  child: SingleChildScrollView(child: detailBuilder(context)),
                ),
              ),
            ),
          ),
          constraints: BoxConstraints(maxWidth: outerWidth),
          padding: _contentPadding,
          margin: const EdgeInsets.symmetric(
            horizontal: _horizontalMargin,
            vertical: _verticalMargin,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(
              color: colors.outlineVariant,
              width: _borderWidth,
            ),
            borderRadius: BorderRadius.circular(StudioRadii.sm),
            boxShadow: StudioShadows.soft(colors.shadow),
          ),
          preferBelow: true,
          verticalOffset: 10,
          waitDuration: const Duration(milliseconds: 120),
          exitDuration: const Duration(milliseconds: 80),
          // 只读读数：长按和点击都不展开，也不会因点击而关闭别的输入上下文。
          triggerMode: TooltipTriggerMode.manual,
          enableTapToDismiss: false,
          // 富详情需要原生指针命中才能在浮层内滚动，并由官方悬浮区域保持展开；
          // 短文本提示与侧栏提示仍使用各自的原生默认。
          ignorePointer: false,
          excludeFromSemantics: true,
          child: MediaQuery(data: media, child: child),
        ),
      ),
    );
  }
}
