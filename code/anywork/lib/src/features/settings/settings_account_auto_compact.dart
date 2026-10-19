import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../shared/studio_driver_keys.dart';
import 'settings_readouts.dart';

/// 页面持有的提交状态；读数仍只使用 canonical [AccountModelAutoCompactView]。
typedef ModelAutoCompactEdit = ({
  int? overrideLimit,
  bool pending,
  bool failed,
});

/// 详情模型列表的唯一阈值编辑入口。原始输入不随旧 ACK 重置，提交由页面 owner 调度。
class AccountModelAutoCompactControl extends StatefulWidget {
  const AccountModelAutoCompactControl({
    super.key,
    required this.limit,
    required this.accountId,
    required this.modelId,
    this.edit,
    this.onOverrideChanged,
    this.onEditingComplete,
    this.onInvalidInput,
  });

  final AccountModelAutoCompactView limit;
  final String accountId;
  final String modelId;
  final ModelAutoCompactEdit? edit;
  final ValueChanged<int?>? onOverrideChanged;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onInvalidInput;

  @override
  State<AccountModelAutoCompactControl> createState() =>
      _ProviderModelAutoCompactControlState();
}

class _ProviderModelAutoCompactControlState
    extends State<AccountModelAutoCompactControl> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _dirty = false;
  bool _wasComposing = false;
  bool _changingText = false;

  int? get _selected => widget.edit == null
      ? widget.limit.overrideLimit ?? widget.limit.defaultLimit
      : widget.edit!.overrideLimit ?? widget.limit.defaultLimit;

  int? get _parsed {
    final text = _controller.text.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value != null && value > 0 ? value : null;
  }

  bool get _composing =>
      _controller.value.composing.isValid &&
      !_controller.value.composing.isCollapsed;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selected?.toString() ?? '');
    _controller.addListener(_onCompositionChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AccountModelAutoCompactControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_focus.hasFocus) {
      _showValue(_selected);
    } else if (!_composing &&
        _parsed != null &&
        widget.edit == null &&
        _parsed == (widget.limit.overrideLimit ?? widget.limit.defaultLimit)) {
      // 只确认本输入已被观察，不用 ACK 改写文本、选区或 IME 状态。
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.removeListener(_onCompositionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _showValue(int? value) {
    final text = value?.toString() ?? '';
    if (_controller.text == text) return;
    _changingText = true;
    try {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _changingText = false;
    }
  }

  void _onCompositionChanged() {
    final composing = _composing;
    final finished = _wasComposing && !composing;
    _wasComposing = composing;
    if (!finished || _changingText || !_dirty) return;
    // IME 可只折叠 composing range、不改文本；TextField.onChanged 不覆盖该事件。
    scheduleMicrotask(() {
      if (!mounted || _composing) return;
      setState(() {});
      _publish();
    });
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      _finishEditing();
      if (!_dirty) setState(() => _showValue(_selected));
    }
  }

  void _publish() {
    final parsed = _parsed;
    if (parsed == null || _composing) {
      widget.onInvalidInput?.call();
      return;
    }
    widget.onOverrideChanged?.call(
      parsed == widget.limit.defaultLimit ? null : parsed,
    );
  }

  void _onFieldChanged(String text) {
    setState(() => _dirty = true);
    _publish();
  }

  void _finishEditing() {
    if (!_dirty || _composing || _parsed == null) return;
    // 不重复排队已提交的意图；页面的 commit 会 flush 防抖或显式重试失败。
    if (widget.edit == null &&
        _parsed != (widget.limit.overrideLimit ?? widget.limit.defaultLimit)) {
      _publish();
    }
    widget.onEditingComplete?.call();
  }

  void _restoreDefault() {
    setState(() {
      _dirty = false;
      _showValue(widget.limit.defaultLimit);
    });
    widget.onOverrideChanged?.call(null);
    widget.onEditingComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final limit = widget.limit;
    final editable = widget.onOverrideChanged != null;
    final parsed = _parsed;
    final safe = limit.safeLimit;
    final edit = widget.edit;
    final field = TextField(
      key: StudioDriverKeys.accountModelAutoCompactInput(
        widget.accountId,
        widget.modelId,
      ),
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: context.l10n.settingsModelAutoCompactInputLabel,
        hintText: '—',
        suffixText: parsed == null ? null : formatTokenCount(parsed),
        errorText: _dirty && parsed == null
            ? context.l10n.settingsModelAutoCompactInvalid
            : null,
        errorMaxLines: 2,
      ),
      onChanged: _onFieldChanged,
      onSubmitted: (_) => _finishEditing(),
      onTapOutside: (_) => _focus.unfocus(),
    );
    final slider = safe == null
        ? null
        : Slider(
            key: StudioDriverKeys.accountModelAutoCompactSlider(
              widget.accountId,
              widget.modelId,
            ),
            min: 1,
            max: safe.toDouble(),
            value: (parsed ?? _selected ?? safe).clamp(1, safe).toDouble(),
            label: formatTokenCount(parsed),
            onChanged: safe <= 1
                ? null
                : (value) {
                    setState(() {
                      _dirty = true;
                      _showValue(value.round());
                    });
                    widget.onInvalidInput?.call();
                  },
            onChangeEnd: safe <= 1
                ? null
                : (value) {
                    setState(() {
                      _dirty = true;
                      _showValue(value.round());
                    });
                    _publish();
                    widget.onEditingComplete?.call();
                  },
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.settingsModelAutoCompactTitle,
                  style: context.text.labelLarge,
                ),
              ),
              if (editable)
                TextButton.icon(
                  key: StudioDriverKeys.accountModelAutoCompactReset(
                    widget.accountId,
                    widget.modelId,
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: Text(context.l10n.settingsModelAutoCompactRestore),
                  onPressed: _restoreDefault,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                SettingsMetric(
                  context.l10n.settingsModelAutoCompactDefaultLabel,
                  formatTokenCount(limit.defaultLimit),
                ),
                SettingsMetric(
                  context.l10n.settingsModelAutoCompactOverrideLabel,
                  limit.hasOverride
                      ? formatTokenCount(limit.overrideLimit)
                      : context.l10n.settingsModelAutoCompactUsingDefault,
                ),
                SettingsMetric(
                  context.l10n.settingsModelAutoCompactEffectiveLabel,
                  formatTokenCount(limit.effectiveLimit),
                ),
                SettingsMetric(
                  context.l10n.settingsModelAutoCompactSafeLabel,
                  formatTokenCount(limit.safeLimit),
                ),
              ],
            ),
          ),
          if (editable) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                if (slider == null) return field;
                if (constraints.maxWidth < 420) {
                  return Column(children: [field, slider]);
                }
                return Row(
                  children: [
                    Expanded(child: slider),
                    const SizedBox(width: 12),
                    SizedBox(width: 184, child: field),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              safe == null
                  ? context.l10n.settingsModelAutoCompactUnknownCapacity
                  : parsed != null && parsed > safe
                  ? context.l10n.settingsModelAutoCompactAboveSafe(
                      formatTokenCount(safe),
                    )
                  : context.l10n.settingsModelAutoCompactHelp,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (edit != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: edit.failed
                      ? Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              context.l10n.settingsModelAutoCompactSaveFailed,
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.error,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(
                                context.l10n.settingsModelAutoCompactRetry,
                              ),
                              onPressed: widget.onEditingComplete,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            const SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.settingsModelAutoCompactSaving,
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
