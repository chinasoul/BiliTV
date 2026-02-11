import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../models/video.dart';
import 'package:keframe/keframe.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../config/build_flags.dart';
import '../../widgets/tv_video_card.dart';
import '../../widgets/time_display.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../core/plugin/plugin_types.dart';
import '../player/player_screen.dart';

class HomeTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onFirstLoadComplete;
  final List<Video>? preloadedVideos; // 接收预加载数据

  const HomeTab({
    super.key,
    this.sidebarFocusNode,
    this.onFirstLoadComplete,
    this.preloadedVideos,
  });

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  int _selectedCategoryIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late List<HomeCategory> _categories;
  late List<FocusNode> _categoryFocusNodes;

  // 数据缓存
  final Map<int, List<Video>> _categoryVideos = {};
  final Map<int, bool> _categoryLoading = {};
  final Map<int, int> _categoryPage = {};
  final Map<int, int> _categoryRefreshIdx = {};
  bool _firstLoadDone = false;
  bool _usedPreloadedData = false; // 标记是否使用了预加载数据
  bool _isRefreshing = false; // 标记是否正在刷新中（用于控制分帧渲染）
  // 每个视频卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _loadCategoryOrder();
    _categoryFocusNodes = List.generate(_categories.length, (_) => FocusNode());

    // 【优化核心 1】如果有预加载数据，立即填充，且标记 loading 为 false
    if (widget.preloadedVideos != null && widget.preloadedVideos!.isNotEmpty) {
      _categoryVideos[0] = widget.preloadedVideos!;
      _categoryRefreshIdx[0] = 1;
      _categoryLoading[0] = false; // 关键：明确标记不加载
      _usedPreloadedData = true; // 标记使用了预加载数据
      _firstLoadDone = true;

      // 通知父组件（用于 Sidebar 焦点处理等）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFirstLoadComplete?.call();
      });
    } else {
      // 只有没数据时，才自己去请求
      _loadVideosForCategory(0);
    }
  }

  // ... (省略 _loadCategoryOrder, dispose 等未改动代码) ...

  void _loadCategoryOrder() {
    final order = SettingsService.categoryOrder;
    final enabled = SettingsService.enabledCategories;
    _categories = order
        .where((name) => enabled.contains(name))
        .map(
          (name) => HomeCategory.values.firstWhere(
            (c) => c.name == name,
            orElse: () => HomeCategory.recommend,
          ),
        )
        .toList();
    if (_categories.isEmpty) _categories = [HomeCategory.recommend];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    // 清理视频卡片的 FocusNode
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

  List<Video> get _currentVideos =>
      _categoryVideos[_selectedCategoryIndex] ?? [];
  bool get _isLoading => _categoryLoading[_selectedCategoryIndex] ?? false;

  Future<void> _loadVideosForCategory(
    int categoryIndex, {
    bool refresh = false,
  }) async {
    if (_categoryLoading[categoryIndex] == true) return;

    // ... (保持原有的分页逻辑) ...
    final currentPage = _categoryPage[categoryIndex] ?? 1;
    final currentRefreshIdx = _categoryRefreshIdx[categoryIndex] ?? 0;

    if (refresh) {
      _categoryPage[categoryIndex] = 1;
      setState(() {
        _categoryLoading[categoryIndex] = true;
        _categoryVideos[categoryIndex] = [];
        _isRefreshing = true; // 开始刷新
      });
    } else {
      setState(() => _categoryLoading[categoryIndex] = true);
    }

    final category = _categories[categoryIndex];
    List<Video> videos;
    bool requestFailed = false;

    try {
      // 网络请求逻辑...
      switch (category) {
        case HomeCategory.recommend:
          final idx = refresh
              ? (_categoryRefreshIdx[categoryIndex] ?? currentRefreshIdx)
              : currentRefreshIdx;
          videos = await BilibiliApi.getRecommendVideos(idx: idx);
          _categoryRefreshIdx[categoryIndex] = idx + 1;
          break;
        case HomeCategory.popular:
          final page = refresh ? 1 : currentPage;
          videos = await BilibiliApi.getPopularVideos(page: page);
          break;
        default:
          final page = refresh ? 1 : currentPage;
          videos = await BilibiliApi.getRegionVideos(
            tid: category.tid,
            page: page,
          );
          break;
      }
    } catch (e) {
      requestFailed = true;
      videos = [];
    }

    if (!mounted) return;
    setState(() {
      final page = _categoryPage[categoryIndex] ?? 1;

      // 插件过滤
      final filteredVideos = _filterVideos(videos);

      if (refresh || page == 1) {
        _categoryVideos[categoryIndex] = filteredVideos;
      } else {
        _categoryVideos[categoryIndex] = [
          ...(_categoryVideos[categoryIndex] ?? []),
          ...filteredVideos,
        ];
      }
      _categoryLoading[categoryIndex] = false;
      _isRefreshing = false; // 刷新完成

      if (!_firstLoadDone) {
        _firstLoadDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onFirstLoadComplete?.call();
        });
      }
    });

    if (refresh) {
      Fluttertoast.showToast(
        msg: requestFailed ? '刷新失败' : '已刷新',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }

  // ... (省略 _loadMore, _switchCategory 等辅助方法) ...
  void _loadMore() {
    if (_isLoading) return;
    final page = (_categoryPage[_selectedCategoryIndex] ?? 1) + 1;
    _categoryPage[_selectedCategoryIndex] = page;
    _loadVideosForCategory(_selectedCategoryIndex);
  }

  void _switchCategory(int index) {
    if (_selectedCategoryIndex == index) return;
    // 切换分类后不再是初始预加载状态
    _usedPreloadedData = false;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() => _selectedCategoryIndex = index);
    if ((_categoryVideos[index] ?? []).isEmpty) _loadVideosForCategory(index);
  }

  void _onCategoryTap(int index) {
    // 点击当前分类时主动刷新，兼容鼠标点击和遥控器确认键
    if (_selectedCategoryIndex == index) {
      refreshCurrentCategory();
      return;
    }
    _switchCategory(index);
  }

  void refreshCurrentCategory() {
    if (_isLoading) {
      Fluttertoast.showToast(
        msg: '正在刷新中，请稍候',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        textColor: Colors.white,
        fontSize: 16.0,
      );
      return;
    }

    Fluttertoast.showToast(
      msg: '正在刷新',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      backgroundColor: Colors.black.withValues(alpha: 0.7),
      textColor: Colors.white,
      fontSize: 16.0,
    );

    // 刷新后不再是初始预加载状态
    _usedPreloadedData = false;
    _loadVideosForCategory(_selectedCategoryIndex, refresh: true);
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    final gridColumns = SettingsService.videoGridColumns;

    // 判断是否是"启动后的第一屏数据"
    // 使用稳定的标志变量，避免 List 引用比较在 loadMore 后失效
    final bool isInitialLoad =
        _selectedCategoryIndex == 0 && _usedPreloadedData;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FocusTraversalGroup(
            child: _isLoading && _currentVideos.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SizeCacheWidget(
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(30, 100, 30, 80),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridColumns,
                                  childAspectRatio: 320 / 280,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 30,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final video = _currentVideos[index];

                              if (index == _currentVideos.length - gridColumns) {
                                _loadMore();
                              }

                              // 【优化】只有刷新时才使用交错加载
                              // 初始加载和从播放器返回时，图片已在缓存中，直接显示
                              final int? staggerIdx = _isRefreshing
                                  ? (index % 8)
                                  : null;

                              // 构建卡片内容
                              Widget buildCard(BuildContext ctx) {
                                return TvVideoCard(
                                  video: video,
                                  focusNode: _getFocusNode(index),
                                  autofocus: isInitialLoad && index == 0,
                                  disableCache: false,
                                  staggerIndex: staggerIdx,
                                  onTap: () => _onVideoTap(video),
                                  onMoveLeft: (index % gridColumns == 0)
                                      ? () => widget.sidebarFocusNode
                                            ?.requestFocus()
                                      : () => _getFocusNode(
                                          index - 1,
                                        ).requestFocus(),
                                  // 强制向右导航，避免 ScaleTransition 导致的误判
                                  onMoveRight:
                                      (index + 1 < _currentVideos.length)
                                      ? () => _getFocusNode(
                                          index + 1,
                                        ).requestFocus()
                                      : null,
                                  // 严格按列向上移动，最顶行跳到分类标签
                                  onMoveUp: index >= gridColumns
                                      ? () => _getFocusNode(
                                          index - gridColumns,
                                        ).requestFocus()
                                      : () =>
                                            _categoryFocusNodes[_selectedCategoryIndex]
                                                .requestFocus(),
                                  // 严格按列向下移动
                                  onMoveDown:
                                      (index + gridColumns < _currentVideos.length)
                                      ? () => _getFocusNode(
                                          index + gridColumns,
                                        ).requestFocus()
                                      : null,
                                  onFocus: () {
                                    if (!_scrollController.hasClients) {
                                      return;
                                    }

                                    final RenderObject? object = ctx
                                        .findRenderObject();
                                    if (object != null && object is RenderBox) {
                                      final viewport =
                                          RenderAbstractViewport.of(object);
                                      final offsetToReveal = viewport
                                          .getOffsetToReveal(object, 0.0)
                                          .offset;
                                      final targetOffset =
                                          (offsetToReveal - 120).clamp(
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

                              // 只有刷新时使用分帧渲染，其他情况直接渲染
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

                              return Builder(builder: buildCard);
                            }, childCount: _currentVideos.length),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // ... (Header / Category Tabs 保持不变) ...
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.only(left: 30, right: 30, top: 20),
            child: FocusTraversalGroup(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_categories.length, (index) {
                    return _CategoryTab(
                      label: _categories[index].label,
                      isSelected: _selectedCategoryIndex == index,
                      focusNode: _categoryFocusNodes[index],
                      onTap: () => _onCategoryTap(index),
                      onFocus: () => _switchCategory(index),
                      onConfirm: refreshCurrentCategory,
                      onMoveLeft: index == 0
                          ? () => widget.sidebarFocusNode?.requestFocus()
                          : null,
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }

  List<Video> _filterVideos(List<Video> videos) {
    if (videos.isEmpty) return [];
    if (!BuildFlags.pluginsEnabled) return videos;
    final plugins = PluginManager().getEnabledPlugins<FeedPlugin>();
    if (plugins.isEmpty) return videos;

    return videos.where((video) {
      for (final plugin in plugins) {
        if (!plugin.shouldShowItem(video)) return false;
      }
      return true;
    }).toList();
  }
}

/// 分类标签组件
class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onConfirm;
  final VoidCallback? onMoveLeft;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
    required this.onConfirm,
    this.onMoveLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) => f ? onFocus() : null,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                onMoveLeft != null) {
              onMoveLeft!();
              return KeyEventResult.handled;
            }
            // 确定键刷新当前分类
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              onConfirm();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final f = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTap: onTap,
              child: Container(
                // 紧凑的 padding 确保文字高度位置与普通标题接近
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                decoration: BoxDecoration(
                  color: f ? const Color(0xFFfb7299) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: f ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: f
                            ? Colors.white
                            : (isSelected
                                  ? const Color(0xFFfb7299)
                                  : Colors.grey),
                        fontSize: 20,
                        fontWeight: f || isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      width: 20,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFfb7299)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 首页分类枚举
enum HomeCategory {
  recommend('推荐', 0),
  popular('热门', 0),
  anime('番剧', 13),
  movie('影视', 181),
  game('游戏', 4),
  knowledge('知识', 36),
  tech('科技', 188),
  music('音乐', 3),
  dance('舞蹈', 129),
  life('生活', 160),
  food('美食', 211),
  douga('动画', 1);

  const HomeCategory(this.label, this.tid);
  final String label;
  final int tid;
}
