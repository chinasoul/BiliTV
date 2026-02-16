import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 全局内存/CPU 监控覆盖层
/// 始终显示在屏幕最上层，用于调试
class GlobalMemoryOverlay extends StatefulWidget {
  final Widget child;

  const GlobalMemoryOverlay({super.key, required this.child});

  @override
  State<GlobalMemoryOverlay> createState() => _GlobalMemoryOverlayState();
}

class _GlobalMemoryOverlayState extends State<GlobalMemoryOverlay> {
  Timer? _memoryTimer;
  String _appMem = '';
  String _availMem = '';
  String _totalMem = '';
  String _cpuUsage = '';
  int _prevProcessJiffies = 0;
  DateTime? _prevCpuSampleTime;

  @override
  void initState() {
    super.initState();
    SettingsService.onShowMemoryInfoChanged = _syncSetting;
    // 尝试初始化（如果 SettingsService 已就绪）
    _syncSetting();
  }

  @override
  void dispose() {
    _memoryTimer?.cancel();
    SettingsService.onShowMemoryInfoChanged = null;
    super.dispose();
  }

  void _syncSetting() {
    final enabled = SettingsService.showMemoryInfo;
    if (enabled && _memoryTimer == null) {
      _startMonitor();
    } else if (!enabled && _memoryTimer != null) {
      _stopMonitor();
    }
  }

  void _startMonitor() {
    _updateMemory();
    _memoryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateMemory(),
    );
  }

  void _stopMonitor() {
    _memoryTimer?.cancel();
    _memoryTimer = null;
    if (mounted) {
      setState(() {
        _appMem = '';
        _availMem = '';
        _totalMem = '';
        _cpuUsage = '';
      });
    }
    _prevProcessJiffies = 0;
    _prevCpuSampleTime = null;
  }

  void _updateMemory() {
    try {
      // App 占用: 从 /proc/self/statm 读取 RSS（第2个字段，单位为页）
      final statm = File('/proc/self/statm').readAsStringSync();
      final pages = int.tryParse(statm.split(' ')[1]) ?? 0;
      final appMb = (pages * 4096 / (1024 * 1024)).toStringAsFixed(0);

      // 系统总内存 / 可用内存: 从 /proc/meminfo 读取
      final meminfo = File('/proc/meminfo').readAsStringSync();
      final totalMatch = RegExp(r'MemTotal:\s+(\d+)').firstMatch(meminfo);
      final availMatch = RegExp(r'MemAvailable:\s+(\d+)').firstMatch(meminfo);
      final totalKb = int.tryParse(totalMatch?.group(1) ?? '') ?? 0;
      final availKb = int.tryParse(availMatch?.group(1) ?? '') ?? 0;
      final totalMb = (totalKb / 1024).toStringAsFixed(0);
      final availMb = (availKb / 1024).toStringAsFixed(0);

      // CPU 占用: 从 /proc/self/stat 读取 utime + stime（单位为 jiffies）
      String cpuStr = _cpuUsage;
      try {
        final stat = File('/proc/self/stat').readAsStringSync();
        // comm 字段可能含空格，安全解析：找到最后一个 ')' 后再 split
        final closeParen = stat.lastIndexOf(')');
        final fields = stat.substring(closeParen + 2).split(' ');
        // fields[11] = utime, fields[12] = stime（从 state 字段后第 0 位开始）
        final utime = int.tryParse(fields[11]) ?? 0;
        final stime = int.tryParse(fields[12]) ?? 0;
        final currentJiffies = utime + stime;

        final now = DateTime.now();
        if (_prevCpuSampleTime != null && _prevProcessJiffies > 0) {
          final elapsedMs = now.difference(_prevCpuSampleTime!).inMilliseconds;
          if (elapsedMs > 0) {
            final deltaJiffies = currentJiffies - _prevProcessJiffies;
            // 每个 jiffy = 1/100 秒（CLK_TCK = 100）
            final cpuSeconds = deltaJiffies / 100;
            final elapsedSeconds = elapsedMs / 1000;
            final cpuPercent = (cpuSeconds / elapsedSeconds * 100);
            cpuStr = '${cpuPercent.toStringAsFixed(0)}%';
          }
        }
        _prevProcessJiffies = currentJiffies;
        _prevCpuSampleTime = now;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _appMem = '占${appMb}M';
          _availMem = '余${availMb}M';
          _totalMem = '共${totalMb}M';
          _cpuUsage = cpuStr;
        });
      }
    } catch (_) {
      // 非 Linux 系统忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = SettingsService.showMemoryInfo && _appMem.isNotEmpty;

    // 侧边栏宽度 = 屏幕宽度 × 5%
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth = screenWidth * 0.05;

    return Stack(
      children: [
        widget.child,
        if (showOverlay)
          Positioned(
            left: 0,
            bottom: 60, // 设置图标上方
            child: IgnorePointer(
              child: SizedBox(
                width: sidebarWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown, // 只缩小不放大
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      [
                        if (_cpuUsage.isNotEmpty) 'CPU$_cpuUsage',
                        _appMem,
                        _availMem,
                        _totalMem,
                      ].join('\n'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontFamily: 'monospace',
                        fontFeatures: [FontFeature.tabularFigures()],
                        height: 1.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
