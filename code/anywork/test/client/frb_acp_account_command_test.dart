import 'dart:async';

import 'package:anywork/src/infrastructure/frb/products/configuration/command_results.dart';
import 'package:anywork/src/infrastructure/frb/products/configuration/configuration_port.dart';
import 'package:anywork/src/rust/api/studio/products/read/configuration_acp_commands.dart'
    as native;
import 'package:anywork/src/rust/api/studio/products/identity.dart'
    as identity_wire;
import 'package:anywork/src/rust/api/studio/products/references.dart'
    as reference_wire;
import 'package:anywork/src/rust/api/studio/types/acp.dart' as acp_wire;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as chat_wire;
import 'package:anywork/src/rust/api/studio/types/command.dart' as command_wire;
import 'package:anywork/src/rust/api/studio/types/error.dart' as error_wire;
import 'package:anywork/src/rust/frb_generated.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter_test/flutter_test.dart';

/// ACP 账号写入的 native 受管调用回归。
///
/// 生产契约（Configuration 调用所有者复用）：
/// 1. `begin` 明确返回 `BridgeError` 是**准入拒绝**（没有真实提交），按 `Rejected` 上报；
/// 2. 一旦原生入口被调用，`find` 或 `result` 的普通异常（**包括** `BridgeError`
///    `staleRevision`）都只能按 `Unknown` 上报，保留真实错误，且绝不自动重发
///    **写入**：不重发指 begin/save 只发生一次。同一原调用的 `result` 是普通读
///    查询，native 结果 retain 可重复读——显式查询两次就登记两次原 owner 查询，
///    适配层既不缓存也不 singleflight，不把重复读当成重放；
/// 3. `Committed` 结果之后的映射失败保留真实回执（`CommittedButUnobserved`），
///    不按 code 猜阶段。
///
/// 这里走**真实**生产 adapter 与**真实** generated 入口
/// （`FrbConfigurationPort` → `FrbAcpAccountCommandCall` →
/// `RustLib.instance.api.crateApiStudioProductsReadConfigurationAcpCommands…`），
/// 原生层用 flutter_rust_bridge 官方 mock 注入点 `RustLib.initMock(api:)` 替换
/// （不加载 FFI）。替身只实现 begin / find 两条入口：其余原生调用是显式失败，
/// 不模拟被测 adapter 或 SDK 逻辑。
const _staleFailure = error_wire.BridgeError(
  code: error_wire.BridgeErrorCode.staleRevision,
  message: 'The Settings CAS base advanced while preparing this ACP write',
  retryable: true,
  correlationId: 'acp-stale-revision',
);

const _operation = OperationId('acp-save-op');

typedef _BeginCall = ({
  String operationId,
  BigInt expectedSettingsRevision,
  native.BridgeAcpAccountMutation mutation,
});

/// 最小 `RustLibApi` 替身：只有 ACP 受管调用的 begin / find 进入。
final class _AcpCommandApi implements RustLibApi {
  final begins = <_BeginCall>[];
  final finds = <String>[];

  /// `null` 表示按原生 Err 返回 [failure]；否则使用给定行为。
  Object? beginFailure = _staleFailure;
  Object? findFailure = _staleFailure;

  /// 受控 native handle：begin 成功后由 native 返回，`result()` 走真实
  /// `BridgeError`。opaque handle 由生成代码声明为
  /// `abstract class … implements RustOpaqueInterface`（见真实生成的
  /// `api/studio/products/read/configuration_acp_commands.dart` 中
  /// `BridgeAcpAccountCommandCall`），因此测试可以 `implements` 它而不伪造
  /// native 身份。
  _MockAcpHandle? handle;

  @override
  Future<native.BridgeAcpAccountCommandCall>
  crateApiStudioProductsReadConfigurationAcpCommandsBeginAcpAccountCommand({
    required String operationId,
    required BigInt expectedSettingsRevision,
    required native.BridgeAcpAccountMutation mutation,
  }) {
    begins.add((
      operationId: operationId,
      expectedSettingsRevision: expectedSettingsRevision,
      mutation: mutation,
    ));
    final failure = beginFailure;
    if (failure != null) {
      return Future<native.BridgeAcpAccountCommandCall>.error(failure);
    }
    final created = handle;
    if (created == null) {
      return Future<native.BridgeAcpAccountCommandCall>.error(
        StateError('This mock has no handle scripted for the begin call'),
      );
    }
    return Future<native.BridgeAcpAccountCommandCall>.value(created);
  }

  @override
  Future<native.BridgeAcpAccountCommandCall?>
  crateApiStudioProductsReadConfigurationAcpCommandsFindAcpAccountCommand({
    required String operationId,
  }) {
    finds.add(operationId);
    final failure = findFailure;
    if (failure != null) {
      return Future<native.BridgeAcpAccountCommandCall?>.error(failure);
    }
    return Future<native.BridgeAcpAccountCommandCall?>.value(null);
  }

  /// 除 begin / find 之外的任何原生调用都是本用例未声明的行为：直接失败。
  @override
  Never noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected native call outside the ACP account command boundary: '
    '${invocation.memberName}',
  );
}

/// 受控 native handle：只声明真实身份与真实失败，不实现任何业务策略。
final class _MockAcpHandle implements native.BridgeAcpAccountCommandCall {
  _MockAcpHandle({required this.callIdValue, required this.operationIdValue});

  final String callIdValue;
  final String operationIdValue;

  /// 每次 `result()` 都是一次独立的原 owner 查询：进入即登记，由测试显式释放
  /// （typed 结局或真实原生错误）。native 结果 retain 可重复读，替身不缓存、
  /// 不合并，也不替被测适配层决定“只读一次”。
  final resultCalls = <String>[];
  final _resultEntrances = <int, Completer<void>>{};
  final _resultReleases = <Completer<native.BridgeAcpAccountCommandOutcome>>[];
  int requestCloseCalls = 0;
  int closeCalls = 0;
  int retryCloseCalls = 0;
  bool _disposed = false;

  /// native `close()` 已经到达原生边界：测试等这个显式 observer gate，
  /// 不靠事件队列猜测时序。
  final closeEntered = Completer<void>();

  @override
  String callId() => callIdValue;

  @override
  String operationId() => operationIdValue;

  /// 第 [index] 次 `result()` 已经进入原生查询（不假设同步登记）。
  Future<void> resultEntered(int index) =>
      _resultEntrances.putIfAbsent(index, Completer<void>.new).future;

  @override
  Future<native.BridgeAcpAccountCommandOutcome> result() {
    resultCalls.add(operationIdValue);
    final pending = Completer<native.BridgeAcpAccountCommandOutcome>();
    _resultReleases.add(pending);
    final entrance = _resultEntrances.putIfAbsent(
      _resultReleases.length - 1,
      Completer<void>.new,
    );
    if (!entrance.isCompleted) entrance.complete();
    return pending.future;
  }

  /// 释放第 [index] 次原生查询为真实 typed 结局。
  void completeResult(
    int index,
    native.BridgeAcpAccountCommandOutcome outcome,
  ) => _resultReleases[index].complete(outcome);

  /// 释放第 [index] 次原生查询为真实原生错误（adapter 必须分类为 Unknown）。
  void failResult(int index, Object failure) =>
      _resultReleases[index].completeError(failure);

  @override
  void requestClose() => requestCloseCalls++;

  @override
  Future<chat_wire.BridgeFeedCloseReport> close() {
    closeCalls++;
    if (!closeEntered.isCompleted) closeEntered.complete();
    return Future.value(
      chat_wire.BridgeFeedCloseReport(
        feedId: callIdValue,
        outcome: const chat_wire.BridgeFeedCloseOutcome.clean(),
      ),
    );
  }

  @override
  Future<chat_wire.BridgeFeedCloseReport> retryClose() {
    retryCloseCalls++;
    return Future<chat_wire.BridgeFeedCloseReport>.error(
      StateError('Retry close was not scripted for this handle'),
    );
  }

  @override
  void dispose() => _disposed = true;

  @override
  bool get isDisposed => _disposed;
}

command_wire.BridgeStudioCommandReceipt _wireReceipt({
  OperationId operation = _operation,
}) => command_wire.BridgeStudioCommandReceipt(
  operationId: operation.value,
  disposition: command_wire.BridgeCommandDisposition.applied,
  targets: [
    command_wire.BridgeResourceStamp(
      resourceKey: 'settings',
      ownerEpoch: 'settings-native',
      revision: BigInt.two,
    ),
  ],
  effect: command_wire.BridgeCommandEffectPoint.immediate,
  effective: false,
  durable: true,
  requiresIdentityObservation: false,
);

/// 真实 typed `Committed` 结局：真实 Settings 回执 + 本次提交捕获的配置目标。
native.BridgeAcpAccountCommandOutcome _committedOutcome({
  OperationId operation = _operation,
  int revision = 9,
}) => native.BridgeAcpAccountCommandOutcome.committed(
  reply: native.BridgeAcpAccountCommandReply(
    receipt: _wireReceipt(operation: operation),
    configuration: reference_wire.BridgeConfigurationReadTarget(
      origin: identity_wire.BridgeProductReadOrigin(
        ownerEpoch: 'settings-native',
        incarnation: BigInt.one,
      ),
      reference: reference_wire.BridgeConfigurationReadRef(
        entry: BigInt.one,
        revision: BigInt.from(revision),
      ),
    ),
  ),
);

void main() {
  late _AcpCommandApi api;

  setUp(() {
    api = _AcpCommandApi();
    // 官方 mock 注入点：显式替换 native API，且不加载任何 FFI 库。
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  test('ACP 保存的 begin 明确 BridgeError 按准入拒绝上报，且只发起一次 begin', () async {
    const port = FrbConfigurationPort();
    const request = UpdateAcpAccountRequest(
      operationId: _operation,
      expectedRevision: 7,
      account: AcpAccountUpdate(
        accountId: 'acct-work',
        name: 'Work',
        provider: AcpProvider.antigravity,
      ),
    );

    await expectLater(
      port.saveAcpAccount(request),
      throwsA(
        isA<RejectedCommandDispatchFailure>()
            .having(
              (failure) => failure.failure.code,
              'code',
              StudioFailureCode.staleRevision,
            )
            .having((failure) => failure.failure.retryable, 'retryable', isTrue)
            .having(
              (failure) => failure.failure.correlationId,
              'correlationId',
              'acp-stale-revision',
            ),
      ),
    );

    expect(api.begins, hasLength(1), reason: '准入拒绝不是重试信号');
    final sent = api.begins.single;
    expect(sent.operationId, 'acp-save-op');
    expect(sent.expectedSettingsRevision, BigInt.from(7));
    final mutation = sent.mutation;
    expect(mutation, isA<native.BridgeAcpAccountMutation_SaveAccount>());
    final input =
        (mutation as native.BridgeAcpAccountMutation_SaveAccount).input;
    expect(input.accountId, 'acct-work');
    expect(input.name, 'Work');
    expect(input.provider, acp_wire.BridgeAcpProvider.antigravity);
    expect(api.finds, isEmpty, reason: '没被受理的原生调用不需要 find 加入');
  });

  test('ACP 删除走真实 removeAcpAccount 入口：重复 result 查询与 close 都不重放写入', () async {
    const port = FrbConfigurationPort();
    const removeOperation = OperationId('acp-remove-op');
    final handle = _MockAcpHandle(
      callIdValue: 'acp-native-call-7',
      operationIdValue: removeOperation.value,
    );
    api.handle = handle;
    api.beginFailure = null;

    const request = RemoveAcpAccountRequest(
      operationId: removeOperation,
      expectedRevision: 11,
      accountId: 'acct-old',
    );
    final call = await port.removeAcpAccount(request);

    // 原生身份来自 handle 本身，不用本地计数器冒充。
    expect(call.callId, 'acp-native-call-7');
    expect(call.operationId, removeOperation);
    expect(api.begins, hasLength(1));
    final sent = api.begins.single;
    expect(sent.operationId, 'acp-remove-op');
    expect(sent.expectedSettingsRevision, BigInt.from(11));
    final mutation = sent.mutation;
    expect(mutation, isA<native.BridgeAcpAccountMutation_RemoveAccount>());
    expect(
      (mutation as native.BridgeAcpAccountMutation_RemoveAccount).accountId,
      'acct-old',
    );
    expect(api.finds, isEmpty, reason: '受理成功不需要 find 加入');

    // 两次显式 `result()` 是两次原 owner 查询：native 结果 retain 可重复读，
    // 适配层不缓存、不 singleflight。这里断言 native 查询精确 2 次，而
    // begin 仍只有 1 次、find 0 次——“未知结局不重发”约束的是写入。
    final first = call.result();
    final second = call.result();
    await handle.resultEntered(0);
    await handle.resultEntered(1);
    expect(
      handle.resultCalls,
      hasLength(2),
      reason: '两次显式查询各自登记一次原结果读取，不合并成一次',
    );

    // 两次原生读取都失败于 BridgeError(staleRevision)：各自 Unknown，各自保留
    // 原始 code/correlationId。
    handle.failResult(0, _staleFailure);
    handle.failResult(1, _staleFailure);
    for (final query in [first, second]) {
      await expectLater(
        query,
        throwsA(
          isA<UnknownOutcomeCommandDispatchFailure>()
              .having(
                (failure) => failure.failure.code,
                'code',
                StudioFailureCode.staleRevision,
              )
              .having(
                (failure) => failure.failure.correlationId,
                'correlationId',
                'acp-stale-revision',
              ),
        ),
      );
    }
    expect(handle.resultCalls, hasLength(2), reason: '失败分类不会追加第三次 native 读取');
    expect(api.begins, hasLength(1), reason: '未知结局不得产生第二次 begin');
    expect(api.finds, isEmpty, reason: 'result 查询不是新的 find/提交');

    // 第三次查询已经进入原生读取后立刻关闭：native close 可以先到达，但本地
    // result 受理工作完成前 close 不得结算，原 handle 必须保留。
    final inFlight = call.result();
    await handle.resultEntered(2);
    final closing = call.close();
    expect(handle.requestCloseCalls, 1);
    var closed = false;
    unawaited(
      closing.then<void>((_) {
        closed = true;
      }),
    );
    await handle.closeEntered.future;
    expect(handle.closeCalls, 1, reason: 'native close 已经到达');
    expect(closed, isFalse, reason: 'close 必须等本地 result 受理工作完成');
    expect(handle.isDisposed, isFalse, reason: '原 handle 保留到本地受理完成');

    // 释放为真实 typed 结局：已受理的 Committed 结果照实返回，随后才 clean 关闭。
    handle.completeResult(2, _committedOutcome(operation: removeOperation));
    final reply = await inFlight;
    expect(reply.receipt.operationId, removeOperation);
    expect(reply.configuration.reference.revision, 9);

    final report = await closing;
    expect(report.feedId, 'acp-native-call-7');
    expect(report.outcome, isA<CleanFeedCloseOutcome>());
    expect(handle.closeCalls, 1);
    expect(handle.retryCloseCalls, 0, reason: '首次 close 成功，不需要显式 retry');
    expect(handle.isDisposed, isTrue, reason: 'clean 关闭后才释放原 handle');
    expect(api.begins, hasLength(1), reason: '整段生命周期只有一次 begin');
    expect(api.finds, isEmpty);
  });

  test('ACP 保存的 find 遇到 staleRevision 只按 Unknown 上报，且不自动重发', () async {
    const port = FrbConfigurationPort();

    final opening = port.findAcpAccountCommand(_operation);
    await expectLater(
      opening,
      throwsA(
        isA<UnknownOutcomeCommandDispatchFailure>()
            .having(
              (failure) => failure.failure.code,
              'code',
              StudioFailureCode.staleRevision,
            )
            .having(
              (failure) => failure.failure.correlationId,
              'correlationId',
              'acp-stale-revision',
            ),
      ),
    );
    expect(api.finds, ['acp-save-op']);
    expect(api.begins, isEmpty, reason: 'find 只加入原调用，绝不发起第二次提交');

    // 第二次查找是新的显式询问，仍不提交任何写入。
    await expectLater(
      port.findAcpAccountCommand(_operation),
      throwsA(isA<UnknownOutcomeCommandDispatchFailure>()),
    );
    expect(api.finds, ['acp-save-op', 'acp-save-op']);
    expect(api.begins, isEmpty);
  });

  test('Committed 结果之后的映射失败保留真实回执，不按 code 猜阶段', () {
    // 负数 revision 无法转换成领域引用：真实回执仍必须随
    // `committedButUnobserved` 交给调用方。
    final committed = _committedOutcome(revision: -1);

    expect(
      () => acpAccountOutcomeFromBridge(committed, _operation),
      throwsA(
        isA<CommittedButUnobservedCommandDispatchFailure>().having(
          (failure) => failure.receipt.operationId,
          'receipt.operationId',
          _operation,
        ),
      ),
    );
  });
}
