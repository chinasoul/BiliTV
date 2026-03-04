import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../utils/image_url_utils.dart';
import '../../config/app_style.dart';
import '../../widgets/time_display.dart';
import '../player/player_screen.dart';
import '../video_detail/video_detail_screen.dart';

/// UP主空间页面（独立页面方式）
/// 包含：UP主详细信息、投稿视频列表、关注/充电按钮
class UpSpaceScreen extends StatefulWidget {
  final int upMid;
  final String upName;
  final String upFace;

  const UpSpaceScreen({
    super.key,
    required this.upMid,
    required this.upName,
    required this.upFace,
  });

  @override
  State<UpSpaceScreen> createState() => _UpSpaceScreenState();
}

class _UpSpaceScreenState extends State<UpSpaceScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, FocusNode> _videoFocusNodes = {};
  final FocusNode _mainFocusNode = FocusNode();

  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  String _order = 'pubdate'; // pubdate / click

  // 排序缓存：order → videos
  final Map<String, List<Video>> _cachedVideos = {};

  // UP主详细信息
  Map<String, dynamic>? _userInfo;
  bool _isLoadingUserInfo = true;
  bool _isFollowing = false;

  // 焦点索引: 0=最新按钮, 1=最热按钮, 2=关注按钮, 3=充电按钮, 4+=视频列表
  int _focusedIndex = 4;

  // 固定高度常量
  static const double _headerHeight = 130.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mainFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _mainFocusNode.dispose();
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _videoFocusNodes.clear();
    super.dispose();
  }

  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void _onScroll() {
    if (!_isLoading &&
        !_isLoadingMore &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadVideos(reset: false);
    }
  }

  Future<void> _loadData() async {
    await Future.wait([_loadUserInfo(), _loadVideos(reset: true)]);
  }

  Future<void> _loadUserInfo() async {
    setState(() => _isLoadingUserInfo = true);
    final info = await BilibiliApi.getUserCardInfo(widget.upMid);
    if (!mounted) return;
    setState(() {
      _userInfo = info;
      _isFollowing = info?['following'] ?? false;
      _isLoadingUserInfo = false;
    });
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _videos = [];
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final list = await BilibiliApi.getSpaceVideos(
      mid: widget.upMid,
      page: reset ? 1 : _page,
      order: _order,
    );
    if (!mounted) return;

    setState(() {
      if (reset) {
        _videos = list;
        _isLoading = false;
        // 初始加载完成后缓存
        if (list.isNotEmpty) {
          _cachedVideos[_order] = List.from(list);
        }
        // 初始加载完成后，让第一个视频获得焦点
        if (list.isNotEmpty && _focusedIndex >= 4) {
          _focusedIndex = 4;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusCurrentItem();
          });
        }
      } else {
        final existing = _videos.map((v) => v.bvid).toSet();
        _videos.addAll(list.where((v) => !existing.contains(v.bvid)));
        _isLoadingMore = false;
      }
      _hasMore = list.isNotEmpty;
      if (!reset && list.isNotEmpty) {
        _page += 1;
      } else if (reset) {
        _page = 2;
      }
    });
  }

  /// 让当前焦点项获得实际焦点并滚动到可见区域
  void _focusCurrentItem() {
    if (!mounted) return;
    if (_focusedIndex >= 4) {
      final videoIndex = _focusedIndex - 4;
      if (_videoFocusNodes.containsKey(videoIndex)) {
        _videoFocusNodes[videoIndex]!.requestFocus();
        _scrollToIndex(videoIndex);
      }
    }
  }

  /// 滚动到指定索引的视频卡片
  void _scrollToIndex(int videoIndex) {
    if (!_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final gridColumns = SettingsService.videoGridColumns;
      final position = _scrollController.position;
      final viewportHeight = position.viewportDimension;

      // 估算行高
      final estimatedRowHeight = viewportHeight * 0.35;
      final row = videoIndex ~/ gridColumns;

      // 当前行的顶部位置
      final rowTop = row * estimatedRowHeight;

      // 可见区域（考虑 header）
      final visibleTop = position.pixels;
      final visibleBottom =
          position.pixels + viewportHeight - _headerHeight - 20;

      double? targetOffset;

      if (row == 0) {
        // 第一行：滚动到顶部
        targetOffset = 0;
      } else if (rowTop < visibleTop) {
        // 行在可见区域上方：向上滚动
        targetOffset = rowTop - 20;
      } else if (rowTop + estimatedRowHeight > visibleBottom) {
        // 行在可见区域下方：向下滚动，让当前行显示在底部
        targetOffset =
            rowTop - viewportHeight + _headerHeight + estimatedRowHeight + 40;
      }

      if (targetOffset == null) return;

      final target = targetOffset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if ((position.pixels - target).abs() < 10) return;

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// 切换排序（左右键）- 使用缓存，瞬间切换
  Future<void> _switchOrder(String newOrder) async {
    if (_order == newOrder) return;

    // 保存当前排序的数据到缓存
    if (_videos.isNotEmpty) {
      _cachedVideos[_order] = List.from(_videos);
    }

    setState(() => _order = newOrder);

    // 尝试从缓存恢复
    if (_cachedVideos.containsKey(newOrder)) {
      setState(() {
        _videos = _cachedVideos[newOrder]!;
      });
      return;
    }

    // 缓存中没有，需要网络加载
    await _loadVideos(reset: true);
    // 加载完成后存入缓存
    if (_videos.isNotEmpty) {
      _cachedVideos[newOrder] = List.from(_videos);
    }
  }

  /// 刷新当前排序（点击确定）- 强制网络请求
  Future<void> _refreshOrder(String order) async {
    setState(() => _order = order);
    // 清除该排序的缓存
    _cachedVideos.remove(order);
    await _loadVideos(reset: true);
    // 重新缓存
    if (_videos.isNotEmpty) {
      _cachedVideos[order] = List.from(_videos);
    }
  }

  Future<void> _toggleFollow() async {
    final success = await BilibiliApi.followUser(
      mid: widget.upMid,
      follow: !_isFollowing,
    );
    if (!mounted) return;
    if (success) {
      setState(() => _isFollowing = !_isFollowing);
      ToastUtils.dismiss();
      ToastUtils.show(context, _isFollowing ? '已关注' : '已取消关注');
    } else {
      ToastUtils.dismiss();
      ToastUtils.show(context, '操作失败');
    }
  }

  void _openCharge() {
    ToastUtils.show(context, '请在手机端进行充电');
  }

  void _openVideo(Video video) {
    final previousFocus = FocusManager.instance.primaryFocus;
    final Widget target = SettingsService.showVideoDetailBeforePlay
        ? VideoDetailScreen(video: video)
        : PlayerScreen(video: video);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => target))
        .then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previousFocus != null && previousFocus.canRequestFocus) {
          previousFocus.requestFocus();
        }
      });
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 返回键关闭页面
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    final gridColumns = SettingsService.videoGridColumns;

    return TvKeyHandler.handleNavigationWithRepeat(
      event,
      onLeft: () {
        if (_focusedIndex == 0) {
          Navigator.of(context).pop();
        } else if (_focusedIndex <= 3) {
          final oldIndex = _focusedIndex;
          setState(() => _focusedIndex--);
          if (oldIndex == 1 && _focusedIndex == 0) {
            _switchOrder('pubdate');
          }
        } else {
          final videoIndex = _focusedIndex - 4;
          if (videoIndex % gridColumns == 0) {
            Navigator.of(context).pop();
          } else {
            setState(() => _focusedIndex--);
            _focusCurrentItem();
          }
        }
      },
      onRight: () {
        if (_focusedIndex < 3) {
          final oldIndex = _focusedIndex;
          setState(() => _focusedIndex++);
          if (oldIndex == 0 && _focusedIndex == 1) {
            _switchOrder('click');
          }
        } else if (_focusedIndex >= 4) {
          final videoIndex = _focusedIndex - 4;
          if (videoIndex + 1 < _videos.length) {
            setState(() => _focusedIndex++);
            _focusCurrentItem();
          }
        }
      },
      onUp: () {
        if (_focusedIndex > 3) {
          final videoIndex = _focusedIndex - 4;
          if (videoIndex < gridColumns) {
            setState(() => _focusedIndex = 0);
            _mainFocusNode.requestFocus();
          } else {
            setState(() => _focusedIndex -= gridColumns);
            _focusCurrentItem();
          }
        }
      },
      onDown: () {
        if (_focusedIndex <= 3) {
          if (_videos.isNotEmpty) {
            setState(() => _focusedIndex = 4);
            _focusCurrentItem();
          }
        } else {
          final videoIndex = _focusedIndex - 4;
          if (videoIndex + gridColumns < _videos.length) {
            setState(() => _focusedIndex += gridColumns);
            _focusCurrentItem();
          }
        }
      },
      onSelect: () {
        if (_focusedIndex == 0) {
          _refreshOrder('pubdate');
        } else if (_focusedIndex == 1) {
          _refreshOrder('click');
        } else if (_focusedIndex == 2) {
          _toggleFollow();
        } else if (_focusedIndex == 3) {
          _openCharge();
        } else if (_focusedIndex >= 4 && _focusedIndex - 4 < _videos.length) {
          _openVideo(_videos[_focusedIndex - 4]);
        }
      },
    );
  }

  String _formatNumber(int num) {
    if (num >= 100000000) {
      return '${(num / 100000000).toStringAsFixed(1)}亿';
    } else if (num >= 10000) {
      return '${(num / 10000).toStringAsFixed(1)}万';
    }
    return num.toString();
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;
    final themeColor = SettingsService.themeColor;

    return Scaffold(
      backgroundColor: AppColors.headerBackground,
      body: Focus(
        focusNode: _mainFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: Stack(
          children: [
            // 视频列表
            Positioned.fill(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _videos.isEmpty
                  ? Center(
                      child: Text(
                        '该 UP 暂无投稿视频',
                        style: TextStyle(color: AppColors.inactiveText, fontSize: AppFonts.sizeXL),
                      ),
                    )
                  : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            30,
                            _headerHeight + 10,
                            30,
                            80,
                          ),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridColumns,
                                  childAspectRatio: GridStyle.videoCardAspectRatio(context, gridColumns),
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 10,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final video = _videos[index];
                                final isFocused = _focusedIndex == index + 4;
                                return _buildVideoCard(video, index, isFocused);
                              },
                              childCount: _videos.length,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: false,
                            ),
                          ),
                        ),
                        if (_isLoadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                      ],
                    ),
            ),
            // 顶部信息栏（固定高度）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _headerHeight,
              child: Container(
                color: AppColors.headerBackground,
                padding: const EdgeInsets.fromLTRB(30, 20, 30, 12),
                child: _buildHeader(themeColor),
              ),
            ),
            // 时间显示
            if (SettingsService.showTimeDisplay)
              const Positioned(top: 10, right: 14, child: TimeDisplay()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color themeColor) {
    final sex = _userInfo?['sex'] ?? '保密';
    final level = _userInfo?['level'] ?? 0;
    final fans = _userInfo?['fans'] ?? 0;
    final attention = _userInfo?['attention'] ?? 0;
    final likeNum = _userInfo?['likeNum'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 第一行：头像、名字、标签信息（固定高度）
        SizedBox(
          height: 56,
          child: Row(
            children: [
              // 头像
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: widget.upFace,
                  cacheManager: BiliCacheManager.instance,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: AppColors.navItemSelectedBackground,
                    alignment: Alignment.center,
                    child: Icon(Icons.person, color: AppColors.inactiveText),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: AppColors.navItemSelectedBackground,
                    alignment: Alignment.center,
                    child: Icon(Icons.person, color: AppColors.inactiveText),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 名字和标签
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 名字行
                    SizedBox(
                      height: 26,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.upName,
                              style: TextStyle(
                                fontSize: AppFonts.sizeXL,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (sex == '男')
                            Icon(Icons.male, color: Colors.blue, size: 18)
                          else if (sex == '女')
                            Icon(
                              Icons.female,
                              color: Colors.pink,
                              size: 18,
                            ),
                          const SizedBox(width: 6),
                          _buildLevelBadge(level),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 粉丝、关注、获赞（固定高度）
                    SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          _buildStatItem('关注', attention, _isLoadingUserInfo),
                          const SizedBox(width: 14),
                          _buildStatItem('粉丝', fans, _isLoadingUserInfo),
                          const SizedBox(width: 14),
                          _buildStatItem('获赞', likeNum, _isLoadingUserInfo),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 第二行：排序按钮 + 关注/充电按钮（固定高度）
        SizedBox(
          height: 32,
          child: Row(
            children: [
              _buildSortButton('最新', 0, _order == 'pubdate', themeColor),
              const SizedBox(width: 10),
              _buildSortButton('最热', 1, _order == 'click', themeColor),
              const Spacer(),
              _buildActionButton(
                _isFollowing ? '已关注' : '+ 关注',
                2,
                _isFollowing ? Colors.grey : themeColor,
                icon: _isFollowing ? Icons.check : Icons.add,
              ),
              const SizedBox(width: 10),
              _buildActionButton('充电', 3, Colors.orange, icon: Icons.flash_on),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLevelBadge(int level) {
    final color = level >= 6
        ? Colors.red
        : level >= 4
        ? Colors.orange
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        'LV$level',
        style: TextStyle(
          color: color,
          fontSize: AppFonts.sizeXS,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, [bool isLoading = false]) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.inactiveText,
            fontSize: AppFonts.sizeSM,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          isLoading ? '--' : _formatNumber(value),
          style: TextStyle(
            color: AppColors.primaryText,
            fontSize: AppFonts.sizeSM,
            fontWeight: AppFonts.semibold,
          ),
        ),
      ],
    );
  }

  Widget _buildSortButton(
    String label,
    int index,
    bool isActive,
    Color themeColor,
  ) {
    final isFocused = _focusedIndex == index;
    return GestureDetector(
      onTap: () => _refreshOrder(index == 0 ? 'pubdate' : 'click'), // 点击：强制刷新
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isFocused
              ? themeColor.withValues(alpha: 0.7)
              : isActive
              ? AppColors.navItemSelectedBackground
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isFocused
                ? AppColors.primaryText
                : isActive
                ? AppColors.inactiveText
                : Colors.transparent,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              index == 0 ? Icons.schedule : Icons.whatshot,
              color: isFocused || isActive
                  ? AppColors.primaryText
                  : AppColors.inactiveText,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isFocused || isActive
                    ? AppColors.primaryText
                    : AppColors.inactiveText,
                fontSize: AppFonts.sizeSM,
                fontWeight: isActive ? AppFonts.semibold : AppFonts.regular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    int index,
    Color color, {
    IconData? icon,
  }) {
    final isFocused = _focusedIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 2) {
          _toggleFollow();
        } else if (index == 3) {
          _openCharge();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isFocused ? color : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isFocused ? Colors.white : color,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.primaryText, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: AppColors.primaryText,
                fontSize: AppFonts.sizeSM,
                fontWeight: AppFonts.semibold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 视频卡片 - 只负责显示和焦点效果，导航由页面控制
  Widget _buildVideoCard(Video video, int index, bool isFocused) {
    final themeColor = SettingsService.themeColor;

    return Focus(
      focusNode: _getFocusNode(index),
      onFocusChange: (hasFocus) {
        if (hasFocus && _focusedIndex != index + 4) {
          setState(() => _focusedIndex = index + 4);
        }
      },
      child: GestureDetector(
        onTap: () => _openVideo(video),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isFocused
                ? themeColor.withValues(alpha: 0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _buildVideoCardContent(video),
        ),
      ),
    );
  }

  /// 构建视频卡片内容（封面、标题、信息）
  Widget _buildVideoCardContent(Video video) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: ImageUrlUtils.getResizedUrl(video.pic, width: 480),
                  cacheManager: BiliCacheManager.instance,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey[850]),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey[850],
                    child: Icon(Icons.error, color: AppColors.inactiveText),
                  ),
                ),
                // 时长
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video.durationFormatted,
                      style: TextStyle(color: Colors.white, fontSize: AppFonts.sizeXS),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // 标题
        Text(
          video.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.secondaryText, fontSize: AppFonts.sizeSM),
        ),
        const SizedBox(height: 2),
        // 播放量
        Text(
          '${video.viewFormatted}播放',
          style: TextStyle(
            color: AppColors.inactiveText,
            fontSize: AppFonts.sizeXS,
          ),
        ),
      ],
    );
  }
}
