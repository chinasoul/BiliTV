import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bili_tv_app/utils/toast_utils.dart';

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

/// 标签页切换策略
enum TabSwitchPolicy {
  smooth('流畅优先'),
  balanced('平衡'),
  memorySaver('省内存');

  final String label;
  const TabSwitchPolicy(this.label);
}

/// 播放性能模式
enum PlaybackPerformanceMode {
  high('高'),
  medium('中'),
  low('低');

  final String label;
  const PlaybackPerformanceMode(this.label);
}

/// 聚焦标题显示模式
enum FocusedTitleDisplayMode {
  normal('普通模式'),
  singleScroll('单次滚动'),
  loopScroll('循环滚动');

  final String label;
  const FocusedTitleDisplayMode(this.label);
}

/// 默认画质
enum VideoQuality {
  q360(16, '360P'),
  q480(32, '480P'),
  q720(64, '720P'),
  q1080(80, '1080P'),
  q1080plus(112, '1080P+'),
  q1080p60(116, '1080P 60帧'),
  q4k(120, '4K'),
  qHdr(125, 'HDR'),
  qDolby(126, '杜比视界'),
  q8k(127, '8K');

  final int qn;
  final String label;
  const VideoQuality(this.qn, this.label);

  static VideoQuality fromQn(int qn) {
    return VideoQuality.values.firstWhere(
      (q) => q.qn == qn,
      orElse: () => q1080,
    );
  }
}

/// 播放完成后行为
enum PlaybackCompletionAction {
  pause('暂停播放'),
  exit('退出播放'),
  playNextEpisode('播放下一集'),
  playRecommended('播放推荐视频');

  final String label;
  const PlaybackCompletionAction(this.label);
}

/// 应用主题模式
enum AppThemeMode {
  dark('深色'),
  light('浅色');

  final String label;
  const AppThemeMode(this.label);
}

/// 自定义缓存管理器
class BiliCacheManager {
  static const key = 'biliTvCache';
  static CacheManager? _instance;

  static CacheManager get instance {
    _instance ??= CacheManager(
      Config(
        key,
        stalePeriod: const Duration(days: 3),
        maxNrOfCacheObjects: SettingsService.cacheMaxObjects,
      ),
    );
    return _instance!;
  }
}

/// 设置服务
class SettingsService {
  static const String _useHardwareDecodeKey = 'use_hardware_decode';
  static SharedPreferences? _prefs;
  static final ValueNotifier<double> _fontScaleNotifier = ValueNotifier(1.0);
  static final ValueNotifier<ThemeMode> _themeModeNotifier = ValueNotifier(
    ThemeMode.dark,
  );

  /// Android SDK 版本号（缓存），非 Android 平台为 99
  static int androidSdkInt = 99;

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _fontScaleNotifier.value = fontScale;
    _themeModeNotifier.value = themeMode;
    // 初始化完成后通知监听者
    onShowMemoryInfoChanged?.call();
  }

  /// 显示 Toast 提示
  static void toast(BuildContext? context, String msg) {
    if (context != null) {
      ToastUtils.show(context, msg);
    }
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

  // 播放完成后行为设置
  static const String _playbackCompletionActionKey =
      'playback_completion_action';

  /// 播放完成后行为
  static PlaybackCompletionAction get playbackCompletionAction {
    final index = _prefs?.getInt(_playbackCompletionActionKey) ?? 0; // 默认暂停
    return PlaybackCompletionAction.values[index.clamp(
      0,
      PlaybackCompletionAction.values.length - 1,
    )];
  }

  /// 设置播放完成后行为
  static Future<void> setPlaybackCompletionAction(
    PlaybackCompletionAction value,
  ) async {
    await init();
    await _prefs!.setInt(_playbackCompletionActionKey, value.index);
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

  // 默认画质设置
  static const String _preferredQualityKey = 'preferred_quality';

  /// 获取默认画质 qn 值
  static int get preferredQualityQn {
    return _prefs?.getInt(_preferredQualityKey) ?? 80;
  }

  /// 获取默认画质枚举
  static VideoQuality get preferredQuality {
    return VideoQuality.fromQn(preferredQualityQn);
  }

  /// 设置默认画质
  static Future<void> setPreferredQuality(VideoQuality quality) async {
    await init();
    await _prefs!.setInt(_preferredQualityKey, quality.qn);
  }

  // 隧道播放模式（Tunnel Mode）
  static const String _tunnelModeEnabledKey = 'tunnel_mode_enabled';

  /// 是否启用隧道播放（解码帧直通显示硬件，部分设备可能黑屏）
  static bool get tunnelModeEnabled {
    return _prefs?.getBool(_tunnelModeEnabledKey) ?? true;
  }

  static Future<void> setTunnelModeEnabled(bool value) async {
    await init();
    await _prefs!.setBool(_tunnelModeEnabledKey, value);
    if (!value) await _prefs!.setBool(_tunnelModeHintShownKey, false);
  }

  static const String _tunnelModeHintShownKey = 'tunnel_mode_hint_shown';

  /// 是否已展示过隧道模式黑屏提示
  static bool get tunnelModeHintShown {
    return _prefs?.getBool(_tunnelModeHintShownKey) ?? false;
  }

  static Future<void> setTunnelModeHintShown(bool value) async {
    await init();
    await _prefs!.setBool(_tunnelModeHintShownKey, value);
  }

  // 隧道模式下倍速支持检测结果缓存
  static const String _tunnelSpeedSupportedKey = 'tunnel_speed_supported';

  /// null = 尚未检测，true = 设备支持隧道+倍速，false = 不支持
  static bool? get tunnelSpeedSupported {
    if (_prefs?.containsKey(_tunnelSpeedSupportedKey) != true) return null;
    return _prefs!.getBool(_tunnelSpeedSupportedKey);
  }

  static Future<void> setTunnelSpeedSupported(bool value) async {
    await init();
    await _prefs!.setBool(_tunnelSpeedSupportedKey, value);
  }

  static Future<void> clearTunnelSpeedSupported() async {
    await init();
    await _prefs!.remove(_tunnelSpeedSupportedKey);
  }

  // 播放前显示视频详情页
  static const String _showVideoDetailKey = 'show_video_detail_before_play';

  /// 是否在播放前显示视频详情页
  static bool get showVideoDetailBeforePlay {
    return _prefs?.getBool(_showVideoDetailKey) ?? true;
  }

  /// 设置是否在播放前显示视频详情页
  static Future<void> setShowVideoDetailBeforePlay(bool value) async {
    await init();
    await _prefs!.setBool(_showVideoDetailKey, value);
    if (!value) await _prefs!.setBool(_videoDetailHintShownKey, false);
  }

  static const String _videoDetailHintShownKey = 'video_detail_hint_shown';

  /// 是否已展示过视频详情页提示
  static bool get videoDetailHintShown {
    return _prefs?.getBool(_videoDetailHintShownKey) ?? false;
  }

  static Future<void> setVideoDetailHintShown(bool value) async {
    await init();
    await _prefs!.setBool(_videoDetailHintShownKey, value);
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

  // 播放页面左上角显示播放进度时间
  static const String _showPlayerProgressTimeKey = 'show_player_progress_time';

  /// 是否显示播放器左上角的“当前时间:总时长”
  static bool get showPlayerProgressTime {
    return _prefs?.getBool(_showPlayerProgressTimeKey) ?? false;
  }

  /// 设置是否显示播放器左上角的“当前时间:总时长”
  static Future<void> setShowPlayerProgressTime(bool value) async {
    await init();
    await _prefs!.setBool(_showPlayerProgressTimeKey, value);
  }

  // 全局时间显示设置（控制app所有界面右上角时间显示）
  static const String _showTimeDisplayKey = 'show_time_display';

  /// 时间显示变更回调
  static VoidCallback? onShowTimeDisplayChanged;

  /// 是否显示时间（全局控制）
  static bool get showTimeDisplay {
    return _prefs?.getBool(_showTimeDisplayKey) ?? true; // 默认开启
  }

  /// 设置是否显示时间（全局控制）
  static Future<void> setShowTimeDisplay(bool value) async {
    await init();
    await _prefs!.setBool(_showTimeDisplayKey, value);
    onShowTimeDisplayChanged?.call();
  }

  /// 兼容旧 API：alwaysShowPlayerTime 现在指向全局设置
  static bool get alwaysShowPlayerTime => showTimeDisplay;

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

  // ==================== 播放器控制栏按钮设置 ====================
  static const String _playerControlOrderKey = 'player_control_order';
  static const String _enabledPlayerControlsKey = 'enabled_player_controls';
  static const List<int> _defaultPlayerControlOrder = [
    0, // 播放/暂停
    1, // 评论
    2, // 选集
    3, // UP主
    4, // 更多视频
    5, // 设置
    6, // 监测
    7, // 互动操作
    8, // 循环播放
    9, // 视频详情
    10, // 关闭播放器
  ];

  /// 获取播放器控制栏按钮顺序
  static List<int> get playerControlOrder {
    final saved = _prefs?.getStringList(_playerControlOrderKey);
    if (saved != null && saved.isNotEmpty) {
      final parsed = saved
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .where((i) => _defaultPlayerControlOrder.contains(i))
          .toList();
      final result = <int>[];
      for (final index in parsed) {
        if (!result.contains(index)) {
          result.add(index);
        }
      }
      for (final index in _defaultPlayerControlOrder) {
        if (!result.contains(index)) {
          result.add(index);
        }
      }
      return result;
    }
    return List<int>.from(_defaultPlayerControlOrder);
  }

  /// 设置播放器控制栏按钮顺序
  static Future<void> setPlayerControlOrder(List<int> order) async {
    await init();
    final sanitized = <int>[];
    for (final index in order) {
      if (_defaultPlayerControlOrder.contains(index) &&
          !sanitized.contains(index)) {
        sanitized.add(index);
      }
    }
    for (final index in _defaultPlayerControlOrder) {
      if (!sanitized.contains(index)) {
        sanitized.add(index);
      }
    }
    await _prefs!.setStringList(
      _playerControlOrderKey,
      sanitized.map((i) => i.toString()).toList(),
    );
  }

  /// 获取已启用的播放器控制栏按钮（默认全部启用）
  static Set<int> get enabledPlayerControls {
    final saved = _prefs?.getStringList(_enabledPlayerControlsKey);
    if (saved != null) {
      final parsed = saved
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .where((i) => _defaultPlayerControlOrder.contains(i))
          .toSet();
      if (parsed.isNotEmpty) return parsed;
    }
    return _defaultPlayerControlOrder.toSet();
  }

  /// 设置启用的播放器控制栏按钮
  static Future<void> setEnabledPlayerControls(Set<int> controls) async {
    await init();
    final sanitized = controls
        .where((i) => _defaultPlayerControlOrder.contains(i))
        .toSet();
    await _prefs!.setStringList(
      _enabledPlayerControlsKey,
      sanitized.map((i) => i.toString()).toList(),
    );
  }

  /// 检查播放器控制栏按钮是否启用
  static bool isPlayerControlEnabled(int index) {
    return enabledPlayerControls.contains(index);
  }

  /// 切换播放器控制栏按钮启用状态
  static Future<void> togglePlayerControl(int index, bool enabled) async {
    if (!_defaultPlayerControlOrder.contains(index)) return;
    final current = enabledPlayerControls;
    if (enabled) {
      current.add(index);
    } else {
      current.remove(index);
    }
    await setEnabledPlayerControls(current);
  }

  /// 获取播放器中可见的控制栏按钮索引（按排序和启用状态过滤）
  static List<int> get visiblePlayerControlIndices {
    final enabled = enabledPlayerControls;
    return playerControlOrder.where((index) => enabled.contains(index)).toList();
  }

  // ==================== 偏好重置 ====================
  static const List<String> _playbackPreferenceKeys = [
    _playbackPerformanceModeKey,
    _playbackCompletionActionKey,
    _showVideoDetailKey,
    _videoDetailHintShownKey,
    _showMiniProgressKey,
    _hideControlsOnStartKey,
    _showPlayerProgressTimeKey,
    _seekPreviewModeKey,
    _preferredCodecKey,
    _tunnelModeEnabledKey,
    _tunnelModeHintShownKey,
    _preferredQualityKey,
    _playerControlOrderKey,
    _enabledPlayerControlsKey,
  ];

  static const List<String> _danmakuPreferenceKeys = [
    _preferNativeDanmakuKey,
    _danmakuEnabledKey,
    _danmakuOpacityKey,
    _danmakuFontSizeKey,
    _danmakuAreaKey,
    _danmakuSpeedKey,
    _hideTopDanmakuKey,
    _hideBottomDanmakuKey,
  ];

  static const List<String> _interfacePreferenceKeys = [
    _tabSwitchPolicyKey,
    _autoRefreshOnLaunchKey,
    _defaultStartPageKey,
    _videoGridColumnsKey,
    _sidePanelWidthKey,
    _showTimeDisplayKey,
    _fontScaleKey,
    _appThemeModeKey,
    _themeColorKey,
    _categoryOrderKey,
    _enabledCategoriesKey,
    _liveCategoryOrderKey,
    _enabledLiveCategoriesKey,
  ];

  static const List<String> _storagePreferenceKeys = [
    _focusedTitleDisplayModeKey,
  ];

  static const List<String> _developerPreferenceKeys = [
    _developerModeKey,
    _showMemoryInfoKey,
    _showAppCpuKey,
    _showCoreFreqKey,
    _marqueeFpsKey,
    _nativeDanmakuStrokeWidthKey,
    _nativeDanmakuStrokeAlphaMinKey,
    _commentFocusAlphaKey,
    _videoCardOverlayAlphaKey,
    _videoCardThemeAlphaKey,
    _popupBarrierAlphaKey,
    _panelBackgroundColorKey,
    _panelBackgroundAlphaKey,
    _popupBackgroundColorKey,
    _popupBackgroundAlphaKey,
  ];

  static Future<void> _removePreferenceKeys(List<String> keys) async {
    await init();
    for (final key in keys) {
      await _prefs!.remove(key);
    }
    _fontScaleNotifier.value = fontScale;
  }

  /// 重置「播放设置」页偏好
  static Future<void> resetPlaybackPreferences() async {
    await _removePreferenceKeys(_playbackPreferenceKeys);
  }

  /// 重置「弹幕设置」页偏好
  static Future<void> resetDanmakuPreferences() async {
    await _removePreferenceKeys(_danmakuPreferenceKeys);
  }

  /// 重置「界面设置」页偏好
  static Future<void> resetInterfacePreferences() async {
    await _removePreferenceKeys(_interfacePreferenceKeys);
    onShowTimeDisplayChanged?.call();
  }

  /// 重置「其他设置」页偏好
  static Future<void> resetStoragePreferences() async {
    await _removePreferenceKeys(_storagePreferenceKeys);
  }

  /// 重置「开发者选项」页偏好
  static Future<void> resetDeveloperPreferences() async {
    await _removePreferenceKeys(_developerPreferenceKeys);
    onShowMemoryInfoChanged?.call();
    onDeveloperModeChanged?.call();
  }

  /// 全局重置偏好（不清理缓存与用户内容）
  static Future<void> resetAllPreferences() async {
    final all = <String>{
      ..._playbackPreferenceKeys,
      ..._danmakuPreferenceKeys,
      ..._interfacePreferenceKeys,
      ..._storagePreferenceKeys,
      _hideLiveControlsOnStartKey,
      _showLiveTimeDisplayKey,
      _showMemoryInfoKey,
      _developerModeKey,
      _showAppCpuKey,
      _showCoreFreqKey,
      _marqueeFpsKey,
      _nativeDanmakuStrokeWidthKey,
      _nativeDanmakuStrokeAlphaMinKey,
      _commentFocusAlphaKey,
      _videoCardOverlayAlphaKey,
      _videoCardThemeAlphaKey,
      _popupBarrierAlphaKey,
      _panelBackgroundColorKey,
      _panelBackgroundAlphaKey,
      _popupBackgroundColorKey,
      _popupBackgroundAlphaKey,
      _tunnelSpeedSupportedKey,
    }.toList();

    await _removePreferenceKeys(all);
    onShowTimeDisplayChanged?.call();
    onShowMemoryInfoChanged?.call();
    onDeveloperModeChanged?.call();
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
  static const String _preferNativeDanmakuKey = 'prefer_native_danmaku';

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

  /// 优先使用原生弹幕渲染 (Android, 默认开启)
  static bool get preferNativeDanmaku =>
      _prefs?.getBool(_preferNativeDanmakuKey) ?? true;
  static Future<void> setPreferNativeDanmaku(bool value) async {
    await init();
    await _prefs!.setBool(_preferNativeDanmakuKey, value);
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
  static const String _lastCategoryRefreshTimePrefix =
      'last_category_refresh_time_';

  /// 获取首页上次刷新时间戳 (毫秒) - 兼容旧版，默认返回推荐分类
  static int get lastHomeRefreshTime {
    return _prefs?.getInt(_lastHomeRefreshTimeKey) ?? 0;
  }

  /// 设置首页上次刷新时间戳
  static Future<void> setLastHomeRefreshTime(int timestamp) async {
    await init();
    await _prefs!.setInt(_lastHomeRefreshTimeKey, timestamp);
  }

  /// 获取指定分类的上次刷新时间戳
  static int getLastCategoryRefreshTime(String categoryName) {
    // 推荐分类使用旧 key 保持兼容
    if (categoryName == 'recommend') {
      return lastHomeRefreshTime;
    }
    return _prefs?.getInt('$_lastCategoryRefreshTimePrefix$categoryName') ?? 0;
  }

  /// 设置指定分类的上次刷新时间戳
  static Future<void> setLastCategoryRefreshTime(String categoryName) async {
    await init();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    if (categoryName == 'recommend') {
      await _prefs!.setInt(_lastHomeRefreshTimeKey, timestamp);
    } else {
      await _prefs!.setInt(
        '$_lastCategoryRefreshTimePrefix$categoryName',
        timestamp,
      );
    }
  }

  // 首页推荐视频缓存 (JSON)
  static const String _cachedHomeVideosKey = 'cached_home_videos';
  static const String _cachedCategoryVideosPrefix = 'cached_category_videos_';

  /// 获取缓存的首页视频 JSON（兼容旧版，推荐分类专用）
  static String? get cachedHomeVideosJson {
    return _prefs?.getString(_cachedHomeVideosKey);
  }

  /// 保存首页视频缓存 JSON，同时更新刷新时间戳（兼容旧版，推荐分类专用）
  static Future<void> setCachedHomeVideosJson(String json) async {
    await init();
    await _prefs!.setString(_cachedHomeVideosKey, json);
    await _prefs!.setInt(
      _lastHomeRefreshTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 获取指定分类的缓存视频 JSON
  static String? getCachedCategoryVideosJson(String categoryName) {
    // 推荐分类使用旧 key 保持兼容
    if (categoryName == 'recommend') {
      return cachedHomeVideosJson;
    }
    return _prefs?.getString('$_cachedCategoryVideosPrefix$categoryName');
  }

  /// 保存指定分类的缓存视频 JSON，同时更新刷新时间戳
  static Future<void> setCachedCategoryVideosJson(
    String categoryName,
    String json,
  ) async {
    await init();
    if (categoryName == 'recommend') {
      await setCachedHomeVideosJson(json);
    } else {
      await _prefs!.setString(
        '$_cachedCategoryVideosPrefix$categoryName',
        json,
      );
      await setLastCategoryRefreshTime(categoryName);
    }
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

  /// 字体缩放比例（0.7 ~ 1.3，默认 1.0）
  static double get fontScale {
    return (_prefs?.getDouble(_fontScaleKey) ?? 1.0).clamp(0.7, 1.3);
  }

  static ValueNotifier<double> get fontScaleListenable => _fontScaleNotifier;

  static ValueNotifier<ThemeMode> get themeModeListenable => _themeModeNotifier;

  /// 设置字体缩放比例
  static Future<void> setFontScale(double value) async {
    await init();
    final clamped = value.clamp(0.7, 1.3);
    await _prefs!.setDouble(_fontScaleKey, clamped);
    _fontScaleNotifier.value = clamped;
  }

  /// 字体缩放选项列表
  static const List<double> fontScaleOptions = [
    0.7,
    0.8,
    0.9,
    1.0,
    1.1,
    1.2,
    1.3,
  ];

  /// 字体缩放选项标签
  static String fontScaleLabel(double scale) {
    if (scale == 1.0) return '默认';
    final pct = ((scale - 1.0) * 100).round();
    return pct > 0 ? '+$pct%' : '$pct%';
  }

  // ==================== 主题模式 ====================
  static const String _appThemeModeKey = 'app_theme_mode';

  static AppThemeMode get appThemeMode {
    final index = _prefs?.getInt(_appThemeModeKey) ?? AppThemeMode.dark.index;
    return AppThemeMode.values[index.clamp(0, AppThemeMode.values.length - 1)];
  }

  static ThemeMode get themeMode {
    return appThemeMode == AppThemeMode.light
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  static Future<void> setAppThemeMode(AppThemeMode value) async {
    await init();
    await _prefs!.setInt(_appThemeModeKey, value.index);
    _themeModeNotifier.value = value == AppThemeMode.light
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  // ==================== 标签页切换策略 ====================
  static const String _focusSwitchTabKey = 'focus_switch_tab';
  static const String _tabSwitchPolicyKey = 'tab_switch_policy';

  /// 标签页切换策略
  /// - smooth: 焦点即切换 + 页面驻留
  /// - balanced: 仅确认键切换 + 页面驻留
  /// - memorySaver: 仅确认键切换 + 离开即释放旧页面
  static TabSwitchPolicy get tabSwitchPolicy {
    final index = _prefs?.getInt(_tabSwitchPolicyKey);
    if (index != null) {
      return TabSwitchPolicy.values[index.clamp(
        0,
        TabSwitchPolicy.values.length - 1,
      )];
    }

    // 兼容旧版本 focusSwitchTab 开关
    final legacy = _prefs?.getBool(_focusSwitchTabKey);
    if (legacy != null) {
      return legacy ? TabSwitchPolicy.smooth : TabSwitchPolicy.balanced;
    }
    return TabSwitchPolicy.smooth;
  }

  static Future<void> setTabSwitchPolicy(TabSwitchPolicy value) async {
    await init();
    await _prefs!.setInt(_tabSwitchPolicyKey, value.index);
  }

  /// 兼容旧逻辑：是否聚焦即切换
  static bool get focusSwitchTab {
    return tabSwitchPolicy == TabSwitchPolicy.smooth;
  }

  /// 兼容旧逻辑：设置聚焦即切换（映射到策略）
  static Future<void> setFocusSwitchTab(bool value) async {
    await setTabSwitchPolicy(
      value ? TabSwitchPolicy.smooth : TabSwitchPolicy.balanced,
    );
  }

  /// 是否保留已访问标签页状态
  static bool get keepTabPagesAlive {
    return tabSwitchPolicy != TabSwitchPolicy.memorySaver;
  }

  // ==================== 播放性能模式 ====================
  static const String _playbackPerformanceModeKey = 'playback_performance_mode';

  static PlaybackPerformanceMode get playbackPerformanceMode {
    final index = _prefs?.getInt(_playbackPerformanceModeKey);
    if (index == null) return PlaybackPerformanceMode.high;
    return PlaybackPerformanceMode.values[index.clamp(
      0,
      PlaybackPerformanceMode.values.length - 1,
    )];
  }

  static Future<void> setPlaybackPerformanceMode(
    PlaybackPerformanceMode value,
  ) async {
    await init();
    await _prefs!.setInt(_playbackPerformanceModeKey, value.index);
  }

  /// 弹幕同步间隔
  static Duration get danmakuSyncInterval {
    switch (playbackPerformanceMode) {
      case PlaybackPerformanceMode.high:
        return const Duration(milliseconds: 80);
      case PlaybackPerformanceMode.medium:
        return const Duration(milliseconds: 120);
      case PlaybackPerformanceMode.low:
        return const Duration(milliseconds: 180);
    }
  }

  /// Stats 刷新间隔
  static Duration get statsInterval {
    switch (playbackPerformanceMode) {
      case PlaybackPerformanceMode.high:
        return const Duration(milliseconds: 250);
      case PlaybackPerformanceMode.medium:
        return const Duration(milliseconds: 500);
      case PlaybackPerformanceMode.low:
        return const Duration(milliseconds: 1000);
    }
  }

  /// 是否在初始化阶段预加载快进预览图
  static bool get preloadVideoshotOnPlayerInit {
    return playbackPerformanceMode != PlaybackPerformanceMode.low;
  }

  /// 快进预览图预加载阈值（当前雪碧图使用进度达到该比例后，预加载下一张）
  static double get videoshotPreloadThreshold {
    switch (playbackPerformanceMode) {
      case PlaybackPerformanceMode.high:
        return 0.8;
      case PlaybackPerformanceMode.medium:
        return 0.7;
      case PlaybackPerformanceMode.low:
        return 0.55;
    }
  }

  /// 图片解码缓存：最大张数（按播放性能模式动态调整）
  static int get imageCacheMaxSize {
    switch (playbackPerformanceMode) {
      case PlaybackPerformanceMode.high:
        return 60;
      case PlaybackPerformanceMode.medium:
        return 40;
      case PlaybackPerformanceMode.low:
        return 20;
    }
  }

  /// 图片解码缓存：最大字节数（按播放性能模式动态调整）
  static int get imageCacheMaxBytes {
    switch (playbackPerformanceMode) {
      case PlaybackPerformanceMode.high:
        return 30 * 1024 * 1024;
      case PlaybackPerformanceMode.medium:
        return 20 * 1024 * 1024;
      case PlaybackPerformanceMode.low:
        return 10 * 1024 * 1024;
    }
  }

  /// 磁盘缓存对象上限（仅在 BiliCacheManager 首次创建时生效）
  static int get cacheMaxObjects {
    switch (playbackPerformanceMode) {
      case PlaybackPerformanceMode.high:
        return 200;
      case PlaybackPerformanceMode.medium:
        return 150;
      case PlaybackPerformanceMode.low:
        return 80;
    }
  }

  /// 列表加载上限
  static const int listMaxItems = 200;

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

  // ==================== 开发者选项 ====================
  static const String _developerModeKey = 'developer_mode';
  static const String _showAppCpuKey = 'show_app_cpu';
  static const String _showCoreFreqKey = 'show_core_freq';
  static const String _marqueeFpsKey = 'marquee_fps';
  static const String _focusedTitleDisplayModeKey =
      'focused_title_display_mode';
  static const String _nativeDanmakuStrokeWidthKey =
      'native_danmaku_stroke_width';
  static const String _nativeDanmakuStrokeAlphaMinKey =
      'native_danmaku_stroke_alpha_min';
  static const String _commentFocusAlphaKey = 'comment_focus_alpha';
  static const String _videoCardOverlayAlphaKey = 'video_card_overlay_alpha';
  static const String _videoCardThemeAlphaKey = 'video_card_theme_alpha';
  static const String _popupBarrierAlphaKey =
      'popup_barrier_alpha';
  static const String _panelBackgroundColorKey =
      'panel_background_color';
  static const String _panelBackgroundAlphaKey =
      'panel_background_alpha';
  static const String _popupBackgroundColorKey =
      'popup_background_color';
  static const String _popupBackgroundAlphaKey =
      'popup_background_alpha';

  /// 开发者选项变更回调（用于刷新设置标签页列表）
  static VoidCallback? onDeveloperModeChanged;

  /// 是否已开启开发者模式
  static bool get developerMode => _prefs?.getBool(_developerModeKey) ?? false;

  static Future<void> setDeveloperMode(bool value) async {
    await init();
    await _prefs!.setBool(_developerModeKey, value);
    onDeveloperModeChanged?.call();
  }

  /// 是否在 overlay 上显示 APP 进程占用率
  static bool get showAppCpu => _prefs?.getBool(_showAppCpuKey) ?? false;

  static Future<void> setShowAppCpu(bool value) async {
    await init();
    await _prefs!.setBool(_showAppCpuKey, value);
    onShowMemoryInfoChanged?.call();
  }

  /// 是否在 overlay 上显示各核心频率
  static bool get showCoreFreq => _prefs?.getBool(_showCoreFreqKey) ?? false;

  static Future<void> setShowCoreFreq(bool value) async {
    await init();
    await _prefs!.setBool(_showCoreFreqKey, value);
    onShowMemoryInfoChanged?.call();
  }

  /// 滚动文字帧率（30 或 60）
  static int get marqueeFps => _prefs?.getInt(_marqueeFpsKey) ?? 60;

  static Future<void> setMarqueeFps(int value) async {
    await init();
    await _prefs!.setInt(_marqueeFpsKey, value);
  }

  /// 聚焦标题显示模式（默认：循环滚动）
  static FocusedTitleDisplayMode get focusedTitleDisplayMode {
    final index =
        _prefs?.getInt(_focusedTitleDisplayModeKey) ??
        FocusedTitleDisplayMode.loopScroll.index;
    return FocusedTitleDisplayMode.values[index.clamp(
      0,
      FocusedTitleDisplayMode.values.length - 1,
    )];
  }

  static Future<void> setFocusedTitleDisplayMode(
    FocusedTitleDisplayMode mode,
  ) async {
    await init();
    await _prefs!.setInt(_focusedTitleDisplayModeKey, mode.index);
  }

  /// 原生弹幕描边宽度（开发者选项）
  static double get nativeDanmakuStrokeWidth {
    return (_prefs?.getDouble(_nativeDanmakuStrokeWidthKey) ?? 1.9).clamp(
      1.2,
      3.8,
    );
  }

  static Future<void> setNativeDanmakuStrokeWidth(double value) async {
    await init();
    await _prefs!.setDouble(
      _nativeDanmakuStrokeWidthKey,
      value.clamp(1.2, 3.8),
    );
  }

  /// 原生弹幕描边最小 alpha（开发者选项）
  static int get nativeDanmakuStrokeAlphaMin {
    final raw = _prefs?.getInt(_nativeDanmakuStrokeAlphaMinKey) ?? 165;
    return raw.clamp(0, 255);
  }

  static Future<void> setNativeDanmakuStrokeAlphaMin(int value) async {
    await init();
    await _prefs!.setInt(_nativeDanmakuStrokeAlphaMinKey, value.clamp(0, 255));
  }

  /// 评论项聚焦背景 alpha（开发者选项）
  static double get commentFocusAlpha {
    final raw = _prefs?.getDouble(_commentFocusAlphaKey) ?? 0.10;
    return raw.clamp(0.03, 0.30);
  }

  static Future<void> setCommentFocusAlpha(double value) async {
    await init();
    await _prefs!.setDouble(_commentFocusAlphaKey, value.clamp(0.03, 0.30));
  }

  /// 视频卡片底部遮罩 alpha（开发者选项）
  static double get videoCardOverlayAlpha {
    final raw = _prefs?.getDouble(_videoCardOverlayAlphaKey) ?? 0.90;
    return raw.clamp(0.50, 1.0);
  }

  static Future<void> setVideoCardOverlayAlpha(double value) async {
    await init();
    await _prefs!.setDouble(_videoCardOverlayAlphaKey, value.clamp(0.50, 1.0));
  }

  /// 视频卡片整体主题背景 alpha（开发者选项）
  static double get videoCardThemeAlpha {
    final raw = _prefs?.getDouble(_videoCardThemeAlphaKey) ?? 0.60;
    return raw.clamp(0.20, 0.90);
  }

  static Future<void> setVideoCardThemeAlpha(double value) async {
    await init();
    await _prefs!.setDouble(_videoCardThemeAlphaKey, value.clamp(0.20, 0.90));
  }

  /// 评论弹窗遮罩 alpha（开发者选项）
  static double get popupBarrierAlpha {
    final raw = _prefs?.getDouble(_popupBarrierAlphaKey) ?? 0.60;
    return raw.clamp(0.30, 0.90);
  }

  static Future<void> setCommentPopupBarrierAlpha(double value) async {
    await init();
    await _prefs!.setDouble(
      _popupBarrierAlphaKey,
      value.clamp(0.30, 0.90),
    );
  }

  /// 评论侧栏背景颜色（开发者选项）
  static int get panelBackgroundColorValue {
    return _prefs?.getInt(_panelBackgroundColorKey) ?? 0xFF2A2A2A;
  }

  static Future<void> setCommentPanelBackgroundColorValue(int value) async {
    await init();
    await _prefs!.setInt(_panelBackgroundColorKey, value);
  }

  /// 评论侧栏背景 alpha（开发者选项）
  static double get panelBackgroundAlpha {
    final raw = _prefs?.getDouble(_panelBackgroundAlphaKey) ?? 0.95;
    return raw.clamp(0.30, 1.0);
  }

  static Future<void> setCommentPanelBackgroundAlpha(double value) async {
    await init();
    await _prefs!.setDouble(
      _panelBackgroundAlphaKey,
      value.clamp(0.30, 1.0),
    );
  }

  /// 评论弹窗背景颜色（开发者选项）
  static int get popupBackgroundColorValue {
    return _prefs?.getInt(_popupBackgroundColorKey) ?? 0xFF2A2A2A;
  }

  static Future<void> setCommentPopupBackgroundColorValue(int value) async {
    await init();
    await _prefs!.setInt(_popupBackgroundColorKey, value);
  }

  /// 评论弹窗背景 alpha（开发者选项）
  static double get popupBackgroundAlpha {
    final raw = _prefs?.getDouble(_popupBackgroundAlphaKey) ?? 0.95;
    return raw.clamp(0.30, 1.0);
  }

  static Future<void> setCommentPopupBackgroundAlpha(double value) async {
    await init();
    await _prefs!.setDouble(
      _popupBackgroundAlphaKey,
      value.clamp(0.30, 1.0),
    );
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
    return Color(_prefs?.getInt(_themeColorKey) ?? 0xFF81C784);
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

  // ==================== 默认启动页面 ====================
  static const String _defaultStartPageKey = 'default_start_page';

  /// 启动页面选项：key → label
  /// 对应 HomeScreen 的 tab 索引或特殊值
  /// 'recommend' -> 主页推荐分类 (index 0)
  /// 'popular' -> 主页热门分类 (index 0，但切换到热门)
  /// 'dynamic' -> 动态 (index 1)
  /// 'history' -> 历史 (index 3)
  /// 'live' -> 直播 (index 4)
  static const Map<String, String> defaultStartPageOptions = {
    'recommend': '推荐',
    'popular': '热门',
    'dynamic': '关注动态',
    'history': '历史',
    'live': '直播',
  };

  /// 获取默认启动页面
  static String get defaultStartPage {
    return _prefs?.getString(_defaultStartPageKey) ?? 'recommend';
  }

  /// 设置默认启动页面
  static Future<void> setDefaultStartPage(String value) async {
    await init();
    await _prefs!.setString(_defaultStartPageKey, value);
  }

  /// 获取默认启动页面标签
  static String get defaultStartPageLabel =>
      defaultStartPageOptions[defaultStartPage] ?? '推荐';
}
