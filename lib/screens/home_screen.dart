import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';
import 'package:bili_tv_app/models/video.dart';
import 'home/home_tab.dart';
import 'home/history_tab.dart';
import 'home/search_tab.dart';
import 'home/login_tab.dart';
import 'home/dynamic_tab.dart';
import 'home/following_tab.dart';
import 'home/live_tab.dart';
import 'home/settings/settings_view.dart';
import 'home/settings/widgets/value_picker_popup.dart';
import '../widgets/tv_focusable_item.dart';
import '../widgets/time_display.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../services/settings_service.dart';
import '../config/app_style.dart';

/// 主页框架
/// Tab 顺序: 首页(0)、动态(1)、关注(2)、历史(3)、直播(4)、我(5)、搜索(6)、设置(7)
class HomeScreen extends StatefulWidget {
  final List<Video>? preloadedVideos;

  const HomeScreen({super.key, this.preloadedVideos});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _selectedTabIndex; // 根据设置初始化
  late Set<int> _visitedTabs; // 已访问过的 tab
  DateTime? _lastBackPressed;
  DateTime? _backFromSearchHandled; // 防止搜索键盘返回键重复处理
  String? _pendingHomeCategory; // 待切换的首页分类（如热门）

  // 主导航区图标 (0~7)，设置图标移到搜索后面
  static const List<String> _mainTabIcons = [
    'assets/icons/home.svg', // 0: 首页
    'assets/icons/dynamic.svg', // 1: 动态
    'assets/icons/favorite.svg', // 2: 关注
    'assets/icons/history.svg', // 3: 历史
    'assets/icons/live.svg', // 4: 直播
    'assets/icons/user.svg', // 5: 我
    'assets/icons/search.svg', // 6: 搜索
    'assets/icons/settings.svg', // 7: 设置
  ];

  static const int _totalTabs = 8; // 0~7

  late List<FocusNode> _sideBarFocusNodes;

  // 用于访问各 Tab 状态
  final GlobalKey<SearchTabState> _searchTabKey = GlobalKey<SearchTabState>();
  final GlobalKey<HomeTabState> _homeTabKey = GlobalKey<HomeTabState>();
  final GlobalKey<DynamicTabState> _dynamicTabKey =
      GlobalKey<DynamicTabState>();
  final GlobalKey<FollowingTabState> _followingTabKey =
      GlobalKey<FollowingTabState>();
  final GlobalKey<HistoryTabState> _historyTabKey =
      GlobalKey<HistoryTabState>();
  final GlobalKey<LoginTabState> _loginTabKey = GlobalKey<LoginTabState>();
  final GlobalKey<LiveTabState> _liveTabKey = GlobalKey<LiveTabState>();
  final GlobalKey<SettingsViewState> _settingsKey =
      GlobalKey<SettingsViewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sideBarFocusNodes = List.generate(_totalTabs, (index) => FocusNode());

    // 根据默认启动页面设置初始化
    final startPage = SettingsService.defaultStartPage;
    final initResult = _getInitialTabIndex(startPage);
    _selectedTabIndex = initResult.tabIndex;
    _pendingHomeCategory = initResult.homeCategory;
    _visitedTabs = {_selectedTabIndex};
    // 首页(0)始终需要被构建，因为可能需要切换到热门等分类
    if (_selectedTabIndex != 0 &&
        (startPage == 'recommend' || startPage == 'popular')) {
      _visitedTabs.add(0);
    }

    // 时间显示设置变更时刷新界面
    SettingsService.onShowTimeDisplayChanged = () {
      if (mounted) setState(() {});
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      // 自动检查更新（根据用户设置的间隔）
      UpdateService.autoCheckAndNotify(context);

      // 如果需要切换到首页的特定分类（如热门），在首次加载完成后执行
      if (_pendingHomeCategory != null && _selectedTabIndex == 0) {
        _switchHomeCategory(_pendingHomeCategory!);
        _pendingHomeCategory = null;
      }
    });
  }

  /// 根据启动页面设置获取初始 tab 索引
  /// 返回 (tabIndex, homeCategory) - homeCategory 用于首页内的分类切换
  ({int tabIndex, String? homeCategory}) _getInitialTabIndex(String startPage) {
    switch (startPage) {
      case 'recommend':
        // 检查推荐分类是否启用
        if (SettingsService.isCategoryEnabled('recommend')) {
          return (tabIndex: 0, homeCategory: null);
        }
        // 推荐未启用，使用首页第一个分类
        return (tabIndex: 0, homeCategory: null);
      case 'popular':
        // 检查热门分类是否启用
        if (SettingsService.isCategoryEnabled('popular')) {
          return (tabIndex: 0, homeCategory: 'popular');
        }
        // 热门未启用，使用首页第一个分类
        return (tabIndex: 0, homeCategory: null);
      case 'dynamic':
        return (tabIndex: 1, homeCategory: null); // 动态
      case 'history':
        return (tabIndex: 3, homeCategory: null); // 历史
      case 'live':
        return (tabIndex: 4, homeCategory: null); // 直播
      default:
        return (tabIndex: 0, homeCategory: null);
    }
  }

  /// 切换首页到指定分类
  void _switchHomeCategory(String categoryName) {
    final success = _homeTabKey.currentState?.switchToCategoryByName(
      categoryName,
    );
    if (success != true) {
      // 分类不存在或切换失败，不做任何操作
      debugPrint('⚠️ Failed to switch to category: $categoryName');
    }
  }

  // 激活焦点系统
  void _activateFocusSystem() {
    if (!mounted) return;

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    // 如果有待切换的首页分类，先执行切换
    if (_pendingHomeCategory != null && _selectedTabIndex == 0) {
      _switchHomeCategory(_pendingHomeCategory!);
      _pendingHomeCategory = null;
    }

    final currentFocusNode = _sideBarFocusNodes[_selectedTabIndex];
    if (!currentFocusNode.hasFocus) {
      currentFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (var node in _sideBarFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // 系统内存不足时主动释放图片缓存
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint('⚠️ [Memory] System memory pressure — image cache cleared');
    if (mounted) {
      ToastUtils.show(
        context,
        '系统内存不足，已释放图片缓存',
        duration: const Duration(seconds: 2),
      );
    }
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

    // 普通模式 / 聚焦即切换模式 均通过确认键切换 tab
    _visitedTabs.add(index);
    setState(() => _selectedTabIndex = index);
  }

  void _handleLoginSuccess() {
    setState(() {});

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

  /// 循环导航：向上
  void _moveUp(int currentIndex) {
    if (currentIndex > 0) {
      _sideBarFocusNodes[currentIndex - 1].requestFocus();
    } else {
      // 从顶部(0)循环到底部(设置，index 7)
      _sideBarFocusNodes[_totalTabs - 1].requestFocus();
    }
  }

  /// 循环导航：向下
  void _moveDown(int currentIndex) {
    if (currentIndex < _totalTabs - 1) {
      _sideBarFocusNodes[currentIndex + 1].requestFocus();
    } else {
      // 从底部(设置)循环到顶部(首页)
      _sideBarFocusNodes[0].requestFocus();
    }
  }

  /// 获取向右导航回调
  VoidCallback? _getMoveRightHandler(int index) {
    // 首页：聚焦记忆的分类标签
    if (index == 0) {
      return () => _homeTabKey.currentState?.focusSelectedCategoryTab();
    }
    // 动态页：聚焦第一个视频卡片
    if (index == 1) {
      return () => _dynamicTabKey.currentState?.focusFirstItem();
    }
    // 关注页：聚焦记忆的顶部标签
    if (index == 2) {
      return () => _followingTabKey.currentState?.focusSelectedTopTab();
    }
    // 直播页：聚焦记忆的分类标签
    if (index == 4) {
      return () => _liveTabKey.currentState?.focusFirstItem();
    }
    // 历史页：聚焦第一个视频卡片
    if (index == 3) {
      return () => _historyTabKey.currentState?.focusFirstItem();
    }
    if (index == 5 && AuthService.isLoggedIn) {
      return null; // 个人资料页不需要特殊右键导航
    }
    // 搜索页：右键进入键盘区默认入口（保持原导航习惯）
    if (index == 6) {
      return () => _searchTabKey.currentState?.focusDefaultEntry();
    }
    // 设置页 (index 7)
    if (index == 7) {
      return () => _settingsKey.currentState?.focusFirstCategory();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_backFromSearchHandled != null &&
            DateTime.now().difference(_backFromSearchHandled!) <
                const Duration(milliseconds: 200)) {
          return;
        }

        // 优先处理全局弹窗（如设置弹窗）
        if (ValuePickerOverlay.close()) {
          return;
        }

        // 侧边栏按返回键：双击退出
        if (_isSidebarFocused()) {
          final now = DateTime.now();
          if (_lastBackPressed == null ||
              now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
            _lastBackPressed = now;
            ToastUtils.show(context, '再按一次返回键退出应用');
          } else {
            SystemNavigator.pop();
          }
          return;
        }

        // 搜索标签特殊处理
        if (_selectedTabIndex == 6) {
          final handled = _searchTabKey.currentState?.handleBack() ?? false;
          if (!handled) {
            _focusSelectedSidebarItem();
          }
          return;
        }

        // 其他页面：内容区按返回 -> 先返回顶部 Tab，再返回侧边栏
        bool handled = false;
        switch (_selectedTabIndex) {
          case 0:
            handled = _homeTabKey.currentState?.handleBack() ?? false;
            break;
          case 2:
            handled = _followingTabKey.currentState?.handleBack() ?? false;
            break;
          case 4:
            handled = _liveTabKey.currentState?.handleBack() ?? false;
            break;
          case 7:
            handled = _settingsKey.currentState?.handleBack() ?? false;
            break;
        }
        if (!handled) {
          _focusSelectedSidebarItem();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧边栏
                Expanded(
                  flex: 5,
                  child: Container(
                    color: const Color(0xFF1E1E1E),
                    child: Column(
                      children: [
                        // 上部区域微调，让首页图标与推荐标签行平齐
                        const SizedBox(height: 2),
                        // 主导航图标 (0~7)，设置按钮已移到搜索后面
                        ...List.generate(_mainTabIcons.length, (index) {
                          final isUserTab = index == 5;
                          final avatarUrl = isUserTab && AuthService.isLoggedIn
                              ? AuthService.face
                              : null;

                          return TvFocusableItem(
                            iconPath: _mainTabIcons[index],
                            avatarUrl: avatarUrl,
                            isSelected: _selectedTabIndex == index,
                            focusNode: _sideBarFocusNodes[index],
                            onFocus: () {
                              // 聚焦即切换：移动焦点立刻切换内容
                              // 普通模式：只高亮图标，不切换内容
                              if (SettingsService.focusSwitchTab) {
                                _visitedTabs.add(index);
                                setState(() => _selectedTabIndex = index);
                              }
                            },
                            onTap: () => _handleSideBarTap(index),
                            onMoveLeft: () {}, // 侧边栏最左侧，阻止左键导航
                            onMoveUp: () => _moveUp(index),
                            onMoveDown: () => _moveDown(index),
                            onMoveRight: _getMoveRightHandler(index),
                          );
                        }),
                        const Spacer(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                // 右侧内容区
                Expanded(flex: 95, child: _buildRightContent()),
              ],
            ),
            // 全局时间显示（右上角）
            if (SettingsService.showTimeDisplay)
              const Positioned(
                top: TabStyle.timeDisplayTop,
                right: TabStyle.timeDisplayRight,
                child: TimeDisplay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightContent() {
    // 懒构建：未访问过的 tab 用占位符代替，避免一次性构建全部 widget 树
    Widget _lazyTab(int index, Widget Function() builder) {
      return _visitedTabs.contains(index) ? builder() : const SizedBox.shrink();
    }

    return IndexedStack(
      index: _selectedTabIndex,
      children: [
        // 0: 首页（始终构建）
        HomeTab(
          key: _homeTabKey,
          sidebarFocusNode: _sideBarFocusNodes[0],
          onFirstLoadComplete: _activateFocusSystem,
          preloadedVideos: widget.preloadedVideos,
        ),
        // 1: 动态
        _lazyTab(
          1,
          () => DynamicTab(
            key: _dynamicTabKey,
            sidebarFocusNode: _sideBarFocusNodes[1],
            isVisible: _selectedTabIndex == 1,
          ),
        ),
        // 2: 关注
        _lazyTab(
          2,
          () => FollowingTab(
            key: _followingTabKey,
            sidebarFocusNode: _sideBarFocusNodes[2],
            isVisible: _selectedTabIndex == 2,
          ),
        ),
        // 3: 历史
        _lazyTab(
          3,
          () => HistoryTab(
            key: _historyTabKey,
            sidebarFocusNode: _sideBarFocusNodes[3],
            isVisible: _selectedTabIndex == 3,
          ),
        ),
        // 4: 直播
        _lazyTab(
          4,
          () => LiveTab(
            key: _liveTabKey,
            sidebarFocusNode: _sideBarFocusNodes[4],
            isVisible: _selectedTabIndex == 4,
          ),
        ),
        // 5: 我 (登录/个人资料)
        _lazyTab(
          5,
          () => LoginTab(
            key: _loginTabKey,
            sidebarFocusNode: _sideBarFocusNodes[5],
            onLoginSuccess: _handleLoginSuccess,
          ),
        ),
        // 6: 搜索
        _lazyTab(
          6,
          () => SearchTab(
            key: _searchTabKey,
            sidebarFocusNode: _sideBarFocusNodes[6],
            onBackToHome: () {
              _backFromSearchHandled = DateTime.now();
              _focusSelectedSidebarItem();
            },
          ),
        ),
        // 7: 设置
        _lazyTab(
          7,
          () => SettingsView(
            key: _settingsKey,
            sidebarFocusNode: _sideBarFocusNodes[7],
          ),
        ),
      ],
    );
  }
}
