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
import '../services/network_check_service.dart';
import '../config/app_style.dart';

/// 主页框架
/// Tab 顺序: 首页(0)、动态(1)、关注(2)、历史(3)、直播(4)、我(5)、搜索(6)、设置(7)
class HomeScreen extends StatefulWidget {
  final List<Video>? preloadedVideos;
  final String? autoConfigMessage;

  const HomeScreen({super.key, this.preloadedVideos, this.autoConfigMessage});

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

      // 如果需要切换到首页的特定分类（如热门），在首次加载完成后执行
      if (_pendingHomeCategory != null && _selectedTabIndex == 0) {
        _switchHomeCategory(_pendingHomeCategory!);
        _pendingHomeCategory = null;
      }

      if (widget.autoConfigMessage != null) {
        // 首次安装：用独立 OverlayEntry 展示，不走 ToastUtils，避免被刷新等 Toast 覆盖
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _showAutoConfigBanner(widget.autoConfigMessage!);
        });
        Future.delayed(const Duration(milliseconds: 6000), () {
          if (mounted) UpdateService.autoCheckAndNotify(context);
        });
      } else {
        UpdateService.autoCheckAndNotify(context);
      }

      _runNetworkCheck();
    });
  }

  // ── 网络可达性检测 ──────────────────────────────────────

  OverlayEntry? _networkWarningEntry;

  Future<void> _runNetworkCheck() async {
    final ok = await NetworkCheckService.check();
    if (ok || !mounted) return;

    _showNetworkWarning();

    NetworkCheckService.startRetrying(onRestored: () {
      if (!mounted) return;
      _dismissNetworkWarning();
      ToastUtils.show(context, '网络已恢复');
    });
  }

  void _showNetworkWarning() {
    _dismissNetworkWarning();
    final overlay = Overlay.of(context);
    _networkWarningEntry = OverlayEntry(
      builder: (context) => _NetworkWarningBanner(
        onDismiss: _dismissNetworkWarning,
      ),
    );
    overlay.insert(_networkWarningEntry!);
  }

  void _dismissNetworkWarning() {
    try {
      _networkWarningEntry?.remove();
    } catch (_) {}
    _networkWarningEntry = null;
  }

  /// 独立 OverlayEntry 展示自动配置提示，不走 ToastUtils，不会被其他 Toast 覆盖
  void _showAutoConfigBanner(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AutoConfigBanner(
        message: message,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
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
    NetworkCheckService.stopRetrying();
    _dismissNetworkWarning();
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

    _switchToTab(index);
  }

  void _switchToTab(int index) {
    if (index == _selectedTabIndex) return;
    final previous = _selectedTabIndex;
    setState(() {
      _visitedTabs.add(index);
      _selectedTabIndex = index;
      if (!SettingsService.keepTabPagesAlive) {
        _visitedTabs.remove(previous);
      }
    });
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
  ///
  /// 确认键切页模式：右键始终进入当前选中（可见）tab 的内容区，
  /// 与 YouTube 等主流 TV App 行为一致。
  /// 聚焦即切页模式：焦点移动即切换 tab，右键进入当前聚焦 tab 的内容。
  VoidCallback? _getMoveRightHandler(int index) {
    final targetTab =
        SettingsService.focusSwitchTab ? index : _selectedTabIndex;
    return _getTabContentEntryHandler(targetTab);
  }

  /// 根据 tab 索引返回进入该 tab 内容区的回调
  VoidCallback? _getTabContentEntryHandler(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return () => _homeTabKey.currentState?.focusSelectedCategoryTab();
      case 1:
        return () => _dynamicTabKey.currentState?.focusFirstItem();
      case 2:
        return () => _followingTabKey.currentState?.focusSelectedTopTab();
      case 3:
        return () => _historyTabKey.currentState?.focusFirstItem();
      case 4:
        return () => _liveTabKey.currentState?.focusFirstItem();
      case 5:
        return () => _loginTabKey.currentState?.focusFirstItem();
      case 6:
        return () => _searchTabKey.currentState?.focusDefaultEntry();
      case 7:
        return () => _settingsKey.currentState?.focusFirstCategory();
      default:
        return null;
    }
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
          case 1:
            handled = _dynamicTabKey.currentState?.handleBack() ?? false;
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
                    color: AppColors.sidebarBackground,
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
                            isFirst: index == 0,
                            isLast: index == _mainTabIcons.length - 1,
                            onFocus: () {
                              // 聚焦即切换：移动焦点立刻切换内容
                              // 普通模式：只高亮图标，不切换内容
                              if (SettingsService.focusSwitchTab) {
                                _switchToTab(index);
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
                Container(
                  width: 1,
                  color: AppColors.dividerLight,
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

/// 首次安装自动配置提示横幅，5 秒后自动淡出，独立于 ToastUtils
class _AutoConfigBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _AutoConfigBanner({required this.message, required this.onDismiss});

  @override
  State<_AutoConfigBanner> createState() => _AutoConfigBannerState();
}

class _AutoConfigBannerState extends State<_AutoConfigBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _opacity;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 5000), () {
      if (mounted && !_dismissed) {
        _dismissed = true;
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    if (!_dismissed) {
      _dismissed = true;
      try { widget.onDismiss(); } catch (_) {}
    }
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = screenWidth * 0.05;
    return Positioned(
      top: 40,
      left: sidebarWidth,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: SettingsService.themeColor.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppFonts.sizeMD,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 网络不可达警告横幅
///
/// 独立 OverlayEntry，不与 ToastUtils 冲突。
/// 15 秒后自动淡出；网络恢复时由外部调用 [onDismiss] 移除。
class _NetworkWarningBanner extends StatefulWidget {
  final VoidCallback onDismiss;

  const _NetworkWarningBanner({required this.onDismiss});

  @override
  State<_NetworkWarningBanner> createState() => _NetworkWarningBannerState();
}

class _NetworkWarningBannerState extends State<_NetworkWarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  bool _dismissed = false;

  static const _autoDismissDelay = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    Future.delayed(_autoDismissDelay, () {
      if (mounted && !_dismissed) {
        _dismissed = true;
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    if (!_dismissed) {
      _dismissed = true;
      try { widget.onDismiss(); } catch (_) {}
    }
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = screenWidth * 0.05;
    return Positioned(
      top: 40,
      left: sidebarWidth,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _curve,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xDD8B6914),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      '无法连接 B 站服务器，请检查网络或 DNS 设置',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppFonts.sizeMD,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
