import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/focus/focus_navigation.dart';
import '../models/dynamic_item.dart';
import 'base_tv_card.dart';
import 'conditional_marquee.dart';
import '../services/settings_service.dart';
import '../utils/image_url_utils.dart';
import '../config/app_style.dart';

/// 图文动态卡片 — 网格布局，基于 BaseTvCard
class TvDynamicDrawCard extends StatelessWidget {
  final DynamicDraw item;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final FocusNode? focusNode;
  final int index;
  final int gridColumns;
  final double topOffset;

  const TvDynamicDrawCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
    this.index = 0,
    this.gridColumns = 3,
    this.topOffset = TabStyle.defaultTopOffset,
  });

  Widget _buildFocusedTitle() {
    final focusedStyle = TextStyle(
      color: AppColors.primaryText,
      fontSize: AppFonts.sizeMD,
      fontWeight: FontWeight.bold,
    );
    final mode = SettingsService.focusedTitleDisplayMode;
    switch (mode) {
      case FocusedTitleDisplayMode.normal:
        return Text(
          item.text,
          style: focusedStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      case FocusedTitleDisplayMode.singleScroll:
        return ConditionalMarquee(
          text: item.text,
          style: focusedStyle,
          blankSpace: 30.0,
          velocity: 30.0,
          repeatBehavior: MarqueeRepeatBehavior.once,
        );
      case FocusedTitleDisplayMode.loopScroll:
        return ConditionalMarquee(
          text: item.text,
          style: focusedStyle,
          blankSpace: 30.0,
          velocity: 30.0,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseTvCard(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onFocus: onFocus,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onBack: onBack,
      index: index,
      gridColumns: gridColumns,
      topOffset: topOffset,
      imageContent: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(),
          if (item.imageCountLabel.isNotEmpty)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.imageCountLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppFonts.sizeXS,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.videoCardOverlay,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Row(
              children: [
                Icon(Icons.favorite_outline, size: 13, color: AppColors.inactiveText),
                const SizedBox(width: 2),
                Text(
                  item.likeFormatted,
                  style: TextStyle(color: AppColors.primaryText, fontSize: AppFonts.sizeXS),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chat_bubble_outline, size: 12, color: AppColors.inactiveText),
                const SizedBox(width: 2),
                Text(
                  item.commentFormatted,
                  style: TextStyle(color: AppColors.primaryText, fontSize: AppFonts.sizeXS),
                ),
              ],
            ),
          ),
        ],
      ),
      infoContentBuilder: (context, isFocused) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    SettingsService.focusedTitleDisplayMode == FocusedTitleDisplayMode.normal
                    ? 40
                    : 20,
              ),
              child: isFocused
                  ? _buildFocusedTitle()
                  : Text(
                      item.text,
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: AppFonts.sizeMD,
                        fontWeight: AppFonts.semibold,
                      ),
                      maxLines: SettingsService.focusedTitleDisplayMode ==
                              FocusedTitleDisplayMode.normal
                          ? 2
                          : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person_outline, size: 12, color: AppColors.inactiveText),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.authorName,
                    style: TextStyle(
                      color: AppColors.inactiveText,
                      fontSize: AppFonts.sizeSM,
                      fontWeight: AppFonts.medium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.pubdateFormatted.isNotEmpty)
                  Text(
                    item.pubdateFormatted,
                    style: TextStyle(
                      color: AppColors.inactiveText,
                      fontSize: AppFonts.sizeSM,
                      fontWeight: AppFonts.medium,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage() {
    if (item.firstImage.isEmpty) {
      return Container(color: Colors.grey[900]);
    }
    return CachedNetworkImage(
      imageUrl: ImageUrlUtils.getResizedUrl(item.firstImage, width: 480, height: 360),
      fit: BoxFit.cover,
      memCacheWidth: 480,
      memCacheHeight: 360,
      cacheManager: BiliCacheManager.instance,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => Container(color: const Color(0xFF2d2d2d)),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[900],
        child: Icon(Icons.broken_image, size: 20, color: Colors.white24),
      ),
    );
  }
}

/// 专栏动态卡片 — 列表布局（左封面右文字）
///
/// 不使用 BaseTvCard（其 16:9 AspectRatio 不适合横向列表布局），
/// 自行实现 TvFocusScope + scrollToReveal 逻辑以保持焦点导航一致性。
class TvDynamicArticleCard extends StatefulWidget {
  final DynamicArticle item;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final FocusNode? focusNode;
  final int index;
  final double topOffset;

  const TvDynamicArticleCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
    this.index = 0,
    this.topOffset = TabStyle.defaultTopOffset,
  });

  @override
  State<TvDynamicArticleCard> createState() => _TvDynamicArticleCardState();
}

class _TvDynamicArticleCardState extends State<TvDynamicArticleCard> {
  bool _isFocused = false;
  DateTime _lastFocusTime = DateTime(0);
  static const _rapidThreshold = Duration(milliseconds: 150);

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      widget.onFocus();
      final now = DateTime.now();
      final isRapid = now.difference(_lastFocusTime) < _rapidThreshold;
      _lastFocusTime = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToReveal(animate: !isRapid);
      });
    }
  }

  void _scrollToReveal({required bool animate}) {
    final ro = context.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize) return;

    final scrollableState = Scrollable.maybeOf(context);
    if (scrollableState == null) return;

    final position = scrollableState.position;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final cardInViewport = ro.localToGlobal(Offset.zero, ancestor: scrollableRO);
    final viewportHeight = scrollableRO.size.height;
    final cardHeight = ro.size.height;
    final cardTop = cardInViewport.dy;
    final cardBottom = cardTop + cardHeight;

    final revealHeight = cardHeight * TabStyle.scrollRevealRatio;
    final topBoundary = widget.topOffset + revealHeight;
    final bottomBoundary = viewportHeight - revealHeight;
    final isFirstRow = widget.index == 0;

    double? targetScrollOffset;

    if (isFirstRow) {
      if ((cardTop - topBoundary).abs() > 50) {
        targetScrollOffset = position.pixels + (cardTop - topBoundary);
      }
    } else if (cardBottom > bottomBoundary) {
      targetScrollOffset = position.pixels + (cardBottom - bottomBoundary);
    } else if (cardTop < topBoundary) {
      targetScrollOffset = position.pixels + (cardTop - topBoundary);
    }

    if (targetScrollOffset == null) return;
    final target = targetScrollOffset.clamp(
        position.minScrollExtent, position.maxScrollExtent);
    if ((position.pixels - target).abs() < 4.0) return;

    if (animate) {
      position.animateTo(target,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      position.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.grid,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onExitLeft: widget.onMoveLeft,
      onExitRight: widget.onMoveRight,
      onExitUp: widget.onMoveUp,
      onExitDown: widget.onMoveDown,
      onSelect: widget.onTap,
      enableKeyRepeat: true,
      child: Builder(
        builder: (ctx) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _isFocused
                      ? SettingsService.themeColor.withValues(
                          alpha: SettingsService.videoCardThemeAlpha)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.item.coverUrl.isNotEmpty)
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: ImageUrlUtils.getResizedUrl(
                                widget.item.coverUrl,
                                width: 360,
                                height: 200),
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            memCacheHeight: 200,
                            cacheManager: BiliCacheManager.instance,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) =>
                                Container(color: const Color(0xFF2d2d2d)),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[900],
                              child: Icon(Icons.broken_image,
                                  size: 20, color: Colors.white24),
                            ),
                          ),
                        ),
                      ),
                    if (widget.item.coverUrl.isNotEmpty)
                      const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.title,
                              style: TextStyle(
                                color: _isFocused
                                    ? AppColors.primaryText
                                    : AppColors.secondaryText,
                                fontSize: AppFonts.sizeMD,
                                fontWeight: _isFocused
                                    ? FontWeight.bold
                                    : AppFonts.semibold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.item.desc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.item.desc,
                                style: TextStyle(
                                  color: AppColors.inactiveText,
                                  fontSize: AppFonts.sizeSM,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_outline,
                                          size: 12,
                                          color: AppColors.inactiveText),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          widget.item.authorName,
                                          style: TextStyle(
                                            color: AppColors.inactiveText,
                                            fontSize: AppFonts.sizeSM,
                                            fontWeight: AppFonts.medium,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(Icons.favorite_outline,
                                          size: 12,
                                          color: AppColors.inactiveText),
                                      const SizedBox(width: 2),
                                      Text(
                                        widget.item.likeFormatted,
                                        style: TextStyle(
                                          color: AppColors.inactiveText,
                                          fontSize: AppFonts.sizeSM,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(Icons.chat_bubble_outline,
                                          size: 11,
                                          color: AppColors.inactiveText),
                                      const SizedBox(width: 2),
                                      Text(
                                        widget.item.commentFormatted,
                                        style: TextStyle(
                                          color: AppColors.inactiveText,
                                          fontSize: AppFonts.sizeSM,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.item.pubdateFormatted
                                    .isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(left: 10),
                                    child: Text(
                                      widget.item.pubdateFormatted,
                                      style: TextStyle(
                                        color: AppColors.inactiveText,
                                        fontSize: AppFonts.sizeSM,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
