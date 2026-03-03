import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bili_tv_app/config/app_style.dart';

class TimeDisplay extends StatefulWidget {
  final TextStyle? textStyle;

  const TimeDisplay({super.key, this.textStyle});

  @override
  State<TimeDisplay> createState() => _TimeDisplayState();
}

class _TimeDisplayState extends State<TimeDisplay> {
  Timer? _timer;
  String _timeString = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final newTime = '$h:$m';
    if (mounted && newTime != _timeString) {
      setState(() {
        _timeString = newTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeString, // 'HH:mm'
      style:
          widget.textStyle ??
          const TextStyle(
            color: Colors.white,
            fontSize: AppFonts.sizeXXL,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 1)),
            ],
          ),
    );
  }
}
