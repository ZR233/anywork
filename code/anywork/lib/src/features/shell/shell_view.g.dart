// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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

String _$shellSessionCostHash() => r'99a4b974ed4eaff687b6b80bee75ff6f5a59820e';

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

String _$shellStartupViewHash() => r'0dec146e9153a0471fb7a1087bab5afc414008f3';

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

String _$shellSelectionHash() => r'a4a056583d94b4ce3e3ac788f3dd0109402420d1';

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

String _$shellGeneralHash() => r'913e92c7e48bdd4521b66f7221e6a27f48b8fdcc';

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

String _$shellChromeViewHash() => r'7d8b87b86dec2c78e812d075c375064de29e7809';

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

String _$sidebarViewHash() => r'1014afa8f10ad0932b2a6efbb04a7bc0be6c5378';

/// Select by value so another project's fresh DTO does not rebuild this one.

@ProviderFor(sidebarProjectView)
final sidebarProjectViewProvider = SidebarProjectViewFamily._();

/// Select by value so another project's fresh DTO does not rebuild this one.

final class SidebarProjectViewProvider
    extends $FunctionalProvider<StudioProject?, StudioProject?, StudioProject?>
    with $Provider<StudioProject?> {
  /// Select by value so another project's fresh DTO does not rebuild this one.
  SidebarProjectViewProvider._({
    required SidebarProjectViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sidebarProjectViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sidebarProjectViewHash();

  @override
  String toString() {
    return r'sidebarProjectViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<StudioProject?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StudioProject? create(Ref ref) {
    final argument = this.argument as String;
    return sidebarProjectView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioProject? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioProject?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SidebarProjectViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sidebarProjectViewHash() =>
    r'efe8ce63e7e6317c12afcad5cfa3f279aced13c2';

/// Select by value so another project's fresh DTO does not rebuild this one.

final class SidebarProjectViewFamily extends $Family
    with $FunctionalFamilyOverride<StudioProject?, String> {
  SidebarProjectViewFamily._()
    : super(
        retry: null,
        name: r'sidebarProjectViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Select by value so another project's fresh DTO does not rebuild this one.

  SidebarProjectViewProvider call(String projectId) =>
      SidebarProjectViewProvider._(argument: projectId, from: this);

  @override
  String toString() => r'sidebarProjectViewProvider';
}

@ProviderFor(sidebarSelectedRootThreadId)
final sidebarSelectedRootThreadIdProvider =
    SidebarSelectedRootThreadIdProvider._();

final class SidebarSelectedRootThreadIdProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  SidebarSelectedRootThreadIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sidebarSelectedRootThreadIdProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sidebarSelectedRootThreadIdHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return sidebarSelectedRootThreadId(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$sidebarSelectedRootThreadIdHash() =>
    r'4a1c6aafa117293e83191d2ae81562ba9ae5f2bf';

@ProviderFor(sidebarRecoveryIssue)
final sidebarRecoveryIssueProvider = SidebarRecoveryIssueFamily._();

final class SidebarRecoveryIssueProvider
    extends
        $FunctionalProvider<
          StudioRecoveryIssue?,
          StudioRecoveryIssue?,
          StudioRecoveryIssue?
        >
    with $Provider<StudioRecoveryIssue?> {
  SidebarRecoveryIssueProvider._({
    required SidebarRecoveryIssueFamily super.from,
    required (String?, {String? threadId}) super.argument,
  }) : super(
         retry: null,
         name: r'sidebarRecoveryIssueProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sidebarRecoveryIssueHash();

  @override
  String toString() {
    return r'sidebarRecoveryIssueProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<StudioRecoveryIssue?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StudioRecoveryIssue? create(Ref ref) {
    final argument = this.argument as (String?, {String? threadId});
    return sidebarRecoveryIssue(ref, argument.$1, threadId: argument.threadId);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioRecoveryIssue? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioRecoveryIssue?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SidebarRecoveryIssueProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sidebarRecoveryIssueHash() =>
    r'814f246d61bfb7abc4daeb112d4ad54fb7a7c79b';

final class SidebarRecoveryIssueFamily extends $Family
    with
        $FunctionalFamilyOverride<
          StudioRecoveryIssue?,
          (String?, {String? threadId})
        > {
  SidebarRecoveryIssueFamily._()
    : super(
        retry: null,
        name: r'sidebarRecoveryIssueProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SidebarRecoveryIssueProvider call(String? workspaceId, {String? threadId}) =>
      SidebarRecoveryIssueProvider._(
        argument: (workspaceId, threadId: threadId),
        from: this,
      );

  @override
  String toString() => r'sidebarRecoveryIssueProvider';
}

/// Read-only, per-identity projection; no list overlay or runtime subscription.

@ProviderFor(sidebarThreadView)
final sidebarThreadViewProvider = SidebarThreadViewFamily._();

/// Read-only, per-identity projection; no list overlay or runtime subscription.

final class SidebarThreadViewProvider
    extends
        $FunctionalProvider<
          SidebarThreadView,
          SidebarThreadView,
          SidebarThreadView
        >
    with $Provider<SidebarThreadView> {
  /// Read-only, per-identity projection; no list overlay or runtime subscription.
  SidebarThreadViewProvider._({
    required SidebarThreadViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'sidebarThreadViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sidebarThreadViewHash();

  @override
  String toString() {
    return r'sidebarThreadViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<SidebarThreadView> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SidebarThreadView create(Ref ref) {
    final argument = this.argument as String;
    return sidebarThreadView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SidebarThreadView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SidebarThreadView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SidebarThreadViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sidebarThreadViewHash() => r'e9df734a40d49cbbae71560270a26aa4be1a243e';

/// Read-only, per-identity projection; no list overlay or runtime subscription.

final class SidebarThreadViewFamily extends $Family
    with $FunctionalFamilyOverride<SidebarThreadView, String> {
  SidebarThreadViewFamily._()
    : super(
        retry: null,
        name: r'sidebarThreadViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Read-only, per-identity projection; no list overlay or runtime subscription.

  SidebarThreadViewProvider call(String threadId) =>
      SidebarThreadViewProvider._(argument: threadId, from: this);

  @override
  String toString() => r'sidebarThreadViewProvider';
}

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

String _$headerViewHash() => r'fd1f85113ce805a213ec5e41376be9d0f8fb8d12';

/// 目的地会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。

@ProviderFor(conversationWorkspace)
final conversationWorkspaceProvider = ConversationWorkspaceFamily._();

/// 目的地会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。

final class ConversationWorkspaceProvider
    extends
        $FunctionalProvider<
          AgentWorkspaceView?,
          AgentWorkspaceView?,
          AgentWorkspaceView?
        >
    with $Provider<AgentWorkspaceView?> {
  /// 目的地会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
  ///
  /// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。
  ConversationWorkspaceProvider._({
    required ConversationWorkspaceFamily super.from,
    required (String, {bool needsOpen}) super.argument,
  }) : super(
         retry: null,
         name: r'conversationWorkspaceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$conversationWorkspaceHash();

  @override
  String toString() {
    return r'conversationWorkspaceProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<AgentWorkspaceView?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentWorkspaceView? create(Ref ref) {
    final argument = this.argument as (String, {bool needsOpen});
    return conversationWorkspace(
      ref,
      argument.$1,
      needsOpen: argument.needsOpen,
    );
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentWorkspaceView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentWorkspaceView?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationWorkspaceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$conversationWorkspaceHash() =>
    r'ba4e79fe7acf0953a89fbfe2abda9d24a3c9a040';

/// 目的地会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
///
/// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。

final class ConversationWorkspaceFamily extends $Family
    with
        $FunctionalFamilyOverride<
          AgentWorkspaceView?,
          (String, {bool needsOpen})
        > {
  ConversationWorkspaceFamily._()
    : super(
        retry: null,
        name: r'conversationWorkspaceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 目的地会话的输入区事实。草稿仍由 interaction 域覆盖；这里只提供 canonical 会话。
  ///
  /// 不在这里持有 shell 租约：pane/预览也会观察它，不能因此拉起真实 Bridge。

  ConversationWorkspaceProvider call(
    String threadId, {
    bool needsOpen = false,
  }) => ConversationWorkspaceProvider._(
    argument: (threadId, needsOpen: needsOpen),
    from: this,
  );

  @override
  String toString() => r'conversationWorkspaceProvider';
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
    r'0ca542d0a02569a64c637d3c753b15d73013cf68';
