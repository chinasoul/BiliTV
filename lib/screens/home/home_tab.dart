import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../config/build_flags.dart';
import '../../config/app_style.dart';
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
  ScrollController _scrollController = ScrollController();
  late List<HomeCategory> _categories;
  late List<FocusNode> _categoryFocusNodes;

  // 数据缓存
  final Map<int, List<Video>> _categoryVideos = {};
  final Map<int, bool> _categoryLoading = {};
  final Map<int, int> _categoryPage = {};
  final Map<int, int> _categoryRefreshIdx = {};
  final Map<int, double> _categoryScrollOffset = {}; // 记忆每个分类的滚动位置
  final Map<int, int> _categoryLimit = {}; // 每个分类的当前加载上限
  final FocusNode _loadMoreFocusNode = FocusNode();
  bool _firstLoadDone = false;
  bool _usedPreloadedData = false; // 标记是否使用了预加载数据
  // 每个分类独立的视频 FocusNode 表，避免跨分类污染
  final Map<int, Map<int, FocusNode>> _categoryFocusNodeMaps = {};
  bool _isSwitchingCategory = false; // 防止 FocusNode dispose 引发的递归切换

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

      // 保存到缓存
      _saveCacheForCategory0(widget.preloadedVideos!);

      // 通知父组件（用于 Sidebar 焦点处理等）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFirstLoadComplete?.call();
      });
    } else if (!SettingsService.autoRefreshOnLaunch) {
      // 【关闭自动刷新】尝试从本地缓存加载
      final cached = _loadCachedVideos();
      if (cached != null && cached.isNotEmpty) {
        _categoryVideos[0] = cached;
        _categoryRefreshIdx[0] = 1;
        _categoryLoading[0] = false;
        _usedPreloadedData = true;
        _firstLoadDone = true;

        // 显示上次更新时间 toast
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final timeStr = SettingsService.formatLastRefreshTime();
          if (timeStr.isNotEmpty) {
            Fluttertoast.showToast(
              msg: timeStr,
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.CENTER,
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              textColor: Colors.white,
              fontSize: 16.0,
            );
          }
          widget.onFirstLoadComplete?.call();
        });
      } else {
        // 没有缓存，首次使用，正常请求
        _loadVideosForCategory(0);
      }
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
    _loadMoreFocusNode.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    // 清理所有分类的视频 FocusNode
    for (final map in _categoryFocusNodeMaps.values) {
      for (final node in map.values) {
        node.dispose();
      }
    }
    _categoryFocusNodeMaps.clear();
    super.dispose();
  }

  // 获取或创建当前分类的视频卡片 FocusNode
  FocusNode _getFocusNode(int index) {
    final map = _categoryFocusNodeMaps.putIfAbsent(
      _selectedCategoryIndex,
      () => {},
    );
    return map.putIfAbsent(index, () => FocusNode());
  }

  List<Video> get _currentVideos =>
      _categoryVideos[_selectedCategoryIndex] ?? [];
  bool get _isLoading => _categoryLoading[_selectedCategoryIndex] ?? false;

  int get _currentLimit =>
      _categoryLimit[_selectedCategoryIndex] ?? SettingsService.listMaxItems;
  bool get _reachedLimit => _currentVideos.length >= _currentLimit;

  /// 从本地缓存加载推荐视频
  List<Video>? _loadCachedVideos() {
    final jsonStr = SettingsService.cachedHomeVideosJson;
    if (jsonStr == null) return null;
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((item) => Video.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  /// 保存推荐视频到本地缓存 (仅分类 0 / 推荐)
  void _saveCacheForCategory0(List<Video> videos) {
    try {
      final jsonStr = jsonEncode(videos.map((v) => v.toMap()).toList());
      SettingsService.setCachedHomeVideosJson(jsonStr);
    } catch (e) {
      // 忽略缓存保存失败
    }
  }

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
      _categoryLimit.remove(categoryIndex); // 重置加载上限
      _categoryScrollOffset.remove(categoryIndex); // 刷新时清除滚动位置记忆
      // 重建 ScrollController，确保刷新后从顶部开始
      // （jumpTo(0) 不够：loading 指示器会替换 ScrollView，
      //   数据到达后重建 ScrollView 时 initialScrollOffset 仍是旧值）
      _scrollController.dispose();
      _scrollController = ScrollController(
        initialScrollOffset: 0.0,
        keepScrollOffset: false,
      );
      // 释放该分类的 FocusNode，防止内存泄漏
      _disposeFocusNodesForCategory(categoryIndex);
      // 主动释放图片内存缓存，避免旧图片占用内存
      PaintingBinding.instance.imageCache.clear();
      setState(() {
        _categoryLoading[categoryIndex] = true;
        _categoryVideos[categoryIndex] = [];
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

      // 保存推荐视频缓存 (仅分类 0)
      if (categoryIndex == 0 && (refresh || page == 1)) {
        _saveCacheForCategory0(_categoryVideos[0] ?? []);
      }

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
    // 达到上限后停止自动加载，等待用户手动触发
    if (_currentVideos.length >= _currentLimit) return;
    final page = (_categoryPage[_selectedCategoryIndex] ?? 1) + 1;
    _categoryPage[_selectedCategoryIndex] = page;
    _loadVideosForCategory(_selectedCategoryIndex);
  }

  /// 用户主动点击"加载更多"时，扩展上限并继续加载
  void _extendLimit() {
    setState(() {
      _categoryLimit[_selectedCategoryIndex] =
          _currentLimit + SettingsService.listMaxItems;
    });
    _loadMore();
  }

  void _switchCategory(int index) {
    if (_selectedCategoryIndex == index) return;
    // 防止 FocusNode dispose 引发焦点迁移，从而递归调用 _switchCategory
    if (_isSwitchingCategory) return;
    _isSwitchingCategory = true;

    // ---- 保存当前分类的滚动位置 ----
    if (_scrollController.hasClients) {
      _categoryScrollOffset[_selectedCategoryIndex] = _scrollController.offset;
    }

    final prevIndex = _selectedCategoryIndex;

    // ---- 用 initialScrollOffset 创建新 ScrollController ----
    // 避免先在 offset=0 处 build 一遍再 jumpTo 目标位置（双重 build）
    // keepScrollOffset: false —— 我们自行管理 offset，禁止 PageStorage 干扰
    _scrollController.dispose();
    _scrollController = ScrollController(
      initialScrollOffset: _categoryScrollOffset[index] ?? 0.0,
      keepScrollOffset: false,
    );

    // 切换分类后不再是初始预加载状态
    _usedPreloadedData = false;
    setState(() => _selectedCategoryIndex = index);

    if ((_categoryVideos[index] ?? []).isEmpty) _loadVideosForCategory(index);

    _isSwitchingCategory = false;

    // ---- 延迟释放旧分类的 FocusNode + 图片缓存 ----
    // 必须在 setState 之后、widget 重建完成后再 dispose，
    // 否则 dispose 会触发焦点迁移，导致递归调用 _switchCategory。
    // imageCache.clear() 也放在这里：此时旧 widget 已 dispose 掉
    // ImageStreamCompleter listener，clear 能真正释放 native 图片内存。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeFocusNodesForCategory(prevIndex);
      PaintingBinding.instance.imageCache.clear();
    });
  }

  /// 释放指定分类的视频 FocusNode
  void _disposeFocusNodesForCategory(int categoryIndex) {
    final map = _categoryFocusNodeMaps.remove(categoryIndex);
    if (map != null) {
      for (final node in map.values) {
        node.dispose();
      }
    }
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

  Widget _buildLoadMoreTile() {
    return Focus(
      focusNode: _loadMoreFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final gridColumns = SettingsService.videoGridColumns;
          final lastRowStart = (_currentVideos.length ~/ gridColumns) * gridColumns;
          final targetIndex = lastRowStart < _currentVideos.length ? lastRowStart : _currentVideos.length - 1;
          _getFocusNode(targetIndex).requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.sidebarFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          _extendLimit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: _extendLimit,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isFocused
                    ? SettingsService.themeColor.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more,
                    color: isFocused ? Colors.white : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已加载 ${_currentVideos.length} 条，按确认键加载更多',
                    style: TextStyle(
                      color: isFocused ? Colors.white : Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
                : CustomScrollView(
                      // key 随分类变化，强制 Flutter 重建 Scrollable 和 ScrollPosition，
                      // 否则 didUpdateWidget 只替换 controller 但复用旧 position（偏移量不对）
                      key: ValueKey('category_$_selectedCategoryIndex'),
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: TabStyle.contentPadding,
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
                              final video = _currentVideos[index];

                              if (!_reachedLimit &&
                                  index == _currentVideos.length - gridColumns) {
                                _loadMore();
                              }

                              // 构建卡片内容
                              Widget buildCard(BuildContext ctx) {
                                return TvVideoCard(
                                  video: video,
                                  focusNode: _getFocusNode(index),
                                  autofocus: isInitialLoad && index == 0,
                                  disableCache: false,
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
                                  // 严格按列向下移动；最后一行：有"加载更多"时跳转到它，否则阻止
                                  onMoveDown:
                                      (index + gridColumns < _currentVideos.length)
                                      ? () => _getFocusNode(
                                          index + gridColumns,
                                        ).requestFocus()
                                      : _reachedLimit
                                          ? () => _loadMoreFocusNode.requestFocus()
                                          : () {},
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

                              return Builder(builder: buildCard);
                            }, childCount: _currentVideos.length),
                          ),
                        ),
                        // 到达上限后显示"加载更多"提示
                        if (_reachedLimit)
                          SliverToBoxAdapter(
                            child: _buildLoadMoreTile(),
                          ),
                      ],
                    ),
          ),
        ),

        // ... (Header / Category Tabs 保持不变) ...
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: TabStyle.headerHeight,
          child: Container(
            color: TabStyle.headerBackgroundColor,
            padding: TabStyle.headerPadding,
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
                      onFocus: () {
                        // 聚焦即切换：移动焦点立刻切换分类
                        // 普通模式：只高亮标签，不切换
                        if (SettingsService.focusSwitchTab) {
                          _switchCategory(index);
                        }
                      },
                      onConfirm: () => _onCategoryTap(index),
                      onMoveLeft: index == 0
                          ? () => widget.sidebarFocusNode?.requestFocus()
                          : null,
                      // 最后一项向右循环到第一项
                      onMoveRight: index == _categories.length - 1
                          ? () => _categoryFocusNodes[0].requestFocus()
                          : null,
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
        const Positioned(top: TabStyle.timeDisplayTop, right: TabStyle.timeDisplayRight, child: TimeDisplay()),
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
  final VoidCallback? onMoveRight;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
    required this.onConfirm,
    this.onMoveLeft,
    this.onMoveRight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
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
            if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                onMoveRight != null) {
              onMoveRight!();
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
                padding: TabStyle.tabPadding,
                decoration: BoxDecoration(
                  color: f ? SettingsService.themeColor.withValues(alpha: 0.6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(TabStyle.tabBorderRadius),
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
                                  ? SettingsService.themeColor
                                  : Colors.grey),
                        fontSize: TabStyle.tabFontSize,
                        fontWeight: f || isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        height: TabStyle.tabLineHeight,
                      ),
                    ),
                    const SizedBox(height: TabStyle.tabUnderlineGap),
                    Container(
                      height: TabStyle.tabUnderlineHeight,
                      width: TabStyle.tabUnderlineWidth,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SettingsService.themeColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(TabStyle.tabUnderlineRadius),
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
