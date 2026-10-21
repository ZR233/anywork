part of 'timeline_view.dart';

enum _MarkdownSurface { assistant, user, panel, reasoning, error }

// 原始字符串（r''）把 \r \n \\ \[ \] 作为**转义**交给 RegExp，因此这里匹配真实 CR/LF、
// 反斜杠与 markdown 符号（反引号、* _ [ ] ( ) # > ~ ! |），而不是字母 r/n；含换行的
// 正文因此走 Markdown 分支。非原始字符串里 \r/\n 会变成真实控制字符、\[ 还会成为非法
// 转义，所以这里必须保持 raw。
final RegExp _streamingMarkdownSyntax = RegExp(r'[\r\n\\`*_\[\]()#>~!|]');

class _AgentMarkdown extends ConsumerStatefulWidget {
  const _AgentMarkdown({
    required this.id,
    required this.text,
    required this.surface,
  });

  final String id;
  final String text;
  final _MarkdownSurface surface;

  @override
  ConsumerState<_AgentMarkdown> createState() => _AgentMarkdownState();
}

class _AgentMarkdownState extends ConsumerState<_AgentMarkdown> {
  GptMarkdownThemeData? _headingTheme;

  @override
  Widget build(BuildContext context) {
    final _AgentMarkdown(:id, :text, :surface) = widget;
    final plainText =
        !_streamingMarkdownSyntax.hasMatch(text) &&
        !text.contains('://') &&
        !text.contains('www.');
    if (plainText) {
      return _PlainBodyText(
        key: ValueKey('plain-$id'),
        id: id,
        text: text,
        surface: surface,
      );
    }
    final repaired = repairAgentMarkdownForDisplay(text);
    final imageAlts = repaired.contains('![')
        ? _markdownImageAlts(repaired)
        : const <String, String>{};
    final scheme = Theme.of(context).colorScheme;
    final onUserSurface = surface == _MarkdownSurface.user;
    final headingTheme = GptMarkdownTheme.of(context).copyWith(
      h1: _timelineHeadingStyle(context, surface, 2.0),
      h2: _timelineHeadingStyle(context, surface, 1.5),
      h3: _timelineHeadingStyle(context, surface, 1.25),
      h4: _timelineHeadingStyle(context, surface, 1.0),
      h5: _timelineHeadingStyle(context, surface, 0.875),
      h6: _timelineHeadingStyle(context, surface, 0.85),
    );
    // The package notifies dependants by theme identity. Retain an equivalent
    // configuration so unrelated window updates do not discard its text caches.
    if (_headingTheme?.isSame(headingTheme) != true) {
      _headingTheme = headingTheme;
    }
    return GptMarkdownTheme(
      // VS Code 预览的标题阶梯：全部 w600、line-height 1.25，字级按正文字号
      // 相对递进（2/1.5/1.25/1/0.875/0.85em）。只能在 GptMarkdownThemeData
      // 上按级提供；用局部 InheritedWidget 覆盖，不改动全局主题。
      gptThemeData: _headingTheme!,
      child: GptMarkdown(
        repaired,
        key: ValueKey('gpt-markdown-$id'),
        style: _markdownBodyStyle(context, surface),
        styleSheet: GptMarkdownStyleSheet(
          blockQuote: BlockQuoteStyle(
            textStyle: TextStyle(
              color: context.colors.onSurfaceVariant,
              height: 1.57,
            ),
          ),
          heading: HeadingStyle(
            // 仅做随表面的语义色覆盖；节奏与 H1/H2 分隔线由 headingBuilder 提供。
            textStyle: switch (surface) {
              _MarkdownSurface.reasoning => TextStyle(
                color: context.colors.onSurfaceVariant,
              ),
              _MarkdownSurface.error => TextStyle(color: scheme.error),
              _ => null,
            },
          ),
          list: ListStyle(
            // 有序/无序列表统一标记距离；标记色弱化，正文保持主导。
            indent: 8,
            gapAfterMarker: 8,
            bulletColor: scheme.onSurfaceVariant,
            markerTextStyle: TextStyle(
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          table: TableStyle(
            // 原生列宽分配在阅读列内折行，短列保留内容宽度，长代码也能断行。
            overflow: TableOverflow.wrap,
            borderColor: scheme.outlineVariant,
            headerBackground: scheme.surfaceContainerLow,
            headerTextStyle: const TextStyle(fontWeight: FontWeight.w600),
            cellPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
        headingBuilder: (context, level, content, style) {
          final bodySize = _markdownBodyStyle(context, surface)?.fontSize ?? 14;
          // VS Code 预览节奏：块间空行承担约一段距（≈1.15em），标题只补
          // margin-top 24px（相对正文 ≈1.7em）；H3-H6 底距交还空行节奏。
          // H1/H2 自带 0.3em 底距与 1px 轻分隔线（padding 在线之上）。
          // 选择顺序：标题整树包 _HeadingSelectionUnit 作为块级选择单元，
          // 外层选择区域见块级边界而非窄标题文本盒，几何排序不再因文本
          // 盒 top 偏移把标题排到后续正文之后（复制错序）。
          final topPadding = bodySize * 24 / 14;
          final Widget heading;
          if (level > 2) {
            heading = LayoutBuilder(
              builder: (context, constraints) {
                // 有界阅读列内标题占满列宽，块级选择边界覆盖整行；
                // 无界约束保持内容宽度，避免 infinity 布局错误。
                return constraints.hasBoundedWidth
                    ? SizedBox(width: double.infinity, child: content)
                    : content;
              },
            );
          } else {
            final headingSize = bodySize * (level == 1 ? 2.0 : 1.5);
            heading = LayoutBuilder(
              builder: (context, constraints) {
                final rule = DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: headingSize * 0.3),
                    child: content,
                  ),
                );
                // 有界阅读列内底线占满列宽、内容保持起始对齐；
                // 无界约束保持内容宽度，避免 infinity 布局错误。
                return constraints.hasBoundedWidth
                    ? SizedBox(width: double.infinity, child: rule)
                    : rule;
              },
            );
          }
          return _HeadingSelectionUnit(
            child: Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: heading,
            ),
          );
        },
        onLinkTap: (url, _) {
          unawaited(_openTimelineWebLink(context, ref, url));
        },
        inlineLinkBuilder: (link) => safeExternalWebUrl(link.url) == null
            ? TextSpan(children: link.labelSpans, style: link.style)
            : link.defaultSpan(),
        inlineCodeStyle: InlineCodeStyle(
          // 与其他代码表面共用包注册字体，中文缺失字形由系统回退。
          fontFamily: studioCodeFontFamily,
          fontSizeFactor: 1.0,
          color: scheme.onSurface,
          backgroundColor: onUserSurface
              ? scheme.surfaceContainerLowest
              : scheme.surfaceContainerLow,
          // 只用轻底色区分，去掉描边和加粗，避免打断中文阅读基线。
          borderWidth: 0,
          borderRadius: Radius.circular(5),
          padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
        ),
        // VS Code 预览引用：常规左侧线 + 低对比背景，无垂直外边距
        // （块间空行已承担节奏），内边距 0 16 0 10、小圆角。
        blockQuoteBuilder: (context, content, style) => LayoutBuilder(
          builder: (context, constraints) {
            final card = DecoratedBox(
              key: const ValueKey('studio-markdown-quote'),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: BorderDirectional(
                  start: BorderSide(color: scheme.outlineVariant, width: 5),
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 16, 0),
                child: content,
              ),
            );
            // 宽度有界时占满可用宽度，与其他块级内容右边缘对齐；
            // 无界约束（如横向滚动内）保持内容宽度，避免 infinity 布局错误。
            return constraints.hasBoundedWidth
                ? SizedBox(width: double.infinity, child: card)
                : card;
          },
        ),
        imageBuilder: (context, url, _, _) =>
            _studioMarkdownImage(context, url, imageAlts[url] ?? '', surface),
        codeBuilder: (context, name, code, closed) {
          final scheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          // VS Code 预览代码区：低对比背景 + 1px 边框，不显示语言栏；
          // 垂直节奏交还块间空行。
          final codeBackground = onUserSurface
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLow;
          final bodyStyle = surface == _MarkdownSurface.reasoning
              ? textTheme.bodySmall
              : textTheme.bodyMedium;
          return StudioCodeBlock(
            text: code,
            horizontalScroll: false,
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(16),
            backgroundColor: codeBackground,
            borderColor: scheme.outlineVariant,
            borderRadius: const Radius.circular(StudioRadii.sm),
            textStyle: bodyStyle?.copyWith(
              color: surface == _MarkdownSurface.reasoning
                  ? context.colors.onSurfaceVariant
                  : surface == _MarkdownSurface.error
                  ? scheme.error
                  : scheme.onSurface,
              fontSize: bodyStyle.fontSize ?? 14,
              height: 1.36,
            ),
          );
        },
      ),
    );
  }

  /// VS Code 预览标题：相对所在 surface 正文字号的递进字级（em），
  /// 全部 w600、line-height 1.25；从全局正文字体派生保持家族继承。
  TextStyle? _timelineHeadingStyle(
    BuildContext context,
    _MarkdownSurface surface,
    double em,
  ) {
    final bodySize = _markdownBodyStyle(context, surface)?.fontSize ?? 14;
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: bodySize * em,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }
}

/// 标题的块级选择单元：内层标题文本注册到局部
/// [StaticSelectionContainerDelegate]，外层选择区域只见 [SelectionContainer]
/// 的 RenderBox 边界（paintBounds，覆盖标题完整 padding 与底线），而不是
/// 窄标题文本盒——几何选择排序因此把标题当作与后续正文平级的块单元，
/// 不会因文本盒 top 偏移把标题排到正文之后（复制错序）。标题仍参与外层
/// 连续选择：委托嵌套是 SDK 官方用法（SelectableRegion 自身即用
/// SelectionContainer 嵌套委托），不通过独立文本编辑控件隔离标题，也不
/// 改变全局选择排序。
class _HeadingSelectionUnit extends StatefulWidget {
  const _HeadingSelectionUnit({required this.child});

  final Widget child;

  @override
  State<_HeadingSelectionUnit> createState() => _HeadingSelectionUnitState();
}

class _HeadingSelectionUnitState extends State<_HeadingSelectionUnit> {
  // State 拥有 delegate 生命周期（create once / dispose），与 SDK
  // SelectionListenerContainer 同构：SelectionContainer 自身 dispose 时
  // 只清理引用，不负责销毁 delegate。
  final StaticSelectionContainerDelegate _delegate =
      StaticSelectionContainerDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

/// 纯文本正文的**分块**渲染（只对超长、纯 LTR 的普通正文生效）。
///
/// 背景与归因：`main26-ui19-large/stress-body-report.json` 记录了 640K 单段纯文本正文
/// 出现 155ms 帧。把这些帧归因于"纯文本分支用单个 [Text]、每来一个增量都对整段做一次
/// 段落布局"是**可证推断**（该正文不含 markdown 语法、确实走单个 [Text]，段落布局成本随
/// 正文长度增长），不是已做 profile 的结论。
///
/// 用固定的完整测量窗确定分区，一次处理本次正文的全部可封存前缀。流式追加与全量重开
/// 得到相同分区，未变正文不会因无关 build 继续切块。每块复用同一个 [Text] 实例，追加时
/// 只布局新增块与尾块；精确前缀验证仍随已有正文长度增长，首次快照仍需 O(n) 排版。
///
/// native 验收证明：相同声明样式的超长段落与短段落仍可能量出不同的字符宽度，因此不能
/// 以“切在一次测量的行起点”推断任意段长下的可见换行都相同。稳定阅读依赖确定分区，
/// 而不是让一个巨型尾段在后续 rebuild 中逐步改变分区。
///
/// 收益是**有条件的**：
/// - **整体退回单个 [Text]**：方向不是 LTR，或当前正文（未封存后缀）含 RTL/bidi 控制
///   字符——此时已封存前缀也会被清掉，不留"已分块前缀 + 风险正文"。
/// - **只是不再新增块**：测量窗内量不出安全断点（单个超长无空白 run、CJK 无空格断行、
///   缩进续行等）时保留已封存前缀 + 单个尾块 [Text]；尾块仍从已确定的分区起点开始，
///   收益到此为止——这种情况不等于整体回退，不伪称"O(尾块)"覆盖所有正文。
///
/// 正确性约束：
///
/// - 断点取自 [TextPainter] 在**有界测量窗**内、用**同一 style/宽度/TextScaler/方向/
///   locale** 量出的候选行起点，且要求上一行以空白结束、下一行以非空白开始。每次使用
///   完整的同长窗口，尾块不足一个窗口时不封存；块内文本顺序拼接仍等于原文，不插换行、
///   不丢空白、不截尾。
/// - 这里不证明所有 Text 继承参数下与单段排版等价：bold/spacing overrides、THB、
///   softWrap/maxLines/widthBasis 仍由 Text 应用；原生阅读与复制验证的范围单独记录。
/// - 只有整个上一版正文逐字未变或严格追加时复用；非追加 Replace 整体重算，包括缩短或
///   只修改断点之后的 lookahead。不能只检查已封存字节，否则重开可能得到另一分区。
/// - 复用前还对**本次 canonical 正文**做一次风险判定：已封存前缀由逐字校验证明未变（且
///   当初是在无风险判定下封存的），未封存后缀整段扫描，因此不会漏掉短于阈值的尾巴或
///   Replace 进尾巴的风险字符。
/// - 跨多个 [Text]（各自一个 RenderParagraph）的 `SelectionArea` 复制内容按 SDK 契约
///   直接顺序拼接各 Selectable 的 plainText、不插分隔（`widgets/selectable_region.dart`
///   的 `getSelectedContent`），因此应与整段一致；该契约与真机的选择手柄/复制表现仍需实机
///   确认，这里不当作已验证结论。
/// - 缓存与正文同源、与 [id] 绑定：换会话/换条目、正文被替换、宽度/文字缩放/方向/locale
///   变化时整体失效重建，不产生第二份正文事实源；缓存随当前正文线性增长，不累积旧版本。
class _PlainBodyText extends StatefulWidget {
  const _PlainBodyText({
    required this.id,
    required this.text,
    required this.surface,
    super.key,
  });

  final String id;
  final String text;
  final _MarkdownSurface surface;

  @override
  State<_PlainBodyText> createState() => _PlainBodyTextState();
}

class _PlainBodyTextState extends State<_PlainBodyText> {
  /// 单个块的期望上限（字符）：断点在不超过它的前提下尽可能靠近。
  static const _sealTargetCharacters = 4096;

  /// 固定测量窗（目标块长 + 尾部上下文）：每次 [TextPainter] 测量有界，同一前缀的分区
  /// 不依赖正文到达批次；不据此推断不同段长的原生排版必然相同。
  static const _sealMeasureCharacters = 6144;

  final List<Text> _sealed = <Text>[];
  int _sealedEnd = 0;
  double? _width;
  TextScaler? _textScaler;
  TextDirection? _textDirection;
  TextStyle? _style;
  Locale? _locale;

  /// 最近一次"未封存后缀是否含 RTL/bidi"判定的结果；只在同一 String 实例且起点相同时复用，
  /// 因此任何内容变化都会重新整段扫描（不采样）。
  String? _riskText;
  int _riskStart = 0;
  bool _riskVerdict = false;

  /// 上一次已验证的 canonical 正文。同一实例可直接复用；其他实例须精确比较完整前缀，
  /// 非追加替换则使全部分区失效。
  String? _validatedText;
  String? _validatedId;

  void _resetSealed() {
    _sealed.clear();
    _sealedEnd = 0;
    _validatedText = null;
    _riskText = null;
  }

  /// 完整比较上一版正文，同时保留每块当时的测量 lookahead。
  bool _canReuseSealed(String text) {
    final validatedText = _validatedText;
    return validatedText == null ||
        identical(validatedText, text) ||
        text.startsWith(validatedText);
  }

  @override
  Widget build(BuildContext context) {
    final bodyStyle = _markdownBodyStyle(context, widget.surface);
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(bodyStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_validatedId != widget.id) {
          _resetSealed();
          _riskText = null;
          _validatedId = widget.id;
        }
        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final locale = Localizations.maybeLocaleOf(context);
        final width = constraints.maxWidth;
        // TextScaler 可以是非线性的，不能用 scale(1) 之类的单一因子代表它；框架约定
        // [TextScaler.==] 用于判断文本控件是否需要重建，这里按实际 TextScaler 值失效。
        if (_width != width ||
            _textScaler != textScaler ||
            _textDirection != textDirection ||
            _style != effectiveStyle ||
            _locale != locale) {
          _width = width;
          _textScaler = textScaler;
          _textDirection = textDirection;
          _style = effectiveStyle;
          _locale = locale;
          _resetSealed();
        }
        if (!_canReuseSealed(widget.text)) {
          _resetSealed();
        }
        _validatedText = widget.text;
        // 复用前对**本次 canonical 正文**做风险判定，而不是只看测量窗：已封存前缀由上面的
        // 逐字校验证明未变（且它是在"当时无风险"的判定下才封存的），未封存后缀在这里整段
        // 扫描——因此不会漏掉短于阈值的尾巴，也不会漏掉 Replace 到尾巴里的风险字符。
        // 方向不是 LTR 或后缀命中 RTL/bidi 时，已封存前缀同样要清掉，整体退回单个 [Text]。
        final chunkable =
            textDirection == TextDirection.ltr &&
            !_suffixHasBidiRisk(widget.text, _sealedEnd);
        if (!chunkable) {
          if (_sealed.isNotEmpty) {
            _resetSealed();
          }
        } else {
          _seal(
            width: width,
            style: effectiveStyle,
            textScaler: textScaler,
            textDirection: textDirection,
            locale: locale,
          );
        }
        final open = widget.text.substring(_sealedEnd);
        final children = <Widget>[
          ..._sealed,
          if (open.isNotEmpty)
            Text(
              open,
              key: ValueKey('plain-open-${widget.id}'),
              style: bodyStyle,
            ),
        ];
        if (children.isEmpty) {
          return const SizedBox.shrink();
        }
        final content = children.length == 1
            ? children.single
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              );
        return content;
      },
    );
  }

  /// 固定完整窗口保证分区与正文的到达批次和 build 次数无关。
  void _seal({
    required double width,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required Locale? locale,
  }) {
    if (!width.isFinite || width <= 0) return;
    while (widget.text.length - _sealedEnd >= _sealMeasureCharacters) {
      // 不逐次复制整个剩余尾串；每个测量窗与新块均有界。
      final window = widget.text.substring(
        _sealedEnd,
        _sealedEnd + _sealMeasureCharacters,
      );
      final boundary = _sealBoundary(
        window,
        width: width,
        style: style,
        textScaler: textScaler,
        textDirection: textDirection,
        locale: locale,
      );
      // 无安全边界时保留单个尾块，不声称所有正文都有块长上限。
      if (boundary <= 0) return;
      final chunkText = window.substring(0, boundary);
      _sealed.add(
        Text(
          chunkText,
          key: ValueKey('plain-chunk-${widget.id}-${_sealed.length}'),
          style: _markdownBodyStyle(context, widget.surface),
        ),
      );
      _sealedEnd += boundary;
    }
  }

  /// [window] 内的候选切分位置（测量窗口的换行点），量不出时返回 0。
  ///
  /// 只读取完整固定 [window]，既不依赖尚未到达的正文，也不构造巨型尾串。
  ///
  /// 行首用 [TextPainter.getPositionForOffset] 用同一 style/宽度/TextScaler/方向/locale
  /// 量出。优先取不超过 [_sealTargetCharacters] 的
  /// 最后一个安全边界；窗口内没有这样的边界时退到最后一个安全边界（仍然有界）。
  int _sealBoundary(
    String window, {
    required double width,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required Locale? locale,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: window, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      textAlign: TextAlign.start,
      locale: locale,
    )..layout(maxWidth: width);
    try {
      final metrics = painter.computeLineMetrics();
      if (metrics.length <= 1) return 0;
      // 只有 LTR 会走到这里，行首取左边缘。
      final starts = <int>[0];
      for (final metric in metrics) {
        final offset = painter
            .getPositionForOffset(Offset(0, metric.baseline))
            .offset;
        if (offset <= 0 || offset >= window.length) continue;
        if (starts.last != offset) starts.add(offset);
      }
      // 断点只在"上一行以空白结束、下一行以非空白开始"的真实行起点上取：上一块以行尾
      // 空白结尾（不可见），下一块以非空白开头。硬换行、缩进续行、超长无空白 run 都
      // 量不出这种断点，于是返回 0 退回单个 Text，绝不从中间切开一行。
      var withinTarget = 0;
      var lastSafe = 0;
      for (final raw in starts) {
        // 行首偏移可能正好落在被断行吞掉的空白上，先归一到空白之后。
        var start = raw;
        while (start < window.length && window.codeUnitAt(start) == 0x20) {
          start += 1;
        }
        // 断点必须落在测量窗内，块长才确实有界（窗口外的正文留给尾块）。
        if (start <= 0 || start >= window.length) continue;
        if (window.codeUnitAt(start - 1) != 0x20 ||
            window.codeUnitAt(start) == 0x20) {
          continue;
        }
        lastSafe = start;
        if (start <= _sealTargetCharacters) withinTarget = start;
      }
      return withinTarget > 0 ? withinTarget : lastSafe;
    } finally {
      painter.dispose();
    }
  }

  /// [text] 自 [start] 起的后缀里是否含 RTL 或 bidi 控制字符，带同一实例/同起点的结果缓存。
  ///
  /// 已封存前缀不在这里重复扫描：它由 [_canReuseSealed] 逐字证明未变，并且是在
  /// "当时无风险"的判定下才封存的；因此"前缀安全 + 后缀安全"覆盖整段当前正文。
  bool _suffixHasBidiRisk(String text, int start) {
    if (identical(_riskText, text) && _riskStart == start) {
      return _riskVerdict;
    }
    // 未配对的尾部 high surrogate 会暂时触发风险，随后追加 low surrogate 可以修复它。
    // 每次内容改变都重查当前后缀，不能把上一版 true 永久 OR 到后续正文。
    final verdict = _hasBidiRisk(text, start, text.length);
    _riskText = text;
    _riskStart = start;
    _riskVerdict = verdict;
    return verdict;
  }

  /// [text] 的 [start], [end) 区间内是否含 RTL 或 bidi 控制字符。
  ///
  /// 保守判定：切块会引入多个 paragraph，RTL/bidi 段落状态不能证明与整段一致，因此一旦
  /// 命中就整体退回单个 [Text]（普通 LTR 正文、CJK 与补充平面非 RTL 字符不受影响）。
  /// 扫描当前未封存后缀；安全分块时它通常有界，无安全断点或整体退回时可以覆盖整段。
  /// 不做采样、不做哈希近似。
  static bool _hasBidiRisk(String text, int start, int end) {
    if (start > 0 &&
        start < end &&
        _isHighSurrogate(text.codeUnitAt(start - 1)) &&
        _isLowSurrogate(text.codeUnitAt(start))) {
      // 起点落在代理对中间时回退一格重新成对判定，避免漏判补充平面的 RTL 字符。
      start -= 1;
    }
    for (var index = start; index < end; index += 1) {
      final unit = text.codeUnitAt(index);
      if (_isHighSurrogate(unit)) {
        if (index + 1 >= end || !_isLowSurrogate(text.codeUnitAt(index + 1))) {
          return true;
        }
        final low = text.codeUnitAt(index + 1);
        final codePoint = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
        if ((codePoint >= 0x10800 && codePoint <= 0x10FFF) ||
            (codePoint >= 0x1E800 && codePoint <= 0x1EFFF)) {
          return true;
        }
        index += 1;
        continue;
      }
      if ((unit >= 0x0590 && unit <= 0x08FF) ||
          (unit >= 0xFB1D && unit <= 0xFDFF) ||
          (unit >= 0xFE70 && unit <= 0xFEFF) ||
          (unit >= 0x200E && unit <= 0x200F) ||
          (unit >= 0x202A && unit <= 0x202E) ||
          (unit >= 0x2066 && unit <= 0x2069)) {
        return true;
      }
    }
    return false;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

Future<void> _openTimelineWebLink(
  BuildContext context,
  WidgetRef ref,
  String rawUrl,
) async {
  final url = safeExternalWebUrl(rawUrl);
  if (url == null) {
    return;
  }
  try {
    await ref.read(externalUrlLauncherProvider)(url);
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.timelineExternalLinkOpenFailed)),
    );
  }
}

TextStyle? _markdownBodyStyle(BuildContext context, _MarkdownSurface surface) {
  final theme = Theme.of(context);
  // VS Code 预览正文行高 22px/14px ≈ 1.57，各阅读表面保持一致节奏。
  if (surface == _MarkdownSurface.reasoning) {
    return theme.textTheme.bodySmall?.copyWith(
      color: context.colors.onSurfaceVariant,
      height: 1.57,
    );
  }
  if (surface == _MarkdownSurface.error) {
    return theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
      height: 1.57,
    );
  }
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurface,
    height: 1.57,
  );
}
