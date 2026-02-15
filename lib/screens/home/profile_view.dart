import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/vip_avatar_badge.dart';
import '../../widgets/time_display.dart';

/// 个人资料页面 (登录后显示)
class ProfileView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback onLogout;

  const ProfileView({
    super.key,
    this.sidebarFocusNode,
    required this.onLogout,
  });

  @override
  State<ProfileView> createState() => ProfileViewState();
}

class ProfileViewState extends State<ProfileView> {
  late FocusNode _logoutFocusNode;

  @override
  void initState() {
    super.initState();
    _logoutFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _logoutFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmDialog('确认退出', '确定要退出登录吗？');
    if (confirmed) {
      widget.onLogout();
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
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child:
                Text('确认', style: TextStyle(color: SettingsService.themeColor)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[700],
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, size: 48, color: Colors.white54),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 头像
                if (AuthService.face != null && AuthService.face!.isNotEmpty)
                  VipAvatarBadge(
                    size: 80,
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: AuthService.face!,
                        cacheManager: BiliCacheManager.instance,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _buildDefaultAvatar(),
                        errorWidget: (_, _, _) => _buildDefaultAvatar(),
                      ),
                    ),
                  )
                else
                  _buildDefaultAvatar(),
                const SizedBox(height: 16),

                // 用户名
                Text(
                  AuthService.uname ?? '已登录',
                  style: TextStyle(
                    color: AuthService.isVip
                        ? SettingsService.themeColor
                        : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),

                // UID
                Text(
                  'UID: ${AuthService.mid ?? ""}',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),

                // 占位：粉丝 / 关注 / 获赞
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatItem('关注', '--'),
                    const SizedBox(width: 40),
                    _buildStatItem('粉丝', '--'),
                    const SizedBox(width: 40),
                    _buildStatItem('获赞', '--'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '个人空间信息将在后续版本完善',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 40),

                // 退出登录按钮
                Focus(
                  focusNode: _logoutFocusNode,
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.select) {
                      _handleLogout();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      widget.sidebarFocusNode?.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final isFocused = Focus.of(context).hasFocus;
                      return GestureDetector(
                        onTap: _handleLogout,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isFocused
                                ? Colors.red
                                : Colors.red.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: isFocused
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                          child: Text(
                            '退出登录',
                            style: TextStyle(
                              color:
                                  isFocused ? Colors.white : Colors.red[300],
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // 常驻时间显示
        const Positioned(top: 10, right: 14, child: TimeDisplay()),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}
