// 从旧 ACP journey 提取的合成 Agent 控制与事件归因。没有产品程序/argv 输入，
// 只接受 harness 明确传入的树外合成目录；不接触 Google 或 Studio 配置/凭据。
import 'dart:convert';
import 'dart:io';

class AcpFixture {
  AcpFixture({required this.stateDir});

  final Directory stateDir;

  File get _behavior => File('${stateDir.path}/behavior.json');
  File _marker(String name) => File('${stateDir.path}/$name');

  Future<void> validate() async {
    if (!stateDir.isAbsolute || !await stateDir.exists()) {
      throw StateError(
        'fixture stateDir must be an existing absolute synthetic directory',
      );
    }
    // harness 必须已建立控制文件；不把任意目录初始化为 fixture。
    await _readBehavior();
  }

  Future<Map<String, dynamic>> _readBehavior() async {
    final decoded = jsonDecode(await _behavior.readAsString());
    if (decoded is! Map) {
      throw StateError('fixture behavior.json is not an object');
    }
    return decoded.cast<String, dynamic>();
  }

  /// 保留 harness 设定的其它行为（包括 serverInfo），只改本子场景负责的字段。
  Future<void> patchBehavior({
    String? authentication,
    String? probe,
    bool? disconnect,
  }) async {
    final current = await _readBehavior();
    final patched = {
      ...current,
      'authentication': ?authentication,
      'probe': ?probe,
      'disconnect': ?disconnect,
    };
    await _behavior.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(patched)}\n',
    );
  }

  /// 每次重新登录前显式重置自己的 marker，不让前一轮 release 假装本轮成功。
  Future<void> resetOwnControls({required bool clearCredential}) async {
    for (final name in [
      'auth-started',
      'auth-release',
      if (clearCredential) 'authenticated',
    ]) {
      final file = _marker(name);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> releaseAuth() async {
    await _marker('auth-release').writeAsString('release\n');
  }

  Future<bool> markerExists(String name) => _marker(name).exists();

  Future<int> eventCount() async => (await events()).length;

  Future<AcpAttemptEvidence> evidenceSince(int from) async {
    final all = await events();
    if (from > all.length) {
      throw StateError('fixture event stream was truncated');
    }
    return AcpAttemptEvidence.from(all.sublist(from));
  }

  Future<List<Map<String, dynamic>>> events() async {
    final file = File('${stateDir.path}/events.jsonl');
    if (!await file.exists()) return const [];
    final text = await file.readAsString();
    final lines = text.split('\n');
    final result = <Map<String, dynamic>>[];
    // 只忽略尚未写完的最后一行，完整坏行必须使旅程失败，不能抹掉失败证据。
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) throw StateError('fixture event is not an object');
        result.add(decoded.cast<String, dynamic>());
      } on FormatException {
        if (index != lines.length - 1) rethrow;
      }
    }
    return result;
  }
}

/// 只从一次动作之前的新水位取证；AuthenticateReleased 本身不是成功/取消，
/// 必须与同 PID 的受理、后续 SessionNew 顺序以及 credential/release marker 合看。
class AcpAttemptEvidence {
  AcpAttemptEvidence({
    required this.authenticatePid,
    required this.authenticateCount,
    required this.releasedPid,
    required this.sessionNewPid,
    required this.initializePid,
    required this.releasedAfterAuthenticate,
    required this.sessionNewForAttempt,
    required this.sessionNewAfterReleaseForAttempt,
    required this.sessionNewAfterInitialize,
  });

  factory AcpAttemptEvidence.from(List<Map<String, dynamic>> events) {
    var authenticateIndex = -1;
    int? authenticatePid;
    var authenticateCount = 0;
    var releasedIndex = -1;
    int? releasedPid;
    var sessionNewIndex = -1;
    int? sessionNewPid;
    var initializeIndex = -1;
    int? initializePid;
    var sessionNewAfterReleaseForAttempt = false;
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final name = event['event'];
      final pid = event['pid'] is int ? event['pid'] as int : null;
      if (name == 'authenticate') {
        authenticateCount += 1;
        if (authenticatePid == null) {
          authenticatePid = pid;
          authenticateIndex = index;
        }
      } else if (name == 'authenticateReleased') {
        if (authenticatePid != null && pid == authenticatePid) {
          releasedPid ??= pid;
          if (releasedIndex < 0) releasedIndex = index;
        }
      } else if (name == 'sessionNew') {
        if (sessionNewPid == null) {
          sessionNewPid = pid;
          sessionNewIndex = index;
        }
        if (authenticatePid != null &&
            pid == authenticatePid &&
            releasedIndex >= 0 &&
            index > releasedIndex) {
          sessionNewAfterReleaseForAttempt = true;
        }
      } else if (name == 'initialize' && initializePid == null) {
        initializePid = pid;
        initializeIndex = index;
      }
    }
    return AcpAttemptEvidence(
      authenticatePid: authenticatePid,
      authenticateCount: authenticateCount,
      releasedPid: releasedPid,
      sessionNewPid: sessionNewPid,
      initializePid: initializePid,
      releasedAfterAuthenticate:
          authenticateIndex >= 0 && releasedIndex > authenticateIndex,
      sessionNewForAttempt:
          authenticatePid != null &&
          events.any(
            (event) =>
                event['event'] == 'sessionNew' &&
                event['pid'] == authenticatePid,
          ),
      sessionNewAfterReleaseForAttempt: sessionNewAfterReleaseForAttempt,
      sessionNewAfterInitialize:
          initializeIndex >= 0 && sessionNewIndex > initializeIndex,
    );
  }

  final int? authenticatePid;
  final int authenticateCount;
  final int? releasedPid;
  final int? sessionNewPid;
  final int? initializePid;
  final bool releasedAfterAuthenticate;
  final bool sessionNewForAttempt;
  final bool sessionNewAfterReleaseForAttempt;
  final bool sessionNewAfterInitialize;

  bool get coversProbe =>
      initializePid != null &&
      sessionNewPid == initializePid &&
      authenticateCount == 0 &&
      sessionNewAfterInitialize;

  bool get coversSuccessfulLogin =>
      authenticateCount == 1 &&
      authenticatePid != null &&
      releasedPid == authenticatePid &&
      sessionNewPid == authenticatePid &&
      releasedAfterAuthenticate &&
      sessionNewAfterReleaseForAttempt;

  bool get isOrderedCancellation =>
      authenticateCount == 1 &&
      authenticatePid != null &&
      releasedPid == authenticatePid &&
      releasedAfterAuthenticate &&
      !sessionNewForAttempt;
}
