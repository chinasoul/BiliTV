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

/// 更新信息模型
class UpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      versionCode: json['versionCode'] ?? 0,
      downloadUrl: json['download_url'] ?? '',
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
class UpdateService {
  static const String _githubRepoKey = 'update_github_repo';
  static const String _githubTokenKey = 'update_github_token';

  // 固定配置（可被本地设置覆盖）
  static const String defaultGitHubRepo = Env.githubRepo;
  static const String defaultGitHubToken = Env.githubToken;

  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 获取 GitHub 仓库（owner/repo）
  static String get githubRepo {
    return _prefs?.getString(_githubRepoKey) ?? defaultGitHubRepo;
  }

  /// 设置 GitHub 仓库（owner/repo）
  static Future<void> setGitHubRepo(String repo) async {
    await init();
    await _prefs!.setString(_githubRepoKey, repo);
  }

  /// 获取 GitHub Token
  static String get githubToken {
    return _prefs?.getString(_githubTokenKey) ?? defaultGitHubToken;
  }

  /// 设置 GitHub Token
  static Future<void> setGitHubToken(String token) async {
    await init();
    await _prefs!.setString(_githubTokenKey, token);
  }

  static bool get _isRepoConfigured => githubRepo.trim().isNotEmpty;

  static Map<String, String> _githubHeaders({bool asJson = false}) {
    final headers = <String, String>{
      'User-Agent': 'BiliTV-UpdateChecker',
      if (asJson) 'Accept': 'application/vnd.github+json',
    };
    final token = githubToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 获取设备 CPU 架构
  static String _getDeviceArch() {
    // Android 设备架构检测
    // arm64-v8a 对应 64 位 ARM
    // armeabi-v7a 对应 32 位 ARM
    final arch = Platform.version;
    if (arch.contains('arm64') || arch.contains('aarch64')) {
      return 'arm64-v8a';
    } else if (arch.contains('arm')) {
      return 'armeabi-v7a';
    }
    // 默认返回 arm64-v8a
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

    final archKeywords = arch == 'armeabi-v7a'
        ? ['armeabi-v7a', 'armv7', 'armeabi']
        : ['arm64-v8a', 'arm64', 'aarch64'];

    for (final asset in apkAssets) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (archKeywords.any(name.contains)) {
        return (asset['browser_download_url'] ?? '').toString();
      }
    }

    // 若没有显式架构后缀，兜底使用第一个 apk 资产
    return (apkAssets.first['browser_download_url'] ?? '').toString();
  }

  /// 检查更新
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      await init();

      if (!_isRepoConfigured) {
        return UpdateCheckResult(hasUpdate: false, error: '未配置 GitHub 仓库');
      }

      // 获取 GitHub latest release 信息
      final latestReleaseUrl = 'https://api.github.com/repos/$githubRepo/releases/latest';
      final response = await http
          .get(
            Uri.parse(latestReleaseUrl),
            headers: _githubHeaders(asJson: true),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        return UpdateCheckResult(
          hasUpdate: false,
          error: '未找到 Release（请先发布 release）',
        );
      }

      if (response.statusCode == 403) {
        return UpdateCheckResult(
          hasUpdate: false,
          error: 'GitHub API 访问受限（可能触发频率限制）',
        );
      }

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          error: 'GitHub 响应错误: ${response.statusCode}',
        );
      }

      final release = Map<String, dynamic>.from(jsonDecode(response.body));
      if ((release['draft'] ?? false) == true) {
        return UpdateCheckResult(hasUpdate: false, error: '当前 latest 是草稿 release');
      }

      final tagName = _normalizeVersion((release['tag_name'] ?? '').toString());
      if (tagName.isEmpty) {
        return UpdateCheckResult(hasUpdate: false, error: 'Release 缺少 tag_name');
      }

      // 获取当前 App 版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 比较版本号（支持 tag: v1.2.3 或 v1.2.3+4）
      final hasUpdate = _compareVersion(tagName, currentVersion) > 0;
      if (!hasUpdate) {
        return UpdateCheckResult(hasUpdate: false, updateInfo: null);
      }

      final arch = _getDeviceArch();
      final assets = (release['assets'] as List?) ?? const [];
      final apkUrl = _pickApkAssetUrl(assets, arch);
      if (apkUrl == null || apkUrl.isEmpty) {
        return UpdateCheckResult(
          hasUpdate: false,
          error: 'Release 中未找到可下载的 APK 资产',
        );
      }

      final updateInfo = UpdateInfo(
        version: tagName,
        versionCode: 0,
        downloadUrl: apkUrl,
        changelog: (release['body'] ?? '').toString(),
        forceUpdate: false,
      );

      return UpdateCheckResult(hasUpdate: true, updateInfo: updateInfo);
    } catch (e) {
      return UpdateCheckResult(hasUpdate: false, error: '检查更新失败: $e');
    }
  }

  /// 下载并安装更新
  static Future<void> downloadAndInstall(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
    Function(String)? onError,
    VoidCallback? onComplete,
  }) async {
    try {
      await init();

      // 请求存储权限
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        // 部分 Android 版本 (11+) 不需要 WRITE_EXTERNAL_STORAGE，而是 scoped storage
        // 但为了兼容旧版本，还是建议请求。如果请求失败，尝试继续（以防是 scoped storage 的情况）
        // 或者请求 REQUEST_INSTALL_PACKAGES (在安装时会触发)

        // 尝试请求 manageExternalStorage (Android 11+)
        if (await Permission.manageExternalStorage.isGranted == false) {
          // 简单的兼容处理: 即使 denied 也尝试继续，因为可能是 Scoped Storage
        }
      }

      // 下载 GitHub Release 资产 APK
      final request = http.Request('GET', Uri.parse(updateInfo.downloadUrl));
      request.headers.addAll(_githubHeaders());

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        onError?.call('下载失败: ${streamedResponse.statusCode}');
        return;
      }

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

      final apkFile = File('${dir.path}/bilitv_update.apk');
      await apkFile.writeAsBytes(bytes);

      // 通知下载完成
      onComplete?.call();

      // 稍等一下确保文件写入完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 调用 Android Intent 安装 APK
      await _installApk(apkFile.path);
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
      // 如果原生方法不存在，使用备用方案
      throw Exception('安装 APK 需要原生代码支持: $e');
    }
  }

  /// 获取当前版本信息
  static Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return '${packageInfo.version} (${packageInfo.buildNumber})';
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
            onPressed: () {
              Navigator.of(context).pop();
              onUpdate?.call();
            },
            child: const Text(
              '立即更新',
              style: TextStyle(color: Color(0xFFfb7299)),
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
          setState(() => _error = error);
        }
      },
      onComplete: () {
        if (mounted) {
          // 下载完成，关闭对话框，系统会弹出安装界面
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('正在下载更新', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ] else ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭', style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}
