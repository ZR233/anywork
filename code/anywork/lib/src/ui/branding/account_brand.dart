import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/studio_tokens.dart';

// Except for Zhipu, provider glyphs under assets/provider-logos/ originate from
// cc-switch (https://github.com/farion1231/cc-switch, MIT). The Zhipu Z symbol
// comes from https://www.zhipuai.cn/logo.svg. All brand marks remain trademarks
// of their respective owners and are bundled for account identification only.

final class _AccountBrandAsset {
  const _AccountBrandAsset({required this.path, required this.color});

  final String path;
  final Color color;
}

const _accountBrandAssets = <String, _AccountBrandAsset>{
  'openai': _AccountBrandAsset(
    path: 'assets/provider-logos/openai.svg',
    color: Color(0xFF000000),
  ),
  'deepseek': _AccountBrandAsset(
    path: 'assets/provider-logos/deepseek.svg',
    color: Color(0xFF4D6BFE),
  ),
  'xai': _AccountBrandAsset(
    path: 'assets/provider-logos/xai.svg',
    color: Color(0xFF000000),
  ),
  'zhipu': _AccountBrandAsset(
    path: 'assets/provider-logos/zhipu.svg',
    color: Color(0xFF000000),
  ),
  'mimo': _AccountBrandAsset(
    path: 'assets/provider-logos/mimo.svg',
    color: Color(0xFF000000),
  ),
};

/// Brand mark for a account, keyed by the catalog `iconKey`.
///
/// Known brand keys render their bundled glyph inside a fixed white rounded
/// tile so brand colors stay legible in both themes; unknown or missing keys
/// fall back to the account name initials, which keeps custom gateways
/// unbranded. Brand identity crosses the bridge only as `iconKey`; paths and
/// tint colors are presentation details owned by this file.
class AccountBrandMark extends StatelessWidget {
  const AccountBrandMark({
    required this.fallbackName,
    this.iconKey,
    this.size = 40,
    this.active = false,
    super.key,
  });

  final String? iconKey;
  final String fallbackName;

  /// Tile edge length; the glyph is inset to keep clear space around it.
  final double size;

  /// Highlights the initials fallback the way a default account row does;
  /// brand tiles always stay white so their tinted glyph remains legible.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = iconKey == null ? null : _accountBrandAssets[iconKey!];
    if (brand == null) {
      return _AccountInitialsMark(
        name: fallbackName,
        size: size,
        active: active,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Center(
          child: SvgPicture.asset(
            brand.path,
            width: size * 0.6,
            height: size * 0.6,
            colorFilter: ColorFilter.mode(brand.color, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

class _AccountInitialsMark extends StatelessWidget {
  const _AccountInitialsMark({
    required this.name,
    required this.size,
    required this.active,
  });

  final String name;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? context.colors.primary
              : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Center(
          child: Text(
            accountInitials(name),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: active ? colors.onPrimary : context.colors.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.35,
            ),
          ),
        ),
      ),
    );
  }
}

String accountInitials(String value) {
  final words = value.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
  }
  return words
      .take(2)
      .map((word) => word.isEmpty ? '' : word.substring(0, 1))
      .join()
      .toUpperCase();
}
