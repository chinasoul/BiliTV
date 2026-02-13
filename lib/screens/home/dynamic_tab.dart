import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import 'package:keframe/keframe.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/tv_video_card.dart';
import '../../widgets/time_display.dart';
import '../player/player_screen.dart';

/// 动态 Tab
class DynamicTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const DynamicTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<DynamicTab> createState() => DynamicTabState();
}

class DynamicTabState extends State<DynamicTab> {
  List<Video> _videos = [];
  bool _isLoading = true;
  String _offset = '';
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasLoaded = false;
  bool _isRefreshing = false; // 标记是否正在刷新中（用于控制分帧渲染）
  // 每个视频卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  @override
  void initState() {
    super.initState();
    // 只有第一次可见时才加载
    if (widget.isVisible && AuthService.isLoggedIn) {
      _loadDynamic(refresh: true);
      _hasLoaded = true;
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(DynamicTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 之前不可见，现在可见了，且没加载过 -> 加载
    if (widget.isVisible &&
        !oldWidget.isVisible &&
        !_hasLoaded &&
        AuthService.isLoggedIn) {
      _loadDynamic(refresh: true);
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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
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
        _offset = '';
        _hasMore = true;
      });
      return;
    }
    _hasLoaded = true; // 标记已加载，避免切换时重复加载
    _loadDynamic(refresh: true);
  }

  Future<void> _loadDynamic({bool refresh = false}) async {
    if (!AuthService.isLoggedIn) return;

    if (refresh) {
      // 释放旧的 FocusNode，防止内存泄漏
      for (final node in _videoFocusNodes.values) {
        node.dispose();
      }
      _videoFocusNodes.clear();
      setState(() {
        _isLoading = true;
        _isRefreshing = true; // 开始刷新
        _videos = [];
        _offset = '';
        _hasMore = true;
      });
    }

    if (!_hasMore && !refresh) return;

    final feed = await BilibiliApi.getDynamicFeed(
      offset: refresh ? '' : _offset,
    );

    if (!mounted) return;

    setState(() {
      if (refresh) {
        _videos = feed.videos;
      } else {
        // 去重：过滤掉已存在的视频
        final existingBvids = _videos.map((v) => v.bvid).toSet();
        final newVideos = feed.videos
            .where((v) => !existingBvids.contains(v.bvid))
            .toList();
        _videos.addAll(newVideos);
      }
      _offset = feed.offset;
      _hasMore = feed.hasMore;
      _isLoading = false;
      _isLoadingMore = false;
      _isRefreshing = false; // 刷新完成
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    // 到 60 条后停止加载更多，防止内存无限增长
    if (_videos.length >= 60) return;
    setState(() => _isLoadingMore = true);
    await _loadDynamic(refresh: false);
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;

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
              '登录后可查看关注的动态',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/dynamic.svg',
              width: 80,
              height: 80,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.3),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '暂无动态',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Column(
            children: [
              Expanded(
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
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final video = _videos[index];

                            // 预取下一页：避免大列数时无法通过下移触发滚动加载
                            if (_hasMore &&
                                !_isLoadingMore &&
                                index >= _videos.length - gridColumns) {
                              _loadMore();
                            }

                            // 构建卡片的内容
                            Widget buildCard(BuildContext ctx) {
                              return TvVideoCard(
                                video: video,
                                focusNode: _getFocusNode(index),
                                disableCache: false,
                                onTap: () => _onVideoTap(video),
                                // 最左列按左键跳到侧边栏
                                onMoveLeft: (index % gridColumns == 0)
                                    ? () => widget.sidebarFocusNode
                                          ?.requestFocus()
                                    : () => _getFocusNode(
                                        index - 1,
                                      ).requestFocus(),
                                // 强制向右导航
                                onMoveRight: (index + 1 < _videos.length)
                                    ? () => _getFocusNode(
                                        index + 1,
                                      ).requestFocus()
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

                                  final RenderObject? object = ctx
                                      .findRenderObject();
                                  if (object != null && object is RenderBox) {
                                    final viewport = RenderAbstractViewport.of(
                                      object,
                                    );
                                    final offsetToReveal = viewport
                                        .getOffsetToReveal(object, 0.0)
                                        .offset;
                                    final targetOffset = (offsetToReveal - 120)
                                        .clamp(
                                          0.0,
                                          _scrollController
                                              .position
                                              .maxScrollExtent,
                                        );

                                    if ((_scrollController.offset -
                                                targetOffset)
                                            .abs() >
                                        50) {
                                      _scrollController.animateTo(
                                        targetOffset,
                                        duration: const Duration(
                                          milliseconds: 500,
                                        ),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                    ],
                  ),
                ),
              ),
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
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
              '关注动态',
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
