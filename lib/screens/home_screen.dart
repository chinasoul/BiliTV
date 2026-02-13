import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:bili_tv_app/models/video.dart';
import 'home/home_tab.dart';
import 'home/history_tab.dart';
import 'home/search_tab.dart';
import 'home/login_tab.dart';
import 'home/dynamic_tab.dart';
import 'home/following_tab.dart';
import 'home/live_tab.dart';
import '../widgets/tv_focusable_item.dart';
import '../services/auth_service.dart';

/// 主页框架 - 完全按照 animeone_tv_app 的方式
class HomeScreen extends StatefulWidget {
  final List<Video>? preloadedVideos;

  const HomeScreen({super.key, this.preloadedVideos});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTabIndex = 0; // 默认选中首页
  DateTime? _lastBackPressed;
  DateTime? _backFromSearchHandled; // 防止搜索键盘返回键重复处理

  // Tab 顺序: 首页、动态、关注、历史、直播、登录、搜索
  final List<String> _tabIcons = [
    'assets/icons/home.svg',
    'assets/icons/dynamic.svg',
    'assets/icons/favorite.svg',
    'assets/icons/history.svg',
    'assets/icons/live.svg',
    'assets/icons/user.svg',
    'assets/icons/search.svg',
  ];

  late List<FocusNode> _sideBarFocusNodes;

  // 用于访问 SearchTab 状态
  final GlobalKey<SearchTabState> _searchTabKey = GlobalKey<SearchTabState>();
  // 用于访问 HomeTab 状态 (刷新功能)
  final GlobalKey<HomeTabState> _homeTabKey = GlobalKey<HomeTabState>();
  // 动态和历史记录 Tab - 每次切换时刷新
  final GlobalKey<DynamicTabState> _dynamicTabKey =
      GlobalKey<DynamicTabState>();
  final GlobalKey<FollowingTabState> _followingTabKey =
      GlobalKey<FollowingTabState>();
  final GlobalKey<HistoryTabState> _historyTabKey =
      GlobalKey<HistoryTabState>();
  final GlobalKey<LoginTabState> _loginTabKey = GlobalKey<LoginTabState>();
  // 直播 Tab
  final GlobalKey<LiveTabState> _liveTabKey = GlobalKey<LiveTabState>();

  @override
  void initState() {
    super.initState();
    _sideBarFocusNodes = List.generate(
      _tabIcons.length,
      (index) => FocusNode(),
    );

    // 可以在这里做一些初始化，但不再强制请求 sidebar 焦点
    // 而是等待 HomeTab 加载完成后请求内容焦点
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 确保 Highlight 策略正确
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    });
  }

  // 激活焦点系统
  void _activateFocusSystem() {
    if (!mounted) return;

    // 强制设置高亮策略为传统模式 (TV 模式)
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    final currentFocusNode = _sideBarFocusNodes[_selectedTabIndex];
    if (!currentFocusNode.hasFocus) {
      currentFocusNode.requestFocus();
    }

    // 首页加载完成后，延迟后台预加载动态和历史记录
    _preloadOtherTabs();
  }

  // 不再预加载其他 Tab，各 Tab 首次可见时自行加载
  // TV 内存有限，避免启动时同时加载所有页面的数据和图片
  void _preloadOtherTabs() {
    // 空实现：各 Tab 通过 _hasLoaded + didUpdateWidget 在首次切换时自行加载
  }

  @override
  void dispose() {
    for (var node in _sideBarFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleSideBarTap(int index) {
    // 如果已经在当前标签，点击刷新
    if (index == _selectedTabIndex) {
      if (index == 0) {
        _homeTabKey.currentState?.refreshCurrentCategory();
      } else if (index == 1) {
        _dynamicTabKey.currentState?.refresh();
      } else if (index == 2) {
        _followingTabKey.currentState?.refresh();
      } else if (index == 3) {
        _historyTabKey.currentState?.refresh();
      } else if (index == 4) {
        _liveTabKey.currentState?.refresh();
      }
      return;
    }

    setState(() => _selectedTabIndex = index);
    _sideBarFocusNodes[index].requestFocus();
    // 切换到不同标签时不刷新，只显示缓存内容
    // 首次加载由各 Tab 的 didUpdateWidget + _hasLoaded 或 _preloadOtherTabs 负责
  }

  void _handleLoginSuccess() {
    // 刷新侧边栏用户头像和登录态相关展示
    setState(() {});

    // 登录成功后主动拉取依赖登录态的页面，避免首次进入仍停留旧状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !AuthService.isLoggedIn) return;
      _dynamicTabKey.currentState?.refresh();
      _followingTabKey.currentState?.refresh();
      _historyTabKey.currentState?.refresh();
    });
  }

  bool _isSidebarFocused() {
    for (final node in _sideBarFocusNodes) {
      if (node.hasFocus) return true;
    }
    return false;
  }

  void _focusSelectedSidebarItem() {
    final index = _selectedTabIndex.clamp(0, _sideBarFocusNodes.length - 1);
    _sideBarFocusNodes[index].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 检查是否刚刚被搜索键盘的返回键处理过
        if (_backFromSearchHandled != null &&
            DateTime.now().difference(_backFromSearchHandled!) <
                const Duration(milliseconds: 200)) {
          return; // 已被处理，忽略
        }

        // 侧边栏按返回键：任意导航项都支持双击退出
        if (_isSidebarFocused()) {
          final now = DateTime.now();
          if (_lastBackPressed == null ||
              now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
            _lastBackPressed = now;
            Fluttertoast.showToast(
              msg: '再按一次返回键退出应用',
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.CENTER,
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              textColor: Colors.white,
              fontSize: 18.0,
            );
          } else {
            SystemNavigator.pop();
          }
          return;
        }

        // 搜索标签特殊处理：优先交给搜索页内部处理
        if (_selectedTabIndex == 6) {
          final handled = _searchTabKey.currentState?.handleBack() ?? false;
          if (!handled) {
            // 搜索页内容区 -> 回到搜索对应侧边栏
            _focusSelectedSidebarItem();
          }
          return;
        }

        // 其他页面：内容区按返回 -> 回当前页面对应的侧边栏
        _focusSelectedSidebarItem();
      },
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧边栏
            Expanded(
              flex: 5,
              child: Container(
                color: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.only(top: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(_tabIcons.length, (index) {
                    final isUserTab = index == 5; // User tab is now at index 5
                    final avatarUrl = isUserTab && AuthService.isLoggedIn
                        ? AuthService.face
                        : null;

                    return TvFocusableItem(
                      iconPath: _tabIcons[index],
                      avatarUrl: avatarUrl,
                      isSelected: _selectedTabIndex == index,
                      focusNode: _sideBarFocusNodes[index],
                      onFocus: () {
                        // 焦点移动时只切换标签页，不刷新任何内容
                        setState(() => _selectedTabIndex = index);
                      },
                      onTap: () => _handleSideBarTap(index), // 按确定键才刷新
                      onMoveUp: () {
                        final target = index > 0 ? index - 1 : 0;
                        _sideBarFocusNodes[target].requestFocus();
                      },
                      onMoveDown: () {
                        final target = index < _tabIcons.length - 1
                            ? index + 1
                            : _tabIcons.length - 1;
                        _sideBarFocusNodes[target].requestFocus();
                      },
                      // 用户标签按右键导航到设置分类标签
                      onMoveRight: index == 2
                          ? () =>
                                _followingTabKey.currentState
                                    ?.focusSelectedTopTab()
                          : index == 4
                          ? () {
                              _liveTabKey.currentState?.focusFirstItem();
                            }
                          : isUserTab && AuthService.isLoggedIn
                          ? () =>
                                _loginTabKey.currentState?.focusFirstCategory()
                          : null,
                    );
                  }),
                ),
              ),
            ),
            // 右侧内容区
            Expanded(flex: 95, child: _buildRightContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildRightContent() {
    // 使用 IndexedStack 保持所有 Tab 状态，避免切换时重新加载
    return IndexedStack(
      index: _selectedTabIndex,
      children: [
        // 0: 首页
        HomeTab(
          key: _homeTabKey,
          sidebarFocusNode: _sideBarFocusNodes[0],
          onFirstLoadComplete: _activateFocusSystem,
          preloadedVideos: widget.preloadedVideos,
        ),
        // 1: 动态
        DynamicTab(
          key: _dynamicTabKey,
          sidebarFocusNode: _sideBarFocusNodes[1],
          isVisible: _selectedTabIndex == 1,
        ),
        // 2: 关注
        FollowingTab(
          key: _followingTabKey,
          sidebarFocusNode: _sideBarFocusNodes[2],
          isVisible: _selectedTabIndex == 2,
        ),
        // 3: 历史
        HistoryTab(
          key: _historyTabKey,
          sidebarFocusNode: _sideBarFocusNodes[3],
          isVisible: _selectedTabIndex == 3,
        ),
        // 4: 直播
        LiveTab(
          key: _liveTabKey,
          sidebarFocusNode: _sideBarFocusNodes[4],
          isVisible: _selectedTabIndex == 4,
        ),
        // 5: 登录/用户
        LoginTab(
          key: _loginTabKey,
          sidebarFocusNode: _sideBarFocusNodes[5],
          onLoginSuccess: _handleLoginSuccess,
        ),
        // 6: 搜索
        SearchTab(
          key: _searchTabKey,
          sidebarFocusNode: _sideBarFocusNodes[6],
          onBackToHome: () {
            _backFromSearchHandled = DateTime.now(); // 记录处理时间
            // 搜索内部返回：不跳主页，只回搜索对应侧边栏
            _focusSelectedSidebarItem();
          },
        ),
      ],
    );
  }
}
