import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import '../../../utils/image_url_utils.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../config/app_style.dart';
import '../../../models/video.dart';

/// Related Videos Panel
class RelatedPanel extends StatefulWidget {
  final String bvid;
  final Function(Video) onVideoSelect;
  final VoidCallback onClose;

  const RelatedPanel({
    super.key,
    required this.bvid,
    required this.onVideoSelect,
    required this.onClose,
  });

  @override
  State<RelatedPanel> createState() => _RelatedPanelState();
}

class _RelatedPanelState extends State<RelatedPanel> {
  List<Video> _videos = [];
  bool _isLoading = true;
  int _focusedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // 用于获取列表项的 GlobalKey
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _loadVideos();
    // Request focus in next frame to ensure panel is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    final videos = await BilibiliApi.getRelatedVideos(widget.bvid);
    if (mounted) {
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    }
  }

  void _scrollToFocused({required bool animate}) {
    if (_videos.isEmpty || _focusedIndex < 0) return;
    if (!_scrollController.hasClients) return;

    final key = _itemKeys[_focusedIndex];
    if (key == null) return;

    final itemContext = key.currentContext;
    if (itemContext == null) return;

    final ro = itemContext.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize) return;

    final scrollableState = Scrollable.maybeOf(itemContext);
    if (scrollableState == null) return;

    final position = scrollableState.position;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final itemInViewport = ro.localToGlobal(
      Offset.zero,
      ancestor: scrollableRO,
    );
    final viewportHeight = scrollableRO.size.height;
    final itemHeight = ro.size.height;
    final itemTop = itemInViewport.dy;
    final itemBottom = itemTop + itemHeight;

    // 定义安全边界
    final revealHeight = itemHeight * 0.3;
    final topBoundary = revealHeight;
    final bottomBoundary = viewportHeight - revealHeight;

    double? targetScrollOffset;

    if (itemBottom > bottomBoundary) {
      // 焦点项底部超出底部边界：向下滚动
      final delta = itemBottom - bottomBoundary;
      targetScrollOffset = position.pixels + delta;
    } else if (itemTop < topBoundary) {
      // 焦点项顶部超出顶部边界：向上滚动
      final delta = itemTop - topBoundary;
      targetScrollOffset = position.pixels + delta;
    }

    if (targetScrollOffset == null) return;

    final target = targetScrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((position.pixels - target).abs() < 4.0) return;

    if (animate) {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      position.jumpTo(target);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isRepeat = event is KeyRepeatEvent;
    // 上下支持长按连续移动
    final upDownResult = TvKeyHandler.handleNavigationWithRepeat(
      event,
      onUp: () {
        if (_focusedIndex > 0) {
          setState(() => _focusedIndex--);
          _scrollToFocused(animate: !isRepeat);
        }
      },
      onDown: () {
        if (_focusedIndex < _videos.length - 1) {
          setState(() => _focusedIndex++);
          _scrollToFocused(animate: !isRepeat);
        }
      },
      blockUp: true,
      blockDown: true,
    );
    if (upDownResult == KeyEventResult.handled) return upDownResult;

    // 左右/确认保持单击触发，避免长按误操作
    return TvKeyHandler.handleSinglePress(
      event,
      onLeft: widget.onClose,
      onSelect: () {
        if (_videos.isNotEmpty) {
          widget.onVideoSelect(_videos[_focusedIndex]);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = SettingsService.getSidePanelWidth(context);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: panelWidth,
          height: double.infinity,
          color: SidePanelStyle.background,
          child: Column(
            children: [
              // 头部
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.expand_more, color: AppColors.primaryText, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '更多视频',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: AppFonts.sizeXL,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: AppColors.navItemSelectedBackground, height: 1),
              // 视频列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _videos.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无相关视频',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _videos.length,
                        itemBuilder: (context, index) {
                          _itemKeys[index] ??= GlobalKey();
                          return _buildVideoItem(
                            _videos[index],
                            index == _focusedIndex,
                            index,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoItem(Video video, bool isFocused, int index) {
    final themeColor = SettingsService.themeColor;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.4);
    final itemHeight = 70.0 + (textScale - 1.0) * 42.0;
    final thumbHeight = 56.0 + (textScale - 1.0) * 10.0;
    final thumbWidth = thumbHeight * 16.0 / 9.0;
    final metaGap = textScale > 1.2 ? 2.0 : 4.0;

    return Container(
      key: _itemKeys[index],
      height: itemHeight,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused
            ? themeColor.withValues(alpha: AppColors.focusAlpha)
            : AppColors.navItemSelectedBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFocused ? AppColors.primaryText : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: ImageUrlUtils.getResizedUrl(
                video.pic,
                width: 200,
                height: 112,
              ),
              cacheManager: BiliCacheManager.instance,
              memCacheWidth: 200,
              memCacheHeight: 112,
              width: thumbWidth,
              height: thumbHeight,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: thumbWidth,
                height: thumbHeight,
                color: Colors.grey[800],
              ),
              errorWidget: (_, _, _) => Container(
                width: thumbWidth,
                height: thumbHeight,
                color: Colors.grey[800],
                child: const Icon(Icons.error, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isFocused ? AppColors.primaryText : AppColors.secondaryText,
                    fontSize: AppFonts.sizeMD,
                  ),
                ),
                SizedBox(height: metaGap),
                Text(
                  [
                    video.ownerName,
                    '${video.viewFormatted}播放',
                    if (video.pubdateFormatted.isNotEmpty) video.pubdateFormatted,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.inactiveText, fontSize: AppFonts.sizeSM),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
