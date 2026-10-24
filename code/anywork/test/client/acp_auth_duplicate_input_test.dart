import 'package:anywork/src/features/settings/settings_acp_account_details.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// 认证命令的 `busy` 何时只是“重复输入”（同账号同连接身份下已有 canonical 在途
/// 操作），何时必须照常呈现失败。
///
/// 说明：生产 tab 只把该判定委托给 [isAcpAuthDuplicateWhileInFlight]，本文件直接
/// 驱动同一份生产规则；不声称覆盖完整 `AccountsTab` 挂载（那需要整套设置页壳层与
/// 权限 scope 装配）。
void main() {
  AcpAccountEntryView entry(
    String id,
    AcpAuthStateView state, {
    int connectionRevision = 1,
  }) => AccountDirectoryView.from(
    acpAccounts: [
      AcpAccountSettingsView(
        accountId: id,
        name: id.toUpperCase(),
        provider: AcpProviderView.antigravity,
        connectionRevision: connectionRevision,
      ),
    ],
    auth: AcpAuthSnapshotView(
      revision: 1,
      updatedAt: 1,
      accounts: [
        AcpAuthAccountView(
          accountId: id,
          connectionRevision: connectionRevision,
          state: state,
        ),
      ],
    ),
  ).acpEntries.single;

  const busy = StudioFailure(
    code: StudioFailureCode.busy,
    message: 'An ACP authentication operation is already active',
    retryable: false,
    correlationId: 'test-acp-busy',
  );

  test('同账号同连接身份且 canonical 在途 → 是重复输入', () {
    for (final state in <AcpAuthStateView>[
      const AcpCheckingState(operationId: 'op-check'),
      const AcpAuthenticatingState(operationId: 'op-auth', methodId: 'browser'),
      const AcpVerifyingState(operationId: 'op-verify'),
      const AcpCancellingState(operationId: 'op-cancel'),
    ]) {
      final target = entry('a', state);
      expect(
        isAcpAuthDuplicateWhileInFlight(
          error: busy,
          accountId: 'a',
          requestConnectionRevision: 1,
          entry: target,
        ),
        isTrue,
        reason: 'busy 命中当前在途操作：$state',
      );
    }
  });

  test('连接身份已前进 → 旧请求的 busy 不得当作重复输入', () {
    // 请求发出时是 revision 1，响应时该接入已重建为 revision 2 且新连接在途。
    final advanced = entry(
      'a',
      const AcpCheckingState(operationId: 'op-new'),
      connectionRevision: 2,
    );
    expect(
      isAcpAuthDuplicateWhileInFlight(
        error: busy,
        accountId: 'a',
        requestConnectionRevision: 1,
        entry: advanced,
      ),
      isFalse,
    );
  });

  test('目标不是该账号 → 不得吞掉另一个账号的 busy', () {
    final other = entry(
      'b',
      const AcpCheckingState(operationId: 'op-b'),
      connectionRevision: 1,
    );
    expect(
      isAcpAuthDuplicateWhileInFlight(
        error: busy,
        accountId: 'a',
        requestConnectionRevision: 1,
        entry: other,
      ),
      isFalse,
    );
  });

  test('非 busy 的 typed 失败 → 一律呈现', () {
    final target = entry('a', const AcpCheckingState(operationId: 'op-check'));
    for (final failure in <StudioFailure>[
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'ACP server did not start',
        retryable: true,
        correlationId: 'test-acp',
      ),
      const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The ACP connection identity changed',
        retryable: false,
        correlationId: 'test-acp',
      ),
      const StudioFailure(
        code: StudioFailureCode.cancellationTooLate,
        message: 'The ACP operation is already settling',
        retryable: false,
        correlationId: 'test-acp',
      ),
    ]) {
      expect(
        isAcpAuthDuplicateWhileInFlight(
          error: failure,
          accountId: 'a',
          requestConnectionRevision: 1,
          entry: target,
        ),
        isFalse,
        reason: '${failure.code}',
      );
    }
    // 非 StudioFailure（例如传输层错误）同样不得被吞掉。
    expect(
      isAcpAuthDuplicateWhileInFlight(
        error: StateError('transport closed'),
        accountId: 'a',
        requestConnectionRevision: 1,
        entry: target,
      ),
      isFalse,
    );
  });

  test('canonical 没有在途操作 → busy 仍是真实失败', () {
    for (final state in <AcpAuthStateView>[
      const AcpUncheckedState(),
      const AcpCancelledState(),
      const AcpRequiredState(
        server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
      ),
      const AcpVerifiedState(
        checkedAt: 90,
        server: AcpServerInfoView(name: 'antigravity', version: '1.2.3'),
      ),
      const AcpFailedState(
        failure: AcpAuthFailureView(
          code: AcpAuthFailureCodeView.cleanup,
          stage: AcpAuthStageView.cleanup,
          message: 'ACP process is still exiting',
          retryable: true,
        ),
      ),
    ]) {
      final target = entry('a', state);
      expect(
        isAcpAuthDuplicateWhileInFlight(
          error: busy,
          accountId: 'a',
          requestConnectionRevision: 1,
          entry: target,
        ),
        isFalse,
        reason: '没有在途操作时不得吞掉 busy：$state',
      );
    }
  });

  test('接入已不存在 → 不得吞掉 busy', () {
    expect(
      isAcpAuthDuplicateWhileInFlight(
        error: busy,
        accountId: 'a',
        requestConnectionRevision: 1,
        entry: null,
      ),
      isFalse,
    );
  });
}
