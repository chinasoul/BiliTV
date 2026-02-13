import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late int _focusedIndex;

  @override
  void initState() {
    super.initState();
    // Find initial index based on current quality
    final index = widget.qualities.indexWhere(
      (q) => q['qn'] == widget.currentQuality,
    );
    _focusedIndex = index != -1 ? index : 0;

    // Scroll to focused item after layout
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
    if (!_scrollController.hasClients) return;
    const itemHeight = 56.0; // ListTile default height approx
    final offset = _focusedIndex * itemHeight;
    final viewport = _scrollController.position.viewportDimension;

    // Simple centering logic or ensure visible
    if (offset < _scrollController.offset ||
        offset + itemHeight > _scrollController.offset + viewport) {
      _scrollController.jumpTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_focusedIndex > 0) {
            setState(() => _focusedIndex--);
            _scrollToFocused();
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_focusedIndex < widget.qualities.length - 1) {
            setState(() => _focusedIndex++);
            _scrollToFocused();
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onSelect(widget.qualities[_focusedIndex]['qn']);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '画质',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
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
                    color: isFocused
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.transparent,
                    child: ListTile(
                      title: Text(
                        q['desc'] ?? '${q['qn']}P',
                        style: TextStyle(
                          color: isCurrent
                              ? const Color(0xFF81C784)
                              : Colors.white,
                          fontWeight: isCurrent || isFocused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check, color: Color(0xFF81C784))
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
