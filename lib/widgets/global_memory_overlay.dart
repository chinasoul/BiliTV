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
  String _appCpu = '';
  List<MapEntry<String, String>> _coreFreqLines = const [];
  int _prevProcessJiffies = 0;
  DateTime? _prevCpuSampleTime;

  static const TextStyle _overlayTextStyle = TextStyle(
    color: Color(0xFFFFC107), // amber, 比纯黄在白底上更稳
    fontSize: 9,
    fontFamily: 'monospace',
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.5,
    decoration: TextDecoration.none,
    shadows: [
      Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(0, 1)),
    ],
  );

  @override
  void initState() {
    super.initState();
    SettingsService.onShowMemoryInfoChanged = _syncSetting;
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
      const Duration(milliseconds: 500),
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
        _appCpu = '';
        _coreFreqLines = const <MapEntry<String, String>>[];
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
      String appCpu = '';
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

            // APP 整机占用率（除以核心数）
            if (SettingsService.showAppCpu) {
              final cores = Platform.numberOfProcessors;
              final appPercent = cpuPercent / cores;
              appCpu = '${appPercent.toStringAsFixed(0)}%/$cores';
            }
          }
        }
        _prevProcessJiffies = currentJiffies;
        _prevCpuSampleTime = now;
      } catch (_) {}

      // 核心频率
      List<MapEntry<String, String>> coreFreqLines = const [];
      if (SettingsService.showCoreFreq) {
        try {
          final cores = Platform.numberOfProcessors;
          final freqRows = <MapEntry<String, String>>[];
          for (int i = 0; i < cores; i++) {
            final freqFile = File(
              '/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq',
            );
            if (freqFile.existsSync()) {
              final khz = int.tryParse(freqFile.readAsStringSync().trim()) ?? 0;
              final mhz = (khz / 1000).round();
              freqRows.add(MapEntry('C$i', '${mhz}M'));
            } else {
              freqRows.add(MapEntry('C$i', '--'));
            }
          }
          coreFreqLines = freqRows;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _appMem = '${appMb}M';
          _availMem = '${availMb}M';
          _totalMem = '${totalMb}M';
          _cpuUsage = cpuStr;
          _appCpu = appCpu;
          _coreFreqLines = coreFreqLines;
        });
      }
    } catch (_) {
      // 非 Linux 系统忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = SettingsService.showMemoryInfo && _appMem.isNotEmpty;
    final baseMetrics = <MapEntry<String, String>>[
      if (_cpuUsage.isNotEmpty) MapEntry('CPU', _cpuUsage),
      MapEntry('APP', _appMem),
      MapEntry('AVL', _availMem),
      MapEntry('TOT', _totalMem),
    ];
    final extraMetrics = <MapEntry<String, String>>[
      if (_appCpu.isNotEmpty) MapEntry('PCT', _appCpu),
      ..._coreFreqLines,
    ];
    final allMetrics = <MapEntry<String, String>>[...baseMetrics, ...extraMetrics];
    final maxValueChars = allMetrics.isEmpty
        ? 0
        : allMetrics.map((e) => e.value.length).reduce((a, b) => a > b ? a : b);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (showOverlay)
          Positioned(
            left: 0,
            bottom: 60, // 设置图标上方
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 基础信息固定显示，避免可选项挤占
                        Text(
                          _formatMetricLines(baseMetrics, maxValueChars),
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: _overlayTextStyle,
                        ),
                        if (extraMetrics.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _formatMetricLines(extraMetrics, maxValueChars),
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: _overlayTextStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatMetricLines(List<MapEntry<String, String>> lines, int maxValueChars) {
    return lines
        .map(
          (line) =>
              '${line.key.padRight(3)} ${line.value.padLeft(maxValueChars)}',
        )
        .join('\n');
  }
}
