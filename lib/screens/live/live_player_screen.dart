import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api/live_api.dart';
import '../../services/live_socket_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/time_display.dart';
import 'widgets/live_settings_panel.dart';

class LivePlayerScreen extends StatefulWidget {
  final int roomId;
  final String title;
  final String? cover;
  final String? uname;
  final String? face;
  final int? online;

  const LivePlayerScreen({
    super.key,
    required this.roomId,
    required this.title,
    this.cover,
    this.uname,
    this.face,
    this.online,
  });

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  final LiveSocketService _socketService = LiveSocketService();
  DanmakuController? _danmakuController;

  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _popularityTimer;
  String _onlineCount = '0';

  // Settings State
  bool _showSettingsPanel = false;
  LiveSettingsMenuType _settingsMenuType = LiveSettingsMenuType.main;
  int _focusedSettingIndex = 0;
  // Controls: 0:Refresh, 1:Quality, 2:Line (if >1), 3:Settings
  int _focusedControlIndex = 0;

  // Danmaku Settings
  bool _danmakuEnabled = true;
  double _danmakuOpacity = 0.6;
  double _danmakuFontSize = 17.0;
  double _danmakuArea = 0.25;
  double _danmakuSpeed = 10.0;
  bool _hideTopDanmaku = false;
  bool _hideBottomDanmaku = false;

  // Line State
  final List<Map<String, dynamic>> _lines = [];
  int _currentLineIndex = 0;
  int _realRoomId = 0;

  // Quality State
  List<Map<String, dynamic>> _qualities = [];
  int _currentQuality = 10000;
  String _currentQualityDesc = '原画';

  // Follow State
  bool _isFollowed = false;
  int _anchorUid = 0;

  // Double back to exit
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    _realRoomId = widget.roomId; // Default
    // _danmakuController will be set by DanmakuScreen
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    // Initialize online count from widget
    final initialOnline = widget.online ?? 0;
    if (initialOnline >= 10000) {
      _onlineCount = '${(initialOnline / 10000).toStringAsFixed(1)}万';
    } else {
      _onlineCount = initialOnline.toString();
    }

    _loadSettings().then((_) {
      _initializePlayer();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
      _danmakuOpacity = prefs.getDouble('danmaku_opacity') ?? 0.6;
      _danmakuFontSize = prefs.getDouble('danmaku_font_size') ?? 17.0;
      _danmakuArea = prefs.getDouble('danmaku_area') ?? 0.25;
      _danmakuSpeed = prefs.getDouble('danmaku_speed') ?? 10.0;
      _hideTopDanmaku = prefs.getBool('hide_top_danmaku') ?? false;
      _hideBottomDanmaku = prefs.getBool('hide_bottom_danmaku') ?? false;

      // Live specific control bar setting
      if (SettingsService.hideLiveControlsOnStart) {
        _showControls = false;
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('danmaku_enabled', _danmakuEnabled);
    await prefs.setDouble('danmaku_opacity', _danmakuOpacity);
    await prefs.setDouble('danmaku_font_size', _danmakuFontSize);
    await prefs.setDouble('danmaku_area', _danmakuArea);
    await prefs.setDouble('danmaku_speed', _danmakuSpeed);
    await prefs.setBool('hide_top_danmaku', _hideTopDanmaku);
    await prefs.setBool('hide_bottom_danmaku', _hideBottomDanmaku);
    _updateDanmakuOption();
  }

  void _updateDanmakuOption() {
    if (_danmakuController != null) {
      _danmakuController!.updateOption(
        DanmakuOption(
          opacity: _danmakuOpacity,
          fontSize: _danmakuFontSize,
          area: _danmakuArea,
          duration: _danmakuSpeed / 1.0, // Live is always 1x speed
          hideTop: _hideTopDanmaku,
          hideBottom: _hideBottomDanmaku,
        ),
      );
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    // _danmakuController is disposed by its widget usually, or doesn't need disposal
    _socketService.dispose();
    _hideTimer?.cancel();
    _popularityTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _controller?.play();
    }
  }

  Future<void> _initializePlayer({int? qn, int? lineIndex}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 0. Resolve Real Room ID (only once)
      Map<String, dynamic>? roomInfo;
      if (_realRoomId == widget.roomId) {
        roomInfo = await LiveApi.getRoomInfo(widget.roomId);
        if (roomInfo != null && roomInfo['room_id'] != null) {
          _realRoomId = roomInfo['room_id'];
        }
      }

      // 1. 获取播放地址
      final playInfo = await LiveApi.getPlayUrl(
        _realRoomId,
        qn: qn ?? _currentQuality,
      );
      if (playInfo == null) {
        throw Exception('获取直播地址失败');
      }
      debugPrint('LivePlayer: PlayInfo Keys: ${playInfo.keys.toList()}');
      if (playInfo['quality_description'] != null) {
        debugPrint(
          'LivePlayer: Quality Desc: ${playInfo['quality_description']}',
        );
      }
      if (playInfo['playurl_info'] != null) {
        // debugPrint('LivePlayer: PlayURL Info: ${playInfo['playurl_info']}');
      }

      String url = '';
      _lines.clear();

      // Parse playurl_info for Lines (Hosts)
      if (playInfo['playurl_info'] != null) {
        final playurl = playInfo['playurl_info']['playurl'];
        final streams = playurl['stream'] as List?;
        if (streams != null) {
          int lineCounter = 1;

          // Helper to add lines from a specific protocol
          void addLinesFromProtocol(String protocol) {
            final stream = streams.firstWhere(
              (s) => s['protocol_name'] == protocol,
              orElse: () => null,
            );

            if (stream != null) {
              final formats = stream['format'] as List?;
              if (formats != null) {
                for (var format in formats) {
                  final codecs = format['codec'] as List?;
                  if (codecs != null) {
                    for (var codec in codecs) {
                      final baseUrl = codec['base_url'] as String;
                      final urlInfo = codec['url_info'] as List?;
                      // final codecName = codec['codec_name'] ?? 'avc'; // avc or hevc

                      if (urlInfo != null) {
                        for (var info in urlInfo) {
                          final host = info['host'] as String;

                          _lines.add({
                            'name': '线路$lineCounter',
                            'host': host,
                            'extra': info['extra'],
                            'base_url': baseUrl,
                          });
                          lineCounter++;
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Fetch HTTP-HLS first (stable)
          addLinesFromProtocol('http_hls');

          // Then HTTP-STREAM (flv) even if HLS exists, to maximize options
          addLinesFromProtocol('http_stream');
        }
      }

      // Select Line
      int targetLineIndex = lineIndex ?? 0;
      if (targetLineIndex >= _lines.length) targetLineIndex = 0;
      _currentLineIndex = targetLineIndex;

      if (_lines.isNotEmpty) {
        final line = _lines[_currentLineIndex];
        url = '${line['host']}${line['base_url']}${line['extra']}';
      } else {
        // Fallback to durl
        final durl = playInfo['durl'] as List?;
        if (durl != null && durl.isNotEmpty) {
          url = durl[0]['url'] as String;
          _lines.add({'name': '默认线路', 'url': url});
        }
      }

      if (url.isEmpty) {
        throw Exception('无法获取有效播放地址');
      }

      // Parse Quality Options
      if (playInfo['quality_description'] != null) {
        final list = List<Map<String, dynamic>>.from(
          playInfo['quality_description'],
        );
        debugPrint('LivePlayer: Raw Qualities: $list');
        // Filter out '默认' or invalid ones
        _qualities = list.where((q) {
          final desc = q['desc'] as String?;
          return desc != null && desc != '默认' && desc.isNotEmpty;
        }).toList();
        debugPrint('LivePlayer: Parsed Qualities: $_qualities');
      }
      if (qn != null) {
        // Optimistically update quality based on request
        _currentQuality = qn;
        debugPrint('LivePlayer: Requested Quality: $qn');
      } else if (playInfo['current_quality'] != null) {
        // Fallback to API reported quality
        _currentQuality = playInfo['current_quality'];
        debugPrint('LivePlayer: API Reported Quality: $_currentQuality');
      }

      final q = _qualities.firstWhere(
        (e) => e['qn'] == _currentQuality,
        orElse: () => {'desc': '未知($_currentQuality)'},
      );
      _currentQualityDesc = q['desc'] ?? '未知';
      debugPrint(
        'LivePlayer: Matched Desc: $_currentQualityDesc (Target: $_currentQuality)',
      );

      _currentQualityDesc = q['desc'] ?? '未知';
      debugPrint('LivePlayer: Matched Desc: $_currentQualityDesc');

      // 3. Get Anchor Info & Relationship
      if (_anchorUid == 0 && roomInfo != null) {
        _anchorUid = roomInfo['uid'] ?? 0;
      }
      if (_anchorUid > 0) {
        LiveApi.getRelation(_anchorUid).then((relation) {
          if (mounted && relation != null) {
            setState(() {
              // attribute: 1=悄悄关注, 2=关注, 6=互粉, 128=拉黑
              // simpler check: just check if attribute is not 0 (no relation)
              // But standard API returns specific fields usually.
              // Let's assume relation map has 'attribute'
              final attr = relation['attribute'] as int? ?? 0;
              _isFollowed = attr == 2 || attr == 6;
            });
          }
        });
      }

      // 4. 初始化播放器
      final oldController = _controller;

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://live.bilibili.com/',
        },
      );

      await _controller!.initialize();
      oldController?.dispose();
      await _controller!.play();

      setState(() {
        _isLoading = false;
      });

      if (!SettingsService.hideLiveControlsOnStart) {
        _startHideTimer();
      }

      // 3. 连接弹幕 (Use Real ID)
      if (!_socketService.isConnected) {
        _connectDanmaku();
      }

      // 4. Start API polling for popularity (fallback for socket)
      _startPopularityTimer();

      // 4. Start API polling for popularity (fallback for socket)
      _startPopularityTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _connectDanmaku() {
    debugPrint('Connecting Danmaku to RoomID: $_realRoomId');
    _socketService.connect(_realRoomId);
    _socketService.messageStream.listen(
      (msg) {
        if (!mounted) return;

        if (msg['type'] == 'danmaku') {
          debugPrint('LivePlayer: Received Danmaku: ${msg['content']}');
          if (_danmakuController != null && _danmakuEnabled) {
            try {
              _danmakuController!.addDanmaku(
                DanmakuContentItem(
                  msg['content'],
                  color: Color(msg['color']).withValues(alpha: 255),
                ),
              );
            } catch (e) {
              debugPrint('Error adding danmaku: $e');
            }
          } else {
            debugPrint(
              'LivePlayer: Danmaku skipped (Controller: $_danmakuController, Enabled: $_danmakuEnabled)',
            );
          }
        } else if (msg['type'] == 'popularity') {
          setState(() {
            final count = msg['count'] as int;
            // Hotfix: Bilibili heartbeat sometimes returns 1 (invalid).
            // If we have a valid count, ignore 1 to avoid UI flicker.
            if (count <= 1) return;

            if (count >= 10000) {
              _onlineCount = '${(count / 10000).toStringAsFixed(1)}万';
            } else {
              _onlineCount = count.toString();
            }
          });
        } else if (msg['type'] == 'error') {
          debugPrint('LiveSocket Error: ${msg['msg']}');
          if (mounted) {
            Fluttertoast.showToast(msg: "弹幕连接: ${msg['msg']}");
          }
        }
      },
      onError: (e) {
        debugPrint('LivePlayer: Danmaku Stream Error: $e');
      },
    );
  }

  void _hideControls() {
    if (_showSettingsPanel) return;
    setState(() => _showControls = false);
  }

  void _startHideTimer() {
    // Cancel any existing timer
    _hideTimer?.cancel();
    // Start a new timer
    _hideTimer = Timer(const Duration(seconds: 5), _hideControls);
  }

  void _startPopularityTimer() {
    _popularityTimer?.cancel();
    // Poll API every 60 seconds as a fallback
    _popularityTimer = Timer.periodic(const Duration(seconds: 60), (
      timer,
    ) async {
      try {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final info = await LiveApi.getRoomInfo(_realRoomId);
        if (info != null && mounted) {
          final online = info['online'] as int?;
          if (online != null && online > 1) {
            setState(() {
              if (online >= 10000) {
                _onlineCount = '${(online / 10000).toStringAsFixed(1)}万';
              } else {
                _onlineCount = online.toString();
              }
            });
          }
        }
      } catch (e) {
        debugPrint('Error polling popularity: $e');
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _startHideTimer(); // Reset timer on input

      if (event.logicalKey == LogicalKeyboardKey.goBack) {
        return KeyEventResult.ignored;
      }

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // if (_showSettingsPanel) handled by _handleSettingsKeyEvent below

        if (_showControls) {
          _hideControls();
          return KeyEventResult.handled;
        }
        // Let PopScope handle exit
        return KeyEventResult.ignored;
      }

      if (!_showControls) {
        // Show controls on any key press (except Back logic above)
        setState(() => _showControls = true);
        return KeyEventResult.handled;
      }

      if (_showSettingsPanel) {
        _handleSettingsKeyEvent(event);
        return KeyEventResult.handled;
      }

      // Handle Control Bar Navigation
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        setState(() {
          final maxIndex = 4; // Refresh, Follow, Quality, Line, Settings
          _focusedControlIndex = (_focusedControlIndex - 1).clamp(0, maxIndex);
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        setState(() {
          final maxIndex = 4;
          _focusedControlIndex = (_focusedControlIndex + 1).clamp(0, maxIndex);
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _handleControlSelect();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleControlSelect() async {
    final hasLines = _lines.length > 1;
    // Map dynamic index to action
    // Indices: 0:Refresh, 1:Quality, [2:Line], [2/3]:Settings
    // If hasLines: 0, 1, 2(Line), 3(Settings)
    // If not: 0, 1, 2(Settings)

    // Easier way: map focused index to Logic

    if (_focusedControlIndex == 0) {
      // Refresh
      debugPrint('Refresh clicked');
      Fluttertoast.showToast(msg: "正在刷新直播流...");
      _initializePlayer();
    } else if (_focusedControlIndex == 1) {
      // Quality (Was 2)
      setState(() {
        _showSettingsPanel = true;
        _settingsMenuType = LiveSettingsMenuType.quality;
        _focusedSettingIndex = 0;
        _hideTimer?.cancel();
      });
    } else if (_focusedControlIndex == 2) {
      // Line (Was 3)
      if (hasLines) {
        setState(() {
          _showSettingsPanel = true;
          _settingsMenuType = LiveSettingsMenuType.line;
          _focusedSettingIndex = 0;
          _hideTimer?.cancel();
        });
      } else {
        Fluttertoast.showToast(msg: "当前只有默认线路");
      }
    } else if (_focusedControlIndex == 3) {
      // Settings (Was 4)
      setState(() {
        _showSettingsPanel = true;
        _settingsMenuType = LiveSettingsMenuType.danmaku;
        _focusedSettingIndex = 0;
        _hideTimer?.cancel();
      });
    } else if (_focusedControlIndex == 4) {
      // Follow (Was 1) -> Moved to last
      if (_anchorUid == 0) {
        Fluttertoast.showToast(msg: "无法获取主播信息");
        return;
      }
      final act = _isFollowed ? 2 : 1; // 1=Follow, 2=Unfollow
      final success = await LiveApi.modifyRelation(_anchorUid, act);
      if (success) {
        setState(() {
          _isFollowed = !_isFollowed;
        });
        Fluttertoast.showToast(msg: _isFollowed ? "已关注" : "已取消关注");
      } else {
        Fluttertoast.showToast(msg: "操作失败");
      }
    }
  }

  void _handleSettingsKeyEvent(KeyDownEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
        // Special case for Danmaku settings which might have distinct focus
        // But here we just use index.
        setState(() {
          _focusedSettingIndex = (_focusedSettingIndex - 1).clamp(
            0,
            6,
          ); // 7 items
        });
        return;
      }
      setState(() {
        _focusedSettingIndex = (_focusedSettingIndex - 1).clamp(
          0,
          _getSettingsItemCount() - 1,
        );
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
        setState(() {
          _focusedSettingIndex = (_focusedSettingIndex + 1).clamp(0, 6);
        });
        return;
      }
      setState(() {
        _focusedSettingIndex = (_focusedSettingIndex + 1).clamp(
          0,
          _getSettingsItemCount() - 1,
        );
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // Left Key Logic
      if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
        // Adjust settings value
        _adjustDanmakuSetting(_focusedSettingIndex, -1);
      } else {
        // In sub-menus (Quality/Line), just close
        setState(() {
          _showSettingsPanel = false;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // Right Key Logic
      if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
        // Adjust settings value
        _adjustDanmakuSetting(_focusedSettingIndex, 1);
      }
      // For other menus, Right might imply select? Or do nothing.
    } else if (event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        // Always close panel on Back/Escape
        _showSettingsPanel = false;
        _settingsMenuType = LiveSettingsMenuType.main;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _handleSettingsSelection();
    }
  }

  void _adjustDanmakuSetting(int index, int direction) async {
    // direction: -1 (Left/Reduce), 1 (Right/Increase)
    switch (index) {
      case 0: // Enabled (Switch)
        // Left/Right doesn't usually toggle switch, Enter does.
        // But for convenience:
        // if direction matches state? No, let's keep it to Enter for toggle.
        break;
      case 1: // Opacity (Slider)
        double newVal = _danmakuOpacity + (direction * 0.1);
        newVal = newVal.clamp(0.1, 1.0);
        if (newVal != _danmakuOpacity) {
          setState(() => _danmakuOpacity = newVal);
          await _saveSettings();
        }
        break;
      case 2: // Font Size (Slider)
        double newVal = _danmakuFontSize + (direction * 1.0);
        newVal = newVal.clamp(10.0, 30.0);
        if (newVal != _danmakuFontSize) {
          setState(() => _danmakuFontSize = newVal);
          await _saveSettings();
        }
        break;
      case 3: // Area (Slider)
        const areas = [0.125, 0.25, 0.5, 0.75, 1.0];
        int currentIndex = areas.indexWhere(
          (v) => (_danmakuArea - v).abs() < 0.001,
        );
        if (currentIndex < 0) {
          final normalized = areas.firstWhere(
            (v) => _danmakuArea <= v + 0.001,
            orElse: () => areas.last,
          );
          currentIndex = areas.indexOf(normalized);
        }
        final newIndex = (currentIndex + direction).clamp(0, areas.length - 1);
        final newVal = areas[newIndex];
        if ((newVal - _danmakuArea).abs() > 0.001) {
          setState(() => _danmakuArea = newVal);
          await _saveSettings();
        }
        break;
      case 4: // Speed (Slider)
        double newVal = _danmakuSpeed + (direction * 1.0);
        newVal = newVal.clamp(5.0, 20.0);
        if (newVal != _danmakuSpeed) {
          setState(() => _danmakuSpeed = newVal);
          await _saveSettings();
        }
        break;
      // 5, 6 are boolean switches (Hide Top/Bottom)
    }
  }

  int _getSettingsItemCount() {
    switch (_settingsMenuType) {
      case LiveSettingsMenuType.main:
        return 0; // Deprecated
      case LiveSettingsMenuType.quality:
        return _qualities.length;
      case LiveSettingsMenuType.line:
        return _lines.length;
      case LiveSettingsMenuType.danmaku:
        return 7;
    }
  }

  void _handleSettingsSelection() {
    if (_settingsMenuType == LiveSettingsMenuType.quality) {
      if (_focusedSettingIndex < _qualities.length) {
        final qn = _qualities[_focusedSettingIndex]['qn'];
        _initializePlayer(qn: qn);
        setState(() {
          _showSettingsPanel = false;
        });
      }
    } else if (_settingsMenuType == LiveSettingsMenuType.line) {
      if (_focusedSettingIndex < _lines.length) {
        _changeLine(_focusedSettingIndex);
        setState(() {
          _showSettingsPanel = false;
        });
      }
    } else if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
      // Toggle logic for switches (items 0, 5, 6)
      _toggleDanmakuSetting(_focusedSettingIndex);
    }
  }

  void _toggleDanmakuSetting(int index) {
    switch (index) {
      case 0: // Toggle Enable
        setState(() => _danmakuEnabled = !_danmakuEnabled);
        _saveSettings();
        break;
      case 1: // Opacity
        double newVal = _danmakuOpacity + 0.2;
        if (newVal > 1.0) newVal = 0.2;
        setState(() => _danmakuOpacity = newVal);
        _saveSettings();
        break;
      // ... others
      // For now, simplify or rely on UI panel's click usage.
      // The UI panel uses InkWell, so Enter key often triggers it if focused.
    }
  }

  void _changeLine(int index) {
    if (index == _currentLineIndex) return;
    _initializePlayer(lineIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_showSettingsPanel) {
          setState(() {
            _showSettingsPanel = false;
            _settingsMenuType = LiveSettingsMenuType.main;
          });
          return;
        }

        if (_showControls) {
          _hideControls();
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          Fluttertoast.showToast(msg: "再按一次退出直播");
          return;
        }

        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video Player
              Center(
                child: _isLoading
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFFfb7299),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 20),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ],
                      )
                    : AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
              ),

              // Danmaku Layer
              if (_controller != null &&
                  _controller!.value.isInitialized &&
                  _danmakuEnabled)
                Positioned.fill(
                  child: DanmakuScreen(
                    createdController: (e) => _danmakuController = e,
                    option: DanmakuOption(
                      opacity: _danmakuOpacity,
                      fontSize: _danmakuFontSize,
                      area: _danmakuArea,
                      duration: _danmakuSpeed / 1.0,
                      hideTop: _hideTopDanmaku,
                      hideBottom: _hideBottomDanmaku,
                    ),
                  ),
                ),

              // Controls Layer
              if (_showControls) _buildControls(),

              // Settings Panel
              if (_showSettingsPanel)
                LiveSettingsPanel(
                  menuType: _settingsMenuType,
                  focusedIndex: _focusedSettingIndex,
                  qualityDesc: _currentQualityDesc,
                  qualities: _qualities,
                  currentQuality: _currentQuality,
                  lines: _lines,
                  currentLineIndex: _currentLineIndex,
                  danmakuEnabled: _danmakuEnabled,
                  danmakuOpacity: _danmakuOpacity,
                  danmakuFontSize: _danmakuFontSize,
                  danmakuArea: _danmakuArea,
                  danmakuSpeed: _danmakuSpeed,
                  hideTopDanmaku: _hideTopDanmaku,
                  hideBottomDanmaku: _hideBottomDanmaku,
                  onNavigate: (type, index) {
                    setState(() {
                      _settingsMenuType = type;
                      _focusedSettingIndex = index;
                    });
                  },
                  onQualitySelect: (qn) {
                    _initializePlayer(qn: qn);
                    setState(() {
                      _showSettingsPanel = false;
                      _settingsMenuType = LiveSettingsMenuType.main;
                    });
                  },
                  onLineSelect: (index) {
                    _changeLine(index);
                    setState(() {
                      _showSettingsPanel = false;
                      _settingsMenuType = LiveSettingsMenuType.main;
                    });
                  },
                  onDanmakuSettingChange: (key, value) async {
                    setState(() {
                      switch (key) {
                        case 'enabled':
                          _danmakuEnabled = value;
                          break;
                        case 'opacity':
                          _danmakuOpacity = value;
                          break;
                        case 'fontSize':
                          _danmakuFontSize = value;
                          break;
                        case 'area':
                          _danmakuArea = value;
                          break;
                        case 'speed':
                          _danmakuSpeed = value;
                          break;
                        case 'hideTop':
                          _hideTopDanmaku = value;
                          break;
                        case 'hideBottom':
                          _hideBottomDanmaku = value;
                          break;
                      }
                    });
                    await _saveSettings();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _showControls ? 1.0 : 0.0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
          ),
        ),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Online Count (Below Title)
                        Row(
                          children: [
                            const Icon(
                              Icons.people,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_onlineCount人正在观看',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const TimeDisplay(),
                ],
              ),
            ),

            const Spacer(),

            // Bottom Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Row(
                children: [
                  // Refresh (0)
                  _buildControlButton(
                    index: 0,
                    icon: Icons.refresh,
                    label: '刷新',
                  ),
                  const SizedBox(width: 20),
                  // Quality (1)
                  _buildControlButton(
                    index: 1,
                    icon: Icons.hd,
                    label: _currentQualityDesc,
                  ),
                  const SizedBox(width: 20),
                  // Line (2)
                  _buildControlButton(
                    index: 2,
                    icon: Icons.router,
                    label: _lines.isNotEmpty
                        ? _lines[_currentLineIndex]['name'] ?? '线路'
                        : '线路',
                  ),
                  const SizedBox(width: 20),
                  // Settings (3)
                  _buildControlButton(
                    index: 3,
                    icon: Icons.settings,
                    label: '弹幕设置',
                  ),
                  const SizedBox(width: 20),
                  // Follow (4)
                  _buildControlButton(
                    index: 4,
                    icon: _isFollowed ? Icons.favorite : Icons.favorite_border,
                    label: _isFollowed ? '已关注' : '关注',
                    iconColor: _isFollowed
                        ? const Color(0xFFfb7299)
                        : Colors.white,
                    textColor: _isFollowed
                        ? const Color(0xFFfb7299)
                        : Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required int index,
    required IconData icon,
    required String label,
    Color? iconColor,
    Color? textColor,
  }) {
    final isFocused = _focusedControlIndex == index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFFfb7299)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: isFocused
            ? Border.all(color: const Color(0xFFfb7299), width: 2)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isFocused ? Colors.white : (iconColor ?? Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isFocused ? Colors.white : (textColor ?? Colors.white),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
