import 'package:flutter/material.dart';

class TimelinePlainText extends StatefulWidget {
  const TimelinePlainText({
    required this.id,
    required this.text,
    this.style,
    super.key,
  });

  final String id;
  final String text;
  final TextStyle? style;

  @override
  State<TimelinePlainText> createState() => TimelinePlainTextState();
}

class TimelinePlainTextState extends State<TimelinePlainText> {
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
    final bodyStyle = widget.style;
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
              softWrap: true,
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
          style: widget.style,
          softWrap: true,
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
