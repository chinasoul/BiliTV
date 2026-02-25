import 'package:flutter/material.dart';
import 'package:bili_tv_app/core/plugin/plugin.dart';
import 'package:bili_tv_app/core/plugin/plugin_manager.dart';
import 'package:bili_tv_app/core/plugin/plugin_store.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/local_server.dart';
import 'package:bili_tv_app/services/settings_service.dart';

/// 插件设置页
class PluginsSettingsTab extends StatefulWidget {
  final VoidCallback? onMoveUp;
  final FocusNode? sidebarFocusNode;

  const PluginsSettingsTab({super.key, this.onMoveUp, this.sidebarFocusNode});

  @override
  State<PluginsSettingsTab> createState() => _PluginsSettingsTabState();
}

class _PluginsSettingsTabState extends State<PluginsSettingsTab> {
  final _pluginManager = PluginManager();

  @override
  Widget build(BuildContext context) {
    if (_pluginManager.plugins.isEmpty) {
      return const Center(
        child: Text('暂无插件', style: TextStyle(color: Colors.white70)),
      );
    }

    final serverAddress = LocalServer.instance.address ?? 'http://TV_IP:3322';

    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // 提示信息
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.devices, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '使用手机或电脑访问 $serverAddress 设置去广告增强和弹幕屏蔽功能',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        // 插件列表
        ..._pluginManager.plugins.asMap().entries.map((entry) {
          final index = entry.key;
          final plugin = entry.value;
          return _PluginCard(
            plugin: plugin,
            onToggle: _togglePlugin,
            isFirst: index == 0,
            isLast: index == _pluginManager.plugins.length - 1,
            onMoveUp: widget.onMoveUp,
            sidebarFocusNode: widget.sidebarFocusNode,
          );
        }),
      ],
    );
  }

  Future<void> _togglePlugin(Plugin plugin, bool enable) async {
    await _pluginManager.setEnabled(plugin, enable);
    setState(() {});
  }
}

class _PluginCard extends StatefulWidget {
  final Plugin plugin;
  final Function(Plugin, bool) onToggle;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onMoveUp;
  final FocusNode? sidebarFocusNode;

  const _PluginCard({
    required this.plugin,
    required this.onToggle,
    required this.isFirst,
    required this.isLast,
    this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PluginStore.isEnabled(widget.plugin.id),
      builder: (context, snapshot) {
        final isEnabled = snapshot.data ?? false;

        return GestureDetector(
          onTap: () => widget.onToggle(widget.plugin, !isEnabled),
          child: TvFocusScope(
            pattern: FocusPattern.vertical,
            enableKeyRepeat: true,
            autofocus: widget.isFirst,
            exitLeft: widget.sidebarFocusNode,
            onExitUp: widget.isFirst ? widget.onMoveUp : null,
            isFirst: widget.isFirst,
            isLast: widget.isLast,
            onSelect: () => widget.onToggle(widget.plugin, !isEnabled),
            onFocusChange: (value) => setState(() => _focused = value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _focused
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: _focused
                    ? Border.all(color: SettingsService.themeColor, width: 2)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.plugin.icon ?? Icons.extension,
                    color: isEnabled ? SettingsService.themeColor : Colors.white54,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.plugin.name,
                          style: TextStyle(
                            color: _focused ? Colors.white : Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.plugin.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              widget.plugin.description,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'v${widget.plugin.version} • ${widget.plugin.author}',
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ExcludeFocus(
                    child: Switch(
                      value: isEnabled,
                      onChanged: (value) => widget.onToggle(widget.plugin, value),
                      activeTrackColor: const Color(
                        0xFF81C784,
                      ).withValues(alpha: 0.5),
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return SettingsService.themeColor;
                        }
                        return Colors.grey;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
