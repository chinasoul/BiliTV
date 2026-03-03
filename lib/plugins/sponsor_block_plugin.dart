import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/plugin/plugin_types.dart';
import '../core/plugin/plugin_store.dart';
import 'package:bili_tv_app/config/app_style.dart';

class SponsorBlockPlugin extends PlayerPlugin {
  @override
  String get id => 'sponsor_block';

  @override
  String get name => '空降助手';

  @override
  String get description => '基于 SponsorBlock 数据库自动跳过视频中的广告、赞助、片头片尾等片段。';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'YangY (Ported)';

  @override
  IconData? get icon => Icons.rocket_launch_outlined;

  List<SponsorSegment> _segments = [];
  final Set<String> _skippedIds = {};
  int _lastPositionMs = 0;
  SponsorBlockConfig _config = SponsorBlockConfig();

  @override
  bool get hasSettings => true;

  @override
  Widget? get settingsWidget => _SponsorBlockSettings(plugin: this);

  @override
  Future<void> onEnable() async {
    _loadConfig();
    debugPrint('✅ 空降助手已启用');
  }

  @override
  Future<void> onDisable() async {
    _segments = [];
    _skippedIds.clear();
    debugPrint('🔴 空降助手已禁用');
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('plugin_config_$id');
    if (jsonStr != null) {
      try {
        _config = SponsorBlockConfig.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        debugPrint('Error loading config: $e');
      }
    }
  }

  Future<void> saveConfig(SponsorBlockConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_config_$id', jsonEncode(config.toJson()));
  }

  @override
  Future<void> onVideoLoad(String bvid, int cid) async {
    _segments = [];
    _skippedIds.clear();
    _lastPositionMs = 0;

    // 如果没有启用，不请求
    if (!await PluginStore.isEnabled(id)) return;

    try {
      // 默认请求所有跳过类型
      // API: https://bsbsb.top/api/skipSegments?videoID={BVID}&category=sponsor&category=intro&...
      // 这里简化处理，请求常用的
      var url = Uri.parse(
        'https://bsbsb.top/api/skipSegments?videoID=$bvid&category=sponsor&category=intro&category=outro&category=interaction&category=selfpromo',
      );

      var response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _segments = data.map((json) => SponsorSegment.fromJson(json)).toList();
        debugPrint(
          '📦 SponsorBlock: Loaded ${_segments.length} segments for $bvid',
        );
      } else if (response.statusCode == 404) {
        debugPrint('SponsorBlock: No segments found for $bvid');
      }
    } catch (e) {
      debugPrint('SponsorBlock Error: $e');
    }
  }

  // 记录手动跳过
  void manualSkip(String segmentId) {
    _skippedIds.add(segmentId);
  }

  @override
  Future<SkipAction> onPositionUpdate(int positionMs) async {
    if (_segments.isEmpty) return SkipActionNone();

    // 简单防抖/回退检测
    if (positionMs < _lastPositionMs - 2000) {
      // 回退超过2秒，重置相关片段的跳过状态，允许再次跳过
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

      if (positionMs >= seg.startTimeMs && positionMs <= seg.endTimeMs) {
        // 命中片段
        if (_config.autoSkip) {
          _skippedIds.add(seg.uuid);
          return SkipActionSkipTo(
            seg.endTimeMs.toInt(),
            '已跳过: ${seg.category}',
          );
        } else {
          // 显示按钮
          return SkipActionShowButton(
            seg.endTimeMs.toInt(),
            '跳过${seg.category}',
            seg.uuid,
          );
        }
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
}

class SponsorSegment {
  final String category;
  final String uuid;
  final double startTime; // seconds
  final double endTime; // seconds

  SponsorSegment({
    required this.category,
    required this.uuid,
    required this.startTime,
    required this.endTime,
  });

  // 转换为毫秒方便比较
  int get startTimeMs => (startTime * 1000).toInt();
  int get endTimeMs => (endTime * 1000).toInt();

  factory SponsorSegment.fromJson(Map<String, dynamic> json) {
    // category map for better display names if needed
    // sponsor, intro, outro, interaction, selfpromo, music_offtopic, preview, poi_highlight, filler
    return SponsorSegment(
      category: json['category'] ?? 'unknown',
      uuid: json['UUID'] ?? '',
      startTime: (json['segment'][0] as num).toDouble(),
      endTime: (json['segment'][1] as num).toDouble(),
    );
  }
}

class SponsorBlockConfig {
  bool autoSkip;

  SponsorBlockConfig({this.autoSkip = true});

  factory SponsorBlockConfig.fromJson(Map<String, dynamic> json) {
    return SponsorBlockConfig(autoSkip: json['autoSkip'] ?? true);
  }

  Map<String, dynamic> toJson() => {'autoSkip': autoSkip};
}

class _SponsorBlockSettings extends StatefulWidget {
  final SponsorBlockPlugin plugin;
  const _SponsorBlockSettings({required this.plugin});

  @override
  State<_SponsorBlockSettings> createState() => _SponsorBlockSettingsState();
}

class _SponsorBlockSettingsState extends State<_SponsorBlockSettings> {
  late bool _autoSkip;

  @override
  void initState() {
    super.initState();
    _autoSkip = widget.plugin._config.autoSkip;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('自动跳过', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              '关闭后将显示手动跳过按钮',
              style: TextStyle(color: AppColors.textTertiary),
            ),
            value: _autoSkip,
            onChanged: (val) {
              setState(() => _autoSkip = val);
              final newConfig = widget.plugin._config..autoSkip = val;
              widget.plugin.saveConfig(newConfig);
            },
          ),
        ],
      ),
    );
  }
}
