import 'dart:async';
import 'dart:io';
import 'dart:ui';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedTabIndex = 0; // 默认选中首页
  final Set<int> _visitedTabs = {0}; // 已访问过的 tab（首页始终构建）
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
  String _cpuUsage = '';
  int _prevProcessJiffies = 0;
  DateTime? _prevCpuSampleTime;

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
    _sideBarFocusNodes = List.generate(
      _totalTabs,
      (index) => FocusNode(),
    );

    _showMemoryInfo = SettingsService.showMemoryInfo;
    if (_showMemoryInfo) _startMemoryMonitor();
    SettingsService.onShowMemoryInfoChanged = _syncMemorySetting;

    // 根据低内存模式配置图片缓存
    _applyImageCacheConfig();
    SettingsService.onHighPerformanceModeChanged = _applyImageCacheConfig;

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
        _cpuUsage = '';
      });
      _prevProcessJiffies = 0;
      _prevCpuSampleTime = null;
    }
  }

  void _applyImageCacheConfig() {
    PaintingBinding.instance.imageCache.maximumSize =
        SettingsService.imageCacheMaxSize;
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        SettingsService.imageCacheMaxBytes;
    // 切换模式时清理超出限制的缓存
    PaintingBinding.instance.imageCache.clear();
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

      // CPU 占用: 从 /proc/self/stat 读取 utime + stime（单位为 jiffies）
      String cpuStr = _cpuUsage;
      try {
        final stat = File('/proc/self/stat').readAsStringSync();
        // comm 字段可能含空格，安全解析：找到最后一个 ')' 后再 split
        final closeParen = stat.lastIndexOf(')');
        final fields = stat.substring(closeParen + 2).split(' ');
        // fields[11] = utime, fields[12] = stime（从 state 字段后第 0 位开始）
        final utime = int.tryParse(fields[11]) ?? 0;
        final stime = int.tryParse(fields[12]) ?? 0;
        final currentJiffies = utime + stime;

        final now = DateTime.now();
        if (_prevCpuSampleTime != null && _prevProcessJiffies > 0) {
          final elapsedMs = now.difference(_prevCpuSampleTime!).inMilliseconds;
          if (elapsedMs > 0) {
            final deltaJiffies = currentJiffies - _prevProcessJiffies;
            // 每个 jiffy = 1/100 秒（CLK_TCK = 100）
            final cpuSeconds = deltaJiffies / 100;
            final elapsedSeconds = elapsedMs / 1000;
            final cpuPercent = (cpuSeconds / elapsedSeconds * 100);
            cpuStr = '${cpuPercent.toStringAsFixed(0)}%';
          }
        }
        _prevProcessJiffies = currentJiffies;
        _prevCpuSampleTime = now;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _appMem = '占${appMb}M';
          _availMem = '余${availMb}M';
          _totalMem = '共${totalMb}M';
          _cpuUsage = cpuStr;
        });
      }
    } catch (_) {
      // 非 Linux 系统忽略
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.onShowMemoryInfoChanged = null;
    SettingsService.onHighPerformanceModeChanged = null;
    _memoryTimer?.cancel();
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
      Fluttertoast.showToast(
        msg: '系统内存不足，已释放图片缓存',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.TOP,
        backgroundColor: Colors.orange.shade800,
        textColor: Colors.white,
        fontSize: 14,
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

    // 切换 tab 时同步内存显示设置
    _syncMemorySetting();

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
                    // 弹性间距，把设置推到底部
                    const Spacer(),
                    // 实时内存信息（右对齐，需在设置中开启）
                    if (_showMemoryInfo && _appMem.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          [
                            if (_cpuUsage.isNotEmpty) 'CPU$_cpuUsage',
                            _appMem,
                            _availMem,
                            _totalMem,
                          ].join('\n'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontFamily: 'monospace',
                            fontFeatures: [FontFeature.tabularFigures()],
                            height: 1.5,
                          ),
                        ),
                      ),
                    // 设置图标 (底部, index 7)
                    TvFocusableItem(
                      iconPath: _settingsIcon,
                      isSelected: _selectedTabIndex == _settingsIndex,
                      focusNode: _sideBarFocusNodes[_settingsIndex],
                      onFocus: () {
                        if (SettingsService.focusSwitchTab) {
                          _visitedTabs.add(_settingsIndex);
                          setState(() => _selectedTabIndex = _settingsIndex);
                        }
                      },
                      onTap: () => _handleSideBarTap(_settingsIndex),
                      onMoveLeft: () {}, // 侧边栏最左侧，阻止左键导航
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
        _lazyTab(1, () => DynamicTab(
          key: _dynamicTabKey,
          sidebarFocusNode: _sideBarFocusNodes[1],
          isVisible: _selectedTabIndex == 1,
        )),
        // 2: 关注
        _lazyTab(2, () => FollowingTab(
          key: _followingTabKey,
          sidebarFocusNode: _sideBarFocusNodes[2],
          isVisible: _selectedTabIndex == 2,
        )),
        // 3: 历史
        _lazyTab(3, () => HistoryTab(
          key: _historyTabKey,
          sidebarFocusNode: _sideBarFocusNodes[3],
          isVisible: _selectedTabIndex == 3,
        )),
        // 4: 直播
        _lazyTab(4, () => LiveTab(
          key: _liveTabKey,
          sidebarFocusNode: _sideBarFocusNodes[4],
          isVisible: _selectedTabIndex == 4,
        )),
        // 5: 我 (登录/个人资料)
        _lazyTab(5, () => LoginTab(
          key: _loginTabKey,
          sidebarFocusNode: _sideBarFocusNodes[5],
          onLoginSuccess: _handleLoginSuccess,
        )),
        // 6: 搜索
        _lazyTab(6, () => SearchTab(
          key: _searchTabKey,
          sidebarFocusNode: _sideBarFocusNodes[6],
          onBackToHome: () {
            _backFromSearchHandled = DateTime.now();
            _focusSelectedSidebarItem();
          },
        )),
        // 7: 设置
        _lazyTab(7, () => SettingsView(
          key: _settingsKey,
          sidebarFocusNode: _sideBarFocusNodes[_settingsIndex],
        )),
      ],
    );
  }
}
