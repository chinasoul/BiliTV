import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/plugin/plugin_types.dart';
import '../core/plugin/plugin_store.dart';
import 'package:bili_tv_app/config/app_style.dart';
import '../screens/home/settings/widgets/setting_toggle_row.dart';
import '../services/settings_service.dart';

// ---------------------------------------------------------------------------
// Category / ActionType 定义
// ---------------------------------------------------------------------------

/// 所有支持的 SponsorBlock 片段类别
enum SBCategory {
  sponsor,
  intro,
  outro,
  interaction,
  selfpromo,
  musicOfftopic,
  preview,
  poiHighlight,
  filler,
}

extension SBCategoryExt on SBCategory {
  String get apiValue => switch (this) {
    SBCategory.sponsor => 'sponsor',
    SBCategory.intro => 'intro',
    SBCategory.outro => 'outro',
    SBCategory.interaction => 'interaction',
    SBCategory.selfpromo => 'selfpromo',
    SBCategory.musicOfftopic => 'music_offtopic',
    SBCategory.preview => 'preview',
    SBCategory.poiHighlight => 'poi_highlight',
    SBCategory.filler => 'filler',
  };

  String get label => switch (this) {
    SBCategory.sponsor => '广告/赞助',
    SBCategory.intro => '片头动画',
    SBCategory.outro => '片尾鸣谢',
    SBCategory.interaction => '三连提醒',
    SBCategory.selfpromo => '自我推广',
    SBCategory.musicOfftopic => '非音乐部分',
    SBCategory.preview => '回顾/预览',
    SBCategory.poiHighlight => '精彩时刻',
    SBCategory.filler => '闲聊/过渡',
  };

  static SBCategory? fromApi(String value) {
    for (final c in SBCategory.values) {
      if (c.apiValue == value) return c;
    }
    return null;
  }
}

enum SBActionType { skip, poi, mute, full, chapter }

extension SBActionTypeExt on SBActionType {
  static SBActionType? fromApi(String value) => switch (value) {
    'skip' => SBActionType.skip,
    'poi' => SBActionType.poi,
    'mute' => SBActionType.mute,
    'full' => SBActionType.full,
    'chapter' => SBActionType.chapter,
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// Segment 数据模型
// ---------------------------------------------------------------------------

class SponsorSegment {
  final SBCategory category;
  final SBActionType actionType;
  final String uuid;
  final double startTime;
  final double endTime;
  final int votes;
  final int locked;
  final double videoDuration;

  SponsorSegment({
    required this.category,
    required this.actionType,
    required this.uuid,
    required this.startTime,
    required this.endTime,
    this.votes = 0,
    this.locked = 0,
    this.videoDuration = 0,
  });

  int get startTimeMs => (startTime * 1000).toInt();
  int get endTimeMs => (endTime * 1000).toInt();

  factory SponsorSegment.fromJson(Map<String, dynamic> json) {
    final cat = SBCategoryExt.fromApi(json['category'] ?? '') ??
        SBCategory.sponsor;
    final action = SBActionTypeExt.fromApi(json['actionType'] ?? 'skip') ??
        SBActionType.skip;
    final seg = json['segment'] as List<dynamic>;
    return SponsorSegment(
      category: cat,
      actionType: action,
      uuid: json['UUID'] ?? '',
      startTime: (seg[0] as num).toDouble(),
      endTime: (seg[1] as num).toDouble(),
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      locked: (json['locked'] as num?)?.toInt() ?? 0,
      videoDuration: (json['videoDuration'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// 配置模型
// ---------------------------------------------------------------------------

class SponsorBlockConfig {
  bool autoSkip;
  bool showNotice;
  bool reportViewed;
  bool devOverlay;
  int apiTimeoutSec;
  Map<String, bool> categoryEnabled;

  SponsorBlockConfig({
    this.autoSkip = true,
    this.showNotice = true,
    this.reportViewed = false,
    this.devOverlay = false,
    this.apiTimeoutSec = 10,
    Map<String, bool>? categoryEnabled,
  }) : categoryEnabled = categoryEnabled ?? _defaultCategories();

  static Map<String, bool> _defaultCategories() {
    final m = <String, bool>{};
    for (final c in SBCategory.values) {
      m[c.apiValue] = c == SBCategory.sponsor;
    }
    return m;
  }

  bool isCategoryEnabled(SBCategory cat) =>
      categoryEnabled[cat.apiValue] ?? false;

  List<String> get enabledApiCategories => categoryEnabled.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();

  factory SponsorBlockConfig.fromJson(Map<String, dynamic> json) {
    return SponsorBlockConfig(
      autoSkip: json['autoSkip'] ?? true,
      showNotice: json['showNotice'] ?? true,
      reportViewed: json['reportViewed'] ?? false,
      devOverlay: json['devOverlay'] ?? false,
      apiTimeoutSec: json['apiTimeoutSec'] ?? 10,
      categoryEnabled: json['categoryEnabled'] != null
          ? Map<String, bool>.from(json['categoryEnabled'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'autoSkip': autoSkip,
    'showNotice': showNotice,
    'reportViewed': reportViewed,
    'devOverlay': devOverlay,
    'apiTimeoutSec': apiTimeoutSec,
    'categoryEnabled': categoryEnabled,
  };
}

// ---------------------------------------------------------------------------
// 插件主体
// ---------------------------------------------------------------------------

class SponsorBlockPlugin extends PlayerPlugin {
  static const String _baseUrl = 'https://bsbsb.top/api';

  @override
  String get id => 'sponsor_block';

  @override
  String get name => '空降助手';

  @override
  String get description =>
      '基于 BilibiliSponsorBlock 数据库自动跳过视频中的广告、赞助、片头片尾等片段。';

  @override
  String get version => '2.0.0';

  @override
  String get author => 'chinasoul modified';

  @override
  IconData? get icon => Icons.rocket_launch_outlined;

  List<SponsorSegment> _segments = [];
  final Set<String> _skippedIds = {};
  int _lastPositionMs = 0;
  SponsorBlockConfig _config = SponsorBlockConfig();
  String _status = '待加载';

  /// Bumped on every config save so UI can listen for external changes.
  final ValueNotifier<int> configVersion = ValueNotifier(0);

  @override
  bool get hasSettings => true;

  @override
  Widget? get settingsWidget => _SponsorBlockSettings(plugin: this);

  SponsorBlockConfig get config => _config;

  /// Whether dev overlay should show in the player.
  bool get showDevOverlay => _config.devOverlay;

  /// Compact debug info for the player overlay.
  String get devInfoText {
    if (_segments.isEmpty) return 'SB: $_status';
    final skippable = _segments.where((s) =>
        s.actionType != SBActionType.full &&
        s.actionType != SBActionType.chapter &&
        s.actionType != SBActionType.poi).length;
    final buf = StringBuffer('SB: ${_segments.length}段(可跳$skippable)  已跳${_skippedIds.length}');
    for (final s in _segments) {
      final skipped = _skippedIds.contains(s.uuid);
      final tag = switch (s.actionType) {
        SBActionType.full => ' [全片标记]',
        SBActionType.chapter => ' [章节]',
        SBActionType.poi => ' [标记点]',
        SBActionType.mute => ' [静音]',
        _ => '',
      };
      buf.write('\n  ${s.category.label} '
          '${_fmtSec(s.startTime)}→${_fmtSec(s.endTime)}'
          '$tag${skipped ? ' ✓' : ''}');
    }
    return buf.toString();
  }

  static String _fmtSec(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toInt();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── 生命周期 ──

  @override
  Future<void> onEnable() async {
    await _loadConfig();
    debugPrint('SponsorBlock: enabled (${_config.enabledApiCategories.length} categories)');
  }

  @override
  Future<void> onDisable() async {
    _segments = [];
    _skippedIds.clear();
    debugPrint('SponsorBlock: disabled');
  }

  // ── 配置持久化 ──

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('plugin_config_$id');
    if (jsonStr != null) {
      try {
        _config = SponsorBlockConfig.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        debugPrint('SponsorBlock: config load error: $e');
      }
    }
  }

  Future<void> saveConfig(SponsorBlockConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_config_$id', jsonEncode(config.toJson()));
    configVersion.value++;
  }

  // ── PlayerPlugin 接口 ──

  @override
  Future<void> onVideoLoad(String bvid, int cid) async {
    _segments = [];
    _skippedIds.clear();
    _lastPositionMs = 0;
    _status = '请求中…';

    if (!await PluginStore.isEnabled(id)) {
      _status = '插件未启用';
      return;
    }

    final enabledCats = _config.enabledApiCategories;
    if (enabledCats.isEmpty) {
      _status = '未选择类别';
      return;
    }

    try {
      final categoriesJson = jsonEncode(enabledCats);
      final url = Uri.parse('$_baseUrl/skipSegments').replace(
        queryParameters: {
          'videoID': bvid,
          'cid': cid.toString(),
          'categories': categoriesJson,
        },
      );

      debugPrint('SponsorBlock URL: $url');

      final response = await http.get(url).timeout(
        Duration(seconds: _config.apiTimeoutSec),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _segments = data
            .map((j) => SponsorSegment.fromJson(j))
            .where((s) => _config.isCategoryEnabled(s.category))
            .toList();
        if (_segments.isEmpty) {
          _status = '无匹配类别片段';
        }
        debugPrint('SponsorBlock: loaded ${_segments.length} segments for $bvid (cid=$cid)');
      } else if (response.statusCode == 404) {
        _status = '该视频无标注';
        debugPrint('SponsorBlock: no segments for $bvid');
      } else {
        _status = 'HTTP ${response.statusCode}';
        debugPrint('SponsorBlock: HTTP ${response.statusCode}');
      }
    } catch (e) {
      final err = e.toString();
      if (err.contains('TimeoutException')) {
        _status = '请求超时(${_config.apiTimeoutSec}s)';
      } else if (err.contains('SocketException')) {
        _status = '网络不可达';
      } else if (err.contains('HandshakeException') || err.contains('Certificate')) {
        _status = 'SSL证书错误';
      } else {
        _status = '请求失败: ${e.runtimeType}';
      }
      debugPrint('SponsorBlock: fetch error: $e');
      if (e is Error) debugPrint('SponsorBlock: stacktrace: ${e.stackTrace}');
    }
  }

  void manualSkip(String segmentId) {
    _skippedIds.add(segmentId);
  }

  @override
  Future<SkipAction> onPositionUpdate(int positionMs) async {
    if (_segments.isEmpty) return SkipActionNone();

    if (positionMs < _lastPositionMs - 2000) {
      for (var seg in _segments) {
        if (_skippedIds.contains(seg.uuid) &&
            positionMs < seg.startTimeMs - 1000) {
          _skippedIds.remove(seg.uuid);
        }
      }
    }
    _lastPositionMs = positionMs;

    for (var seg in _segments) {
      if (_skippedIds.contains(seg.uuid)) continue;
      if (positionMs < seg.startTimeMs || positionMs > seg.endTimeMs) continue;

      // poi_highlight 和 full 不是可跳过片段
      if (seg.actionType == SBActionType.poi ||
          seg.actionType == SBActionType.full ||
          seg.actionType == SBActionType.chapter) continue;

      if (_config.autoSkip) {
        _skippedIds.add(seg.uuid);
        _reportViewed(seg.uuid);
        return SkipActionSkipTo(
          seg.endTimeMs,
          '已跳过: ${seg.category.label}',
        );
      } else {
        return SkipActionShowButton(
          seg.endTimeMs,
          '跳过${seg.category.label}',
          seg.uuid,
        );
      }
    }

    return SkipActionNone();
  }

  @override
  void onVideoEnd() {
    _segments = [];
    _skippedIds.clear();
    _lastPositionMs = 0;
  }

  // ── 上报跳过 ──

  void _reportViewed(String uuid) {
    if (!_config.reportViewed) return;
    http
        .post(Uri.parse('$_baseUrl/viewedVideoSponsorTime'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'UUID': uuid}))
        .timeout(const Duration(seconds: 3))
        .catchError((_) => http.Response('', 0));
  }
}

// ---------------------------------------------------------------------------
// 设置界面
// ---------------------------------------------------------------------------

class _SponsorBlockSettings extends StatefulWidget {
  final SponsorBlockPlugin plugin;
  const _SponsorBlockSettings({required this.plugin});

  @override
  State<_SponsorBlockSettings> createState() => _SponsorBlockSettingsState();
}

class _SponsorBlockSettingsState extends State<_SponsorBlockSettings> {
  late SponsorBlockConfig _cfg;

  @override
  void initState() {
    super.initState();
    _cfg = widget.plugin.config;
    widget.plugin.configVersion.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    widget.plugin.configVersion.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (!mounted) return;
    setState(() => _cfg = widget.plugin.config);
  }

  void _save() => widget.plugin.saveConfig(_cfg);

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('行为设置'),
          SettingToggleRow(
            label: '自动跳过',
            subtitle: '关闭后将显示手动跳过按钮',
            value: _cfg.autoSkip,
            onChanged: (val) {
              setState(() => _cfg.autoSkip = val);
              _save();
            },
          ),
          SettingToggleRow(
            label: '跳过提示',
            subtitle: '自动跳过时显示 Toast 提示',
            value: _cfg.showNotice,
            onChanged: (val) {
              setState(() => _cfg.showNotice = val);
              _save();
            },
          ),
          SettingToggleRow(
            label: '上报跳过',
            subtitle: 'TV 端暂不支持',
            value: _cfg.reportViewed,
            enabled: false,
            onChanged: (_) {},
          ),
          SettingToggleRow(
            label: '恰饭统计（调试用）',
            subtitle: '右下角显示时间段',
            value: _cfg.devOverlay,
            onChanged: (val) {
              setState(() => _cfg.devOverlay = val);
              _save();
            },
          ),
          _sectionHeader('跳过类别'),
          _CategoryGrid(
            config: _cfg,
            onSave: _save,
            onChanged: () => setState(() {}),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.textHint, size: 14),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '片段数据由 bsbsb.top 社区标注提供',
                    style: TextStyle(color: AppColors.textHint, fontSize: AppFonts.sizeXS),
                  ),
                ),
              ],
            ),
          ),
        ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: AppFonts.sizeSM,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分类 3×3 矩阵
// ---------------------------------------------------------------------------

class _CategoryGrid extends StatefulWidget {
  final SponsorBlockConfig config;
  final VoidCallback onSave;
  final VoidCallback onChanged;

  const _CategoryGrid({
    required this.config,
    required this.onSave,
    required this.onChanged,
  });

  @override
  State<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<_CategoryGrid> {
  static const int _cols = 3;
  static final int _rows = (SBCategory.values.length / _cols).ceil();

  late final List<List<FocusNode>> _nodes;
  bool _gridHasFocus = false;

  @override
  void initState() {
    super.initState();
    _nodes = List.generate(
      _rows,
      (r) => List.generate(_cols, (_) => FocusNode()),
    );
    for (final row in _nodes) {
      for (final n in row) {
        n.addListener(_onChildFocusChanged);
      }
    }
  }

  @override
  void dispose() {
    for (final row in _nodes) {
      for (final n in row) {
        n.removeListener(_onChildFocusChanged);
        n.dispose();
      }
    }
    super.dispose();
  }

  void _onChildFocusChanged() {
    final any = _nodes.any((row) => row.any((n) => n.hasFocus));
    if (any && !_gridHasFocus && !_nodes[0][0].hasFocus) {
      _nodes[0][0].requestFocus();
    }
    _gridHasFocus = any;
  }

  int _idx(int r, int c) => r * _cols + c;

  bool _valid(int r, int c) =>
      r >= 0 && r < _rows && c >= 0 && c < _cols &&
      _idx(r, c) < SBCategory.values.length;

  void _navigate(int r, int c, LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) {
      if (r > 0 && _valid(r - 1, c)) {
        _nodes[r - 1][c].requestFocus();
      } else {
        // 顶行向上：交给 Flutter 方向性遍历，回到上方 SettingToggleRow
        FocusTraversalGroup.of(_nodes[r][c].context!)
            .inDirection(_nodes[r][c], TraversalDirection.up);
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (r < _rows - 1 && _valid(r + 1, c)) {
        _nodes[r + 1][c].requestFocus();
      } else {
        // 底行向下：交给 Flutter，进入下方插件卡片
        FocusTraversalGroup.of(_nodes[r][c].context!)
            .inDirection(_nodes[r][c], TraversalDirection.down);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (c > 0) {
        _nodes[r][c - 1].requestFocus();
      }
      // 左边界：吞掉事件，阻止焦点跑到侧边栏
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (c < _cols - 1 && _valid(r, c + 1)) {
        _nodes[r][c + 1].requestFocus();
      }
      // 右边界：阻止
    }
  }

  void _toggle(SBCategory cat) {
    final key = cat.apiValue;
    widget.config.categoryEnabled[key] = !(widget.config.isCategoryEnabled(cat));
    widget.onSave();
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: List.generate(_rows, (r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: List.generate(_cols, (c) {
                if (!_valid(r, c)) {
                  return const Expanded(child: SizedBox.shrink());
                }
                final cat = SBCategory.values[_idx(r, c)];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: c > 0 ? 3 : 0,
                      right: c < _cols - 1 ? 3 : 0,
                    ),
                    child: _buildCell(cat, r, c),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCell(SBCategory cat, int r, int c) {
    final enabled = widget.config.isCategoryEnabled(cat);

    return Focus(
      focusNode: _nodes[r][c],
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown ||
            k == LogicalKeyboardKey.arrowLeft ||
            k == LogicalKeyboardKey.arrowRight) {
          _navigate(r, c, k);
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (k == LogicalKeyboardKey.enter ||
                k == LogicalKeyboardKey.select)) {
          _toggle(cat);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          final themeColor = SettingsService.themeColor;
          return GestureDetector(
            onTap: () => _toggle(cat),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white.withValues(alpha: 0.12)
                    : enabled
                        ? themeColor.withValues(alpha: 0.08)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.6)
                      : enabled
                          ? themeColor.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: enabled ? themeColor : AppColors.textHint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cat.label,
                      style: TextStyle(
                        color: focused
                            ? Colors.white
                            : enabled
                                ? AppColors.textSecondary
                                : AppColors.textHint,
                        fontSize: AppFonts.sizeSM,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    enabled ? Icons.check_circle : Icons.circle_outlined,
                    color: enabled ? themeColor : AppColors.textHint,
                    size: 16,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
