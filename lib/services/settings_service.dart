import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// 视频编解码器枚举
enum VideoCodec {
  auto('自动', ''),
  avc('H.264', 'avc'),
  hevc('H.265', 'hev'),
  av1('AV1', 'av01');

  final String label;
  final String prefix; // codecs 字段前缀
  const VideoCodec(this.label, this.prefix);
}

/// 自定义缓存管理器
class BiliCacheManager {
  static const key = 'biliTvCache';
  static CacheManager? _instance;
  static int _cachedMaxObjects = 0;

  static CacheManager get instance {
    final maxObjects = SettingsService.diskCacheMaxObjects;
    // 性能模式切换时重建 CacheManager
    if (_instance == null || _cachedMaxObjects != maxObjects) {
      _cachedMaxObjects = maxObjects;
      _instance = CacheManager(
        Config(
          key,
          stalePeriod: const Duration(days: 3),
          maxNrOfCacheObjects: maxObjects,
        ),
      );
    }
    return _instance!;
  }
}

/// 设置服务
class SettingsService {
  static const String _useHardwareDecodeKey = 'use_hardware_decode';
  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // 初始化完成后通知监听者
    onShowMemoryInfoChanged?.call();
  }

  /// 显示 Toast 提示
  static void toast(BuildContext? context, String msg) {
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      timeInSecForIosWeb: 2,
      backgroundColor: const Color(0xFF333333),
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  /// 获取图片缓存大小 (MB)
  static Future<double> getImageCacheSizeMB() async {
    double totalSize = 0;

    try {
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      totalSize += await _getDirectorySize(tempDir);

      // 获取应用缓存目录
      final cacheDir = await getApplicationCacheDirectory();
      if (cacheDir.path != tempDir.path) {
        totalSize += await _getDirectorySize(cacheDir);
      }
    } catch (e) {
      // 忽略错误
    }

    // 转换为 MB
    return totalSize / (1024 * 1024);
  }

  /// 计算目录大小
  static Future<double> _getDirectorySize(Directory dir) async {
    double size = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (e) {
      // 忽略权限错误等
    }
    return size;
  }

  /// 清除图片缓存 (不包含播放进度)
  static Future<void> clearImageCache() async {
    // 清除图片缓存
    await CachedNetworkImage.evictFromCache('');
    await BiliCacheManager.instance.emptyCache();
    await DefaultCacheManager().emptyCache();

    // 清除临时文件
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            // 忽略单个文件删除失败
          }
        }
      }
    } catch (e) {
      // 忽略错误
    }
  }

  /// 是否使用硬件解码
  static bool get useHardwareDecode {
    return _prefs?.getBool(_useHardwareDecodeKey) ?? true; // 默认硬解
  }

  /// 设置硬件解码
  static Future<void> setUseHardwareDecode(bool value) async {
    await init();
    await _prefs!.setBool(_useHardwareDecodeKey, value);
  }

  // 自动连播设置
  static const String _autoPlayKey = 'auto_play';

  /// 是否自动连播
  static bool get autoPlay {
    return _prefs?.getBool(_autoPlayKey) ?? false; // 默认关闭
  }

  /// 设置自动连播
  static Future<void> setAutoPlay(bool value) async {
    await init();
    await _prefs!.setBool(_autoPlayKey, value);
  }

  // 首选编解码器设置
  static const String _preferredCodecKey = 'preferred_codec';

  /// 获取首选编解码器
  static VideoCodec get preferredCodec {
    final index = _prefs?.getInt(_preferredCodecKey) ?? 0; // 默认自动 (index 0)
    return VideoCodec.values[index.clamp(0, VideoCodec.values.length - 1)];
  }

  /// 设置首选编解码器
  static Future<void> setPreferredCodec(VideoCodec codec) async {
    await init();
    await _prefs!.setInt(_preferredCodecKey, codec.index);
  }

  // 迷你进度条设置
  static const String _showMiniProgressKey = 'show_mini_progress';

  /// 是否显示迷你进度条
  static bool get showMiniProgress {
    return _prefs?.getBool(_showMiniProgressKey) ?? true; // 默认开启
  }

  /// 设置迷你进度条
  static Future<void> setShowMiniProgress(bool value) async {
    await init();
    await _prefs!.setBool(_showMiniProgressKey, value);
  }

  // 默认隐藏控制栏设置
  static const String _hideControlsOnStartKey = 'hide_controls_on_start';

  /// 是否默认隐藏控制栏
  static bool get hideControlsOnStart {
    // 兼容直播 (User request: hide live controls by default setting)
    return _prefs?.getBool(_hideControlsOnStartKey) ?? false;
  }

  // 直播: 默认隐藏控制栏设置
  static const String _hideLiveControlsOnStartKey =
      'hide_live_controls_on_start';
  static bool get hideLiveControlsOnStart {
    return _prefs?.getBool(_hideLiveControlsOnStartKey) ?? false;
  }

  static Future<void> setHideLiveControlsOnStart(bool value) async {
    await init();
    await _prefs!.setBool(_hideLiveControlsOnStartKey, value);
  }

  // 直播: 播放器右上角时间显示设置
  static const String _showLiveTimeDisplayKey = 'show_live_time_display';
  static bool get showLiveTimeDisplay {
    return _prefs?.getBool(_showLiveTimeDisplayKey) ?? false;
  }

  static Future<void> setShowLiveTimeDisplay(bool value) async {
    await init();
    await _prefs!.setBool(_showLiveTimeDisplayKey, value);
  }

  /// 设置默认隐藏控制栏
  static Future<void> setHideControlsOnStart(bool value) async {
    await init();
    await _prefs!.setBool(_hideControlsOnStartKey, value);
  }

  // 播放器右上角时间显示设置
  static const String _alwaysShowPlayerTimeKey = 'always_show_player_time';

  /// 是否在播放器右上角常驻显示时间
  static bool get alwaysShowPlayerTime {
    return _prefs?.getBool(_alwaysShowPlayerTimeKey) ?? true; // 默认开启
  }

  /// 设置是否在播放器右上角常驻显示时间
  static Future<void> setAlwaysShowPlayerTime(bool value) async {
    await init();
    await _prefs!.setBool(_alwaysShowPlayerTimeKey, value);
  }

  // 视频网格列数设置
  static const String _videoGridColumnsKey = 'video_grid_columns';

  /// 视频网格每行列数（3~6）
  static int get videoGridColumns {
    final raw = _prefs?.getInt(_videoGridColumnsKey) ?? 4;
    return raw.clamp(3, 6);
  }

  /// 设置视频网格每行列数（3~6）
  static Future<void> setVideoGridColumns(int value) async {
    await init();
    await _prefs!.setInt(_videoGridColumnsKey, value.clamp(3, 6));
  }

  // 分区顺序设置
  static const String _categoryOrderKey = 'home_category_order';

  // 默认分区顺序 (使用枚举名称字符串)
  static const List<String> _defaultCategoryOrder = [
    'recommend',
    'popular',
    'anime',
    'movie',
    'game',
    'knowledge',
    'tech',
    'music',
    'dance',
    'life',
    'food',
    'douga',
  ];

  /// 获取分区顺序
  static List<String> get categoryOrder {
    final saved = _prefs?.getStringList(_categoryOrderKey);
    if (saved != null && saved.isNotEmpty) {
      // 确保所有分区都在列表中 (防止新增分区丢失)
      final result = List<String>.from(saved);
      for (final cat in _defaultCategoryOrder) {
        if (!result.contains(cat)) {
          result.add(cat);
        }
      }
      return result;
    }
    return List<String>.from(_defaultCategoryOrder);
  }

  /// 设置分区顺序
  static Future<void> setCategoryOrder(List<String> order) async {
    await init();
    await _prefs!.setStringList(_categoryOrderKey, order);
  }

  // 分区启用设置
  static const String _enabledCategoriesKey = 'enabled_categories';

  /// 获取启用的分区 (默认全部启用)
  static Set<String> get enabledCategories {
    final saved = _prefs?.getStringList(_enabledCategoriesKey);
    if (saved != null) {
      return saved.toSet();
    }
    // 默认全部启用
    return _defaultCategoryOrder.toSet();
  }

  /// 设置启用的分区
  static Future<void> setEnabledCategories(Set<String> categories) async {
    await init();
    await _prefs!.setStringList(_enabledCategoriesKey, categories.toList());
  }

  /// 检查分区是否启用
  static bool isCategoryEnabled(String name) {
    return enabledCategories.contains(name);
  }

  /// 切换分区启用状态
  static Future<void> toggleCategory(String name, bool enabled) async {
    final current = enabledCategories;
    if (enabled) {
      current.add(name);
    } else {
      current.remove(name);
    }
    await setEnabledCategories(current);
  }

  // 快进预览模式设置
  static const String _seekPreviewModeKey = 'seek_preview_mode';

  /// 是否开启快进预览模式 (显示缩略图)
  static bool get seekPreviewMode {
    return _prefs?.getBool(_seekPreviewModeKey) ?? false; // 默认关闭
  }

  /// 设置快进预览模式
  static Future<void> setSeekPreviewMode(bool value) async {
    await init();
    await _prefs!.setBool(_seekPreviewModeKey, value);
  }

  // ==================== 弹幕全局默认设置 ====================
  // 使用与播放器相同的 SharedPreferences key，确保共享数据

  static const String _danmakuEnabledKey = 'danmaku_enabled';
  static const String _danmakuOpacityKey = 'danmaku_opacity';
  static const String _danmakuFontSizeKey = 'danmaku_font_size';
  static const String _danmakuAreaKey = 'danmaku_area';
  static const String _danmakuSpeedKey = 'danmaku_speed';
  static const String _hideTopDanmakuKey = 'hide_top_danmaku';
  static const String _hideBottomDanmakuKey = 'hide_bottom_danmaku';

  /// 弹幕开关 (默认开)
  static bool get danmakuEnabled => _prefs?.getBool(_danmakuEnabledKey) ?? true;
  static Future<void> setDanmakuEnabled(bool value) async {
    await init();
    await _prefs!.setBool(_danmakuEnabledKey, value);
  }

  /// 弹幕透明度 (0.1 ~ 1.0, 默认 0.6)
  static double get danmakuOpacity {
    return (_prefs?.getDouble(_danmakuOpacityKey) ?? 0.6).clamp(0.1, 1.0);
  }

  static Future<void> setDanmakuOpacity(double value) async {
    await init();
    await _prefs!.setDouble(_danmakuOpacityKey, value.clamp(0.1, 1.0));
  }

  /// 弹幕字体大小 (10 ~ 50, 默认 17)
  static double get danmakuFontSize {
    return (_prefs?.getDouble(_danmakuFontSizeKey) ?? 17.0).clamp(10.0, 50.0);
  }

  static Future<void> setDanmakuFontSize(double value) async {
    await init();
    await _prefs!.setDouble(_danmakuFontSizeKey, value.clamp(10.0, 50.0));
  }

  /// 弹幕占屏比 (默认 0.25 即 1/4)
  static const List<double> danmakuAreaOptions = [0.125, 0.25, 0.5, 0.75, 1.0];
  static const List<String> danmakuAreaLabels = [
    '1/8',
    '1/4',
    '1/2',
    '3/4',
    '全屏',
  ];
  static double get danmakuArea {
    final raw = _prefs?.getDouble(_danmakuAreaKey) ?? 0.25;
    // 找到最近的有效选项
    return danmakuAreaOptions.reduce(
      (a, b) => (a - raw).abs() < (b - raw).abs() ? a : b,
    );
  }

  static Future<void> setDanmakuArea(double value) async {
    await init();
    await _prefs!.setDouble(_danmakuAreaKey, value);
  }

  static String danmakuAreaLabel(double area) {
    final idx = danmakuAreaOptions.indexOf(area);
    return idx >= 0 ? danmakuAreaLabels[idx] : '${(area * 100).toInt()}%';
  }

  /// 弹幕速度 (4 ~ 20, 默认 10)
  static double get danmakuSpeed {
    return (_prefs?.getDouble(_danmakuSpeedKey) ?? 10.0).clamp(4.0, 20.0);
  }

  static Future<void> setDanmakuSpeed(double value) async {
    await init();
    await _prefs!.setDouble(_danmakuSpeedKey, value.clamp(4.0, 20.0));
  }

  /// 隐藏顶部悬停弹幕 (默认不隐藏)
  static bool get hideTopDanmaku =>
      _prefs?.getBool(_hideTopDanmakuKey) ?? false;
  static Future<void> setHideTopDanmaku(bool value) async {
    await init();
    await _prefs!.setBool(_hideTopDanmakuKey, value);
  }

  /// 隐藏底部悬停弹幕 (默认不隐藏)
  static bool get hideBottomDanmaku =>
      _prefs?.getBool(_hideBottomDanmakuKey) ?? false;
  static Future<void> setHideBottomDanmaku(bool value) async {
    await init();
    await _prefs!.setBool(_hideBottomDanmakuKey, value);
  }

  // ==================== 直播分区设置 ====================

  static const Map<String, String> liveCategoryLabels = {
    'online_games': '网游',
    'mobile_games': '手游',
    'console_games': '单机',
    'virtual': '虚拟主播',
    'entertainment': '娱乐',
    'radio': '电台',
    'match': '赛事',
    'chat': '聊天室',
    'lifestyle': '生活',
    'knowledge': '知识',
    'interactive': '互动玩法',
  };

  static const Map<String, int> liveCategoryIds = {
    'online_games': 2,
    'mobile_games': 3,
    'console_games': 6,
    'virtual': 9,
    'entertainment': 1,
    'radio': 5,
    'match': 13,
    'chat': 14,
    'lifestyle': 10,
    'knowledge': 11,
    'interactive': 15,
  };

  static const List<String> _defaultLiveCategoryOrder = [
    'online_games',
    'mobile_games',
    'console_games',
    'virtual',
    'entertainment',
    'radio',
    'match',
    'chat',
    'lifestyle',
    'knowledge',
    'interactive',
  ];

  static const String _liveCategoryOrderKey = 'live_category_order';
  static const String _enabledLiveCategoriesKey = 'enabled_live_categories';

  /// 获取直播分区顺序
  static List<String> get liveCategoryOrder {
    final saved = _prefs?.getStringList(_liveCategoryOrderKey);
    if (saved != null && saved.isNotEmpty) {
      final result = List<String>.from(saved);
      for (final cat in _defaultLiveCategoryOrder) {
        if (!result.contains(cat)) {
          result.add(cat);
        }
      }
      return result;
    }
    return List<String>.from(_defaultLiveCategoryOrder);
  }

  /// 设置直播分区顺序
  static Future<void> setLiveCategoryOrder(List<String> order) async {
    await init();
    await _prefs!.setStringList(_liveCategoryOrderKey, order);
  }

  /// 获取启用的直播分区
  static Set<String> get enabledLiveCategories {
    final saved = _prefs?.getStringList(_enabledLiveCategoriesKey);
    if (saved != null) {
      return saved.toSet();
    }
    return _defaultLiveCategoryOrder.toSet();
  }

  /// 设置启用的直播分区
  static Future<void> setEnabledLiveCategories(Set<String> categories) async {
    await init();
    await _prefs!.setStringList(_enabledLiveCategoriesKey, categories.toList());
  }

  /// 检查直播分区是否启用
  static bool isLiveCategoryEnabled(String name) {
    return enabledLiveCategories.contains(name);
  }

  /// 切换直播分区启用状态
  static Future<void> toggleLiveCategory(String name, bool enabled) async {
    final current = enabledLiveCategories;
    if (enabled) {
      current.add(name);
    } else {
      current.remove(name);
    }
    await setEnabledLiveCategories(current);
  }

  // 启动时自动刷新首页
  static const String _autoRefreshOnLaunchKey = 'auto_refresh_on_launch';

  /// 是否启动时自动刷新首页 (默认关闭)
  static bool get autoRefreshOnLaunch {
    return _prefs?.getBool(_autoRefreshOnLaunchKey) ?? false;
  }

  /// 设置启动时自动刷新首页
  static Future<void> setAutoRefreshOnLaunch(bool value) async {
    await init();
    await _prefs!.setBool(_autoRefreshOnLaunchKey, value);
  }

  // 首页上次刷新时间戳 (毫秒)
  static const String _lastHomeRefreshTimeKey = 'last_home_refresh_time';

  /// 获取首页上次刷新时间戳 (毫秒)
  static int get lastHomeRefreshTime {
    return _prefs?.getInt(_lastHomeRefreshTimeKey) ?? 0;
  }

  /// 设置首页上次刷新时间戳
  static Future<void> setLastHomeRefreshTime(int timestamp) async {
    await init();
    await _prefs!.setInt(_lastHomeRefreshTimeKey, timestamp);
  }

  // 首页推荐视频缓存 (JSON)
  static const String _cachedHomeVideosKey = 'cached_home_videos';

  /// 获取缓存的首页视频 JSON
  static String? get cachedHomeVideosJson {
    return _prefs?.getString(_cachedHomeVideosKey);
  }

  /// 保存首页视频缓存 JSON，同时更新刷新时间戳
  static Future<void> setCachedHomeVideosJson(String json) async {
    await init();
    await _prefs!.setString(_cachedHomeVideosKey, json);
    await _prefs!.setInt(
      _lastHomeRefreshTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 格式化上次刷新时间为可读字符串（首页专用）
  static String formatLastRefreshTime() {
    return formatTimestamp(lastHomeRefreshTime);
  }

  /// 通用：格式化毫秒时间戳为 "更新于X前" 字符串
  static String formatTimestamp(int timestampMs) {
    if (timestampMs == 0) return '';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    if (diff.inDays > 0) return '更新于${diff.inDays}天前';
    if (diff.inHours > 0) return '更新于${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '更新于${diff.inMinutes}分钟前';
    return '更新于刚刚';
  }

  // ==================== 关注/收藏/稍后再看 缓存 ====================

  static const String _cachedFollowingKey = 'cached_following_users';
  static const String _cachedFavoriteFoldersKey = 'cached_favorite_folders';
  static const String _cachedFavoriteVideosKey =
      'cached_favorite_videos'; // 默认收藏夹视频
  static const String _cachedWatchLaterKey = 'cached_watch_later';
  static const String _lastFollowingRefreshTimeKey =
      'last_following_refresh_time';

  /// 关注列表上次刷新时间戳
  static int get lastFollowingRefreshTime =>
      _prefs?.getInt(_lastFollowingRefreshTimeKey) ?? 0;

  /// 关注列表缓存
  static String? get cachedFollowingJson =>
      _prefs?.getString(_cachedFollowingKey);
  static Future<void> setCachedFollowingJson(String json) async {
    await init();
    await _prefs!.setString(_cachedFollowingKey, json);
    await _prefs!.setInt(
      _lastFollowingRefreshTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 收藏夹列表缓存
  static String? get cachedFavoriteFoldersJson =>
      _prefs?.getString(_cachedFavoriteFoldersKey);
  static Future<void> setCachedFavoriteFoldersJson(String json) async {
    await init();
    await _prefs!.setString(_cachedFavoriteFoldersKey, json);
  }

  /// 默认收藏夹视频缓存
  static String? get cachedFavoriteVideosJson =>
      _prefs?.getString(_cachedFavoriteVideosKey);
  static Future<void> setCachedFavoriteVideosJson(String json) async {
    await init();
    await _prefs!.setString(_cachedFavoriteVideosKey, json);
  }

  /// 稍后再看缓存
  static String? get cachedWatchLaterJson =>
      _prefs?.getString(_cachedWatchLaterKey);
  static Future<void> setCachedWatchLaterJson(String json) async {
    await init();
    await _prefs!.setString(_cachedWatchLaterKey, json);
  }

  // 动态缓存
  static const String _cachedDynamicKey = 'cached_dynamic_videos';
  static const String _lastDynamicRefreshTimeKey = 'last_dynamic_refresh_time';

  /// 动态页上次刷新时间戳
  static int get lastDynamicRefreshTime =>
      _prefs?.getInt(_lastDynamicRefreshTimeKey) ?? 0;

  static String? get cachedDynamicJson => _prefs?.getString(_cachedDynamicKey);
  static Future<void> setCachedDynamicJson(String json) async {
    await init();
    await _prefs!.setString(_cachedDynamicKey, json);
    await _prefs!.setInt(
      _lastDynamicRefreshTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  // 历史记录缓存
  static const String _cachedHistoryKey = 'cached_history_videos';
  static const String _lastHistoryRefreshTimeKey = 'last_history_refresh_time';

  /// 历史记录上次刷新时间戳
  static int get lastHistoryRefreshTime =>
      _prefs?.getInt(_lastHistoryRefreshTimeKey) ?? 0;

  static String? get cachedHistoryJson => _prefs?.getString(_cachedHistoryKey);
  static Future<void> setCachedHistoryJson(String json) async {
    await init();
    await _prefs!.setString(_cachedHistoryKey, json);
    await _prefs!.setInt(
      _lastHistoryRefreshTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 清除所有用户内容缓存 (登出时调用)
  static Future<void> clearUserContentCache() async {
    await init();
    await _prefs!.remove(_cachedFollowingKey);
    await _prefs!.remove(_cachedFavoriteFoldersKey);
    await _prefs!.remove(_cachedFavoriteVideosKey);
    await _prefs!.remove(_cachedWatchLaterKey);
    await _prefs!.remove(_cachedDynamicKey);
    await _prefs!.remove(_cachedHistoryKey);
  }

  // App 全局字体大小缩放
  static const String _fontScaleKey = 'app_font_scale';

  /// 字体缩放比例（0.8 ~ 1.4，默认 1.0）
  static double get fontScale {
    return (_prefs?.getDouble(_fontScaleKey) ?? 1.0).clamp(0.8, 1.4);
  }

  /// 设置字体缩放比例
  static Future<void> setFontScale(double value) async {
    await init();
    await _prefs!.setDouble(_fontScaleKey, value.clamp(0.8, 1.4));
  }

  /// 字体缩放选项列表
  static const List<double> fontScaleOptions = [
    0.8,
    0.9,
    1.0,
    1.1,
    1.2,
    1.3,
    1.4,
  ];

  /// 字体缩放选项标签
  static String fontScaleLabel(double scale) {
    if (scale == 1.0) return '默认';
    final pct = ((scale - 1.0) * 100).round();
    return pct > 0 ? '+$pct%' : '$pct%';
  }

  // ==================== 聚焦即切换 ====================
  static const String _focusSwitchTabKey = 'focus_switch_tab';

  /// 聚焦即切换 (默认开启：移动焦点立刻切换 tab)
  static bool get focusSwitchTab {
    return _prefs?.getBool(_focusSwitchTabKey) ?? true;
  }

  /// 设置聚焦即切换
  static Future<void> setFocusSwitchTab(bool value) async {
    await init();
    await _prefs!.setBool(_focusSwitchTabKey, value);
  }

  // ==================== 高性能模式 ====================
  static const String _highPerformanceModeKey = 'high_performance_mode';

  /// 高性能模式变更回调（需要重新配置图片缓存等）
  static VoidCallback? onHighPerformanceModeChanged;

  /// 是否开启高性能模式（默认开启；关闭 = 省内存）
  static bool get highPerformanceMode {
    return _prefs?.getBool(_highPerformanceModeKey) ?? true;
  }

  /// 设置高性能模式
  static Future<void> setHighPerformanceMode(bool value) async {
    await init();
    await _prefs!.setBool(_highPerformanceModeKey, value);
    onHighPerformanceModeChanged?.call();
  }

  /// 图片解码缓存：最大张数
  static int get imageCacheMaxSize => highPerformanceMode ? 60 : 30;

  /// 图片解码缓存：最大字节数
  static int get imageCacheMaxBytes =>
      highPerformanceMode ? 30 * 1024 * 1024 : 15 * 1024 * 1024;

  /// 列表加载上限
  static int get listMaxItems => highPerformanceMode ? 200 : 60;

  /// 磁盘缓存最大对象数
  static int get diskCacheMaxObjects => highPerformanceMode ? 200 : 100;

  // ==================== 侧边栏内存显示 ====================
  static const String _showMemoryInfoKey = 'show_memory_info';

  /// 内存显示设置变更回调
  static VoidCallback? onShowMemoryInfoChanged;

  /// 是否在侧边栏显示内存信息 (默认关闭)
  static bool get showMemoryInfo {
    return _prefs?.getBool(_showMemoryInfoKey) ?? false;
  }

  /// 设置是否显示内存信息
  static Future<void> setShowMemoryInfo(bool value) async {
    await init();
    await _prefs!.setBool(_showMemoryInfoKey, value);
    onShowMemoryInfoChanged?.call();
  }

  // ==================== 主题色 ====================
  static const String _themeColorKey = 'theme_color';

  /// 主题色选项：value → label
  static const Map<int, String> themeColorOptions = {
    0xFF81C784: '草绿',
    0xFFFB7299: 'B站粉',
    0xFF64B5F6: '天蓝',
    0xFFBA68C8: '薰衣紫',
    0xFFFFB74D: '暖橙',
    0xFF4DD0E1: '湖青',
    0xFFE57373: '珊瑚红',
    0xFF4DB6AC: '薄荷',
    0xFFFFD54F: '琥珀',
    0xFFA1887F: '可可',
  };

  /// 当前主题色
  static Color get themeColor {
    final value = _prefs?.getInt(_themeColorKey) ?? 0xFF81C784;
    return Color(value);
  }

  /// 当前主题色的 int 值
  static int get themeColorValue =>
      _prefs?.getInt(_themeColorKey) ?? 0xFF81C784;

  /// 设置主题色
  static Future<void> setThemeColor(int colorValue) async {
    await init();
    await _prefs!.setInt(_themeColorKey, colorValue);
  }

  /// 当前主题色标签
  static String get themeColorLabel =>
      themeColorOptions[themeColorValue] ?? '自定义';

  // ==================== 右侧栏宽度设置 ====================
  static const String _sidePanelWidthKey = 'side_panel_width';

  /// 右侧栏宽度选项：屏幕宽度的比例
  static const List<double> sidePanelWidthOptions = [0.2, 0.25, 0.33];
  static const List<String> sidePanelWidthLabels = ['1/5', '1/4', '1/3'];

  /// 获取右侧栏宽度比例 (默认 1/4)
  static double get sidePanelWidthRatio {
    final raw = _prefs?.getDouble(_sidePanelWidthKey) ?? 0.25;
    // 找到最近的有效选项
    return sidePanelWidthOptions.reduce(
      (a, b) => (a - raw).abs() < (b - raw).abs() ? a : b,
    );
  }

  /// 设置右侧栏宽度比例
  static Future<void> setSidePanelWidthRatio(double value) async {
    await init();
    await _prefs!.setDouble(_sidePanelWidthKey, value);
  }

  /// 获取右侧栏宽度标签
  static String sidePanelWidthLabel(double ratio) {
    final idx = sidePanelWidthOptions.indexOf(ratio);
    return idx >= 0 ? sidePanelWidthLabels[idx] : '${(ratio * 100).toInt()}%';
  }

  /// 根据屏幕宽度计算右侧栏实际宽度
  static double getSidePanelWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth * sidePanelWidthRatio;
  }
}
