import 'dart:async';
import 'dart:io';
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
import 'home/settings/settings_view.dart';
import '../widgets/tv_focusable_item.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../services/settings_service.dart';

/// 主页框架
/// Tab 顺序: 首页(0)、动态(1)、关注(2)、历史(3)、直播(4)、我(5)、搜索(6)、设置(7)
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

  // 主导航区图标 (0~6)
  static const List<String> _mainTabIcons = [
    'assets/icons/home.svg',     // 0: 首页
    'assets/icons/dynamic.svg',  // 1: 动态
    'assets/icons/favorite.svg', // 2: 关注
    'assets/icons/history.svg',  // 3: 历史
    'assets/icons/live.svg',     // 4: 直播
    'assets/icons/user.svg',     // 5: 我
    'assets/icons/search.svg',   // 6: 搜索
  ];

  // 设置图标 (底部，index 7)
  static const String _settingsIcon = 'assets/icons/settings.svg';

  static const int _totalTabs = 8; // 0~7
  static const int _settingsIndex = 7;

  late List<FocusNode> _sideBarFocusNodes;
  Timer? _memoryTimer;
  bool _showMemoryInfo = false;
  String _appMem = '';
  String _availMem = '';
  String _totalMem = '';

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
    _sideBarFocusNodes = List.generate(
      _totalTabs,
      (index) => FocusNode(),
    );

    _showMemoryInfo = SettingsService.showMemoryInfo;
    if (_showMemoryInfo) _startMemoryMonitor();
    SettingsService.onShowMemoryInfoChanged = _syncMemorySetting;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      // 自动检查更新（根据用户设置的间隔）
      UpdateService.autoCheckAndNotify(context);
    });
  }

  // 激活焦点系统
  void _activateFocusSystem() {
    if (!mounted) return;

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    final currentFocusNode = _sideBarFocusNodes[_selectedTabIndex];
    if (!currentFocusNode.hasFocus) {
      currentFocusNode.requestFocus();
    }
  }

  void _syncMemorySetting() {
    final enabled = SettingsService.showMemoryInfo;
    if (enabled == _showMemoryInfo) return;
    _showMemoryInfo = enabled;
    if (enabled) {
      _startMemoryMonitor();
    } else {
      _memoryTimer?.cancel();
      _memoryTimer = null;
      setState(() {
        _appMem = '';
        _availMem = '';
        _totalMem = '';
      });
    }
  }

  void _startMemoryMonitor() {
    _updateMemory();
    _memoryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateMemory(),
    );
  }

  void _updateMemory() {
    try {
      // App 占用: 从 /proc/self/statm 读取 RSS（第2个字段，单位为页）
      final statm = File('/proc/self/statm').readAsStringSync();
      final pages = int.tryParse(statm.split(' ')[1]) ?? 0;
      final appMb = (pages * 4096 / (1024 * 1024)).toStringAsFixed(0);

      // 系统总内存 / 可用内存: 从 /proc/meminfo 读取
      final meminfo = File('/proc/meminfo').readAsStringSync();
      final totalMatch = RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo);
      final availMatch = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(meminfo);
      final totalKb = int.tryParse(totalMatch?.group(1) ?? '') ?? 0;
      final availKb = int.tryParse(availMatch?.group(1) ?? '') ?? 0;
      final totalMb = (totalKb / 1024).toStringAsFixed(0);
      final availMb = (availKb / 1024).toStringAsFixed(0);

      if (mounted) {
        setState(() {
          _appMem = '${appMb}M';
          _availMem = '${availMb}M';
          _totalMem = '${totalMb}M';
        });
      }
    } catch (_) {
      // 非 Linux 系统忽略
    }
  }

  @override
  void dispose() {
    SettingsService.onShowMemoryInfoChanged = null;
    _memoryTimer?.cancel();
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

    // 切换 tab 时同步内存显示设置
    _syncMemorySetting();

    // 普通模式 / 聚焦即切换模式 均通过确认键切换 tab
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
      // 从顶部(0)循环到底部(设置)
      _sideBarFocusNodes[_settingsIndex].requestFocus();
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
    if (index == 2) {
      return () =>
          _followingTabKey.currentState?.focusSelectedTopTab();
    }
    if (index == 4) {
      return () => _liveTabKey.currentState?.focusFirstItem();
    }
    if (index == 5 && AuthService.isLoggedIn) {
      return null; // 个人资料页不需要特殊右键导航
    }
    if (index == _settingsIndex) {
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

        // 侧边栏按返回键：双击退出
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

        // 搜索标签特殊处理
        if (_selectedTabIndex == 6) {
          final handled = _searchTabKey.currentState?.handleBack() ?? false;
          if (!handled) {
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
                child: Column(
                  children: [
                    // 上部区域微调，让首页图标与推荐标签行平齐
                    const SizedBox(height: 2),
                    // 主导航图标 (0~6)
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
                          _syncMemorySetting();
                          // 聚焦即切换：移动焦点立刻切换内容
                          // 普通模式：只高亮图标，不切换内容
                          if (SettingsService.focusSwitchTab) {
                            setState(() => _selectedTabIndex = index);
                          }
                        },
                        onTap: () => _handleSideBarTap(index),
                        onMoveUp: () => _moveUp(index),
                        onMoveDown: () => _moveDown(index),
                        onMoveRight: _getMoveRightHandler(index),
                      );
                    }),
                    // 弹性间距，把设置推到底部
                    const Spacer(),
                    // 实时内存信息（右对齐，需在设置中开启）
                    if (_showMemoryInfo && _appMem.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, right: 6, left: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('占用 $_appMem',
                              style: const TextStyle(color: Colors.white38, fontSize: 9)),
                            Text('可用 $_availMem',
                              style: const TextStyle(color: Colors.white38, fontSize: 9)),
                            Text('总共 $_totalMem',
                              style: const TextStyle(color: Colors.white24, fontSize: 9)),
                          ],
                        ),
                      ),
                    // 设置图标 (底部, index 7)
                    TvFocusableItem(
                      iconPath: _settingsIcon,
                      isSelected: _selectedTabIndex == _settingsIndex,
                      focusNode: _sideBarFocusNodes[_settingsIndex],
                      onFocus: () {
                        if (SettingsService.focusSwitchTab) {
                          setState(() => _selectedTabIndex = _settingsIndex);
                        }
                      },
                      onTap: () => _handleSideBarTap(_settingsIndex),
                      onMoveUp: () => _moveUp(_settingsIndex),
                      onMoveDown: () => _moveDown(_settingsIndex),
                      onMoveRight: _getMoveRightHandler(_settingsIndex),
                    ),
                    const SizedBox(height: 16),
                  ],
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
        // 5: 我 (登录/个人资料)
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
            _backFromSearchHandled = DateTime.now();
            _focusSelectedSidebarItem();
          },
        ),
        // 7: 设置
        SettingsView(
          key: _settingsKey,
          sidebarFocusNode: _sideBarFocusNodes[_settingsIndex],
        ),
      ],
    );
  }
}
