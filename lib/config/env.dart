/// 环境配置
class Env {
  /// GitHub 仓库（格式: owner/repo）
  /// 例如: chinasoul/BT
  static const String githubRepo = 'chinasoul/BT';

  /// GitHub Token（可选）
  /// 不填也可用；若频繁请求触发 rate limit，可配置 token
  static const String githubToken = '';

  /// Gitee 仓库（格式: owner/repo）
  /// 用于中国大陆用户的备用下载源，留空则不使用 Gitee
  /// 例如: chinasoul/BT
  static const String giteeRepo = 'chinasoul/BT';

  /// Gitee 私人令牌（可选）
  /// 公开仓库不需要；私有仓库需配置
  static const String giteeToken = '';

  /// 哀悼模式远程配置 URL（按顺序回退）。
  /// 当前建议顺序：GitHub Raw -> Gitee Raw -> 其他备用源（OSS/COS/CDN）。
  static const List<String> mourningModeConfigUrls = [
    'https://raw.githubusercontent.com/chinasoul/BT/main/configs/mourning-config.json',
    'https://gitee.com/chinasoul/BT/raw/main/configs/mourning-config.json',
  ];
}
