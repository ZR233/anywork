// D1 纯库先行门禁样板的 Driver 入口（opt-in）。
//
// 由 root 通过
//   cargo xtask run-gui --driver --profile --native-launch \
//     --native-launch-driver-target test_driver/timeline_native_gate_main.dart \
//     --native-exit-report <report>
// 启动；不经生产 `lib/main.dart`、不接 FRB/AppGraph，只证明组件路线。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pointer_drag_extension.dart';
import 'pointer_scroll_extension.dart';
import 'raw_tap_extension.dart';
import 'timeline_native_gate_app.dart';

/// 门禁样板状态句柄：Driver 命令只读/驱动这一个样板，不接触生产状态。
final GlobalKey<TimelineGateState> timelineGateKey =
    GlobalKey<TimelineGateState>();

void main() {
  if (const bool.fromEnvironment('dart.vm.product')) {
    throw StateError('Flutter Driver mode is unavailable in product builds');
  }
  enableFlutterDriverExtension(
    handler: _handleDriverData,
    commands: <CommandExtension>[
      RawTapCommandExtension(),
      PointerScrollCommandExtension(),
      PointerDragCommandExtension(),
    ],
  );
  // 与组件测试共用同一个完整根形状（ProviderScope + MaterialApp + home）。
  runApp(ProviderScope(child: buildGateRootBody(key: timelineGateKey)));
}

/// 命令协议（全部 JSON 字符串）：
/// - `{"cmd":"snapshot"}`：代次/模式/消息身份/tail 基线/分页状态/滚动几何/版本与释放请求
/// - `{"cmd":"pid"}`：进程 PID（native-launch 报告用）
/// - `{"cmd":"stream-update","chars":240}` / `{"cmd":"stream-append","chars":120}`
/// - `{"cmd":"arm-load"}` / `{"cmd":"release-load"}`：显式放行在途分页（握手，不靠等待）
/// - `{"cmd":"fail-next"}` / `{"cmd":"fail-next","unexpected":true}`（后者模拟程式错误，
///   由样板上报 FlutterError 并显示可重试错误，不抛给库）
/// - `{"cmd":"load-older"}`（非阻塞启动，用 snapshot 观察收束）
/// - `{"cmd":"return-live"}` / `{"cmd":"reset-short"}` / `{"cmd":"empty"}`
/// - `{"cmd":"geometry","rowIds":[...]}`：只读几何诊断（视口 rect + 与视口相交的行 rect，
///   `rowIds` 可选、最多 64；缺失目标进入 `missing`）。不参与任何滚动/锚点决策。
/// - `{"cmd":"shutdown"}`：先关闭 fixture 发布/在途查询并卸载子树，等所有代次流真正
///   done 后走既有 native `host_lifecycle` 协议 `finishExit{exitCode}`（0 成功 / 1 失败）。
///   native 会在此调用中直接终止进程，**本命令的响应可能收不到**；退出码以 native-exit
///   报告为准，不依赖自然退出。
Future<String> _handleDriverData(String? message) async {
  final raw = (message ?? '').trim();
  final Map<String, dynamic> payload;
  if (raw.isEmpty) {
    payload = <String, dynamic>{'cmd': 'snapshot'};
  } else if (raw.startsWith('{')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'commandMustBeJsonObject',
        });
      }
      payload = decoded;
    } on FormatException catch (error) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'invalidJson',
        'detail': error.message,
      });
    }
  } else {
    payload = <String, dynamic>{'cmd': raw};
  }

  final command = payload['cmd'] as String? ?? 'snapshot';
  final state = timelineGateKey.currentState;
  switch (command) {
    case 'pid':
      return jsonEncode(<String, Object?>{'ok': true, 'pid': pid});
    case 'snapshot':
      if (state == null) return _notReady();
      return jsonEncode(<String, Object?>{'ok': true, ...state.snapshot()});
    case 'geometry':
      if (state == null) return _notReady();
      final rowIds = payload['rowIds'];
      if (rowIds != null && rowIds is! List) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'rowIdsMustBeList',
        });
      }
      return jsonEncode(<String, Object?>{
        ...state.geometry(
          rowIds: rowIds == null
              ? null
              : <String>[for (final id in rowIds) '$id'],
        ),
      });
    case 'stream-update':
      if (state == null) return _notReady();
      state.streamUpdate(chars: payload['chars'] as int? ?? 240);
      return jsonEncode(<String, Object?>{'ok': true});
    case 'stream-append':
      if (state == null) return _notReady();
      state.streamAppend(chars: payload['chars'] as int? ?? 120);
      return jsonEncode(<String, Object?>{'ok': true});
    case 'arm-load':
      if (state == null) return _notReady();
      state.armNextLoad();
      return jsonEncode(<String, Object?>{'ok': true});
    case 'release-load':
      if (state == null) return _notReady();
      return jsonEncode(<String, Object?>{
        'ok': true,
        'released': state.releasePendingLoad(),
      });
    case 'fail-next':
      if (state == null) return _notReady();
      state.failNextLoad(unexpected: payload['unexpected'] == true);
      return jsonEncode(<String, Object?>{'ok': true});
    case 'load-older':
      if (state == null) return _notReady();
      // 非阻塞：分页在样板内部完成，调用方用 snapshot 观察 loading/error/hasOlder。
      state.loadOlder();
      return jsonEncode(<String, Object?>{'ok': true, 'started': true});
    case 'return-live':
      if (state == null) return _notReady();
      state.returnLive();
      return jsonEncode(<String, Object?>{'ok': true});
    case 'reset-short':
      if (state == null) return _notReady();
      state.resetShort();
      return jsonEncode(<String, Object?>{'ok': true});
    case 'empty':
      if (state == null) return _notReady();
      state.makeEmpty();
      return jsonEncode(<String, Object?>{'ok': true});
    case 'shutdown':
      if (state == null) return _notReady();
      // 收束由本 fixture 自己拥有：关闭发布/在途查询 → 卸载子树 → 等到流真正 done →
      // finishExit(0)。native 会在此调用中终止进程，响应可能收不到；退出码以
      // native-exit 报告为准。任何一步失败都以 1 退出并上报，不伪报 0。
      unawaited(
        runGateShutdown(
          state: state,
          unmount: () async {
            runApp(const ProviderScope(child: SizedBox.shrink()));
          },
        ),
      );
      return jsonEncode(<String, Object?>{
        'ok': true,
        'shutdown': 'requested',
        'note': 'process may exit before this response is delivered',
      });
    default:
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'unknownCommand',
        'command': command,
      });
  }
}

String _notReady() =>
    jsonEncode(<String, Object?>{'ok': false, 'error': 'notReady'});
