/// 环境配置
class Env {
  /// GitHub 仓库（格式: owner/repo）
  /// 例如: chinasoul/BiliTV
  static const String githubRepo = 'chinasoul/BiliTV';

  /// GitHub Token（可选）
  /// 不填也可用；若频繁请求触发 rate limit，可配置 token
  static const String githubToken = '';
}
