// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_attachment_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Borrows the already-owned draft and route reader. Only a current exact-model
/// read can enable an entry; neither a last-known route nor a catalog page can.

@ProviderFor(ComposerAttachmentViewModel)
final composerAttachmentViewModelProvider =
    ComposerAttachmentViewModelFamily._();

/// Borrows the already-owned draft and route reader. Only a current exact-model
/// read can enable an entry; neither a last-known route nor a catalog page can.
final class ComposerAttachmentViewModelProvider
    extends
        $AsyncNotifierProvider<
          ComposerAttachmentViewModel,
          ComposerAttachmentState
        > {
  /// Borrows the already-owned draft and route reader. Only a current exact-model
  /// read can enable an entry; neither a last-known route nor a catalog page can.
  ComposerAttachmentViewModelProvider._({
    required ComposerAttachmentViewModelFamily super.from,
    required ComposerKey super.argument,
  }) : super(
         retry: null,
         name: r'composerAttachmentViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$composerAttachmentViewModelHash();

  @override
  String toString() {
    return r'composerAttachmentViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ComposerAttachmentViewModel create() => ComposerAttachmentViewModel();

  @override
  bool operator ==(Object other) {
    return other is ComposerAttachmentViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$composerAttachmentViewModelHash() =>
    r'6d4fc1d0f1bfcc20e98ba248298f4146a500c0c7';

/// Borrows the already-owned draft and route reader. Only a current exact-model
/// read can enable an entry; neither a last-known route nor a catalog page can.

final class ComposerAttachmentViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ComposerAttachmentViewModel,
          AsyncValue<ComposerAttachmentState>,
          ComposerAttachmentState,
          FutureOr<ComposerAttachmentState>,
          ComposerKey
        > {
  ComposerAttachmentViewModelFamily._()
    : super(
        retry: null,
        name: r'composerAttachmentViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Borrows the already-owned draft and route reader. Only a current exact-model
  /// read can enable an entry; neither a last-known route nor a catalog page can.

  ComposerAttachmentViewModelProvider call(ComposerKey target) =>
      ComposerAttachmentViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'composerAttachmentViewModelProvider';
}

/// Borrows the already-owned draft and route reader. Only a current exact-model
/// read can enable an entry; neither a last-known route nor a catalog page can.

abstract class _$ComposerAttachmentViewModel
    extends $AsyncNotifier<ComposerAttachmentState> {
  late final _$args = ref.$arg as ComposerKey;
  ComposerKey get target => _$args;

  FutureOr<ComposerAttachmentState> build(ComposerKey target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<ComposerAttachmentState>,
              ComposerAttachmentState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ComposerAttachmentState>,
                ComposerAttachmentState
              >,
              AsyncValue<ComposerAttachmentState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
