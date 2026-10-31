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

String _$sidebarViewHash() => r'3085cd6b54e6019e6b0c123ee5006eb1adb16e23';

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

String _$headerViewHash() => r'937e9473191389b3cc86b241eaa035c9d6bd5cf2';

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
    r'580cd8e1ac24b0747f9068d58e305f19efc56b94';

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
    r'655d90a3dbf1662620e081ae202cc27b3f132776';

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
    r'1f7a8020bc1e1e54fdc1b7e314a0ec1da915102c';
