import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import '../../models/favorite_folder.dart';
import '../../models/following_user.dart';
import '../../models/video.dart';
import '../../services/auth_service.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../config/app_style.dart';
import '../../utils/image_url_utils.dart';
import '../../widgets/tv_video_card.dart';
import '../player/player_screen.dart';
import 'up_space_popup.dart';

/// 我的内容 Tab（关注列表 / 收藏夹 / 稍后再看）
class FollowingTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const FollowingTab({
    super.key,
    this.sidebarFocusNode,
    this.isVisible = false,
  });

  @override
  State<FollowingTab> createState() => FollowingTabState();
}

class FollowingTabState extends State<FollowingTab> {
  // 每个子 tab 独立的 ScrollController，切换 tab 时保持各自滚动位置
  final ScrollController _followingScrollController = ScrollController();
  final ScrollController _favoritesScrollController = ScrollController();
  final ScrollController _watchLaterScrollController = ScrollController();

  ScrollController get _activeScrollController {
    switch (_selectedTabIndex) {
      case 0:
        return _followingScrollController;
      case 1:
        return _favoritesScrollController;
      default:
        return _watchLaterScrollController;
    }
  }

  final Map<int, FocusNode> _followingFocusNodes = {};
  final Map<int, FocusNode> _favoriteVideoFocusNodes = {};
  final Map<int, FocusNode> _watchLaterFocusNodes = {};
  late final List<FocusNode> _tabFocusNodes;
  List<FocusNode> _folderFocusNodes = [];

  /// 处理返回键：如果焦点在内容卡片上，先回到顶部 Tab；否则返回 false 让上层处理
  bool handleBack() {
    // 如果 UP主弹窗正在显示，先关闭弹窗
    if (_selectedUpUser != null) {
      _closeUpSpacePopup();
      return true;
    }
    // 检查焦点是否在顶部 Tab 上
    for (final node in _tabFocusNodes) {
      if (node.hasFocus) {
        return false; // 已经在顶部 Tab 上，让上层处理
      }
    }
    // 检查焦点是否在收藏夹文件夹标签上
    for (final node in _folderFocusNodes) {
      if (node.hasFocus) {
        // 在文件夹标签上，回到顶部 Tab
        _tabFocusNodes[_selectedTabIndex].requestFocus();
        return true;
      }
    }
    // 焦点在内容卡片上，回到当前顶部 Tab
    _tabFocusNodes[_selectedTabIndex].requestFocus();
    return true;
  }

  int _selectedTabIndex = 0; // 0=关注列表, 1=收藏夹, 2=稍后再看
  final Set<int> _visitedSubTabs = {0}; // 已访问过的子 tab（默认只构建关注列表）
  bool _hasLoadedFollowing = false;
  bool _hasLoadedFavorites = false;
  bool _hasLoadedWatchLater = false;

  // 关注列表
  List<FollowingUser> _users = [];
  bool _followingLoading = false;
  bool _followingLoadingMore = false;
  bool _followingHasMore = true;
  int _followingPage = 1;

  // 收藏夹
  List<FavoriteFolder> _folders = [];
  int _selectedFolderIndex = 0;
  List<Video> _favoriteVideos = [];
  final Map<int, List<Video>> _favoriteVideosCache = {};
  final Map<int, int> _favoriteNextPageCache = {};
  final Map<int, bool> _favoriteHasMoreCache = {};
  bool _favoritesLoading = false;
  bool _favoritesLoadingMore = false;
  bool _favoritesHasMore = true;
  int _favoritesPage = 1;

  // 稍后再看
  List<Video> _watchLaterVideos = [];
  bool _watchLaterLoading = false;

  // UP主空间弹窗
  FollowingUser? _selectedUpUser;

  @override
  void initState() {
    super.initState();
    _tabFocusNodes = List.generate(3, (_) => FocusNode());
    _followingScrollController.addListener(_onFollowingScroll);
    _favoritesScrollController.addListener(_onFavoritesScroll);
    // 首次创建且可见时立即加载当前子 tab（默认关注列表）
    if (widget.isVisible && AuthService.isLoggedIn) {
      _loadCurrentTab(reset: false);
    }
  }

  @override
  void didUpdateWidget(covariant FollowingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从不可见切换到可见时，加载当前子 tab（如尚未加载）
    if (widget.isVisible && !oldWidget.isVisible && AuthService.isLoggedIn) {
      _loadCurrentTab(reset: false);
    }
  }

  @override
  void dispose() {
    _followingScrollController.removeListener(_onFollowingScroll);
    _followingScrollController.dispose();
    _favoritesScrollController.removeListener(_onFavoritesScroll);
    _favoritesScrollController.dispose();
    _watchLaterScrollController.dispose();
    for (final node in _followingFocusNodes.values) {
      node.dispose();
    }
    for (final node in _favoriteVideoFocusNodes.values) {
      node.dispose();
    }
    for (final node in _watchLaterFocusNodes.values) {
      node.dispose();
    }
    for (final node in _tabFocusNodes) {
      node.dispose();
    }
    for (final node in _folderFocusNodes) {
      node.dispose();
    }
    _followingFocusNodes.clear();
    _favoriteVideoFocusNodes.clear();
    _watchLaterFocusNodes.clear();
    _folderFocusNodes.clear();
    super.dispose();
  }

  FocusNode _getFollowingFocusNode(int index) {
    return _followingFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  FocusNode _getFavoriteVideoFocusNode(int index) {
    return _favoriteVideoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  FocusNode _getWatchLaterFocusNode(int index) {
    return _watchLaterFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void _onFollowingScroll() {
    if (_followingScrollController.position.pixels <
        _followingScrollController.position.maxScrollExtent - 200)
      return;
    if (!_followingLoading &&
        !_followingLoadingMore &&
        _followingHasMore &&
        _users.length < 60) {
      _loadFollowingUsers(reset: false);
    }
  }

  void _onFavoritesScroll() {
    if (_favoritesScrollController.position.pixels <
        _favoritesScrollController.position.maxScrollExtent - 200)
      return;
    if (!_favoritesLoading &&
        !_favoritesLoadingMore &&
        _favoritesHasMore &&
        _favoriteVideos.length < 60) {
      _loadFavoriteVideos(reset: false);
    }
  }

  /// 公开刷新方法 - 供 HomeScreen 调用
  void refresh() {
    if (!AuthService.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _followingLoading = false;
        _followingLoadingMore = false;
        _favoritesLoading = false;
        _favoritesLoadingMore = false;
        _watchLaterLoading = false;
        _users = [];
        _folders = [];
        _favoriteVideos = [];
        _watchLaterVideos = [];
      });
      _hasLoadedFollowing = false;
      _hasLoadedFavorites = false;
      _hasLoadedWatchLater = false;
      return;
    }
    _loadCurrentTab(reset: true);
  }

  /// 公开焦点方法 - 从侧边栏进入时聚焦当前主 Tab
  void focusSelectedTopTab() {
    if (_tabFocusNodes.isEmpty) return;
    final index = _selectedTabIndex.clamp(0, _tabFocusNodes.length - 1);
    _tabFocusNodes[index].requestFocus();
  }

  void _switchTab(int index, {bool refreshIfSame = true}) {
    if (_selectedTabIndex == index) {
      if (refreshIfSame) {
        _scrollToTop();
        _loadCurrentTab(reset: true);
      }
      return;
    }
    _visitedSubTabs.add(index);
    setState(() => _selectedTabIndex = index);
    // 不重置滚动位置，IndexedStack 保持各 tab 的滚动状态
    _loadCurrentTab(reset: false);
  }

  void _loadCurrentTab({required bool reset}) {
    if (!AuthService.isLoggedIn) return;

    if (_selectedTabIndex == 0) {
      if (reset) {
        _hasLoadedFollowing = true;
        _loadFollowingUsers(reset: true);
      } else if (!_hasLoadedFollowing) {
        // 首次加载：先尝试缓存
        if (_tryLoadFollowingFromCache()) {
          _hasLoadedFollowing = true;
        } else {
          _hasLoadedFollowing = true;
          _loadFollowingUsers(reset: true);
        }
      }
    } else if (_selectedTabIndex == 1) {
      if (reset) {
        _hasLoadedFavorites = true;
        _loadFavoriteFoldersAndFirstPage(reset: true);
      } else if (!_hasLoadedFavorites) {
        if (_tryLoadFavoritesFromCache()) {
          _hasLoadedFavorites = true;
        } else {
          _hasLoadedFavorites = true;
          _loadFavoriteFoldersAndFirstPage(reset: true);
        }
      }
    } else {
      if (reset) {
        _hasLoadedWatchLater = true;
        _loadWatchLaterVideos();
      } else if (!_hasLoadedWatchLater) {
        if (_tryLoadWatchLaterFromCache()) {
          _hasLoadedWatchLater = true;
        } else {
          _hasLoadedWatchLater = true;
          _loadWatchLaterVideos();
        }
      }
    }
  }

  Future<void> _loadFollowingUsers({required bool reset}) async {
    if (reset) {
      // 释放旧的 FocusNode，防止内存泄漏
      for (final node in _followingFocusNodes.values) {
        node.dispose();
      }
      _followingFocusNodes.clear();
      setState(() {
        _followingLoading = true;
        _users = [];
        _followingPage = 1;
        _followingHasMore = true;
      });
    } else {
      setState(() => _followingLoadingMore = true);
    }

    final result = await BilibiliApi.getFollowingUsers(
      page: reset ? 1 : _followingPage,
      pageSize: 30,
    );
    if (!mounted) return;

    final newUsers = result['list'] as List<FollowingUser>;
    final hasMore = result['hasMore'] as bool;
    setState(() {
      if (reset) {
        _users = newUsers;
        _followingLoading = false;
      } else {
        final existingMids = _users.map((e) => e.mid).toSet();
        final uniqueNewUsers = newUsers
            .where((u) => !existingMids.contains(u.mid))
            .toList();
        _users.addAll(uniqueNewUsers);
        _followingLoadingMore = false;
      }
      _followingHasMore = hasMore;
      if (!reset && newUsers.isNotEmpty) {
        _followingPage += 1;
      } else if (reset) {
        _followingPage = 2;
      }
    });

    // 首页加载完成后保存缓存
    if (reset && _users.isNotEmpty) {
      _saveFollowingCache();
    }
  }

  Future<void> _loadFavoriteFoldersAndFirstPage({required bool reset}) async {
    if (reset) {
      // 释放旧的 FocusNode，防止内存泄漏
      for (final node in _favoriteVideoFocusNodes.values) {
        node.dispose();
      }
      _favoriteVideoFocusNodes.clear();
      setState(() {
        _favoritesLoading = true;
        _folders = [];
        _favoriteVideos = [];
        _favoriteVideosCache.clear();
        _favoriteNextPageCache.clear();
        _favoriteHasMoreCache.clear();
        _favoritesHasMore = true;
        _favoritesPage = 1;
      });
    }

    final folders = await BilibiliApi.getFavoriteFolders();
    if (!mounted) return;

    if (folders.isEmpty) {
      setState(() {
        _folders = [];
        _favoritesLoading = false;
      });
      return;
    }

    int folderIndex = _selectedFolderIndex;
    if (reset || folderIndex >= folders.length) {
      final defaultIndex = folders.indexWhere((f) => f.isDefault);
      folderIndex = defaultIndex >= 0 ? defaultIndex : 0;
    }

    _rebuildFolderFocusNodes(folders.length);
    setState(() {
      _folders = folders;
      _selectedFolderIndex = folderIndex;
    });

    await _loadFavoriteVideos(reset: true);
  }

  Future<void> _loadFavoriteVideos({required bool reset}) async {
    if (_folders.isEmpty) {
      setState(() {
        _favoriteVideos = [];
        _favoritesLoading = false;
        _favoritesLoadingMore = false;
        _favoritesHasMore = false;
      });
      return;
    }

    // 在请求发起时捕获当前选中的收藏夹索引和 ID
    final requestFolderIndex = _selectedFolderIndex;
    final folderId = _folders[requestFolderIndex].id;

    if (reset) {
      setState(() {
        _favoritesLoading = true;
        _favoriteVideos = [];
        _favoritesPage = 1;
        _favoritesHasMore = true;
      });
    } else {
      setState(() => _favoritesLoadingMore = true);
    }

    final result = await BilibiliApi.getFavoriteFolderVideos(
      mediaId: folderId,
      page: reset ? 1 : _favoritesPage,
      pageSize: 20,
    );
    if (!mounted) return;

    final list = result['list'] as List<Video>;
    final hasMore = result['hasMore'] as bool;
    final nextPage = reset ? 2 : _favoritesPage + 1;

    // 先更新缓存（无论当前选中的收藏夹是否改变）
    if (reset) {
      _favoriteVideosCache[folderId] = List<Video>.from(list);
    } else {
      final cached = _favoriteVideosCache[folderId] ?? [];
      final existingBvids = cached.map((v) => v.bvid).toSet();
      final unique = list
          .where((v) => !existingBvids.contains(v.bvid))
          .toList();
      _favoriteVideosCache[folderId] = [...cached, ...unique];
    }
    _favoriteNextPageCache[folderId] = nextPage;
    _favoriteHasMoreCache[folderId] = hasMore;

    // 只有当前选中的收藏夹仍然是请求发起时的收藏夹，才更新 UI
    if (_selectedFolderIndex == requestFolderIndex) {
      setState(() {
        // 直接引用缓存，避免额外拷贝
        _favoriteVideos = _favoriteVideosCache[folderId]!;
        _favoritesHasMore = hasMore;
        _favoritesPage = nextPage;
        if (reset) {
          _favoritesLoading = false;
        } else {
          _favoritesLoadingMore = false;
        }
      });

      // 首页加载完成后保存缓存（仅保存首次 reset 加载的默认收藏夹）
      if (reset && _favoriteVideos.isNotEmpty && _folders.isNotEmpty) {
        _saveFavoritesCache();
      }
    }
    // 收藏夹已切换时不更新 UI，缓存已保存供后续使用
  }

  Future<void> _loadWatchLaterVideos() async {
    // 释放旧的 FocusNode，防止内存泄漏
    for (final node in _watchLaterFocusNodes.values) {
      node.dispose();
    }
    _watchLaterFocusNodes.clear();
    setState(() => _watchLaterLoading = true);
    final list = await BilibiliApi.getWatchLaterVideos();
    if (!mounted) return;
    setState(() {
      _watchLaterVideos = list;
      _watchLaterLoading = false;
    });

    // 保存缓存
    if (_watchLaterVideos.isNotEmpty) {
      _saveWatchLaterCache();
    }
  }

  // ==================== 本地缓存读写 ====================

  void _saveFollowingCache() {
    try {
      final json = jsonEncode(_users.map((u) => u.toMap()).toList());
      SettingsService.setCachedFollowingJson(json);
    } catch (_) {}
  }

  void _saveFavoritesCache() {
    try {
      final foldersJson = jsonEncode(_folders.map((f) => f.toMap()).toList());
      SettingsService.setCachedFavoriteFoldersJson(foldersJson);
      final videosJson = jsonEncode(
        _favoriteVideos.map((v) => v.toMap()).toList(),
      );
      SettingsService.setCachedFavoriteVideosJson(videosJson);
    } catch (_) {}
  }

  void _saveWatchLaterCache() {
    try {
      final json = jsonEncode(_watchLaterVideos.map((v) => v.toMap()).toList());
      SettingsService.setCachedWatchLaterJson(json);
    } catch (_) {}
  }

  /// 从缓存加载关注列表，成功返回 true
  bool _tryLoadFollowingFromCache() {
    final jsonStr = SettingsService.cachedFollowingJson;
    if (jsonStr == null) return false;
    try {
      final list = jsonDecode(jsonStr) as List;
      final users = list
          .map((item) => FollowingUser.fromMap(item as Map<String, dynamic>))
          .toList();
      if (users.isEmpty) return false;
      setState(() {
        _users = users;
        _followingLoading = false;
        _followingHasMore = false; // 缓存不支持加载更多
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 从缓存加载收藏夹，成功返回 true
  bool _tryLoadFavoritesFromCache() {
    final foldersStr = SettingsService.cachedFavoriteFoldersJson;
    final videosStr = SettingsService.cachedFavoriteVideosJson;
    if (foldersStr == null || videosStr == null) return false;
    try {
      final folderList = jsonDecode(foldersStr) as List;
      final folders = folderList
          .map((item) => FavoriteFolder.fromMap(item as Map<String, dynamic>))
          .toList();
      final videoList = jsonDecode(videosStr) as List;
      final videos = videoList
          .map((item) => Video.fromMap(item as Map<String, dynamic>))
          .toList();
      if (folders.isEmpty) return false;
      final defaultIndex = folders.indexWhere((f) => f.isDefault);
      final folderIndex = defaultIndex >= 0 ? defaultIndex : 0;
      _rebuildFolderFocusNodes(folders.length);
      setState(() {
        _folders = folders;
        _selectedFolderIndex = folderIndex;
        _favoriteVideos = videos;
        _favoritesLoading = false;
        _favoritesHasMore = false; // 缓存不支持加载更多
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 从缓存加载稍后再看，成功返回 true
  bool _tryLoadWatchLaterFromCache() {
    final jsonStr = SettingsService.cachedWatchLaterJson;
    if (jsonStr == null) return false;
    try {
      final list = jsonDecode(jsonStr) as List;
      final videos = list
          .map((item) => Video.fromMap(item as Map<String, dynamic>))
          .toList();
      if (videos.isEmpty) return false;
      setState(() {
        _watchLaterVideos = videos;
        _watchLaterLoading = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _switchFolder(int index, {bool refreshIfSame = true}) {
    if (index < 0 || index >= _folders.length) return;
    if (_selectedFolderIndex == index) {
      if (refreshIfSame) {
        _loadFavoriteVideos(reset: true);
      }
      return;
    }
    if (_favoritesScrollController.hasClients) {
      _favoritesScrollController.jumpTo(0);
    }
    _showFolder(index);
  }

  void _showFolder(int index) {
    if (index < 0 || index >= _folders.length) return;

    final folderId = _folders[index].id;
    final cachedVideos = _favoriteVideosCache[folderId];

    if (cachedVideos != null) {
      setState(() {
        _selectedFolderIndex = index;
        _favoriteVideos = cachedVideos; // 直接引用缓存
        _favoritesLoading = false;
        _favoritesLoadingMore = false;
        _favoritesPage = _favoriteNextPageCache[folderId] ?? 1;
        _favoritesHasMore = _favoriteHasMoreCache[folderId] ?? false;
      });
      return;
    }

    setState(() {
      _selectedFolderIndex = index;
      _favoriteVideos = [];
      _favoritesLoading = true;
      _favoritesLoadingMore = false;
      _favoritesHasMore = true;
      _favoritesPage = 1;
    });
    _loadFavoriteVideos(reset: true);
  }

  void _rebuildFolderFocusNodes(int count) {
    for (final node in _folderFocusNodes) {
      node.dispose();
    }
    _folderFocusNodes = List.generate(count, (_) => FocusNode());
  }

  void _scrollToTop() {
    final controller = _activeScrollController;
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  void _openVideo(Video video) {
    if (video.bvid.isEmpty) {
      ToastUtils.show(context, '该视频不可播放');
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  void _openUserSpace(FollowingUser user) {
    setState(() {
      _selectedUpUser = user;
    });
  }

  void _closeUpSpacePopup() {
    // 先保存用户信息用于恢复焦点
    final closingUser = _selectedUpUser;
    setState(() {
      _selectedUpUser = null;
    });
    // 恢复焦点到之前的UP主卡片
    if (closingUser != null) {
      final index = _users.indexWhere((u) => u.mid == closingUser.mid);
      if (index >= 0 && _followingFocusNodes.containsKey(index)) {
        // 延迟执行焦点恢复，等待 popup 完全关闭
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _followingFocusNodes.containsKey(index)) {
            _followingFocusNodes[index]!.requestFocus();
          }
        });
      }
    }
  }

  Widget _buildTopTabs() {
    const labels = ['关注列表', '收藏夹', '稍后再看'];
    return Row(
      children: List.generate(labels.length, (index) {
        return _TopTab(
          label: labels[index],
          focusNode: _tabFocusNodes[index],
          isSelected: _selectedTabIndex == index,
          onFocus: () => _switchTab(index, refreshIfSame: false),
          onTap: () => _switchTab(index, refreshIfSame: true),
          onMoveLeft: index == 0
              ? () => widget.sidebarFocusNode?.requestFocus()
              : null,
          // 最后一项向右循环到第一项
          onMoveRight: index == labels.length - 1
              ? () => _tabFocusNodes[0].requestFocus()
              : null,
          // 收藏夹 Tab 向下移动到第一个子收藏夹
          onMoveDown: index == 1 && _folderFocusNodes.isNotEmpty
              ? () => _folderFocusNodes[_selectedFolderIndex].requestFocus()
              : null,
        );
      }),
    );
  }

  Widget _buildFolderTabs() {
    if (_selectedTabIndex != 1 || _folders.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_folders.length, (index) {
            final folder = _folders[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FolderTab(
                label: '${folder.title} (${folder.mediaCount})',
                isSelected: _selectedFolderIndex == index,
                focusNode: _folderFocusNodes[index],
                onFocus: () => _switchFolder(index, refreshIfSame: false),
                onTap: () => _switchFolder(index, refreshIfSame: true),
                onMoveLeft: index == 0
                    ? () => widget.sidebarFocusNode?.requestFocus()
                    : () => _folderFocusNodes[index - 1].requestFocus(),
                onMoveRight: (index + 1 < _folderFocusNodes.length)
                    ? () => _folderFocusNodes[index + 1].requestFocus()
                    : () => _folderFocusNodes[0].requestFocus(),
                onMoveUp: () => _tabFocusNodes[1].requestFocus(),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCurrentContent() {
    // 懒构建：未访问过的子 tab 用占位符代替，减少不必要的 widget 构建
    Widget _lazySubTab(int index, Widget Function() builder) {
      return _visitedSubTabs.contains(index)
          ? builder()
          : const SizedBox.shrink();
    }

    return IndexedStack(
      index: _selectedTabIndex,
      children: [
        _buildFollowingContent(),
        _lazySubTab(1, _buildFavoritesContent),
        _lazySubTab(2, _buildWatchLaterContent),
      ],
    );
  }

  Widget _buildFollowingContent() {
    if (_followingLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasLoadedFollowing) {
      return const SizedBox.shrink();
    }
    if (_users.isEmpty) {
      return _buildEmpty('暂无关注', Icons.people_outline);
    }
    return _buildFollowingGrid();
  }

  Widget _buildFavoritesContent() {
    if (_favoritesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasLoadedFavorites) {
      return const SizedBox.shrink();
    }
    if (_folders.isEmpty) {
      return _buildEmpty('暂无收藏夹', Icons.folder_open);
    }
    if (_favoriteVideos.isEmpty) {
      return _buildEmpty('当前收藏夹暂无视频', Icons.video_library_outlined);
    }
    return _buildVideoGrid(
      videos: _favoriteVideos,
      focusNodeAt: _getFavoriteVideoFocusNode,
      scrollController: _favoritesScrollController,
    );
  }

  Widget _buildWatchLaterContent() {
    if (_watchLaterLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasLoadedWatchLater) {
      return const SizedBox.shrink();
    }
    if (_watchLaterVideos.isEmpty) {
      return _buildEmpty('稍后再看为空', Icons.watch_later_outlined);
    }
    return _buildVideoGrid(
      videos: _watchLaterVideos,
      focusNodeAt: _getWatchLaterFocusNode,
      scrollController: _watchLaterScrollController,
    );
  }

  Widget _buildEmpty(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.white38),
          const SizedBox(height: 20),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowingGrid() {
    return CustomScrollView(
      controller: _followingScrollController,
      slivers: [
        SliverPadding(
          padding: TabStyle.contentPadding,
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 320 / 100,
              crossAxisSpacing: 20,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final user = _users[index];
                if (_followingHasMore &&
                    !_followingLoading &&
                    !_followingLoadingMore &&
                    index >= _users.length - 4) {
                  _loadFollowingUsers(reset: false);
                }
                return Builder(
                  builder: (ctx) => _FollowingUserCard(
                    user: user,
                    focusNode: _getFollowingFocusNode(index),
                    onTap: () => _openUserSpace(user),
                    onMoveLeft: (index % 4 == 0)
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () =>
                              _getFollowingFocusNode(index - 1).requestFocus(),
                    onMoveRight: (index + 1 < _users.length)
                        ? () => _getFollowingFocusNode(index + 1).requestFocus()
                        : null,
                    onMoveUp: index >= 4
                        ? () => _getFollowingFocusNode(index - 4).requestFocus()
                        : () =>
                              _tabFocusNodes[_selectedTabIndex].requestFocus(),
                    onMoveDown: (index + 4 < _users.length)
                        ? () => _getFollowingFocusNode(index + 4).requestFocus()
                        : null,
                    onFocus: () => _scrollToCard(ctx),
                  ),
                );
              },
              childCount: _users.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
        if (_followingLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoGrid({
    required List<Video> videos,
    required FocusNode Function(int index) focusNodeAt,
    required ScrollController scrollController,
  }) {
    final gridColumns = SettingsService.videoGridColumns;
    // 收藏夹存在子标签时，给列表更大顶部间距，避免覆盖第一行卡片
    final topPadding = (_selectedTabIndex == 1 && _folders.isNotEmpty)
        ? 90.0
        : 60.0;
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, topPadding, 24, 80),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridColumns,
              childAspectRatio: 320 / 280,
              crossAxisSpacing: 20,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final video = videos[index];
                if (_selectedTabIndex == 1 &&
                    _favoritesHasMore &&
                    !_favoritesLoading &&
                    !_favoritesLoadingMore &&
                    index >= videos.length - gridColumns) {
                  _loadFavoriteVideos(reset: false);
                }
                return Builder(
                  builder: (ctx) => TvVideoCard(
                    video: video,
                    focusNode: focusNodeAt(index),
                    disableCache: false,
                    index: index,
                    gridColumns: gridColumns,
                    topOffset: topPadding,
                    onTap: () => _openVideo(video),
                    onMoveLeft: (index % gridColumns == 0)
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () => focusNodeAt(index - 1).requestFocus(),
                    onMoveRight: (index + 1 < videos.length)
                        ? () => focusNodeAt(index + 1).requestFocus()
                        : null,
                    onMoveUp: index >= gridColumns
                        ? () => focusNodeAt(index - gridColumns).requestFocus()
                        : () {
                            if (_selectedTabIndex == 1 &&
                                _folderFocusNodes.isNotEmpty) {
                              _folderFocusNodes[_selectedFolderIndex]
                                  .requestFocus();
                            } else {
                              _tabFocusNodes[_selectedTabIndex].requestFocus();
                            }
                          },
                    onMoveDown: (index + gridColumns < videos.length)
                        ? () => focusNodeAt(index + gridColumns).requestFocus()
                        : null,
                    onFocus: () {},
                  ),
                );
              },
              childCount: videos.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
        if (_favoritesLoadingMore && _selectedTabIndex == 1)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  void _scrollToCard(BuildContext cardContext) {
    final controller = _activeScrollController;
    if (!controller.hasClients) return;

    final RenderObject? object = cardContext.findRenderObject();
    if (object == null || object is! RenderBox || !object.hasSize) return;

    final scrollableState = Scrollable.maybeOf(cardContext);
    if (scrollableState == null) return;

    final scrollableRO =
        scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollableRO == null || !scrollableRO.hasSize) return;

    final cardInViewport = object.localToGlobal(
      Offset.zero,
      ancestor: scrollableRO,
    );
    final viewportHeight = scrollableRO.size.height;
    final cardHeight = object.size.height;
    final cardTop = cardInViewport.dy;
    final cardBottom = cardTop + cardHeight;

    // 使用与 BaseTvCard 相同的渐进式滚动逻辑
    final revealHeight = cardHeight * TabStyle.scrollRevealRatio;
    final topBoundary = TabStyle.defaultTopOffset + revealHeight;
    final bottomBoundary = viewportHeight - revealHeight;

    double? targetScrollOffset;

    if (cardBottom > bottomBoundary) {
      // 卡片底部超出底部边界：向上滚动
      final delta = cardBottom - bottomBoundary;
      targetScrollOffset = controller.offset + delta;
    } else if (cardTop < topBoundary) {
      // 卡片顶部超出顶部边界：向下滚动
      final delta = cardTop - topBoundary;
      targetScrollOffset = controller.offset + delta;
    }

    if (targetScrollOffset == null) return;

    final target = targetScrollOffset.clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );

    if ((controller.offset - target).abs() < 4.0) return;

    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('请先登录', style: TextStyle(color: Colors.white70, fontSize: 20)),
            SizedBox(height: 10),
            Text(
              '登录后可查看关注列表',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: _buildCurrentContent()),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: TabStyle.headerBackgroundColor,
            padding: TabStyle.headerPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: TabStyle.headerHeight - 12, // 减去 top padding
                  child: _buildTopTabs(),
                ),
                _buildFolderTabs(),
              ],
            ),
          ),
        ),
        // UP主空间弹窗
        if (_selectedUpUser != null)
          Positioned.fill(
            child: UpSpacePopup(
              user: _selectedUpUser!,
              onClose: _closeUpSpacePopup,
            ),
          ),
      ],
    );
  }
}

class _TopTab extends StatelessWidget {
  final String label;
  final FocusNode focusNode;
  final bool isSelected;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveDown;

  const _TopTab({
    required this.label,
    required this.focusNode,
    required this.isSelected,
    required this.onFocus,
    required this.onTap,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) => f ? onFocus() : null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
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
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            onMoveDown != null) {
          onMoveDown!();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: TabStyle.tabPadding,
              decoration: BoxDecoration(
                color: focused
                    ? SettingsService.themeColor.withValues(alpha: 0.6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(TabStyle.tabBorderRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: focused
                          ? Colors.white
                          : (isSelected
                                ? SettingsService.themeColor
                                : Colors.white70),
                      fontSize: TabStyle.tabFontSize,
                      fontWeight: focused || isSelected
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
                      borderRadius: BorderRadius.circular(
                        TabStyle.tabUnderlineRadius,
                      ),
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

class _FolderTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;

  const _FolderTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onFocus,
    required this.onTap,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) => f ? onFocus() : null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
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
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            onMoveUp != null) {
          onMoveUp!();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: focused
                    ? SettingsService.themeColor.withValues(alpha: 0.6)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(10),
                border: isSelected && !focused
                    ? Border.all(color: SettingsService.themeColor, width: 1)
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : (isSelected
                            ? SettingsService.themeColor
                            : Colors.white70),
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FollowingUserCard extends StatelessWidget {
  final FollowingUser user;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onFocus;

  const _FollowingUserCard({
    required this.user,
    required this.focusNode,
    required this.onTap,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (focused) {
        if (focused) {
          onFocus?.call();
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
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
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            onMoveUp != null) {
          onMoveUp!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            onMoveDown != null) {
          onMoveDown!();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: focused
                  ? SettingsService.themeColor.withValues(alpha: 0.6)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(10),
              border: null,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
                children: [
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: ImageUrlUtils.getResizedUrl(
                        user.face,
                        width: 80,
                        height: 80,
                      ),
                      cacheManager: BiliCacheManager.instance,
                      memCacheWidth: 80,
                      memCacheHeight: 80,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          user.uname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.sign.isEmpty ? '这个人很神秘，什么都没写' : user.sign,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
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
