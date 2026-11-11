// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_content_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(acpDecodedImage)
final acpDecodedImageProvider = AcpDecodedImageFamily._();

final class AcpDecodedImageProvider
    extends
        $FunctionalProvider<
          AsyncValue<AcpDecodedImagePresentation>,
          AcpDecodedImagePresentation,
          FutureOr<AcpDecodedImagePresentation>
        >
    with
        $FutureModifier<AcpDecodedImagePresentation>,
        $FutureProvider<AcpDecodedImagePresentation> {
  AcpDecodedImageProvider._({
    required AcpDecodedImageFamily super.from,
    required AcpImagePayload super.argument,
  }) : super(
         retry: null,
         name: r'acpDecodedImageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpDecodedImageHash();

  @override
  String toString() {
    return r'acpDecodedImageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AcpDecodedImagePresentation> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AcpDecodedImagePresentation> create(Ref ref) {
    final argument = this.argument as AcpImagePayload;
    return acpDecodedImage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AcpDecodedImageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpDecodedImageHash() => r'92f7cfb18f80d1ee60f284d49bfae07f0f13c12a';

final class AcpDecodedImageFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AcpDecodedImagePresentation>,
          AcpImagePayload
        > {
  AcpDecodedImageFamily._()
    : super(
        retry: null,
        name: r'acpDecodedImageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpDecodedImageProvider call(AcpImagePayload image) =>
      AcpDecodedImageProvider._(argument: image, from: this);

  @override
  String toString() => r'acpDecodedImageProvider';
}
