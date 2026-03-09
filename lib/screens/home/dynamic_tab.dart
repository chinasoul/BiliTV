import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/video.dart';
import '../../models/dynamic_item.dart';
import '../../services/bilibili_api.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../config/app_style.dart';
import '../../widgets/tv_video_card.dart';
import '../../widgets/tv_dynamic_card.dart';
import '../../widgets/update_time_banner.dart';
import '../player/player_screen.dart';
import '../video_detail/video_detail_screen.dart';
import '../dynamic_detail_screen.dart';

enum _DynamicSubTab { video, draw, article }

/// 动态 Tab — 视频 / 图文 / 专栏 三个子 Tab
class DynamicTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const DynamicTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<DynamicTab> createState() => DynamicTabState();
}

class DynamicTabState extends State<DynamicTab> {
  // ========== Tab 管理 ==========
  _DynamicSubTab _selectedTab = _DynamicSubTab.video;
  final List<FocusNode> _tabFocusNodes =
      List.generate(3, (_) => FocusNode());
  bool _isSwitchingTab = false;

  // ========== 视频子 Tab ==========
  List<Video> _videos = [];
  bool _videoLoading = true;
  String _videoOffset = '';
  bool _videoHasMore = true;
  bool _videoHasLoaded = false;
  int _videoLimit = SettingsService.listMaxItems;

  // ========== 图文子 Tab ==========
  List<DynamicDraw> _draws = [];
  bool _drawLoading = true;
  String _drawOffset = '';
  bool _drawHasMore = true;
  bool _drawHasLoaded = false;
  int _drawLimit = SettingsService.listMaxItems;

  // ========== 专栏子 Tab ==========
  List<DynamicArticle> _articles = [];
  bool _articleLoading = true;
  String _articleOffset = '';
  bool _articleHasMore = true;
  bool _articleHasLoaded = false;
  int _articleLimit = SettingsService.listMaxItems;

  // ========== 共享 ==========
  ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  String _updateTimeText = '';
  int _updateTimeBannerKey = 0;
  final FocusNode _loadMoreFocusNode = FocusNode();

  // 每个子 Tab 独立的 FocusNode 表
  final Map<_DynamicSubTab, Map<int, FocusNode>> _tabCardFocusNodes = {};
  // 每个子 Tab 的滚动位置记忆
  final Map<_DynamicSubTab, double> _tabScrollOffsets = {};

  // ========== 公开 API（供 HomeScreen 调用） ==========

  bool handleBack() {
    for (final node in _tabFocusNodes) {
      if (node.hasFocus) return false;
    }
    _tabFocusNodes[_selectedTab.index].requestFocus();
    return true;
  }

  void focusFirstItem() {
    _tabFocusNodes[_selectedTab.index].requestFocus();
  }

  void refresh() {
    if (!AuthService.isLoggedIn) {
      _videoHasLoaded = false;
      _drawHasLoaded = false;
      _articleHasLoaded = false;
      if (!mounted) return;
      setState(() {
        _videoLoading = false;
        _drawLoading = false;
        _articleLoading = false;
        _videos = [];
        _draws = [];
        _articles = [];
        _videoOffset = '';
        _drawOffset = '';
        _articleOffset = '';
        _videoHasMore = true;
        _drawHasMore = true;
        _articleHasMore = true;
        _updateTimeText = '';
      });
      return;
    }
    _tabScrollOffsets.remove(_selectedTab);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollController = ScrollController(
      initialScrollOffset: 0,
      keepScrollOffset: false,
    );
    _scrollController.addListener(_onScroll);

    setState(() => _updateTimeText = '');
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        _loadVideos(refresh: true, isManualRefresh: true);
        break;
      case _DynamicSubTab.draw:
        _loadDraws(refresh: true, isManualRefresh: true);
        break;
      case _DynamicSubTab.article:
        _loadArticles(refresh: true, isManualRefresh: true);
        break;
    }
  }

  // ========== 生命周期 ==========

  @override
  void initState() {
    super.initState();
    if (widget.isVisible && AuthService.isLoggedIn) {
      if (!_tryLoadVideosFromCache()) {
        _loadVideos(refresh: true);
      }
      _videoHasLoaded = true;
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(DynamicTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible &&
        !oldWidget.isVisible &&
        !_videoHasLoaded &&
        AuthService.isLoggedIn) {
      if (!_tryLoadVideosFromCache()) {
        _loadVideos(refresh: true);
      }
      _videoHasLoaded = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _loadMoreFocusNode.dispose();
    for (final node in _tabFocusNodes) {
      node.dispose();
    }
    for (final map in _tabCardFocusNodes.values) {
      for (final node in map.values) {
        node.dispose();
      }
    }
    _tabCardFocusNodes.clear();
    super.dispose();
  }

  // ========== FocusNode 管理 ==========

  FocusNode _getCardFocusNode(int index) {
    final map = _tabCardFocusNodes.putIfAbsent(_selectedTab, () => {});
    return map.putIfAbsent(index, () => FocusNode());
  }

  void _disposeCardFocusNodesFor(_DynamicSubTab tab) {
    final map = _tabCardFocusNodes.remove(tab);
    if (map != null) {
      for (final node in map.values) {
        node.dispose();
      }
    }
  }

  // ========== 滚动 ==========

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreForCurrentTab();
    }
  }

  // ========== Tab 切换 ==========

  void _switchTab(_DynamicSubTab tab) {
    if (_selectedTab == tab || _isSwitchingTab) return;
    _isSwitchingTab = true;

    if (_scrollController.hasClients) {
      _tabScrollOffsets[_selectedTab] = _scrollController.offset;
    }

    final prevTab = _selectedTab;

    _scrollController.dispose();
    _scrollController = ScrollController(
      initialScrollOffset: _tabScrollOffsets[tab] ?? 0.0,
      keepScrollOffset: false,
    );
    _scrollController.addListener(_onScroll);

    setState(() {
      _selectedTab = tab;
      _updateTimeText = '';
    });

    _ensureTabDataLoaded(tab);

    _isSwitchingTab = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeCardFocusNodesFor(prevTab);
    });
  }

  void _ensureTabDataLoaded(_DynamicSubTab tab) {
    if (!AuthService.isLoggedIn) return;
    switch (tab) {
      case _DynamicSubTab.video:
        if (!_videoHasLoaded) {
          if (!_tryLoadVideosFromCache()) {
            _loadVideos(refresh: true);
          }
          _videoHasLoaded = true;
        }
        break;
      case _DynamicSubTab.draw:
        if (!_drawHasLoaded) {
          if (!_tryLoadDrawsFromCache()) {
            _loadDraws(refresh: true);
          }
          _drawHasLoaded = true;
        }
        break;
      case _DynamicSubTab.article:
        if (!_articleHasLoaded) {
          if (!_tryLoadArticlesFromCache()) {
            _loadArticles(refresh: true);
          }
          _articleHasLoaded = true;
        }
        break;
    }
  }

  void _onTabTap(int index) {
    final tab = _DynamicSubTab.values[index];
    if (_selectedTab == tab) {
      refresh();
      return;
    }
    _switchTab(tab);
  }

  // ========== 视频数据加载 ==========

  Future<void> _loadVideos({
    bool refresh = false,
    bool isManualRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) return;

    final oldFirstBvid =
        isManualRefresh && _videos.isNotEmpty ? _videos.first.bvid : null;

    if (refresh) {
      _disposeCardFocusNodesFor(_DynamicSubTab.video);
      _videoLimit = SettingsService.listMaxItems;
      setState(() {
        _videoLoading = true;
        _videos = [];
        _videoOffset = '';
        _videoHasMore = true;
      });
    }
    if (!_videoHasMore && !refresh) return;

    final feed = await BilibiliApi.getDynamicFeed(
      offset: refresh ? '' : _videoOffset,
    );
    if (!mounted) return;

    setState(() {
      if (refresh) {
        _videos = feed.videos;
      } else {
        final existing = _videos.map((v) => v.bvid).toSet();
        _videos.addAll(feed.videos.where((v) => !existing.contains(v.bvid)));
      }
      _videoOffset = feed.offset;
      _videoHasMore = feed.hasMore;
      _videoLoading = false;
      _isLoadingMore = false;
    });

    if (refresh && _videos.isNotEmpty) {
      _handlePostRefresh(
        isManualRefresh: isManualRefresh,
        hasChanged: oldFirstBvid != (_videos.isNotEmpty ? _videos.first.bvid : null),
        saveCache: _saveVideoCache,
        lastRefreshTime: SettingsService.lastDynamicRefreshTime,
      );
    }
  }

  void _saveVideoCache() {
    try {
      final data = {
        'videos': _videos.map((v) => v.toMap()).toList(),
        'offset': _videoOffset,
      };
      SettingsService.setCachedDynamicJson(jsonEncode(data));
    } catch (_) {}
  }

  bool _tryLoadVideosFromCache() {
    final jsonStr = SettingsService.cachedDynamicJson;
    if (jsonStr == null) return false;
    try {
      final decoded = jsonDecode(jsonStr);
      List videoList;
      String offset = '';
      if (decoded is List) {
        videoList = decoded;
      } else if (decoded is Map) {
        videoList = decoded['videos'] as List;
        offset = decoded['offset'] as String? ?? '';
      } else {
        return false;
      }
      final videos = videoList
          .map((item) => Video.fromMap(item as Map<String, dynamic>))
          .toList();
      if (videos.isEmpty) return false;
      setState(() {
        _videos = videos;
        _videoLoading = false;
        _videoOffset = offset;
        _videoHasMore = offset.isNotEmpty;
      });
      _showCachedTimeBanner(SettingsService.lastDynamicRefreshTime);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ========== 图文数据加载 ==========

  Future<void> _loadDraws({
    bool refresh = false,
    bool isManualRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) return;

    final oldFirstId =
        isManualRefresh && _draws.isNotEmpty ? _draws.first.id : null;

    if (refresh) {
      _disposeCardFocusNodesFor(_DynamicSubTab.draw);
      _drawLimit = SettingsService.listMaxItems;
      setState(() {
        _drawLoading = true;
        _draws = [];
        _drawOffset = '';
        _drawHasMore = true;
      });
    }
    if (!_drawHasMore && !refresh) return;

    final feed = await BilibiliApi.getDynamicDrawFeed(
      offset: refresh ? '' : _drawOffset,
    );
    if (!mounted) return;

    setState(() {
      if (refresh) {
        _draws = feed.items;
      } else {
        final existing = _draws.map((d) => d.id).toSet();
        _draws.addAll(feed.items.where((d) => !existing.contains(d.id)));
      }
      _drawOffset = feed.offset;
      _drawHasMore = feed.hasMore;
      _drawLoading = false;
      _isLoadingMore = false;
    });

    if (refresh && _draws.isNotEmpty) {
      _handlePostRefresh(
        isManualRefresh: isManualRefresh,
        hasChanged: oldFirstId != (_draws.isNotEmpty ? _draws.first.id : null),
        saveCache: _saveDrawCache,
        lastRefreshTime: SettingsService.lastDynamicDrawRefreshTime,
      );
    }
  }

  void _saveDrawCache() {
    try {
      final data = {
        'items': _draws.map((d) => d.toMap()).toList(),
        'offset': _drawOffset,
      };
      SettingsService.setCachedDynamicDrawJson(jsonEncode(data));
    } catch (_) {}
  }

  bool _tryLoadDrawsFromCache() {
    final jsonStr = SettingsService.cachedDynamicDrawJson;
    if (jsonStr == null) return false;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return false;
      final itemList = decoded['items'] as List? ?? [];
      final offset = decoded['offset'] as String? ?? '';
      final draws = itemList
          .map((item) => DynamicDraw.fromMap(item as Map<String, dynamic>))
          .toList();
      if (draws.isEmpty) return false;
      setState(() {
        _draws = draws;
        _drawLoading = false;
        _drawOffset = offset;
        _drawHasMore = offset.isNotEmpty;
      });
      _showCachedTimeBanner(SettingsService.lastDynamicDrawRefreshTime);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ========== 专栏数据加载 ==========

  Future<void> _loadArticles({
    bool refresh = false,
    bool isManualRefresh = false,
  }) async {
    if (!AuthService.isLoggedIn) return;

    final oldFirstId =
        isManualRefresh && _articles.isNotEmpty ? _articles.first.id : null;

    if (refresh) {
      _disposeCardFocusNodesFor(_DynamicSubTab.article);
      _articleLimit = SettingsService.listMaxItems;
      setState(() {
        _articleLoading = true;
        _articles = [];
        _articleOffset = '';
        _articleHasMore = true;
      });
    }
    if (!_articleHasMore && !refresh) return;

    final feed = await BilibiliApi.getDynamicArticleFeed(
      offset: refresh ? '' : _articleOffset,
    );
    if (!mounted) return;

    setState(() {
      if (refresh) {
        _articles = feed.items;
      } else {
        final existing = _articles.map((a) => a.id).toSet();
        _articles.addAll(feed.items.where((a) => !existing.contains(a.id)));
      }
      _articleOffset = feed.offset;
      _articleHasMore = feed.hasMore;
      _articleLoading = false;
      _isLoadingMore = false;
    });

    if (refresh && _articles.isNotEmpty) {
      _handlePostRefresh(
        isManualRefresh: isManualRefresh,
        hasChanged:
            oldFirstId != (_articles.isNotEmpty ? _articles.first.id : null),
        saveCache: _saveArticleCache,
        lastRefreshTime: SettingsService.lastDynamicArticleRefreshTime,
      );
    }
  }

  void _saveArticleCache() {
    try {
      final data = {
        'items': _articles.map((a) => a.toMap()).toList(),
        'offset': _articleOffset,
      };
      SettingsService.setCachedDynamicArticleJson(jsonEncode(data));
    } catch (_) {}
  }

  bool _tryLoadArticlesFromCache() {
    final jsonStr = SettingsService.cachedDynamicArticleJson;
    if (jsonStr == null) return false;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return false;
      final itemList = decoded['items'] as List? ?? [];
      final offset = decoded['offset'] as String? ?? '';
      final articles = itemList
          .map((item) =>
              DynamicArticle.fromMap(item as Map<String, dynamic>))
          .toList();
      if (articles.isEmpty) return false;
      setState(() {
        _articles = articles;
        _articleLoading = false;
        _articleOffset = offset;
        _articleHasMore = offset.isNotEmpty;
      });
      _showCachedTimeBanner(SettingsService.lastDynamicArticleRefreshTime);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ========== 共用工具方法 ==========

  void _handlePostRefresh({
    required bool isManualRefresh,
    required bool hasChanged,
    required VoidCallback saveCache,
    required int lastRefreshTime,
  }) {
    if (isManualRefresh) {
      if (hasChanged) {
        saveCache();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _updateTimeText = '更新于刚刚';
              _updateTimeBannerKey++;
            });
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final timeStr =
                SettingsService.formatTimestamp(lastRefreshTime);
            if (timeStr.isNotEmpty) {
              setState(() {
                _updateTimeText = timeStr;
                _updateTimeBannerKey++;
              });
            }
          }
        });
      }
    } else {
      saveCache();
    }
  }

  void _showCachedTimeBanner(int lastRefreshTime) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timeStr = SettingsService.formatTimestamp(lastRefreshTime);
      if (timeStr.isNotEmpty && mounted) {
        setState(() {
          _updateTimeText = timeStr;
          _updateTimeBannerKey++;
        });
      }
    });
  }

  // ========== 加载更多 ==========

  bool get _currentReachedLimit {
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        return _videos.length >= _videoLimit && _videoHasMore;
      case _DynamicSubTab.draw:
        return _draws.length >= _drawLimit && _drawHasMore;
      case _DynamicSubTab.article:
        return _articles.length >= _articleLimit && _articleHasMore;
    }
  }

  int get _currentItemCount {
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        return _videos.length;
      case _DynamicSubTab.draw:
        return _draws.length;
      case _DynamicSubTab.article:
        return _articles.length;
    }
  }

  bool get _currentHasMore {
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        return _videoHasMore;
      case _DynamicSubTab.draw:
        return _drawHasMore;
      case _DynamicSubTab.article:
        return _articleHasMore;
    }
  }

  bool get _currentIsLoading {
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        return _videoLoading;
      case _DynamicSubTab.draw:
        return _drawLoading;
      case _DynamicSubTab.article:
        return _articleLoading;
    }
  }

  void _loadMoreForCurrentTab() {
    if (_isLoadingMore || !_currentHasMore) return;
    if (_currentItemCount >= _currentLimit) return;
    setState(() => _isLoadingMore = true);
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        _loadVideos(refresh: false);
        break;
      case _DynamicSubTab.draw:
        _loadDraws(refresh: false);
        break;
      case _DynamicSubTab.article:
        _loadArticles(refresh: false);
        break;
    }
  }

  int get _currentLimit {
    switch (_selectedTab) {
      case _DynamicSubTab.video:
        return _videoLimit;
      case _DynamicSubTab.draw:
        return _drawLimit;
      case _DynamicSubTab.article:
        return _articleLimit;
    }
  }

  void _extendLimit() {
    setState(() {
      switch (_selectedTab) {
        case _DynamicSubTab.video:
          _videoLimit += SettingsService.listMaxItems;
          break;
        case _DynamicSubTab.draw:
          _drawLimit += SettingsService.listMaxItems;
          break;
        case _DynamicSubTab.article:
          _articleLimit += SettingsService.listMaxItems;
          break;
      }
    });
    _loadMoreForCurrentTab();
  }

  // ========== 点击事件 ==========

  void _onVideoTap(Video video) {
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

  void _onDrawTap(DynamicDraw draw) {
    final previousFocus = FocusManager.instance.primaryFocus;
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => DynamicDetailScreen.fromDraw(draw)))
        .then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previousFocus != null && previousFocus.canRequestFocus) {
          previousFocus.requestFocus();
        }
      });
    });
  }

  void _onArticleTap(DynamicArticle article) {
    final previousFocus = FocusManager.instance.primaryFocus;
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => DynamicDetailScreen.fromArticle(article)))
        .then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previousFocus != null && previousFocus.canRequestFocus) {
          previousFocus.requestFocus();
        }
      });
    });
  }

  // ========== 构建 ==========

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '请先登录',
              style: TextStyle(
                  color: AppColors.inactiveText, fontSize: AppFonts.sizeXL),
            ),
            const SizedBox(height: 10),
            Text(
              '登录后可查看关注的动态',
              style: TextStyle(
                  color: AppColors.disabledText, fontSize: AppFonts.sizeMD),
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
              Expanded(child: _buildContent()),
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        _buildHeader(),
        if (_updateTimeText.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).size.height * 2 / 3,
            left: 0,
            right: 0,
            child: Center(
              child: UpdateTimeBanner(
                key: ValueKey(_updateTimeBannerKey),
                timeText: _updateTimeText,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    const tabLabels = ['视频投稿', '图文（开发中）', '专栏'];
    return Positioned(
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
              children: List.generate(3, (index) {
                final isSelected =
                    _selectedTab == _DynamicSubTab.values[index];
                return _DynamicTabLabel(
                  label: tabLabels[index],
                  isSelected: isSelected,
                  focusNode: _tabFocusNodes[index],
                  onTap: () => _onTabTap(index),
                  onFocus: () {
                    if (SettingsService.focusSwitchTab) {
                      _switchTab(_DynamicSubTab.values[index]);
                    }
                  },
                  onConfirm: () => _onTabTap(index),
                  onMoveLeft: index == 0
                      ? () => widget.sidebarFocusNode?.requestFocus()
                      : null,
                  onMoveRight: index == 2
                      ? () => _tabFocusNodes[0].requestFocus()
                      : null,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_currentIsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentItemCount == 0) {
      return _buildEmptyState();
    }

    switch (_selectedTab) {
      case _DynamicSubTab.video:
        return _buildVideoGrid();
      case _DynamicSubTab.draw:
        return _buildDrawGrid();
      case _DynamicSubTab.article:
        return _buildArticleList();
    }
  }

  Widget _buildEmptyState() {
    final messages = {
      _DynamicSubTab.video: '暂无视频动态',
      _DynamicSubTab.draw: '暂无图文动态',
      _DynamicSubTab.article: '暂无专栏动态',
    };
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
          Text(
            messages[_selectedTab] ?? '暂无动态',
            style: TextStyle(
                color: AppColors.inactiveText, fontSize: AppFonts.sizeXL),
          ),
        ],
      ),
    );
  }

  // ========== 视频网格 ==========

  Widget _buildVideoGrid() {
    final gridColumns = SettingsService.videoGridColumns;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: TabStyle.contentPadding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridColumns,
              childAspectRatio:
                  GridStyle.videoCardAspectRatio(context, gridColumns),
              crossAxisSpacing: 20,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final video = _videos[index];
                if (_videoHasMore &&
                    !_isLoadingMore &&
                    !_currentReachedLimit &&
                    index >= _videos.length - gridColumns) {
                  _loadMoreForCurrentTab();
                }
                return Builder(
                  builder: (ctx) => TvVideoCard(
                    video: video,
                    focusNode: _getCardFocusNode(index),
                    disableCache: false,
                    index: index,
                    gridColumns: gridColumns,
                    onTap: () => _onVideoTap(video),
                    onMoveLeft: (index % gridColumns == 0)
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () => _getCardFocusNode(index - 1).requestFocus(),
                    onMoveRight: (index + 1 < _videos.length)
                        ? () => _getCardFocusNode(index + 1).requestFocus()
                        : null,
                    onMoveUp: index >= gridColumns
                        ? () =>
                            _getCardFocusNode(index - gridColumns).requestFocus()
                        : (index < gridColumns
                            ? () => _tabFocusNodes[0].requestFocus()
                            : () {}),
                    onMoveDown: (index + gridColumns < _videos.length)
                        ? () =>
                            _getCardFocusNode(index + gridColumns).requestFocus()
                        : _currentReachedLimit
                            ? () => _loadMoreFocusNode.requestFocus()
                            : () {},
                    onFocus: () {},
                  ),
                );
              },
              childCount: _videos.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
        if (_currentReachedLimit)
          SliverToBoxAdapter(child: _buildLoadMoreTile()),
      ],
    );
  }

  // ========== 图文网格 ==========

  Widget _buildDrawGrid() {
    final gridColumns = SettingsService.drawGridColumns;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: TabStyle.contentPadding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridColumns,
              childAspectRatio:
                  GridStyle.videoCardAspectRatio(context, gridColumns),
              crossAxisSpacing: 20,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final draw = _draws[index];
                if (_drawHasMore &&
                    !_isLoadingMore &&
                    !_currentReachedLimit &&
                    index >= _draws.length - gridColumns) {
                  _loadMoreForCurrentTab();
                }
                return Builder(
                  builder: (ctx) => TvDynamicDrawCard(
                    item: draw,
                    focusNode: _getCardFocusNode(index),
                    index: index,
                    gridColumns: gridColumns,
                    onTap: () => _onDrawTap(draw),
                    onMoveLeft: (index % gridColumns == 0)
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () => _getCardFocusNode(index - 1).requestFocus(),
                    onMoveRight: (index + 1 < _draws.length)
                        ? () => _getCardFocusNode(index + 1).requestFocus()
                        : null,
                    onMoveUp: index >= gridColumns
                        ? () =>
                            _getCardFocusNode(index - gridColumns).requestFocus()
                        : (index < gridColumns
                            ? () => _tabFocusNodes[1].requestFocus()
                            : () {}),
                    onMoveDown: (index + gridColumns < _draws.length)
                        ? () =>
                            _getCardFocusNode(index + gridColumns).requestFocus()
                        : _currentReachedLimit
                            ? () => _loadMoreFocusNode.requestFocus()
                            : () {},
                    onFocus: () {},
                  ),
                );
              },
              childCount: _draws.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
        if (_currentReachedLimit)
          SliverToBoxAdapter(child: _buildLoadMoreTile()),
      ],
    );
  }

  // ========== 专栏列表 ==========

  Widget _buildArticleList() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: TabStyle.contentPadding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final article = _articles[index];
                if (_articleHasMore &&
                    !_isLoadingMore &&
                    !_currentReachedLimit &&
                    index >= _articles.length - 1) {
                  _loadMoreForCurrentTab();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 134,
                    child: TvDynamicArticleCard(
                      item: article,
                      focusNode: _getCardFocusNode(index),
                      index: index,
                      onTap: () => _onArticleTap(article),
                      onMoveLeft: () =>
                          widget.sidebarFocusNode?.requestFocus(),
                      onMoveRight: null,
                      onMoveUp: index > 0
                          ? () =>
                              _getCardFocusNode(index - 1).requestFocus()
                          : () => _tabFocusNodes[2].requestFocus(),
                      onMoveDown: (index + 1 < _articles.length)
                          ? () =>
                              _getCardFocusNode(index + 1).requestFocus()
                          : _currentReachedLimit
                              ? () => _loadMoreFocusNode.requestFocus()
                              : () {},
                      onFocus: () {},
                    ),
                  ),
                );
              },
              childCount: _articles.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
        if (_currentReachedLimit)
          SliverToBoxAdapter(child: _buildLoadMoreTile()),
      ],
    );
  }

  // ========== 加载更多按钮 ==========

  Widget _buildLoadMoreTile() {
    final gridColumns = _selectedTab == _DynamicSubTab.article
        ? 1
        : (_selectedTab == _DynamicSubTab.draw
            ? SettingsService.drawGridColumns
            : SettingsService.videoGridColumns);

    return Focus(
      focusNode: _loadMoreFocusNode,
      onKeyEvent: (node, event) {
        return TvKeyHandler.handleSinglePress(
          event,
          onUp: () {
            final total = _currentItemCount;
            final lastRowStart = (total ~/ gridColumns) * gridColumns;
            final targetIndex =
                lastRowStart < total ? lastRowStart : total - 1;
            _getCardFocusNode(targetIndex).requestFocus();
          },
          blockDown: true,
          onLeft: () => widget.sidebarFocusNode?.requestFocus(),
          onSelect: _extendLimit,
        );
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
                    ? SettingsService.themeColor
                        .withValues(alpha: AppColors.focusAlpha)
                    : AppColors.navItemSelectedBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more,
                    color: isFocused
                        ? AppColors.primaryText
                        : AppColors.inactiveText,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已加载 $_currentItemCount 条，按确认键加载更多',
                    style: TextStyle(
                      color: isFocused
                          ? AppColors.primaryText
                          : AppColors.inactiveText,
                      fontSize: AppFonts.sizeMD,
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
}

/// 动态 Tab 标签组件
class _DynamicTabLabel extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onConfirm;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;

  const _DynamicTabLabel({
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
          return TvKeyHandler.handleSinglePress(
            event,
            onLeft: onMoveLeft,
            onRight: onMoveRight,
            onSelect: onConfirm,
            blockUp: true,
          );
        },
        child: Builder(
          builder: (ctx) {
            final f = Focus.of(ctx).hasFocus;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  focusNode.requestFocus();
                  onTap();
                },
                child: Container(
                  padding: TabStyle.tabPadding,
                  decoration: BoxDecoration(
                    color: f
                        ? SettingsService.themeColor
                            .withValues(alpha: AppColors.focusAlpha)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(TabStyle.tabBorderRadius),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: f
                              ? AppColors.primaryText
                              : (isSelected
                                  ? AppColors.primaryText
                                  : AppColors.inactiveText),
                          fontSize: TabStyle.tabFontSize,
                          fontWeight: f || isSelected
                              ? AppFonts.bold
                              : AppFonts.medium,
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
                                  .withValues(alpha: AppColors.focusAlpha)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            TabStyle.tabUnderlineRadius,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
