import 'package:flutter/widgets.dart';

/// BT 插件基础抽象类
/// 所有插件必须继承此类
abstract class Plugin {
  /// 唯一标识符，建议使用反向域名风格，如 "com.example.plugin"
  String get id;

  /// 显示名称
  String get name;

  /// 插件描述
  String get description;

  /// 版本号
  String get version;

  /// 作者
  String get author;

  /// 插件图标 (可选)
  IconData? get icon => null;

  /// 插件启用时调用
  Future<void> onEnable() async {}

  /// 插件禁用时调用
  Future<void> onDisable() async {}

  /// 插件是否有设置界面
  bool get hasSettings => false;

  /// 插件设置界面 (可选)
  Widget? get settingsWidget => null;
}
