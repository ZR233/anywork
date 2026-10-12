// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Shell 常驻 topic 租约。观察者离开时释放，不在 provider 初始化里写业务状态。

@ProviderFor(shellTopicLease)
final shellTopicLeaseProvider = ShellTopicLeaseProvider._();

/// Shell 常驻 topic 租约。观察者离开时释放，不在 provider 初始化里写业务状态。

final class ShellTopicLeaseProvider
    extends
        $FunctionalProvider<
          BridgeTopicLeaseBundle,
          BridgeTopicLeaseBundle,
          BridgeTopicLeaseBundle
        >
    with $Provider<BridgeTopicLeaseBundle> {
  /// Shell 常驻 topic 租约。观察者离开时释放，不在 provider 初始化里写业务状态。
  ShellTopicLeaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellTopicLeaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellTopicLeaseHash();

  @$internal
  @override
  $ProviderElement<BridgeTopicLeaseBundle> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BridgeTopicLeaseBundle create(Ref ref) {
    return shellTopicLease(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BridgeTopicLeaseBundle value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BridgeTopicLeaseBundle>(value),
    );
  }
}

String _$shellTopicLeaseHash() => r'd77b05113388fc18a8f87cae2ee521a254c96578';

/// 持久化面板可见时才持有队列租约。

@ProviderFor(persistenceQueueLease)
final persistenceQueueLeaseProvider = PersistenceQueueLeaseProvider._();

/// 持久化面板可见时才持有队列租约。

final class PersistenceQueueLeaseProvider
    extends
        $FunctionalProvider<
          BridgeTopicLease,
          BridgeTopicLease,
          BridgeTopicLease
        >
    with $Provider<BridgeTopicLease> {
  /// 持久化面板可见时才持有队列租约。
  PersistenceQueueLeaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'persistenceQueueLeaseProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$persistenceQueueLeaseHash();

  @$internal
  @override
  $ProviderElement<BridgeTopicLease> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BridgeTopicLease create(Ref ref) {
    return persistenceQueueLease(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BridgeTopicLease value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BridgeTopicLease>(value),
    );
  }
}

String _$persistenceQueueLeaseHash() =>
    r'c55e668df5cbb7bacefc0d5eab28f5f0f178c0f3';

/// 根会话费用租约。family 参数是稳定 rootThreadId，观察者离开即释放。

@ProviderFor(shellSessionCostsLease)
final shellSessionCostsLeaseProvider = ShellSessionCostsLeaseFamily._();

/// 根会话费用租约。family 参数是稳定 rootThreadId，观察者离开即释放。

final class ShellSessionCostsLeaseProvider
    extends
        $FunctionalProvider<
          BridgeTopicLease,
          BridgeTopicLease,
          BridgeTopicLease
        >
    with $Provider<BridgeTopicLease> {
  /// 根会话费用租约。family 参数是稳定 rootThreadId，观察者离开即释放。
  ShellSessionCostsLeaseProvider._({
    required ShellSessionCostsLeaseFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shellSessionCostsLeaseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shellSessionCostsLeaseHash();

  @override
  String toString() {
    return r'shellSessionCostsLeaseProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<BridgeTopicLease> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BridgeTopicLease create(Ref ref) {
    final argument = this.argument as String;
    return shellSessionCostsLease(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BridgeTopicLease value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BridgeTopicLease>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShellSessionCostsLeaseProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shellSessionCostsLeaseHash() =>
    r'28e6c45285e92ea0ae05862d76fb478135986f0c';

/// 根会话费用租约。family 参数是稳定 rootThreadId，观察者离开即释放。

final class ShellSessionCostsLeaseFamily extends $Family
    with $FunctionalFamilyOverride<BridgeTopicLease, String> {
  ShellSessionCostsLeaseFamily._()
    : super(
        retry: null,
        name: r'shellSessionCostsLeaseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 根会话费用租约。family 参数是稳定 rootThreadId，观察者离开即释放。

  ShellSessionCostsLeaseProvider call(String rootThreadId) =>
      ShellSessionCostsLeaseProvider._(argument: rootThreadId, from: this);

  @override
  String toString() => r'shellSessionCostsLeaseProvider';
}

@ProviderFor(shellSessionCost)
final shellSessionCostProvider = ShellSessionCostFamily._();

final class ShellSessionCostProvider
    extends
        $FunctionalProvider<
          SessionCostView?,
          SessionCostView?,
          SessionCostView?
        >
    with $Provider<SessionCostView?> {
  ShellSessionCostProvider._({
    required ShellSessionCostFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'shellSessionCostProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$shellSessionCostHash();

  @override
  String toString() {
    return r'shellSessionCostProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<SessionCostView?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SessionCostView? create(Ref ref) {
    final argument = this.argument as String;
    return shellSessionCost(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionCostView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionCostView?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ShellSessionCostProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$shellSessionCostHash() => r'3a2c268befa70eacc337459368c23370c8aba14f';

final class ShellSessionCostFamily extends $Family
    with $FunctionalFamilyOverride<SessionCostView?, String> {
  ShellSessionCostFamily._()
    : super(
        retry: null,
        name: r'shellSessionCostProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ShellSessionCostProvider call(String rootThreadId) =>
      ShellSessionCostProvider._(argument: rootThreadId, from: this);

  @override
  String toString() => r'shellSessionCostProvider';
}

@ProviderFor(shellStartupView)
final shellStartupViewProvider = ShellStartupViewProvider._();

final class ShellStartupViewProvider
    extends
        $FunctionalProvider<
          ShellStartupView,
          ShellStartupView,
          ShellStartupView
        >
    with $Provider<ShellStartupView> {
  ShellStartupViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellStartupViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellStartupViewHash();

  @$internal
  @override
  $ProviderElement<ShellStartupView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShellStartupView create(Ref ref) {
    return shellStartupView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellStartupView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellStartupView>(value),
    );
  }
}

String _$shellStartupViewHash() => r'be3caf579de206a48f0ff4445a32bbd6f231bb0c';

/// 已订阅的选择事实。Widget 用它替代一次性读取。

@ProviderFor(shellSelection)
final shellSelectionProvider = ShellSelectionProvider._();

/// 已订阅的选择事实。Widget 用它替代一次性读取。

final class ShellSelectionProvider
    extends
        $FunctionalProvider<
          SelectionStoreState,
          SelectionStoreState,
          SelectionStoreState
        >
    with $Provider<SelectionStoreState> {
  /// 已订阅的选择事实。Widget 用它替代一次性读取。
  ShellSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellSelectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellSelectionHash();

  @$internal
  @override
  $ProviderElement<SelectionStoreState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SelectionStoreState create(Ref ref) {
    return shellSelection(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SelectionStoreState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SelectionStoreState>(value),
    );
  }
}

String _$shellSelectionHash() => r'71cec947a694b6d7685fc55df890d9562d5c69cd';

@ProviderFor(shellGeneral)
final shellGeneralProvider = ShellGeneralProvider._();

final class ShellGeneralProvider
    extends
        $FunctionalProvider<
          GeneralSettingsView,
          GeneralSettingsView,
          GeneralSettingsView
        >
    with $Provider<GeneralSettingsView> {
  ShellGeneralProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellGeneralProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellGeneralHash();

  @$internal
  @override
  $ProviderElement<GeneralSettingsView> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GeneralSettingsView create(Ref ref) {
    return shellGeneral(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GeneralSettingsView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GeneralSettingsView>(value),
    );
  }
}

String _$shellGeneralHash() => r'1ea8ab6e73b2886486e7b5496e08822092f33ca8';

@ProviderFor(shellChromeView)
final shellChromeViewProvider = ShellChromeViewProvider._();

final class ShellChromeViewProvider
    extends
        $FunctionalProvider<ShellChromeView, ShellChromeView, ShellChromeView>
    with $Provider<ShellChromeView> {
  ShellChromeViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellChromeViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellChromeViewHash();

  @$internal
  @override
  $ProviderElement<ShellChromeView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShellChromeView create(Ref ref) {
    return shellChromeView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellChromeView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellChromeView>(value),
    );
  }
}

String _$shellChromeViewHash() => r'7542867a6a57cb3bcba618f2067195f2ef01a65d';

@ProviderFor(sidebarView)
final sidebarViewProvider = SidebarViewProvider._();

final class SidebarViewProvider
    extends $FunctionalProvider<SidebarView, SidebarView, SidebarView>
    with $Provider<SidebarView> {
  SidebarViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sidebarViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sidebarViewHash();

  @$internal
  @override
  $ProviderElement<SidebarView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SidebarView create(Ref ref) {
    return sidebarView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SidebarView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SidebarView>(value),
    );
  }
}

String _$sidebarViewHash() => r'0dd0167c7b840e8337165e1c617ede45c689a458';

@ProviderFor(headerView)
final headerViewProvider = HeaderViewProvider._();

final class HeaderViewProvider
    extends $FunctionalProvider<HeaderView, HeaderView, HeaderView>
    with $Provider<HeaderView> {
  HeaderViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'headerViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$headerViewHash();

  @$internal
  @override
  $ProviderElement<HeaderView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HeaderView create(Ref ref) {
    return headerView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HeaderView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HeaderView>(value),
    );
  }
}

String _$headerViewHash() => r'bc12eb0cd4ba1e35cdad66a7e8bd48fac94ad1a3';

/// `needsOpen` 时不订阅会话。已有历史窗口后不再请求首窗。

@ProviderFor(shellHistoryOpenRequest)
final shellHistoryOpenRequestProvider = ShellHistoryOpenRequestProvider._();

/// `needsOpen` 时不订阅会话。已有历史窗口后不再请求首窗。

final class ShellHistoryOpenRequestProvider
    extends
        $FunctionalProvider<
          ShellHistoryOpenRequest?,
          ShellHistoryOpenRequest?,
          ShellHistoryOpenRequest?
        >
    with $Provider<ShellHistoryOpenRequest?> {
  /// `needsOpen` 时不订阅会话。已有历史窗口后不再请求首窗。
  ShellHistoryOpenRequestProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellHistoryOpenRequestProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellHistoryOpenRequestHash();

  @$internal
  @override
  $ProviderElement<ShellHistoryOpenRequest?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ShellHistoryOpenRequest? create(Ref ref) {
    return shellHistoryOpenRequest(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellHistoryOpenRequest? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellHistoryOpenRequest?>(value),
    );
  }
}

String _$shellHistoryOpenRequestHash() =>
    r'6f9bcb92bc3664ced0880acab66e4b2d58468f22';

/// 当前选中会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。

@ProviderFor(shellComposerWorkspace)
final shellComposerWorkspaceProvider = ShellComposerWorkspaceProvider._();

/// 当前选中会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。

final class ShellComposerWorkspaceProvider
    extends
        $FunctionalProvider<
          AgentWorkspaceView?,
          AgentWorkspaceView?,
          AgentWorkspaceView?
        >
    with $Provider<AgentWorkspaceView?> {
  /// 当前选中会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
  ///
  /// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。
  ShellComposerWorkspaceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellComposerWorkspaceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellComposerWorkspaceHash();

  @$internal
  @override
  $ProviderElement<AgentWorkspaceView?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentWorkspaceView? create(Ref ref) {
    return shellComposerWorkspace(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentWorkspaceView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentWorkspaceView?>(value),
    );
  }
}

String _$shellComposerWorkspaceHash() =>
    r'9210d3a225215a03e0b41108a80b06be1714bafd';

@ProviderFor(conversationActivityInput)
final conversationActivityInputProvider = ConversationActivityInputFamily._();

final class ConversationActivityInputProvider
    extends
        $FunctionalProvider<
          ConversationActivityInput?,
          ConversationActivityInput?,
          ConversationActivityInput?
        >
    with $Provider<ConversationActivityInput?> {
  ConversationActivityInputProvider._({
    required ConversationActivityInputFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'conversationActivityInputProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$conversationActivityInputHash();

  @override
  String toString() {
    return r'conversationActivityInputProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ConversationActivityInput?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConversationActivityInput? create(Ref ref) {
    final argument = this.argument as String;
    return conversationActivityInput(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationActivityInput? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationActivityInput?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationActivityInputProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$conversationActivityInputHash() =>
    r'd6c52770ced07c0680b3ee71ad75c84fefeb7644';

final class ConversationActivityInputFamily extends $Family
    with $FunctionalFamilyOverride<ConversationActivityInput?, String> {
  ConversationActivityInputFamily._()
    : super(
        retry: null,
        name: r'conversationActivityInputProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ConversationActivityInputProvider call(String threadId) =>
      ConversationActivityInputProvider._(argument: threadId, from: this);

  @override
  String toString() => r'conversationActivityInputProvider';
}

@ProviderFor(persistencePanelView)
final persistencePanelViewProvider = PersistencePanelViewProvider._();

final class PersistencePanelViewProvider
    extends
        $FunctionalProvider<
          PersistencePanelView,
          PersistencePanelView,
          PersistencePanelView
        >
    with $Provider<PersistencePanelView> {
  PersistencePanelViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'persistencePanelViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$persistencePanelViewHash();

  @$internal
  @override
  $ProviderElement<PersistencePanelView> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PersistencePanelView create(Ref ref) {
    return persistencePanelView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PersistencePanelView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PersistencePanelView>(value),
    );
  }
}

String _$persistencePanelViewHash() =>
    r'b800defde0586a79257dffd2145c07527398c823';
