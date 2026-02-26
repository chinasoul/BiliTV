import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../models/following_user.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../utils/image_url_utils.dart';
import '../player/player_screen.dart';

/// UP主空间弹窗（Popup方式，半透明遮罩+居中弹窗）
/// 相比新窗口方式，内存开销更低，同时保持上下文感
class UpSpacePopup extends StatefulWidget {
  final FollowingUser user;
  final VoidCallback onClose;

  const UpSpacePopup({super.key, required this.user, required this.onClose});

  @override
  State<UpSpacePopup> createState() => _UpSpacePopupState();
}

class _UpSpacePopupState extends State<UpSpacePopup> {
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

  // 快速导航节流：记录上次焦点时间，短间隔内用 jumpTo 而非 animateTo
  DateTime _lastFocusTime = DateTime(0);
  static const _rapidThreshold = Duration(milliseconds: 150);

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
    final info = await BilibiliApi.getUserCardInfo(widget.user.mid);
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
      mid: widget.user.mid,
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
        // 记录当前时间，判断是否快速导航
        final now = DateTime.now();
        final isRapid = now.difference(_lastFocusTime) < _rapidThreshold;
        _lastFocusTime = now;
        // 延迟滚动，等待焦点切换完成后获取正确的 RenderObject 位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToFocusedCard(videoIndex, animate: !isRapid);
        });
      }
    }
  }

  /// 滚动到指定索引的视频卡片（使用实际 RenderObject 位置，与主页一致）
  void _scrollToFocusedCard(int videoIndex, {required bool animate}) {
    if (!mounted || !_scrollController.hasClients) return;

    final focusNode = _videoFocusNodes[videoIndex];
    if (focusNode == null || focusNode.context == null) return;

    final ro = focusNode.context!.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize) return;

    final scrollableState = Scrollable.maybeOf(focusNode.context!);
    if (scrollableState == null) return;

    final position = scrollableState.position;
    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    // 获取卡片在滚动视口中的位置
    final cardInViewport = ro.localToGlobal(
      Offset.zero,
      ancestor: scrollableRO,
    );
    final viewportHeight = scrollableRO.size.height;
    final cardHeight = ro.size.height;
    final cardTop = cardInViewport.dy;
    final cardBottom = cardTop + cardHeight;

    // 顶部安全边界：header 高度 + 露出上一行的比例
    final revealHeight = cardHeight * 0.25; // TabStyle.scrollRevealRatio
    final topBoundary = _headerHeight + revealHeight;

    // 底部安全边界：屏幕底部留出空间，用于显示下一行
    final bottomBoundary = viewportHeight - revealHeight;

    // 判断是否是第一行
    final gridColumns = SettingsService.videoGridColumns;
    final isFirstRow = videoIndex < gridColumns;

    double? targetScrollOffset;

    if (isFirstRow) {
      // 第一行：确保卡片顶部在顶部边界位置
      if ((cardTop - topBoundary).abs() > 50) {
        final delta = cardTop - topBoundary;
        targetScrollOffset = position.pixels + delta;
      }
    } else if (cardBottom > bottomBoundary) {
      // 卡片底部超出底部边界：向上滚动
      final delta = cardBottom - bottomBoundary;
      targetScrollOffset = position.pixels + delta;
    } else if (cardTop < topBoundary) {
      // 卡片顶部超出顶部边界：向下滚动
      final delta = cardTop - topBoundary;
      targetScrollOffset = position.pixels + delta;
    }
    // 卡片在安全区域内：不滚动

    if (targetScrollOffset == null) return;

    final target = targetScrollOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    // 只有滚动距离超过阈值才执行
    if ((position.pixels - target).abs() < 4.0) return;

    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
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
      mid: widget.user.mid,
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
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 处理 KeyDownEvent 和 KeyRepeatEvent（支持长按）
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final gridColumns = SettingsService.videoGridColumns;

    // 返回键由 FollowingTab 的 handleBack 统一处理，这里只处理 ESC 键
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_focusedIndex == 0) {
        widget.onClose();
      } else if (_focusedIndex <= 3) {
        final oldIndex = _focusedIndex;
        setState(() => _focusedIndex--);
        // 在排序按钮之间切换时，使用缓存切换
        if (oldIndex == 1 && _focusedIndex == 0) {
          _switchOrder('pubdate');
        }
      } else {
        final videoIndex = _focusedIndex - 4;
        if (videoIndex % gridColumns == 0) {
          widget.onClose();
        } else {
          setState(() => _focusedIndex--);
          _focusCurrentItem();
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_focusedIndex < 3) {
        final oldIndex = _focusedIndex;
        setState(() => _focusedIndex++);
        // 在排序按钮之间切换时，使用缓存切换
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
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex <= 3) {
        // 已在顶部
      } else {
        final videoIndex = _focusedIndex - 4;
        if (videoIndex < gridColumns) {
          setState(() => _focusedIndex = 0);
          _mainFocusNode.requestFocus();
        } else {
          setState(() => _focusedIndex -= gridColumns);
          _focusCurrentItem();
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedIndex == 0) {
        _refreshOrder('pubdate'); // 点击确定：强制刷新
      } else if (_focusedIndex == 1) {
        _refreshOrder('click'); // 点击确定：强制刷新
      } else if (_focusedIndex == 2) {
        _toggleFollow();
      } else if (_focusedIndex == 3) {
        _openCharge();
      } else if (_focusedIndex >= 4 && _focusedIndex - 4 < _videos.length) {
        _openVideo(_videos[_focusedIndex - 4]);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
    final screenSize = MediaQuery.of(context).size;
    final popupWidth = screenSize.width * 0.88;
    final popupHeight = screenSize.height * 0.90;
    final gridColumns = SettingsService.videoGridColumns;
    final themeColor = SettingsService.themeColor;

    return FocusScope(
      // 使用 FocusScope 限制焦点范围，防止焦点逃逸到 popup 外部
      autofocus: true,
      // 在 FocusScope 层级捕获所有键盘事件，优先于子组件处理
      onKeyEvent: (node, event) {
        final result = _handleKeyEvent(node, event);
        // 如果我们处理了事件，阻止它继续传播
        if (result == KeyEventResult.handled) {
          return KeyEventResult.handled;
        }
        // 对于方向键，即使我们没有处理，也要阻止默认行为防止焦点逃逸
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Focus(
        focusNode: _mainFocusNode,
        child: Stack(
          children: [
            // 半透明遮罩背景
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(color: Colors.black.withValues(alpha: 0.7)),
              ),
            ),
            // 居中弹窗
            Center(
              child: Container(
                width: popupWidth,
                height: popupHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // 视频列表
                      Positioned.fill(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _videos.isEmpty
                            ? const Center(
                                child: Text(
                                  '该 UP 暂无投稿视频',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 20,
                                  ),
                                ),
                              )
                            : CustomScrollView(
                                controller: _scrollController,
                                slivers: [
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      24,
                                      _headerHeight + 10,
                                      24,
                                      40,
                                    ),
                                    sliver: SliverGrid(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: gridColumns,
                                            childAspectRatio: 320 / 280,
                                            crossAxisSpacing: 16,
                                            mainAxisSpacing: 8,
                                          ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                          final video = _videos[index];
                                          final isFocused =
                                              _focusedIndex == index + 4;
                                          return _buildVideoCard(
                                            video,
                                            index,
                                            isFocused,
                                          );
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
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                          child: _buildHeader(themeColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                  imageUrl: ImageUrlUtils.getResizedUrl(
                    widget.user.face,
                    width: 96,
                    height: 96,
                  ),
                  cacheManager: BiliCacheManager.instance,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: Colors.white12,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person, color: Colors.white54),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.white12,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person, color: Colors.white54),
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
                              widget.user.uname,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (sex == '男')
                            const Icon(Icons.male, color: Colors.blue, size: 18)
                          else if (sex == '女')
                            const Icon(
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
          fontSize: 10,
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
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          isLoading ? '--' : _formatNumber(value),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isFocused
                ? Colors.white
                : isActive
                ? Colors.white24
                : Colors.transparent,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              index == 0 ? Icons.schedule : Icons.whatshot,
              color: isFocused || isActive ? Colors.white : Colors.white54,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isFocused || isActive ? Colors.white : Colors.white54,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 视频卡片 - 只负责显示和焦点效果，导航由 popup 控制
  Widget _buildVideoCard(Video video, int index, bool isFocused) {
    final gridColumns = SettingsService.videoGridColumns;
    final themeColor = SettingsService.themeColor;

    // 使用简单的 Focus 包装，不使用 TvVideoCard 的内置导航
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
                  memCacheWidth: 480,
                  memCacheHeight: 270,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey[850]),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.grey[850],
                    child: const Icon(Icons.error, color: Colors.white54),
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
                      style: const TextStyle(color: Colors.white, fontSize: 11),
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
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        const SizedBox(height: 2),
        // 播放量
        Text(
          '${video.viewFormatted}播放',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
