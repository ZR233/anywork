import 'package:flutter/material.dart';

/// 已完成正文的标准 Flutter 排版；原文由 SelectionArea 统一选择和复制。
class TimelinePlainText extends StatelessWidget {
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
  Widget build(BuildContext context) =>
      Text(text, key: ValueKey('plain-text-$id'), style: style, softWrap: true);
}
