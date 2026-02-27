import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/env.dart';
import 'settings_service.dart';

/// 更新信息模型
class UpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final List<String> fallbackUrls;
  final String changelog;
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    this.fallbackUrls = const [],
    required this.changelog,
    required this.forceUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      versionCode: json['versionCode'] ?? 0,
      downloadUrl: json['download_url'] ?? '',
      fallbackUrls: (json['fallback_urls'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      changelog: json['changelog'] ?? '',
      forceUpdate: json['force_update'] ?? false,
    );
  }
}

/// 更新检查结果
class UpdateCheckResult {
  final bool hasUpdate;
  final UpdateInfo? updateInfo;
  final String? error;

  UpdateCheckResult({required this.hasUpdate, this.updateInfo, this.error});
}

/// 更新服务
///
/// 更新源优先级：GitHub → Gitee → GitHub 代理镜像
/// 对用户完全透明，无需任何配置
class UpdateService {
  // ============ GitHub 配置 ============
  static const String _githubRepoKey = 'update_github_repo';
  static const String _githubTokenKey = 'update_github_token';

  static const String defaultGitHubRepo = Env.githubRepo;
  static const String defaultGitHubToken = Env.githubToken;

  // ============ Gitee 配置 ============
  static const String _giteeRepoKey = 'update_gitee_repo';
  static const String _giteeTokenKey = 'update_gitee_token';

  static const String defaultGiteeRepo = Env.giteeRepo;
  static const String defaultGiteeToken = Env.giteeToken;

  // ============ GitHub 代理镜像（最后的回退手段） ============
  static const List<String> _builtinProxies = [
    'https://mirror.ghproxy.com/',
    'https://ghfast.top/',
    'https://gh-proxy.com/',
  ];

  // ============ 自动检查配置 ============
  static const String _autoCheckIntervalKey = 'update_auto_check_interval';
  static const String _lastCheckTimeKey = 'update_last_check_time';

  /// 自动检查间隔选项 & 标签
  static const List<int> autoCheckOptions = [0, 1, 3, 7];
  static const List<String> autoCheckLabels = ['关闭', '每天', '每3天', '每7天'];

  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ============ GitHub 仓库 & Token ============

  static String get githubRepo {
    return _prefs?.getString(_githubRepoKey) ?? defaultGitHubRepo;
  }

  static Future<void> setGitHubRepo(String repo) async {
    await init();
    await _prefs!.setString(_githubRepoKey, repo);
  }

  static String get githubToken {
    return _prefs?.getString(_githubTokenKey) ?? defaultGitHubToken;
  }

  static Future<void> setGitHubToken(String token) async {
    await init();
    await _prefs!.setString(_githubTokenKey, token);
  }

  // ============ Gitee 仓库 & Token ============

  static String get giteeRepo {
    return _prefs?.getString(_giteeRepoKey) ?? defaultGiteeRepo;
  }

  static Future<void> setGiteeRepo(String repo) async {
    await init();
    await _prefs!.setString(_giteeRepoKey, repo);
  }

  static String get giteeToken {
    return _prefs?.getString(_giteeTokenKey) ?? defaultGiteeToken;
  }

  static Future<void> setGiteeToken(String token) async {
    await init();
    await _prefs!.setString(_giteeTokenKey, token);
  }

  // ============ 自动检查设置 ============

  /// 自动检查间隔（天数，0 = 关闭）
  static int get autoCheckInterval {
    return _prefs?.getInt(_autoCheckIntervalKey) ?? 7;
  }

  static Future<void> setAutoCheckInterval(int days) async {
    await init();
    await _prefs!.setInt(_autoCheckIntervalKey, days);
  }

  /// 上次检查时间（毫秒时间戳）
  static int get lastCheckTime {
    return _prefs?.getInt(_lastCheckTimeKey) ?? 0;
  }

  static Future<void> _recordCheckTime() async {
    await init();
    await _prefs!.setInt(
      _lastCheckTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 是否需要自动检查更新
  static bool shouldAutoCheck() {
    final interval = autoCheckInterval;
    if (interval <= 0) return false;
    final last = lastCheckTime;
    if (last == 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= interval * 24 * 60 * 60 * 1000;
  }

  // ============ 内部工具方法 ============

  static bool get _isGitHubConfigured => githubRepo.trim().isNotEmpty;
  static bool get _isGiteeConfigured => giteeRepo.trim().isNotEmpty;

  static Map<String, String> _githubHeaders({bool asJson = false}) {
    final headers = <String, String>{
      'User-Agent': 'BT-UpdateChecker',
      if (asJson) 'Accept': 'application/vnd.github+json',
    };
    final token = githubToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 构建 Gitee API URL（将 token 附加为查询参数）
  static String _giteeApiUrl(String path) {
    final base = 'https://gitee.com/api/v5/repos/$giteeRepo/$path';
    final token = giteeToken.trim();
    if (token.isEmpty) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}access_token=$token';
  }

  /// 获取设备 CPU 架构（通过原生 MethodChannel 获取真实设备架构）
  static Future<String> _getDeviceArch() async {
    try {
      const channel = MethodChannel('com.bili.tv/device_info');
      final info = await channel.invokeMethod('getDeviceInfo');
      final abis = (info['supportedAbis'] as List?)?.cast<String>() ?? [];
      // 优先选择 64 位
      if (abis.any((abi) => abi.contains('arm64'))) {
        return 'arm64-v8a';
      }
      if (abis.any((abi) => abi.contains('armeabi'))) {
        return 'armeabi-v7a';
      }
      if (abis.isNotEmpty) return abis.first;
    } catch (_) {
      // MethodChannel 失败时回退到 Dart VM 检测
    }
    final arch = Platform.version;
    if (arch.contains('arm64') || arch.contains('aarch64')) {
      return 'arm64-v8a';
    } else if (arch.contains('arm')) {
      return 'armeabi-v7a';
    }
    return 'arm64-v8a';
  }

  static String _normalizeVersion(String raw) {
    final s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      return s.substring(1);
    }
    return s;
  }

  static List<int> _parseVersion(String raw) {
    final normalized = _normalizeVersion(raw);
    final core = normalized.split('+').first; // 忽略 +build，仅比较主版本
    final coreNums = core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (coreNums.length < 3) {
      coreNums.add(0);
    }
    return [coreNums[0], coreNums[1], coreNums[2]];
  }

  static int _compareVersion(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] > pb[i]) return 1;
      if (pa[i] < pb[i]) return -1;
    }
    return 0;
  }

  /// 优先从 release body 中提取 APK 下载链接（如 R2 镜像链接）
  static String? _pickApkUrlFromBody(String body, String arch) {
    if (body.trim().isEmpty) return null;

    final urlRegex = RegExp(
      r'https?://[^\s\)\]\}<>"]+\.apk(?:\?[^\s\)\]\}<>"]*)?',
      caseSensitive: false,
    );
    final matches = urlRegex.allMatches(body).map((m) => m.group(0)!).toList();
    if (matches.isEmpty) return null;

    final candidates = <String>{};
    for (final url in matches) {
      candidates.add(url);
    }
    final urls = candidates.toList();

    final archPattern = arch == 'armeabi-v7a'
        ? RegExp(r'v7|armeabi|arm.?32', caseSensitive: false)
        : RegExp(r'v8|arm64|aarch64', caseSensitive: false);

    for (final url in urls) {
      final uri = Uri.tryParse(url);
      final fileName = uri?.pathSegments.isNotEmpty == true
          ? uri!.pathSegments.last
          : '';
      if (archPattern.hasMatch(url) || archPattern.hasMatch(fileName)) {
        return url;
      }
    }

    return urls.first;
  }

  static String? _pickApkAssetUrl(
    List<dynamic> assets,
    String arch,
  ) {
    final apkAssets = assets
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((asset) {
          final name = (asset['name'] ?? '').toString().toLowerCase();
          final url = (asset['browser_download_url'] ?? '').toString();
          return name.endsWith('.apk') && url.isNotEmpty;
        })
        .toList();

    if (apkAssets.isEmpty) return null;

    // 用正则模糊匹配，无需枚举所有命名变体
    final archPattern = arch == 'armeabi-v7a'
        ? RegExp(r'v7|armeabi|arm.?32', caseSensitive: false)
        : RegExp(r'v8|arm64|aarch64', caseSensitive: false);

    for (final asset in apkAssets) {
      final name = (asset['name'] ?? '').toString();
      if (archPattern.hasMatch(name)) {
        return (asset['browser_download_url'] ?? '').toString();
      }
    }

    // 若没有显式架构后缀，兜底使用第一个 apk 资产
    return (apkAssets.first['browser_download_url'] ?? '').toString();
  }

  // ============ 通用 Release 检查 ============

  /// 从指定 API 端点检查更新（GitHub / Gitee 通用）
  /// 返回 null 表示该源不可用，调用方应尝试下一个源
  static Future<UpdateCheckResult?> _checkRelease(
    String apiUrl,
    Map<String, String> headers, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await http
          .get(Uri.parse(apiUrl), headers: headers)
          .timeout(timeout);

      if (response.statusCode != 200) return null;

      final release = Map<String, dynamic>.from(jsonDecode(response.body));
      if ((release['draft'] ?? false) == true) return null;

      final tagName =
          _normalizeVersion((release['tag_name'] ?? '').toString());
      if (tagName.isEmpty) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final hasUpdate = _compareVersion(tagName, currentVersion) > 0;

      if (!hasUpdate) {
        return UpdateCheckResult(hasUpdate: false);
      }

      final arch = await _getDeviceArch();
      final body = (release['body'] ?? '').toString();
      final bodyApkUrl = _pickApkUrlFromBody(body, arch);
      final assets = (release['assets'] as List?) ?? const [];
      final assetApkUrl = _pickApkAssetUrl(assets, arch);
      final apkUrl = bodyApkUrl ?? assetApkUrl;
      if (apkUrl == null || apkUrl.isEmpty) return null;

      // body 链接优先；若主链接不可达，立即回退到 assets
      final fallbackUrls = <String>[];
      if (assetApkUrl != null &&
          assetApkUrl.isNotEmpty &&
          assetApkUrl != apkUrl &&
          !fallbackUrls.contains(assetApkUrl)) {
        fallbackUrls.add(assetApkUrl);
      }

      return UpdateCheckResult(
        hasUpdate: true,
        updateInfo: UpdateInfo(
          version: tagName,
          versionCode: 0,
          downloadUrl: apkUrl,
          fallbackUrls: fallbackUrls,
          changelog: body,
          forceUpdate: false,
        ),
      );
    } catch (_) {
      return null; // 连接失败，返回 null 让调用方尝试下一个源
    }
  }

  // ============ GitHub 下载代理回退 ============

  /// 为 GitHub URL 构建代理候选列表：直连 → 代理镜像
  static List<String> _buildGitHubDownloadCandidates(String githubUrl) {
    return [
      githubUrl,
      ...(_builtinProxies.map((p) => '$p$githubUrl')),
    ];
  }

  /// 流式下载 GitHub 资源（自动代理回退）
  /// 返回 (StreamedResponse, 实际使用的 URL)
  static Future<(http.StreamedResponse, String)> _downloadWithGitHubFallback(
    String githubUrl, {
    Map<String, String>? headers,
  }) async {
    final urls = _buildGitHubDownloadCandidates(githubUrl);
    Object? lastError;
    for (var i = 0; i < urls.length; i++) {
      try {
        final request = http.Request('GET', Uri.parse(urls[i]));
        if (headers != null) request.headers.addAll(headers);
        // 直连用较短超时以便快速回退
        final timeout = i == 0
            ? const Duration(seconds: 8)
            : const Duration(seconds: 15);
        final resp = await request.send().timeout(timeout);
        if (resp.statusCode == 200) return (resp, urls[i]);
        lastError = 'HTTP ${resp.statusCode} from ${urls[i]}';
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('所有下载请求均失败');
  }

  // ============ 核心业务方法 ============

  /// 检查更新（自动选择最佳源：GitHub → Gitee）
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      await init();

      if (!_isGitHubConfigured && !_isGiteeConfigured) {
        return UpdateCheckResult(hasUpdate: false, error: '未配置更新仓库');
      }

      // 1. 尝试 GitHub（短超时，不可用时快速切 Gitee）
      if (_isGitHubConfigured) {
        final result = await _checkRelease(
          'https://api.github.com/repos/$githubRepo/releases/latest',
          _githubHeaders(asJson: true),
          timeout: const Duration(seconds: 3),
        );
        if (result != null) {
          await _recordCheckTime();
          return result;
        }
      }

      // 2. 尝试 Gitee
      if (_isGiteeConfigured) {
        final result = await _checkRelease(
          _giteeApiUrl('releases/latest'),
          const {'User-Agent': 'BT-UpdateChecker'},
          timeout: const Duration(seconds: 10),
        );
        if (result != null) {
          await _recordCheckTime();
          return result;
        }
      }

      // 都不可用
      await _recordCheckTime(); // 仍然记录，避免反复重试
      final sources = [
        if (_isGitHubConfigured) 'GitHub',
        if (_isGiteeConfigured) 'Gitee',
      ].join(' 和 ');
      return UpdateCheckResult(
        hasUpdate: false,
        error: '无法连接更新服务器（$sources 均不可用）',
      );
    } catch (e) {
      return UpdateCheckResult(hasUpdate: false, error: '检查更新失败: $e');
    }
  }

  /// 下载并安装更新
  static Future<void> downloadAndInstall(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
    Function(String)? onError,
    Function(String)? onUrl,
    VoidCallback? onComplete,
  }) async {
    try {
      await init();

      // 请求存储权限
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (await Permission.manageExternalStorage.isGranted == false) {
          // 简单的兼容处理: 即使 denied 也尝试继续（scoped storage 场景）
        }
      }

      final url = updateInfo.downloadUrl;
      final fallbackUrl = updateInfo.fallbackUrls.isNotEmpty
          ? updateInfo.fallbackUrls.first
          : '';

      Future<(http.StreamedResponse, String)> startDownload(String candidate) async {
        if (candidate.contains('github.com')) {
          return _downloadWithGitHubFallback(candidate, headers: _githubHeaders());
        }
        final request = http.Request('GET', Uri.parse(candidate));
        request.headers.addAll(const {'User-Agent': 'BT-UpdateChecker'});
        final resp = await request.send().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        return (resp, candidate);
      }

      http.StreamedResponse streamedResponse;
      String actualUrl;
      try {
        (streamedResponse, actualUrl) = await startDownload(url);
      } catch (e) {
        if (fallbackUrl.isEmpty || fallbackUrl == url) {
          onError?.call('下载安装失败: $e');
          return;
        }
        try {
          (streamedResponse, actualUrl) = await startDownload(fallbackUrl);
        } catch (fallbackError) {
          onError?.call('下载安装失败: $fallbackError');
          return;
        }
      }

      onUrl?.call(actualUrl);

      final contentLength = streamedResponse.contentLength ?? 0;
      final bytes = <int>[];
      var received = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        }
      }

      // 保存到本地
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        onError?.call('无法获取存储目录');
        return;
      }

      final apkFile = File('${dir.path}/bt_update.apk');
      await apkFile.writeAsBytes(bytes);

      // 先调用系统安装 Intent，再关闭对话框
      await _installApk(apkFile.path);

      // 安装 Intent 已成功发送，关闭下载对话框
      onComplete?.call();
    } catch (e) {
      onError?.call('下载安装失败: $e');
    }
  }

  /// 调用系统安装 APK
  static Future<void> _installApk(String apkPath) async {
    const platform = MethodChannel('com.bili.tv/update');
    try {
      await platform.invokeMethod('installApk', {'path': apkPath});
    } catch (e) {
      throw Exception('安装 APK 需要原生代码支持: $e');
    }
  }

  /// 获取当前版本信息
  static Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return '${packageInfo.version} (${packageInfo.buildNumber})';
  }

  /// 自动检查更新并弹窗通知（首页启动时调用）
  static Future<void> autoCheckAndNotify(BuildContext context) async {
    if (!shouldAutoCheck()) return;
    try {
      final result = await checkForUpdate();
      if (!context.mounted) return;
      if (result.hasUpdate && result.updateInfo != null) {
        showUpdateDialog(
          context,
          result.updateInfo!,
          onUpdate: () {
            showDownloadProgress(context, result.updateInfo!);
          },
        );
      }
    } catch (_) {
      // 自动检查静默失败，不打扰用户
    }
  }

  /// 显示更新对话框
  static void showUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo, {
    VoidCallback? onUpdate,
    VoidCallback? onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          '发现新版本 ${updateInfo.version}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '更新内容:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              updateInfo.changelog,
              style: const TextStyle(color: Colors.white70),
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (!updateInfo.forceUpdate)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onCancel?.call();
              },
              child: const Text(
                '稍后再说',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          TextButton(
            autofocus: true,
            onPressed: () {
              Navigator.of(context).pop();
              onUpdate?.call();
            },
            child: Text(
              '立即更新',
              style: TextStyle(color: SettingsService.themeColor),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示下载进度对话框
  static void showDownloadProgress(
    BuildContext context,
    UpdateInfo updateInfo,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(updateInfo: updateInfo),
    );
  }
}

/// 下载进度对话框
class _DownloadProgressDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const _DownloadProgressDialog({required this.updateInfo});

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String? _error;
  bool _installing = false;
  String _downloadUrl = '';
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() {
    UpdateService.downloadAndInstall(
      widget.updateInfo,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = error;
            _installing = false;
          });
        }
      },
      onUrl: (url) {
        if (mounted) {
          setState(() {
            _downloadUrl = url;
            _connecting = false;
          });
        }
      },
      onComplete: () {
        // 安装 Intent 已发送成功，关闭对话框
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 下载完成(progress >= 1.0)但还没出错 → 正在调起安装
    if (_progress >= 1.0 && _error == null && !_installing) {
      _installing = true;
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: Text(
        _installing ? '正在启动安装...' : '正在下载更新',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ] else if (_installing) ...[
            CircularProgressIndicator(color: SettingsService.themeColor),
            const SizedBox(height: 16),
            const Text(
              '下载完成，正在调起安装...',
              style: TextStyle(color: Colors.white70),
            ),
          ] else ...[
            LinearProgressIndicator(
              value: _progress,
              color: SettingsService.themeColor,
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 16),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _connecting ? '正在连接下载源...' : _downloadUrl,
            style: TextStyle(
              color: _connecting ? Colors.white54 : Colors.white38,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭', style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}
