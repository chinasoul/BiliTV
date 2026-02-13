import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../../../services/settings_service.dart';
import '../widgets/setting_action_row.dart';

class StorageSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const StorageSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  double _cacheSizeMB = 0;
  bool _isClearing = false;
  final FocusNode _buttonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  @override
  void dispose() {
    _buttonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCacheSize() async {
    final size = await SettingsService.getImageCacheSizeMB();
    if (mounted) setState(() => _cacheSizeMB = size);
  }

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    await SettingsService.clearImageCache();
    await _loadCacheSize();
    if (mounted) {
      setState(() => _isClearing = false);
      Fluttertoast.showToast(
        msg: '缓存已清除',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
      );
    }
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认', style: TextStyle(color: Color(0xFF81C784))),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingActionRow(
          label: '清除图片缓存',
          value: '${_cacheSizeMB.toStringAsFixed(1)} MB',
          buttonLabel: _isClearing ? '清除中...' : '清除',
          autofocus: true,
          focusNode: _buttonFocusNode,
          isFirst: true,
          isLast: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: _isClearing
              ? null
              : () async {
                  final confirmed = await _showConfirmDialog(
                    '确认清除',
                    '确定要清除图片缓存吗？',
                  );
                  if (confirmed) _clearCache();
                },
        ),
      ],
    );
  }
}
