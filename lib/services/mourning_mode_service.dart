import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import '../utils/server_time.dart';

class MourningPeriod {
  final DateTime? startAt;
  final DateTime? endAt;

  const MourningPeriod({required this.startAt, required this.endAt});

  factory MourningPeriod.fromJson(Map<String, dynamic> json) {
    return MourningPeriod(
      startAt: MourningModeConfig.parseDateTime(json['start_at']),
      endAt: MourningModeConfig.parseDateTime(json['end_at']),
    );
  }

  bool contains(DateTime now) {
    final hasStart = startAt != null;
    final hasEnd = endAt != null;
    if (!hasStart && !hasEnd) return false;
    if (hasStart && now.isBefore(startAt!)) return false;
    if (hasEnd && now.isAfter(endAt!)) return false;
    return true;
  }
}

class MourningModeConfig {
  final int version;
  final bool? forceGrayscale;
  final DateTime? startAt;
  final DateTime? endAt;
  final List<MourningPeriod> fixedPeriods;
  final List<MourningPeriod> customPeriods;
  final DateTime? updatedAt;
  final String sourceUrl;

  const MourningModeConfig({
    required this.version,
    required this.forceGrayscale,
    required this.startAt,
    required this.endAt,
    required this.fixedPeriods,
    required this.customPeriods,
    required this.updatedAt,
    required this.sourceUrl,
  });

  factory MourningModeConfig.fromJson(
    Map<String, dynamic> json, {
    required String sourceUrl,
  }) {
    final fixedDates = _parseFixedDates(json['fixed_dates']);
    final fixedPeriods = _parsePeriods(json['fixed_periods']);
    final customPeriods = _parsePeriods(json['custom_periods']);
    return MourningModeConfig(
      version: parseVersion(json['version']),
      forceGrayscale: parseBool(json['force_grayscale']),
      startAt: parseDateTime(json['start_at']),
      endAt: parseDateTime(json['end_at']),
      fixedPeriods: [...fixedDates, ...fixedPeriods],
      customPeriods: customPeriods,
      updatedAt: parseDateTime(json['updated_at']),
      sourceUrl: sourceUrl,
    );
  }

  bool isActiveAt(DateTime now) {
    final forced = forceGrayscale;
    if (forced != null) return forced;
    final legacy = MourningPeriod(startAt: startAt, endAt: endAt);
    if (legacy.contains(now)) return true;
    for (final period in fixedPeriods) {
      if (period.contains(now)) return true;
    }
    for (final period in customPeriods) {
      if (period.contains(now)) return true;
    }
    return false;
  }

  static int parseVersion(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) {
      return int.tryParse(raw.trim()) ?? 0;
    }
    return 0;
  }

  static bool? parseBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  static DateTime? parseDateTime(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  static List<MourningPeriod> _parsePeriods(dynamic raw) {
    if (raw is! List) return const [];
    final result = <MourningPeriod>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final period = MourningPeriod.fromJson(map);
      if (period.startAt == null && period.endAt == null) continue;
      result.add(period);
    }
    return result;
  }

  static List<MourningPeriod> _parseFixedDates(dynamic raw) {
    if (raw is! List) return const [];
    final result = <MourningPeriod>[];
    for (final item in raw) {
      if (item is! String) continue;
      final date = _parseDateOnly(item);
      if (date == null) continue;
      final start = DateTime(date.year, date.month, date.day, 0, 0, 0);
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
      result.add(MourningPeriod(startAt: start, endAt: end));
    }
    return result;
  }

  static DateTime? _parseDateOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

/// 远程哀悼模式服务：
/// - 支持多 URL 依次回退（建议 GitHub -> Gitee -> 备源）
/// - 本地缓存最后一次成功配置，离线可继续生效
/// - 定时轮询拉取，实时切换全局灰度开关
class MourningModeService {
  static const String _cacheConfigJsonKey = 'mourning_mode_cached_json';
  static const String _cacheVersionKey = 'mourning_mode_cached_version';
  static const String _lastFetchAtKey = 'mourning_mode_last_fetch_at';
  static const String _cacheSourceUrlKey = 'mourning_mode_cached_source_url';

  static const Duration _requestTimeout = Duration(seconds: 3);
  static const Duration _fetchInterval = Duration(minutes: 10);
  static const Duration _statusEvalInterval = Duration(minutes: 1);
  static const int _maxFetchJitterSeconds = 10;
  static final Random _random = Random();

  static final ValueNotifier<bool> _enabledNotifier = ValueNotifier(false);
  static ValueListenable<bool> get enabledListenable => _enabledNotifier;
  static bool get enabled => _enabledNotifier.value;

  static SharedPreferences? _prefs;
  static MourningModeConfig? _config;
  static Timer? _statusEvalTimer;
  static Timer? _remoteFetchTimer;
  static bool _refreshing = false;
  static bool _lifecycleRegistered = false;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _restoreCachedConfig();
    _registerLifecycleObserver();
    _startTimers();
    unawaited(refreshRemoteConfig(force: true));
  }

  static Future<void> refreshRemoteConfig({bool force = false}) async {
    await initPrefsIfNeeded();
    if (_refreshing) return;
    if (!force && !_shouldFetchNow()) return;

    _refreshing = true;
    try {
      final urls = _candidateUrls;
      if (urls.isEmpty) return;

      for (final url in urls) {
        final result = await _fetchOne(url);
        if (result == null) continue;

        final cachedVersion = _prefs!.getInt(_cacheVersionKey) ?? 0;
        if (result.version < cachedVersion) {
          continue;
        }

        _config = result;
        _setEnabled(result.isActiveAt(DateTime.now()));
        await _saveConfig(result);
        await _prefs!.setInt(_lastFetchAtKey, DateTime.now().millisecondsSinceEpoch);
        return;
      }

      await _prefs!.setInt(_lastFetchAtKey, DateTime.now().millisecondsSinceEpoch);
    } finally {
      _refreshing = false;
    }
  }

  static List<String> get _candidateUrls {
    return Env.mourningModeConfigUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static Future<MourningModeConfig?> _fetchOne(String rawUrl) async {
    try {
      final baseUri = Uri.parse(rawUrl);
      final qp = Map<String, String>.from(baseUri.queryParameters);
      qp['_ts'] = DateTime.now().millisecondsSinceEpoch.toString();
      final uri = baseUri.replace(queryParameters: qp);
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      ).timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      ServerTime.updateFromHeader(response.headers['date']);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      return MourningModeConfig.fromJson(decoded, sourceUrl: rawUrl);
    } catch (_) {
      return null;
    }
  }

  static Future<void> initPrefsIfNeeded() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static bool _shouldFetchNow() {
    final last = _prefs?.getInt(_lastFetchAtKey) ?? 0;
    if (last <= 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= _fetchInterval.inMilliseconds;
  }

  static void _restoreCachedConfig() {
    final raw = _prefs?.getString(_cacheConfigJsonKey);
    if (raw == null || raw.isEmpty) {
      _setEnabled(false);
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _setEnabled(false);
        return;
      }
      final sourceUrl = _prefs?.getString(_cacheSourceUrlKey) ?? '';
      _config = MourningModeConfig.fromJson(decoded, sourceUrl: sourceUrl);
      _setEnabled(_config!.isActiveAt(DateTime.now()));
    } catch (_) {
      _setEnabled(false);
    }
  }

  static Future<void> _saveConfig(MourningModeConfig config) async {
    final raw = <String, dynamic>{
      'version': config.version,
      'force_grayscale': config.forceGrayscale,
      'start_at': config.startAt?.toIso8601String(),
      'end_at': config.endAt?.toIso8601String(),
      'fixed_periods': config.fixedPeriods
          .map(
            (e) => {
              'start_at': e.startAt?.toIso8601String(),
              'end_at': e.endAt?.toIso8601String(),
            },
          )
          .toList(),
      'custom_periods': config.customPeriods
          .map(
            (e) => {
              'start_at': e.startAt?.toIso8601String(),
              'end_at': e.endAt?.toIso8601String(),
            },
          )
          .toList(),
      'updated_at': config.updatedAt?.toIso8601String(),
    };
    await _prefs!.setString(_cacheConfigJsonKey, jsonEncode(raw));
    await _prefs!.setInt(_cacheVersionKey, config.version);
    await _prefs!.setString(_cacheSourceUrlKey, config.sourceUrl);
  }

  static void _startTimers() {
    _statusEvalTimer?.cancel();
    _stopRemoteFetchTimer();

    _statusEvalTimer = Timer.periodic(_statusEvalInterval, (_) {
      final cfg = _config;
      if (cfg == null) return;
      _setEnabled(cfg.isActiveAt(DateTime.now()));
    });

    _startRemoteFetchTimer();
  }

  static void _startRemoteFetchTimer() {
    _remoteFetchTimer?.cancel();
    _remoteFetchTimer = Timer.periodic(_fetchInterval, (_) {
      unawaited(_refreshRemoteConfigWithJitter());
    });
  }

  static Future<void> _refreshRemoteConfigWithJitter() async {
    // 为周期轮询增加轻微随机抖动，降低设备在同一秒请求远端配置的概率。
    final delaySeconds = _random.nextInt(_maxFetchJitterSeconds + 1);
    if (delaySeconds > 0) {
      await Future<void>.delayed(Duration(seconds: delaySeconds));
    }
    await refreshRemoteConfig();
  }

  static void _stopRemoteFetchTimer() {
    _remoteFetchTimer?.cancel();
    _remoteFetchTimer = null;
  }

  static void _registerLifecycleObserver() {
    if (_lifecycleRegistered) return;
    WidgetsBinding.instance.addObserver(_MourningLifecycleObserver());
    _lifecycleRegistered = true;
  }

  static void onAppLifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startRemoteFetchTimer();
        unawaited(refreshRemoteConfig(force: true));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopRemoteFetchTimer();
        break;
    }
  }

  static void _setEnabled(bool enabled) {
    if (_enabledNotifier.value == enabled) return;
    _enabledNotifier.value = enabled;
  }

  static List<double> get grayscaleMatrix => const <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

class _MourningLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    MourningModeService.onAppLifecycleChanged(state);
  }
}
