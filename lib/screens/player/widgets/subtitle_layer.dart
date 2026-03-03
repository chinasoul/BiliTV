import 'package:flutter/material.dart';
import 'package:bili_tv_app/config/app_style.dart';

class SubtitleLayer extends StatelessWidget {
  final String text;
  final bool showControls;

  const SubtitleLayer({
    super.key,
    required this.text,
    required this.showControls,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 56,
      right: 56,
      bottom: showControls ? 128 : 52,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppFonts.sizeXXL,
                fontWeight: AppFonts.medium,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
