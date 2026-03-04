import 'package:flutter/material.dart';
import 'package:bili_tv_app/core/focus/focus_navigation.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/config/app_style.dart';

class QualityPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> qualities;
  final int currentQuality;
  final Function(int) onSelect;

  const QualityPickerSheet({
    super.key,
    required this.qualities,
    required this.currentQuality,
    required this.onSelect,
  });

  @override
  State<QualityPickerSheet> createState() => _QualityPickerSheetState();
}

class _QualityPickerSheetState extends State<QualityPickerSheet> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  late int _focusedIndex;

  @override
  void initState() {
    super.initState();
    final index = widget.qualities.indexWhere(
      (q) => q['qn'] == widget.currentQuality,
    );
    _focusedIndex = index != -1 ? index : 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToFocused();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFocused() {
    if (!mounted) return;
    final key = _itemKeys[_focusedIndex];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        return TvKeyHandler.handleNavigation(
          event,
          onUp: _focusedIndex > 0
              ? () {
                  setState(() => _focusedIndex--);
                  _scrollToFocused();
                }
              : null,
          onDown: _focusedIndex < widget.qualities.length - 1
              ? () {
                  setState(() => _focusedIndex++);
                  _scrollToFocused();
                }
              : null,
          onSelect: () =>
              widget.onSelect(widget.qualities[_focusedIndex]['qn']),
        );
      },
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '画质',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontSize: AppFonts.sizeXL,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: widget.qualities.length,
                itemBuilder: (context, index) {
                  final q = widget.qualities[index];
                  final isCurrent = q['qn'] == widget.currentQuality;
                  final isFocused = index == _focusedIndex;

                  return Container(
                    key: _itemKeys.putIfAbsent(index, () => GlobalKey()),
                    color: isFocused
                        ? AppColors.navItemSelectedBackground
                        : Colors.transparent,
                    child: ListTile(
                      title: Text(
                        q['desc'] ?? '${q['qn']}P',
                        style: TextStyle(
                          color: isCurrent
                              ? SettingsService.themeColor
                              : AppColors.primaryText,
                          fontWeight: isCurrent || isFocused
                              ? FontWeight.bold
                              : AppFonts.regular,
                        ),
                      ),
                      trailing: isCurrent
                          ? Icon(Icons.check, color: SettingsService.themeColor)
                          : null,
                      onTap: () => widget.onSelect(q['qn']),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
