import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import '../player_screen.dart';
import '../widgets/settings_panel.dart';
import '../../../models/videoshot.dart';

/// 播放器状态 Mixin
/// 包含所有 State 变量
mixin PlayerStateMixin on State<PlayerScreen> {
  // 控制器
  VideoPlayerController? videoController;
  DanmakuController? danmakuController;

  // 插件跳过动作 (如空降助手)
  dynamic currentSkipAction; // SkipActionShowButton?

  // 加载状态
  bool isLoading = true;
  String? errorMessage;
  int? cid;
  int? aid; // 视频 aid (用于点赞/投币/收藏)

  // 完整视频信息 (从 API 获取，统一数据来源)
  Map<String, dynamic>? fullVideoInfo;

  // 在线观看人数
  String? onlineCount;
  Timer? onlineCountTimer;

  // 当前播放的音频 URL (DASH 模式)
  String? currentAudioUrl;

  // 播放器流订阅
  List<StreamSubscription> playerSubscriptions = [];

  // 弹幕设置
  bool danmakuEnabled = true;
  double danmakuOpacity = 0.6;
  double danmakuFontSize = 17.0;
  double danmakuArea = 0.25;
  double danmakuSpeed = 10.0;
  bool hideTopDanmaku = false;
  bool hideBottomDanmaku = false;

  // 播放设置
  double playbackSpeed = 1.0;
  final List<double> availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // UI 控制
  bool showControls = true;
  bool showSettingsPanel = false;
  SettingsMenuType settingsMenuType = SettingsMenuType.main;
  Timer? hideTimer;
  Timer? progressReportTimer;
  int focusedButtonIndex = 0; // 0=Play, 1=Settings, 2=Playlist, 3=More
  int focusedSettingIndex = 0;

  // 分辨率
  List<Map<String, dynamic>> qualities = [];
  int currentQuality = 80;
  String currentCodec = ''; // 当前编解码器 (avc/hev/av01)
  bool showStatsForNerds = false;
  int videoWidth = 0;
  int videoHeight = 0;
  double videoFrameRate = 0.0;
  int videoDataRateKbps = 0;
  double videoSpeedKbps = 0;
  double networkActivityKb = 0;
  Duration lastStatsBuffered = Duration.zero;
  DateTime? lastStatsTime;
  Timer? statsTimer;

  // 双击返回
  DateTime? lastBackPressed;

  // 选集
  List<dynamic> episodes = [];
  bool showEpisodePanel = false;
  int focusedEpisodeIndex = 0;

  // 弹幕数据
  List<dynamic> danmakuList = [];
  int lastDanmakuIndex = 0;

  // 新面板
  bool showUpPanel = false;
  bool showRelatedPanel = false;
  bool showActionButtons = false;

  // 进度条聚焦模式
  bool isProgressBarFocused = false;
  Duration? previewPosition; // 拖动预览位置

  // 自动续播
  int? initialProgress; // 从历史记录恢复的进度

  // 相关视频 (用于自动连播)
  List<dynamic> relatedVideos = [];

  // 返回键处理标志 - 防止 handleGlobalKeyEvent 和 onPopInvoked 重复处理
  bool backKeyJustHandled = false;

  // 快进快退指示器
  bool showSeekIndicator = false;
  Timer? seekIndicatorTimer;

  // 快进预览模式 (雪碧图)
  VideoshotData? videoshotData;
  bool isSeekPreviewMode = false; // 当前是否处于预览快进模式
  int precachedSpriteIndex = -1; // 已预缓存的雪碧图最大索引 (滑动窗口)
  bool hasShownVideoshotFailToast = false; // 是否已显示过预览图失败提示
  bool hasHandledVideoComplete = false; // 防止重复触发视频完成回调

  // 获取编解码器简称
  String get _codecLabel {
    if (currentCodec.startsWith('av01')) {
      return 'AV1';
    }
    if (currentCodec.startsWith('hev') ||
        currentCodec.startsWith('hvc') ||
        currentCodec.startsWith('dvh')) {
      return 'H.265';
    }
    if (currentCodec.startsWith('avc')) {
      return 'H.264';
    }
    return '';
  }

  // 获取当前画质描述 (含编解码器)
  String get currentQualityDesc {
    String desc = '${currentQuality}P';
    for (var q in qualities) {
      if (q['qn'] == currentQuality) {
        desc = q['desc'] ?? desc;
        break;
      }
    }
    if (_codecLabel.isNotEmpty) {
      return '$desc ($_codecLabel)';
    }
    return desc;
  }
}
