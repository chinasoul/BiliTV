import 'package:flutter/material.dart';
import 'search/search_keyboard_view.dart';
import 'search/search_results_view.dart';

/// 搜索 Tab
class SearchTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onBackToHome; // 搜索键盘界面按返回 → 回主页
  final bool Function()? shouldHandleBack; // 返回 true 表示搜索结果界面，HomeScreen 不处理返回

  const SearchTab({
    super.key,
    this.sidebarFocusNode,
    this.onBackToHome,
    this.shouldHandleBack,
  });

  @override
  State<SearchTab> createState() => SearchTabState();
}

// 公开状态类，以便 HomeScreen 可以调用 handleBack
class SearchTabState extends State<SearchTab> {
  String _searchText = '';
  bool _showResults = false; // true: 显示视频结果, false: 显示建议
  final GlobalKey<SearchKeyboardViewState> _searchKeyboardKey =
      GlobalKey<SearchKeyboardViewState>();

  // 防止返回键重复处理
  DateTime? _lastBackHandled;

  /// 处理返回键，返回 true 表示已处理（结果界面回到键盘），返回 false 表示未处理（应该回主页）
  bool handleBack() {
    // 如果刚刚被 TvVideoCard.onBack 处理过, 不再重复处理
    if (_lastBackHandled != null &&
        DateTime.now().difference(_lastBackHandled!) <
            const Duration(milliseconds: 100)) {
      return true; // 已处理，不要再跳主页
    }

    if (_showResults) {
      // 结果界面 → 回到键盘
      _backToKeyboard();
      return true;
    }
    // 键盘界面 → 让 HomeScreen 处理（回主页）
    return false;
  }

  void _backToKeyboard() {
    _lastBackHandled = DateTime.now(); // 记录处理时间，防止重复
    setState(() {
      _showResults = false;
      // _searchText remains to show what was searched, allowing modification
    });
  }

  void _onSearch(String query) {
    setState(() {
      _searchText = query;
      _showResults = true;
    });
  }

  void focusSearchInput() {
    if (_showResults) {
      _backToKeyboard();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchKeyboardKey.currentState?.focusSearchInput();
      });
      return;
    }
    _searchKeyboardKey.currentState?.focusSearchInput();
  }

  void focusDefaultEntry() {
    if (_showResults) {
      _backToKeyboard();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchKeyboardKey.currentState?.focusDefaultEntry();
      });
      return;
    }
    _searchKeyboardKey.currentState?.focusDefaultEntry();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _showResults
            ? SearchResultsView(
                query: _searchText,
                sidebarFocusNode: widget.sidebarFocusNode,
                onBackToKeyboard: _backToKeyboard,
              )
            : SearchKeyboardView(
                key: _searchKeyboardKey,
                sidebarFocusNode: widget.sidebarFocusNode,
                onBackToHome: widget.onBackToHome,
                onSearch: _onSearch,
              ),
      ],
    );
  }
}
