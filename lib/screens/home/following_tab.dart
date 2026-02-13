import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../models/favorite_folder.dart';
import '../../models/following_user.dart';
import '../../models/video.dart';
import '../../services/auth_service.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../widgets/time_display.dart';
import '../../widgets/tv_video_card.dart';
import '../player/player_screen.dart';
import 'up_space_screen.dart';

/// 我的内容 Tab（关注列表 / 收藏夹 / 稍后再看）
class FollowingTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const FollowingTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<FollowingTab> createState() => FollowingTabState();
}

class FollowingTabState extends State<FollowingTab> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, FocusNode> _followingFocusNodes = {};
  final Map<int, FocusNode> _favoriteVideoFocusNodes = {};
  final Map<int, FocusNode> _watchLaterFocusNodes = {};
  late final List<FocusNode> _tabFocusNodes;
  List<FocusNode> _folderFocusNodes = [];

  int _selectedTabIndex = 0; // 0=关注列表, 1=收藏夹, 2=稍后再看
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

  @override
  void initState() {
    super.initState();
    _tabFocusNodes = List.generate(3, (_) => FocusNode());
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant FollowingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅通过“点击关注”触发 refresh()，焦点切换到该页不自动刷新
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  void _onScroll() {
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }

    if (_selectedTabIndex == 0 &&
        !_followingLoading &&
        !_followingLoadingMore &&
        _followingHasMore &&
        _users.length < 60) {
      _loadFollowingUsers(reset: false);
      return;
    }

    if (_selectedTabIndex == 1 &&
        !_favoritesLoading &&
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
        _loadCurrentTab(reset: true);
      }
      return;
    }
    setState(() => _selectedTabIndex = index);
    _scrollToTop();
    _loadCurrentTab(reset: false);
  }

  void _loadCurrentTab({required bool reset}) {
    if (!AuthService.isLoggedIn) return;

    if (_selectedTabIndex == 0) {
      if (reset || !_hasLoadedFollowing) {
        _hasLoadedFollowing = true;
        _loadFollowingUsers(reset: true);
      }
    } else if (_selectedTabIndex == 1) {
      if (reset || !_hasLoadedFavorites) {
        _hasLoadedFavorites = true;
        _loadFavoriteFoldersAndFirstPage(reset: true);
      }
    } else {
      if (reset || !_hasLoadedWatchLater) {
        _hasLoadedWatchLater = true;
        _loadWatchLaterVideos();
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

    final folderId = _folders[_selectedFolderIndex].id;
    final result = await BilibiliApi.getFavoriteFolderVideos(
      mediaId: folderId,
      page: reset ? 1 : _favoritesPage,
      pageSize: 20,
    );
    if (!mounted) return;

    final list = result['list'] as List<Video>;
    final hasMore = result['hasMore'] as bool;
    setState(() {
      if (reset) {
        _favoriteVideos = list;
        _favoritesLoading = false;
      } else {
        final existingBvids = _favoriteVideos.map((v) => v.bvid).toSet();
        final unique = list.where((v) => !existingBvids.contains(v.bvid)).toList();
        _favoriteVideos.addAll(unique);
        _favoritesLoadingMore = false;
      }
      _favoritesHasMore = hasMore;
      if (!reset && list.isNotEmpty) {
        _favoritesPage += 1;
      } else if (reset) {
        _favoritesPage = 2;
      }

      // 按收藏夹缓存内容和分页状态，切换子收藏夹时可直接显示
      _favoriteVideosCache[folderId] = List<Video>.from(_favoriteVideos);
      _favoriteNextPageCache[folderId] = _favoritesPage;
      _favoriteHasMoreCache[folderId] = _favoritesHasMore;
    });
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
  }

  void _switchFolder(int index, {bool refreshIfSame = true}) {
    if (index < 0 || index >= _folders.length) return;
    if (_selectedFolderIndex == index) {
      if (refreshIfSame) {
        _loadFavoriteVideos(reset: true);
      }
      return;
    }
    _scrollToTop();
    _showFolder(index);
  }

  void _showFolder(int index) {
    if (index < 0 || index >= _folders.length) return;

    final folderId = _folders[index].id;
    final cachedVideos = _favoriteVideosCache[folderId];

    if (cachedVideos != null) {
      setState(() {
        _selectedFolderIndex = index;
        _favoriteVideos = List<Video>.from(cachedVideos);
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
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _openVideo(Video video) {
    if (video.bvid.isEmpty) {
      Fluttertoast.showToast(
        msg: '该视频不可播放',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  void _openUserSpace(FollowingUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            UpSpaceScreen(upMid: user.mid, upName: user.uname, upFace: user.face),
      ),
    );
  }

  bool get _isCurrentLoading {
    if (_selectedTabIndex == 0) return _followingLoading;
    if (_selectedTabIndex == 1) return _favoritesLoading;
    return _watchLaterLoading;
  }

  bool get _isCurrentLoadingMore {
    if (_selectedTabIndex == 0) return _followingLoadingMore;
    if (_selectedTabIndex == 1) return _favoritesLoadingMore;
    return false;
  }

  Widget _buildTopTabs() {
    const labels = ['关注列表', '收藏夹', '稍后再看'];
    return Row(
      children: List.generate(labels.length, (index) {
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _TopTab(
            label: labels[index],
            focusNode: _tabFocusNodes[index],
            isSelected: _selectedTabIndex == index,
            onFocus: () => _switchTab(index, refreshIfSame: false),
            onTap: () => _switchTab(index, refreshIfSame: true),
            onMoveLeft: index == 0
                ? () => widget.sidebarFocusNode?.requestFocus()
                : null,
          ),
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
                    : null,
                onMoveUp: () => _tabFocusNodes[1].requestFocus(),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCurrentContent() {
    if (_isCurrentLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedTabIndex == 0) {
      if (_users.isEmpty) {
        return _buildEmpty('暂无关注', Icons.people_outline);
      }
      return _buildFollowingGrid();
    }

    if (_selectedTabIndex == 1) {
      if (_folders.isEmpty) {
        return _buildEmpty('暂无收藏夹', Icons.folder_open);
      }
      if (_favoriteVideos.isEmpty) {
        return _buildEmpty('当前收藏夹暂无视频', Icons.video_library_outlined);
      }
      return _buildVideoGrid(
        videos: _favoriteVideos,
        focusNodeAt: _getFavoriteVideoFocusNode,
      );
    }

    if (_watchLaterVideos.isEmpty) {
      return _buildEmpty('稍后再看为空', Icons.watch_later_outlined);
    }
    return _buildVideoGrid(
      videos: _watchLaterVideos,
      focusNodeAt: _getWatchLaterFocusNode,
    );
  }

  Widget _buildEmpty(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.white38),
          const SizedBox(height: 20),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildFollowingGrid() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 90, 24, 80),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 320 / 132,
              crossAxisSpacing: 20,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
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
                      : () => _getFollowingFocusNode(index - 1).requestFocus(),
                  onMoveRight: (index + 1 < _users.length)
                      ? () => _getFollowingFocusNode(index + 1).requestFocus()
                      : null,
                  onMoveUp: index >= 4
                      ? () => _getFollowingFocusNode(index - 4).requestFocus()
                      : () => _tabFocusNodes[_selectedTabIndex].requestFocus(),
                  onMoveDown: (index + 4 < _users.length)
                      ? () => _getFollowingFocusNode(index + 4).requestFocus()
                      : null,
                  onFocus: () => _scrollToCard(ctx),
                ),
              );
            }, childCount: _users.length),
          ),
        ),
        if (_isCurrentLoadingMore)
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
  }) {
    final gridColumns = SettingsService.videoGridColumns;
    // 收藏夹存在子标签时，给列表更大顶部间距，避免覆盖第一行卡片
    final topPadding = (_selectedTabIndex == 1 && _folders.isNotEmpty) ? 120.0 : 90.0;
    return CustomScrollView(
      controller: _scrollController,
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
            delegate: SliverChildBuilderDelegate((context, index) {
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
                          if (_selectedTabIndex == 1 && _folderFocusNodes.isNotEmpty) {
                            _folderFocusNodes[_selectedFolderIndex].requestFocus();
                          } else {
                            _tabFocusNodes[_selectedTabIndex].requestFocus();
                          }
                        },
                  onMoveDown: (index + gridColumns < videos.length)
                      ? () => focusNodeAt(index + gridColumns).requestFocus()
                      : null,
                  onFocus: () => _scrollToCard(ctx),
                ),
              );
            }, childCount: videos.length),
          ),
        ),
        if (_isCurrentLoadingMore)
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
    if (!_scrollController.hasClients) return;
    final RenderObject? object = cardContext.findRenderObject();
    if (object != null && object is RenderBox) {
      final viewport = RenderAbstractViewport.of(object);
      final offsetToReveal = viewport.getOffsetToReveal(object, 0.0).offset;
      final targetOffset = (offsetToReveal - 120).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if ((_scrollController.offset - targetOffset).abs() > 50) {
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    }
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
            color: const Color(0xFF121212),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我的内容',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTopTabs(),
                _buildFolderTabs(),
              ],
            ),
          ),
        ),
        const Positioned(top: 10, right: 14, child: TimeDisplay()),
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

  const _TopTab({
    required this.label,
    required this.focusNode,
    required this.isSelected,
    required this.onFocus,
    required this.onTap,
    this.onMoveLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onFocusChange: (f) => f ? onFocus() : null,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            onMoveLeft != null) {
          onMoveLeft!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: focused ? const Color(0xFF81C784) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: focused ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : (isSelected ? const Color(0xFF81C784) : Colors.white70),
                  fontSize: 16,
                  fontWeight: focused || isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
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
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
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
                color: focused ? const Color(0xFF81C784) : Colors.white10,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused
                      ? Colors.white
                      : (isSelected ? const Color(0xFF81C784) : Colors.transparent),
                  width: focused ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: focused
                      ? Colors.white
                      : (isSelected ? const Color(0xFF81C784) : Colors.white70),
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
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
        if (event.logicalKey == LogicalKeyboardKey.arrowUp && onMoveUp != null) {
          onMoveUp!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            onMoveDown != null) {
          onMoveDown!();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: focused ? const Color(0xFF81C784) : Colors.white10,
              borderRadius: BorderRadius.circular(10),
              border: focused ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
                children: [
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: user.face,
                      cacheManager: BiliCacheManager.instance,
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
