import 'package:flutter/material.dart';
import 'package:bili_tv_app/core/plugin/plugin.dart';
import 'package:bili_tv_app/core/plugin/plugin_manager.dart';
import 'package:bili_tv_app/core/plugin/plugin_store.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/local_server.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

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
      return Center(
        child: Text('暂无插件', style: TextStyle(color: AppColors.inactiveText)),
      );
    }

    final serverAddress = LocalServer.instance.address ?? 'http://TV_IP:3322';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.devices, color: Colors.blue, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '按 → 展开设置，或访问 $serverAddress 配置',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: AppFonts.sizeXS),
                ),
              ),
            ],
          ),
        ),
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
  bool _expanded = false;
  bool _isEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadEnabled();
  }

  Future<void> _loadEnabled() async {
    final enabled = await PluginStore.isEnabled(widget.plugin.id);
    if (mounted) setState(() => _isEnabled = enabled);
  }

  void _toggle() {
    final newState = !_isEnabled;
    setState(() {
      _isEnabled = newState;
      if (!newState) _expanded = false;
    });
    widget.onToggle(widget.plugin, newState);
  }

  void _toggleExpand() {
    if (!_isEnabled || !widget.plugin.hasSettings) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final hasExpandableSettings = widget.plugin.hasSettings && _isEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 插件卡片行 ──
        GestureDetector(
          onTap: _toggle,
          child: TvFocusScope(
            pattern: FocusPattern.vertical,
            enableKeyRepeat: true,
            autofocus: widget.isFirst,
            exitLeft: widget.sidebarFocusNode,
            onExitUp: widget.isFirst ? widget.onMoveUp : null,
            isFirst: widget.isFirst,
            isLast: widget.isLast && !_expanded,
            onSelect: _toggle,
            onExitRight: hasExpandableSettings ? _toggleExpand : null,
            onFocusChange: (value) => setState(() => _focused = value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _focused
                    ? AppColors.navItemSelectedBackground
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.plugin.icon ?? Icons.extension,
                    color: _isEnabled ? SettingsService.themeColor : AppColors.textHint,
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
                            color: _focused ? AppColors.primaryText : AppColors.inactiveText,
                            fontSize: AppFonts.sizeLG,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.plugin.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              widget.plugin.description,
                              style: TextStyle(
                                color: AppColors.disabledText,
                                fontSize: AppFonts.sizeSM,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text(
                                'v${widget.plugin.version} • ${widget.plugin.author}',
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: AppFonts.sizeXS,
                                ),
                              ),
                              if (hasExpandableSettings) ...[
                                const SizedBox(width: 12),
                                Icon(
                                  _expanded ? Icons.expand_less : Icons.chevron_right,
                                  color: _focused ? SettingsService.themeColor : Colors.white24,
                                  size: 16,
                                ),
                                Text(
                                  _expanded ? '按 → 收起设置' : '按 → 展开设置',
                                  style: TextStyle(
                                    color: _focused ? SettingsService.themeColor : Colors.white24,
                                    fontSize: AppFonts.sizeXS,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ExcludeFocus(
                    child: Switch(
                      value: _isEnabled,
                      onChanged: (value) {
                        setState(() {
                          _isEnabled = value;
                          if (!value) _expanded = false;
                        });
                        widget.onToggle(widget.plugin, value);
                      },
                      activeTrackColor: const Color(0xFF81C784).withValues(alpha: 0.5),
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
        ),

        // ── 展开的设置内容 ──
        if (_expanded && hasExpandableSettings)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: widget.plugin.settingsWidget!,
          ),
      ],
    );
  }
}
