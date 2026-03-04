import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/plugin/plugin_types.dart';
import '../services/local_server.dart';
import 'package:bili_tv_app/config/app_style.dart';
import '../screens/home/settings/widgets/setting_toggle_row.dart';

/// 弹幕屏蔽插件
///
/// 功能：屏蔽包含指定关键词的弹幕
class DanmakuEnhancePlugin extends DanmakuPlugin {
  @override
  String get id => 'danmaku_enhance';

  @override
  String get name => '弹幕屏蔽';

  @override
  String get description => '屏蔽包含指定关键词的弹幕';

  @override
  String get version => '2.1.0';

  @override
  String get author => 'YangY (Ported)';

  @override
  IconData? get icon => Icons.block_outlined;

  DanmakuBlockConfig _config = DanmakuBlockConfig();

  @override
  bool get hasSettings => true;

  @override
  Widget? get settingsWidget => _DanmakuBlockSettings(plugin: this);

  @override
  Future<void> onEnable() async {
    await _loadConfig();
    debugPrint('✅ 弹幕屏蔽已启用');
    debugPrint('📋 屏蔽词: ${_config.blockKeywords}');
  }

  @override
  Future<void> onDisable() async {
    debugPrint('🔴 弹幕屏蔽已禁用');
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('plugin_config_$id');
    if (jsonStr != null) {
      try {
        _config = DanmakuBlockConfig.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        debugPrint('Error loading config: $e');
      }
    }
  }

  Future<void> saveConfig(DanmakuBlockConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_config_$id', jsonEncode(config.toJson()));
  }

  // 添加屏蔽词
  void addBlockKeyword(String keyword) {
    if (keyword.isNotEmpty && !_config.blockKeywords.contains(keyword)) {
      _config.blockKeywords.add(keyword);
      saveConfig(_config);
    }
  }

  // 移除屏蔽词
  void removeBlockKeyword(String keyword) {
    if (_config.blockKeywords.contains(keyword)) {
      _config.blockKeywords.remove(keyword);
      saveConfig(_config);
    }
  }

  // 获取屏蔽词列表 (API 使用)
  List<String> getBlockKeywords() => List.unmodifiable(_config.blockKeywords);

  // 获取配置 (API 使用)
  DanmakuBlockConfig getConfig() => _config;

  // 设置开关
  void setEnableFilter(bool value) {
    _config.enableFilter = value;
    saveConfig(_config);
  }

  // 添加全词屏蔽词
  void addFullKeyword(String keyword) {
    if (keyword.isNotEmpty && !_config.fullKeywords.contains(keyword)) {
      _config.fullKeywords.add(keyword);
      saveConfig(_config);
    }
  }

  // 移除全词屏蔽词
  void removeFullKeyword(String keyword) {
    if (_config.fullKeywords.contains(keyword)) {
      _config.fullKeywords.remove(keyword);
      saveConfig(_config);
    }
  }

  // 获取全词屏蔽词列表
  List<String> getFullKeywords() => List.unmodifiable(_config.fullKeywords);

  @override
  dynamic filterDanmaku(dynamic item) {
    if (item is! Map) return item;
    if (!_config.enableFilter) return item;

    final content = item['content'] as String? ?? '';

    // 1. 部分匹配检测 (contains)
    for (var keyword in _config.blockKeywords) {
      if (keyword.isNotEmpty && content.contains(keyword)) {
        return null; // 屏蔽
      }
    }

    // 2. 全词匹配检测 (equals)
    for (var keyword in _config.fullKeywords) {
      if (keyword.isNotEmpty && content == keyword) {
        return null; // 屏蔽
      }
    }

    return item;
  }

  @override
  DanmakuStyle? styleDanmaku(dynamic item) {
    return null;
  }
}

/// 弹幕屏蔽配置
class DanmakuBlockConfig {
  bool enableFilter; // 启用屏蔽
  List<String> blockKeywords; // 部分匹配关键词
  List<String> fullKeywords; // 全词匹配关键词

  DanmakuBlockConfig({
    this.enableFilter = true,
    List<String>? blockKeywords,
    List<String>? fullKeywords,
  }) : blockKeywords = blockKeywords ?? ['剧透', '前方高能'],
       fullKeywords = fullKeywords ?? [];

  factory DanmakuBlockConfig.fromJson(Map<String, dynamic> json) {
    return DanmakuBlockConfig(
      enableFilter: json['enableFilter'] ?? true,
      blockKeywords: List<String>.from(json['blockKeywords'] ?? ['剧透', '前方高能']),
      fullKeywords: List<String>.from(json['fullKeywords'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'enableFilter': enableFilter,
    'blockKeywords': blockKeywords,
    'fullKeywords': fullKeywords,
  };
}

class _DanmakuBlockSettings extends StatefulWidget {
  final DanmakuEnhancePlugin plugin;
  const _DanmakuBlockSettings({required this.plugin});

  @override
  State<_DanmakuBlockSettings> createState() => _DanmakuBlockSettingsState();
}

class _DanmakuBlockSettingsState extends State<_DanmakuBlockSettings> {
  final TextEditingController _partialInputController = TextEditingController();
  final TextEditingController _fullInputController = TextEditingController();

  @override
  void dispose() {
    _partialInputController.dispose();
    _fullInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.plugin._config;
    final serverAddress = LocalServer.instance.address ?? 'http://TV_IP:3322';

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.phone_android, color: AppColors.textHint, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '推荐使用手机访问 $serverAddress 进行管理',
                    style: const TextStyle(color: AppColors.textHint, fontSize: AppFonts.sizeXS),
                  ),
                ),
              ],
            ),
          ),

          SettingToggleRow(
            label: '启用弹幕屏蔽',
            subtitle: '屏蔽包含指定关键词的弹幕',
            value: config.enableFilter,
            onChanged: (val) {
              setState(() => widget.plugin.setEnableFilter(val));
            },
          ),

          _buildKeywordSection(
            title: '部分匹配关键词',
            subtitle: '包含即屏蔽（如 "第一" 会屏蔽 "我是第一名"）',
            controller: _partialInputController,
            keywords: config.blockKeywords,
            onAdd: (k) => widget.plugin.addBlockKeyword(k),
            onRemove: (k) => widget.plugin.removeBlockKeyword(k),
          ),

          const SizedBox(height: 24),

          // 全词匹配关键词
          _buildKeywordSection(
            title: '全词匹配关键词',
            subtitle: '完全一致才屏蔽（如 "第一" 只屏蔽 "第一"）',
            controller: _fullInputController,
            keywords: config.fullKeywords,
            onAdd: (k) => widget.plugin.addFullKeyword(k),
            onRemove: (k) => widget.plugin.removeFullKeyword(k),
          ),
        ],
    );
  }

  Widget _buildKeywordSection({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required List<String> keywords,
    required Function(String) onAdd,
    required Function(String) onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: AppFonts.sizeSM,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textHint, fontSize: AppFonts.sizeXS),
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '输入关键词',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: AppColors.navItemSelectedBackground,
                  isDense: true,
                ),
                style: TextStyle(color: AppColors.primaryText),
                onSubmitted: (_) {
                  final val = controller.text.trim();
                  if (val.isNotEmpty) {
                    setState(() {
                      onAdd(val);
                      controller.clear();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                final val = controller.text.trim();
                if (val.isNotEmpty) {
                  setState(() {
                    onAdd(val);
                    controller.clear();
                  });
                }
              },
              icon: Icon(Icons.add, color: Colors.blue),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 关键词列表
        keywords.isEmpty
            ? Text(
                '暂无屏蔽词',
                style: TextStyle(
                  color: AppColors.disabledText,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keywords
                    .map(
                      (k) => Chip(
                        label: Text(k),
                        backgroundColor: Colors.red.withValues(alpha: 0.2),
                        onDeleted: () {
                          setState(() {
                            onRemove(k);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
      ],
      ),
    );
  }
}
