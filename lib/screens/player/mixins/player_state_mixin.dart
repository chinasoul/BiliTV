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
  bool preferNativeDanmaku = false;

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
  List<dynamic> episodes = []; // 懒加载：初始为空或 pages，打开选集面板时才填充完整合集列表
  bool showEpisodePanel = false;
  int focusedEpisodeIndex = 0;
  bool isUgcSeason = false; // 是否为合集（ugc_season），合集的每集有不同 bvid
  bool episodesFullyLoaded = false; // 标记 episodes 是否已填充完整合集数据

  // 自动连播用：预计算的下一集信息（不需要加载完整列表）
  Map<String, dynamic>? precomputedNextEpisode; // {title, pic, bvid?, cid?}
  bool hasMultipleEpisodes = false; // 是否有多集（合集或分P > 1）
  String? currentEpisodeTitle; // 当前集标题（用于 getDisplayVideo）

  // 下一集预览
  bool showNextEpisodePreview = false;
  int nextEpisodeCountdown = 0; // 剩余秒数
  Map<String, dynamic>? nextEpisodeInfo; // {title, pic}

  // 弹幕数据
  List<dynamic> danmakuList = [];
  int lastDanmakuIndex = 0;
  DateTime? lastUiRebuildAt;
  DateTime? lastPluginHandleAt;
  Timer? danmakuSyncTimer;
  Timer? danmakuOptionApplyTimer;

  // 新面板
  bool showUpPanel = false;
  bool showRelatedPanel = false;
  bool showActionButtons = false;
  bool showCommentPanel = false;

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

  // 长按快进快退：暂停+加速+批量提交
  int seekRepeatCount = 0; // 连续快进/快退次数，用于加速
  bool wasPlayingBeforeSeek = false; // 快进前是否在播放
  Timer? seekCommitTimer; // 松手后提交并恢复播放
  Duration? pendingSeekTarget; // 快进累积目标位置
  Duration? lastCommittedSeekTarget; // 上次提交的快进位置（用于连续快进时避免回退）
  DateTime? lastSeekCommitTime; // 上次提交快进的时间
  bool hideBufferAfterSeek = false; // 快进提交后短暂隐藏缓冲条，防止旧数据闪烁
  Timer? bufferHideTimer;

  // 快进预览模式 (雪碧图)
  VideoshotData? videoshotData;
  bool isSeekPreviewMode = false; // 当前是否处于预览快进模式
  int precachedSpriteIndex = -1; // 已预缓存的雪碧图最大索引 (滑动窗口)
  bool hasShownVideoshotFailToast = false; // 是否已显示过预览图失败提示
  bool hasHandledVideoComplete = false; // 防止重复触发视频完成回调
  Timer? completionFallbackTimer; // 末尾播完兜底检测防抖定时器
  bool isUserInitiatedPause = false; // 用户主动暂停标志，区分播放器异常停止
  Timer? progressBarSeekTimer; // 进度条模式延迟跳转定时器

  // 循环播放模式
  bool isLoopMode = false;

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
