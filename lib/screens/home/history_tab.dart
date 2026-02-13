import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import 'package:keframe/keframe.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/history_video_card.dart';
import '../../widgets/time_display.dart';
import '../player/player_screen.dart';

/// 观看历史 Tab
class HistoryTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const HistoryTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<HistoryTab> createState() => HistoryTabState();
}

class HistoryTabState extends State<HistoryTab> {
  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _viewAt = 0;
  int _max = 0;
  final ScrollController _scrollController = ScrollController();
  bool _hasLoaded = false;
  bool _isRefreshing = false; // 标记是否正在刷新中（用于控制分帧渲染）
  // 每个视频卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.isVisible && AuthService.isLoggedIn) {
      _loadHistory(reset: true);
      _hasLoaded = true;
    }
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible &&
        !oldWidget.isVisible &&
        !_hasLoaded &&
        AuthService.isLoggedIn) {
      _loadHistory(reset: true);
      _hasLoaded = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // 清理所有视频卡片的 FocusNode
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _videoFocusNodes.clear();
    super.dispose();
  }

  // 获取或创建视频卡片的 FocusNode
  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void _onScroll() {
    if (!_isLoading && !_isLoadingMore && _hasMore) {
      // 到 60 条后停止加载更多，防止内存无限增长
      if (_videos.length >= 60) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadHistory(reset: false);
      }
    }
  }

  /// 公开的刷新方法 - 供外部调用
  void refresh() {
    if (!AuthService.isLoggedIn) {
      _hasLoaded = false;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _isRefreshing = false;
        _videos = [];
        _viewAt = 0;
        _max = 0;
        _hasMore = true;
      });
      return;
    }
    _hasLoaded = true; // 标记已加载，避免切换时重复加载
    _loadHistory(reset: true);
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (!AuthService.isLoggedIn) return;

    if (reset) {
      // 释放旧的 FocusNode，防止内存泄漏
      for (final node in _videoFocusNodes.values) {
        node.dispose();
      }
      _videoFocusNodes.clear();
      setState(() {
        _isLoading = true;
        _isRefreshing = true; // 开始刷新
        _videos = [];
        _viewAt = 0;
        _max = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final result = await BilibiliApi.getHistory(
      ps: 30,
      viewAt: reset ? 0 : _viewAt,
      max: reset ? 0 : _max,
    );

    if (!mounted) return;

    final newVideos = result['list'] as List<Video>;
    final nextViewAt = result['viewAt'] as int;
    final nextMax = result['max'] as int;
    final hasMore = result['hasMore'] as bool;

    setState(() {
      if (reset) {
        _videos = newVideos;
        _isLoading = false;
        _isRefreshing = false; // 刷新完成
      } else {
        // 去重：过滤掉已存在的视频
        final existingBvids = _videos.map((v) => v.bvid).toSet();
        final uniqueNewVideos = newVideos
            .where((v) => !existingBvids.contains(v.bvid))
            .toList();
        _videos.addAll(uniqueNewVideos);
        _isLoadingMore = false;
      }

      _viewAt = nextViewAt;
      _max = nextMax;

      if (!hasMore || newVideos.isEmpty) {
        _hasMore = false;
      }
    });
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;

    // 未登录提示
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '请先登录',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
            const SizedBox(height: 10),
            const Text(
              '登录后可查看观看历史',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/history.svg',
              width: 80,
              height: 80,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.3),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '暂无观看历史',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 视频网格
        Positioned.fill(
          child: SizeCacheWidget(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 56, 24, 80),
                  sliver: SliverGrid(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridColumns,
                          childAspectRatio: 320 / 280,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 10,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final video = _videos[index];

                      // 构建卡片内容
                      Widget buildCard(BuildContext ctx) {
                        return HistoryVideoCard(
                          video: video,
                          focusNode: _getFocusNode(index),
                          onTap: () => _onVideoTap(video),
                          // 最左列按左键跳到侧边栏
                          onMoveLeft: (index % gridColumns == 0)
                              ? () => widget.sidebarFocusNode?.requestFocus()
                              : () => _getFocusNode(index - 1).requestFocus(),
                          // 强制向右导航
                          onMoveRight: (index + 1 < _videos.length)
                              ? () => _getFocusNode(index + 1).requestFocus()
                              : null,
                          // 严格按列向上移动
                          onMoveUp: index >= gridColumns
                              ? () => _getFocusNode(
                                  index - gridColumns,
                                ).requestFocus()
                              : () {}, // 最顶行为无效输入
                          // 严格按列向下移动
                          onMoveDown: (index + gridColumns < _videos.length)
                              ? () => _getFocusNode(
                                  index + gridColumns,
                                ).requestFocus()
                              : null,
                          onFocus: () {
                            if (!_scrollController.hasClients) return;

                            final RenderObject? object = ctx.findRenderObject();
                            if (object != null && object is RenderBox) {
                              final viewport = RenderAbstractViewport.of(
                                object,
                              );
                              final offsetToReveal = viewport
                                  .getOffsetToReveal(object, 0.0)
                                  .offset;
                              final targetOffset = (offsetToReveal - 120).clamp(
                                0.0,
                                _scrollController.position.maxScrollExtent,
                              );

                              if ((_scrollController.offset - targetOffset)
                                      .abs() >
                                  50) {
                                _scrollController.animateTo(
                                  targetOffset,
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            }
                          },
                        );
                      }

                      // 只有在刷新时才使用分帧渲染，否则直接渲染
                      if (_isRefreshing) {
                        return FrameSeparateWidget(
                          index: index,
                          placeHolder: const Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          child: Builder(builder: buildCard),
                        );
                      }

                      // 非刷新状态（从播放器返回）直接渲染
                      return Builder(builder: buildCard);
                    }, childCount: _videos.length),
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
        ),
        // 固定标题
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: const Text(
              '观看历史',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // 右上角时间
        const Positioned(top: 10, right: 14, child: TimeDisplay()),
      ],
    );
  }
}
