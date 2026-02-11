import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';

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

/// 自定义缓存管理器 - 限制 200MB
class BiliCacheManager {
  static const key = 'biliTvCache';
  static CacheManager? _instance;

  static CacheManager get instance {
    _instance ??= CacheManager(
      Config(
        key,
        stalePeriod: const Duration(days: 7), // 7天过期
        maxNrOfCacheObjects: 350, // 最多350个缓存对象 (约200MB)
      ),
    );
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
}
