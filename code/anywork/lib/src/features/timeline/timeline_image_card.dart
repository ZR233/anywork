part of 'timeline_view.dart';

/// 展示工具（`show_image`）的图片卡片（design/19 §19.9）。
///
/// 卡片在时间线占一行，与其他块共用同一条左对齐内容列：头部是图片图标、标题与工具
/// 状态胶囊，中间按可用宽度等比展示大图并限制最大高度，图片下方展示模型给出的说明
/// 文案。图片字节只经 Thread 附件缓存按 typed 附件身份读取，卡片不解析 opaque 工具
/// 回执，也不建立第二份附件缓存（design/25 §25.6）。
class _TimelineImageCardBlock extends StatelessWidget {
  const _TimelineImageCardBlock({required this.payload});

  final TimelineMessagePayload payload;

  @override
  Widget build(BuildContext context) => Padding(
    key: StudioDriverKeys.timelineRow(payload.id),
    padding: const EdgeInsets.only(bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: _ImageCardPart(payload: payload),
      ),
    ),
  );
}

class _ImageCardPart extends StatelessWidget {
  const _ImageCardPart({required this.payload});

  final TimelineMessagePayload payload;

  @override
  Widget build(BuildContext context) {
    final item = payload.item;
    final tool = item.tool;
    // 只消费 canonical 工具输出里的 typed 附件：第一个图片类型的附件就是被展示的图片。
    final attachment = tool?.attachments
        .where((item) => item.modality == AttachmentModalityView.image)
        .firstOrNull;
    // 条目身份沿用 owning 调用 + 附件身份：同一资源被不同调用展示时仍是两张卡片。
    final entryId = attachment == null
        ? null
        : StudioDriverKeys.toolImageEntryId(
            tool?.callId ?? tool?.toolCallId ?? item.id,
            attachment.id,
          );
    final status = item.status;
    final failed = const {
      'failed',
      'denied',
      'cancelled',
      'interrupted',
      'budgetLimited',
    }.contains(status);
    final caption = _imageCardCaption(tool?.arguments);
    return SizedBox(
      key: entryId == null ? null : StudioDriverKeys.imageCard(entryId),
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          border: Border.all(color: context.colors.outlineVariant),
          borderRadius: BorderRadius.circular(StudioRadii.lg),
          boxShadow: StudioShadows.soft(context.colors.shadow),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: context.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.timelineImageCardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StudioPill(
                      label: context.toolStatusLabel(status),
                      tone: failed ? StudioTone.error : StudioTone.neutral,
                    ),
                  ],
                ),
              ),
              if (attachment != null && entryId != null)
                _ImageCardMedia(
                  threadId: item.threadId,
                  attachment: attachment,
                  entryId: entryId,
                )
              else
                const _ImageCardUnavailable(),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片说明文案的最大长度；超出按 rune 截断而不是按 UTF-16 码元。
const int _maxImageCardCaptionRunes = 240;

/// 卡片文案只来自 canonical 工具参数中的 `caption`（design/19 §19.9）。
///
/// 非字符串、空白与无法解析的参数都视为没有文案：不猜测图片内容，也不把参数正文直接
/// 铺进卡片；超长文案按 rune 截断，避免代理异常参数撑破阅读列。
String? _imageCardCaption(String? arguments) {
  final value = decodeJsonObject(arguments ?? '')['caption'];
  if (value is! String) return null;
  final caption = value.trim();
  if (caption.isEmpty) return null;
  final runes = caption.runes;
  if (runes.length <= _maxImageCardCaptionRunes) return caption;
  return String.fromCharCodes(runes.take(_maxImageCardCaptionRunes));
}

/// 没有可展示的 typed 图片附件时的占位：卡片保持可读的错误态，不抛异常。
class _ImageCardUnavailable extends StatelessWidget {
  const _ImageCardUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          context.l10n.timelineImageCardEmpty,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: context.colors.error),
        ),
      ),
    );
  }
}

/// 卡片的图片区：稳定尺寸、显式加载/失败状态，成功后可打开可缩放预览。
///
/// 加载、成功与失败共用同一个由附件比例推出的方框（宽度跟随卡片、高度不超过
/// [_maxImageCardHeight]），因此异步读取不会带来布局抖动，也不改变阅读位置。
class _ImageCardMedia extends ConsumerStatefulWidget {
  const _ImageCardMedia({
    required this.threadId,
    required this.attachment,
    required this.entryId,
  });

  final String threadId;
  final ThreadAttachmentView attachment;
  final String entryId;

  @override
  ConsumerState<_ImageCardMedia> createState() => _ImageCardMediaState();
}

/// 展示工具图片卡片的最大高度（design/19 §19.9：宽屏不超过约 360）。
const _maxImageCardHeight = 360.0;

/// 附件没有尺寸元数据时的默认比例，保证占位仍与成功态同尺寸。
const _fallbackImageCardAspect = 16 / 9;

class _ImageCardMediaState extends ConsumerState<_ImageCardMedia> {
  Future<Uint8List>? _image;
  int _imageGeneration = 0;

  @override
  void didUpdateWidget(covariant _ImageCardMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.threadId != oldWidget.threadId ||
        widget.attachment.id != oldWidget.attachment.id) {
      _imageGeneration++;
      _image = null;
    }
  }

  Future<Uint8List> _loadImage() => _ThreadImageCacheScope.of(context).load(
    widget.threadId,
    widget.attachment.id,
    () => ref
        .read(anyworkClientProvider)
        .readAttachmentBytes(widget.threadId, widget.attachment.id),
  );

  @override
  Widget build(BuildContext context) {
    // 同一帧内订阅，缓存里已有的失败结果同样进入失败态而不是一直等待。
    _image ??= _loadImage();
    final width = widget.attachment.width;
    final height = widget.attachment.height;
    final aspect = width != null && height != null && height > 0
        ? width / height
        : _fallbackImageCardAspect;
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        final boxHeight = math.min(
          _maxImageCardHeight,
          boxWidth / (aspect > 0 ? aspect : _fallbackImageCardAspect),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          child: SizedBox(
            width: boxWidth,
            height: boxHeight,
            child: ColoredBox(
              color: context.colors.surfaceContainerHigh,
              child: _ThreadImageFuture(
                presentationId: widget.entryId,
                image: _image!,
                fit: BoxFit.cover,
                onRetry: _retry,
                retryKey: StudioDriverKeys.imageCardRetry(widget.entryId),
                loadedKey: StudioDriverKeys.imageCardImage(widget.entryId),
                onTap: _showImage,
              ),
            ),
          ),
        );
      },
    );
  }

  void _retry() {
    final failed = _image;
    _imageGeneration++;
    if (failed != null) {
      // 只作废本条目持有的那次读取：另一次调用已开始的新读取不受影响。
      _ThreadImageCacheScope.of(context)
          .invalidate(widget.threadId, widget.attachment.id, failed);
    }
    setState(() => _image = _loadImage());
  }

  Future<void> _showImage() async {
    final generation = _imageGeneration;
    Uint8List image;
    try {
      image = await _image!;
    } on Object {
      return;
    }
    if (!mounted || generation != _imageGeneration) return;
    await _showStudioImageDialog(
      context,
      MemoryImage(image),
      dialogKey: StudioDriverKeys.timelineImageDialog(widget.attachment.id),
      label: widget.attachment.filename,
    );
  }
}
