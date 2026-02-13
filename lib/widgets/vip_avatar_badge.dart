import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class VipAvatarBadge extends StatelessWidget {
  final Widget child;
  final double size; // 头像的总大小 (宽/高)

  const VipAvatarBadge({super.key, required this.child, required this.size});

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isVip) {
      return child;
    }

    // Badge 的大小相对于头像大小的比例
    final badgeSize = size * 0.35;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: const Color(0xFF81C784), // B站粉
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 1.5, // 白色描边
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '大',
              style: TextStyle(
                color: Colors.white,
                fontSize: badgeSize * 0.7, // 字号根据 badge 大小动态调整
                fontWeight: FontWeight.bold,
                height: 1.1, // 微调行高以垂直居中
              ),
            ),
          ),
        ),
      ],
    );
  }
}
