// 宿主侧只读详情/剪贴板读命令的唯一入口。
//
// `timeline-content-window` 与 `clipboard-text` 只在 Driver 的 JSON 命令分支注册
// （`driver_main.dart` 的 `_handleJsonDriverCommand`）。发纯字符串会落到
// `unsupported driver request` 默认分支，把真实正文静默读成 0/null，看起来像
// “查看器不支持”。这里统一构造 JSON 命令并严格校验 typed 响应：形状不符、`ok`
// 不为真或带 error 一律抛错，绝不用默认值继续跑满 deadline。
//
// 只依赖 flutter_driver 的 `requestData` 形状（`FlutterDriver` 与
// `FlutterDriverSession` 都满足），不 import dart:ui/flutter/services。
import 'dart:convert';

typedef DriverReadRequest = Future<String> Function(
  String message, {
  Duration? timeout,
});

/// Exactly one displayed range with its actual controller qualification.
final class ContentWindowRead {
  ContentWindowRead._(this.fact);
  final Map<String, dynamic> fact;
  bool get open => fact['open'] as bool;
  String get text => _string(fact, 'text', 'content window');
  int get offset => _int(fact, 'offset', 'content window');
  int get end => _int(fact, 'end', 'content window');
  int get availableThrough => _int(fact, 'availableThrough', 'content window');
  int get characters => _int(fact, 'characters', 'content window');
  String get hash => _string(fact, 'hash', 'content window');
  Object get qualification => (
    fact['threadId'],
    fact['generation'],
    fact['parentId'],
    fact['scopeGeneration'],
    fact['itemId'],
    fact['field'],
  );
  static Future<ContentWindowRead> read(
    DriverReadRequest request, {
    required String itemId,
    required String field,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final map = _decodeObject(
      await request(
        jsonEncode({
          'cmd': 'timeline-content-window',
          'itemId': itemId,
          'field': field,
        }),
        timeout: timeout,
      ),
      'timeline-content-window',
    );
    _requireOk(map, 'timeline-content-window');
    if (map['open'] is! bool ||
        map['itemId'] != itemId ||
        map['field'] != field) {
      throw StateError('content window source or open state disagrees');
    }
    final result = ContentWindowRead._(map);
    _string(map, 'threadId', 'content window');
    _int(map, 'generation', 'content window');
    _int(map, 'scopeGeneration', 'content window');
    final parent = map['parentId'];
    if (!map.containsKey('parentId') ||
        (parent != null && (parent is! String || parent.isEmpty)) ||
        (parent == null && map['scopeGeneration'] != map['generation'])) {
      throw StateError('content window scope qualification is invalid');
    }
    if (result.open &&
        (result.offset < 0 ||
            result.end < result.offset ||
            result.end > result.availableThrough ||
            result.end - result.offset > 64 * 1024 ||
            result.characters != result.text.length)) {
      throw StateError('invalid displayed content range');
    }
    return result;
  }
}

/// 平台剪贴板当前内容（`clipboard-text`）的只读事实。
///
/// 只读取产品自己的复制动作写入的内容，不写剪贴板。
final class ClipboardRead {
  const ClipboardRead._({
    required this.characters,
    required this.hash,
    required this.text,
  });

  static Future<ClipboardRead> read(
    DriverReadRequest request, {
    bool full = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final command = full
        ? '{"cmd":"clipboard-text","full":true}'
        : '{"cmd":"clipboard-text"}';
    final map = _decodeObject(
      await request(command, timeout: timeout),
      'clipboard-text',
    );
    _requireOk(map, 'clipboard-text');
    return ClipboardRead._(
      characters: _int(map, 'characters', 'clipboard-text'),
      hash: _string(map, 'hash', 'clipboard-text'),
      text: full ? _string(map, 'text', 'clipboard-text') : null,
    );
  }

  final int characters;
  final String hash;

  /// `full` 请求时的剪贴板原文；默认 null（只读事实不需要搬运全文）。
  final String? text;
}

Map<String, dynamic> _decodeObject(String raw, String label) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw StateError('$label returned non-JSON payload: ${error.message}');
  }
  if (decoded is! Map) {
    throw StateError('$label response is not an object: $decoded');
  }
  return decoded.cast<String, dynamic>();
}

void _requireOk(Map<String, dynamic> map, String label) {
  if (map['ok'] != true) {
    throw StateError('$label was not accepted by the Driver: ${_raw(map)}');
  }
}

int _int(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  // 真实协议里这些字段是 Dart `int`（JSON 整数）。strict typed 读取：浮点、负数、
  // 数字字符串都不接受，也不做截断/钳制，避免把 12.7 静默读成 12。
  if (value is! int || value < 0) {
    throw StateError(
      '$label.$field is not a non-negative integer: ${_raw(map)}',
    );
  }
  return value;
}

String _string(Map<String, dynamic> map, String field, String label) {
  final value = map[field];
  if (value is! String) {
    throw StateError('$label.$field is not a string: ${_raw(map)}');
  }
  return value;
}

/// 有界诊断：只截取响应头部，避免把整段正文带进异常。
String _raw(Map<String, dynamic> map) {
  final encoded = jsonEncode(map);
  return encoded.length <= 200 ? encoded : '${encoded.substring(0, 200)}...';
}
