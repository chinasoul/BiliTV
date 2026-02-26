import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import 'package:bili_tv_app/utils/image_url_utils.dart';
import '../../../services/bilibili_api.dart';
import '../../../models/video.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// Uploader Panel - Shows uploader's videos and follow button
class UpPanel extends StatefulWidget {
  final String upName;
  final String upFace;
  final int upMid;
  final Function(Video) onVideoSelect;
  final VoidCallback onClose;

  const UpPanel({
    super.key,
    required this.upName,
    required this.upFace,
    required this.upMid,
    required this.onVideoSelect,
    required this.onClose,
  });

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  List<Video> _videos = [];
  bool _isFollowing = false;
  bool _isLoading = true;
  String _order = 'pubdate'; // 'pubdate' = time, 'click' = popularity
  // Focus index: 0+ = video list, -1 = sort最新, -2 = sort最热, -3 = follow button
  int _focusedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // 用于获取列表项的 GlobalKey
  final Map<int, GlobalKey> _itemKeys = {};

  // 排序缓存：order → videos
  final Map<String, List<Video>> _cachedVideos = {};

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      BilibiliApi.getSpaceVideos(mid: widget.upMid, order: _order),
      BilibiliApi.checkFollowStatus(widget.upMid),
    ]);

    if (mounted) {
      setState(() {
        _videos = results[0] as List<Video>;
        _isFollowing = results[1] as bool;
        _isLoading = false;
        // Default focus on first video
        _focusedIndex = _videos.isNotEmpty ? 0 : -1;
      });
    }
  }

  Future<void> _toggleSort() async {
    final newOrder = _order == 'pubdate' ? 'click' : 'pubdate';
    // 保存当前焦点位置
    final currentFocusIndex = _focusedIndex;

    // 保存当前排序的数据到缓存
    if (_videos.isNotEmpty) {
      _cachedVideos[_order] = List.from(_videos);
    }

    setState(() {
      _order = newOrder;
    });

    // 尝试从缓存恢复
    if (_cachedVideos.containsKey(newOrder)) {
      setState(() {
        _videos = _cachedVideos[newOrder]!;
        // 保持焦点不变
        _focusedIndex = currentFocusIndex;
      });
      return;
    }

    // 缓存中没有，需要加载
    setState(() => _isLoading = true);

    final videos = await BilibiliApi.getSpaceVideos(
      mid: widget.upMid,
      order: newOrder,
    );
    if (mounted) {
      setState(() {
        _videos = videos;
        _cachedVideos[newOrder] = List.from(videos);
        _isLoading = false;
        // 保持焦点不变，除非视频列表为空
        if (currentFocusIndex >= 0 && _videos.isEmpty) {
          _focusedIndex = _order == 'pubdate' ? -1 : -2;
        } else {
          _focusedIndex = currentFocusIndex;
        }
      });
    }
  }

  Future<void> _toggleFollow() async {
    final success = await BilibiliApi.followUser(
      mid: widget.upMid,
      follow: !_isFollowing,
    );

    if (success) {
      setState(() => _isFollowing = !_isFollowing);
      ToastUtils.dismiss();
      ToastUtils.show(context, _isFollowing ? '已关注' : '已取消关注');
    } else {
      ToastUtils.dismiss();
      ToastUtils.show(context, '操作失败');
    }
  }

  void _scrollToFocused() {
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

    position.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > -3) {
        setState(() => _focusedIndex--);
        if (_focusedIndex >= 0) _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _videos.length - 1) {
        setState(() => _focusedIndex++);
        if (_focusedIndex >= 0) _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // 排序按钮区域：左右切换
      if (_focusedIndex == -2) {
        setState(() => _focusedIndex = -1);
        // 聚焦即切换模式
        if (SettingsService.focusSwitchTab) {
          _switchOrder('pubdate');
        }
      } else if (_focusedIndex == -3) {
        setState(() => _focusedIndex = -2);
      } else if (_focusedIndex >= 0) {
        // 视频列表：左键关闭面板
        widget.onClose();
      } else if (_focusedIndex == -1) {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // 排序按钮区域：左右切换
      if (_focusedIndex == -1) {
        setState(() => _focusedIndex = -2);
        // 聚焦即切换模式
        if (SettingsService.focusSwitchTab) {
          _switchOrder('click');
        }
      } else if (_focusedIndex == -2) {
        setState(() => _focusedIndex = -3);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedIndex == -1) {
        _switchOrder('pubdate');
      } else if (_focusedIndex == -2) {
        _switchOrder('click');
      } else if (_focusedIndex == -3) {
        _toggleFollow();
      } else if (_videos.isNotEmpty && _focusedIndex >= 0) {
        widget.onVideoSelect(_videos[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }

    // Back key: Not handled here, handled by PopScope/onPopInvoked
    return KeyEventResult.ignored;
  }

  void _switchOrder(String newOrder) {
    if (_order == newOrder) return;
    _toggleSort();
  }

  @override
  Widget build(BuildContext context) {
    final isNewSortFocused = _focusedIndex == -1;
    final isHotSortFocused = _focusedIndex == -2;
    final isFollowButtonFocused = _focusedIndex == -3;
    final panelWidth = SettingsService.getSidePanelWidth(context);
    final themeColor = SettingsService.themeColor;

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
              // Header: Uploader Info
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 第一行：头像 + 名字
                    Row(
                      children: [
                        // 头像
                        ClipOval(
                          child: widget.upFace.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: ImageUrlUtils.getResizedUrl(
                                    widget.upFace,
                                    width: 80,
                                    height: 80,
                                  ),
                                  cacheManager: BiliCacheManager.instance,
                                  memCacheWidth: 80,
                                  memCacheHeight: 80,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => const CircleAvatar(
                                    radius: 20,
                                    child: Icon(Icons.person, size: 20),
                                  ),
                                )
                              : const CircleAvatar(
                                  radius: 20,
                                  child: Icon(Icons.person, size: 20),
                                ),
                        ),
                        const SizedBox(width: 12),
                        // 名称 - 可以占用更多空间
                        Expanded(
                          child: Text(
                            widget.upName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 第二行：排序按钮 + 关注按钮
                    Row(
                      children: [
                        // 排序按钮组
                        _buildSortChip(
                          '最新',
                          -1,
                          _order == 'pubdate',
                          isNewSortFocused,
                          themeColor,
                        ),
                        const SizedBox(width: 8),
                        _buildSortChip(
                          '最热',
                          -2,
                          _order == 'click',
                          isHotSortFocused,
                          themeColor,
                        ),
                        const Spacer(),
                        // 关注按钮
                        _buildFollowButton(isFollowButtonFocused, themeColor),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.grey, height: 1),
              // 视频列表
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _videos.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无视频',
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

  Widget _buildSortChip(
    String label,
    int focusIndex,
    bool isActive,
    bool isFocused,
    Color themeColor,
  ) {
    return GestureDetector(
      onTap: () => _switchOrder(focusIndex == -1 ? 'pubdate' : 'click'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isFocused
              ? themeColor.withValues(alpha: 0.6)
              : isActive
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isActive && !isFocused
              ? Border.all(color: Colors.white24, width: 0.5)
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isFocused
                ? Colors.white
                : isActive
                ? Colors.white
                : Colors.white54,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton(bool isFocused, Color themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused
            ? themeColor.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isFocused ? Colors.white : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isFollowing ? Icons.check : Icons.add,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            _isFollowing ? '已关注' : '关注',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoItem(Video video, bool isFocused, int index) {
    return Container(
      key: _itemKeys[index],
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFocused ? Colors.white : Colors.transparent,
          width: 2,
        ),
      ),
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
              width: 100,
              height: 56,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 100,
                height: 56,
                color: Colors.grey[800],
              ),
              errorWidget: (_, _, _) => Container(
                width: 100,
                height: 56,
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
                    color: isFocused ? Colors.white : Colors.grey[300],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${video.viewFormatted} 播放',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    if (video.pubdateFormatted.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        video.pubdateFormatted,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
