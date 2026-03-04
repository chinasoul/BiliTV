import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/videoshot.dart';
import '../../../services/api/videoshot_api.dart';
import 'package:bili_tv_app/config/app_style.dart';

/// 快进预览缩略图 Widget
/// 从雪碧图中裁剪并显示指定帧
class SeekPreviewThumbnail extends StatefulWidget {
  /// 快照数据
  final VideoshotData videoshotData;

  /// 当前预览位置
  final Duration previewPosition;

  /// 显示尺寸缩放比例
  final double scale;

  const SeekPreviewThumbnail({
    super.key,
    required this.videoshotData,
    required this.previewPosition,
    this.scale = 2.0,
  });

  @override
  State<SeekPreviewThumbnail> createState() => _SeekPreviewThumbnailState();
}

class _SeekPreviewThumbnailState extends State<SeekPreviewThumbnail> {
  // 缓存上一次成功加载的帧信息
  FrameInfo? _lastLoadedFrame;
  String? _lastLoadedUrl;

  @override
  Widget build(BuildContext context) {
    final frameInfo = widget.videoshotData.getFrameAt(widget.previewPosition);
    if (frameInfo == null) {
      return const SizedBox.shrink();
    }

    final displayWidth = frameInfo.width * widget.scale;
    final displayHeight = frameInfo.height * widget.scale;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: _buildCroppedImage(frameInfo, displayWidth, displayHeight),
        ),
      ),
    );
  }

  Widget _buildCroppedImage(
    FrameInfo frameInfo,
    double displayWidth,
    double displayHeight,
  ) {
    // 计算雪碧图总尺寸
    final spriteWidth =
        (widget.videoshotData.imgXLen * widget.videoshotData.imgXSize)
            .toDouble();
    final spriteHeight =
        (widget.videoshotData.imgYLen * widget.videoshotData.imgYSize)
            .toDouble();

    // 缩放后的雪碧图尺寸
    final scaledSpriteWidth = spriteWidth * widget.scale;
    final scaledSpriteHeight = spriteHeight * widget.scale;

    // 缩放后的偏移
    final offsetX = frameInfo.x * widget.scale;
    final offsetY = frameInfo.y * widget.scale;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // 显示上一张成功加载的图片作为底层（防止闪烁）
        if (_lastLoadedFrame != null && _lastLoadedUrl != null)
          Positioned(
            left: -(_lastLoadedFrame!.x * widget.scale),
            top: -(_lastLoadedFrame!.y * widget.scale),
            child: CachedNetworkImage(
              imageUrl: _lastLoadedUrl!,
              cacheManager: VideoshotApi.cacheManager,
              width: scaledSpriteWidth,
              height: scaledSpriteHeight,
              fit: BoxFit.fill,
              httpHeaders: const {
                'Referer': 'https://www.bilibili.com',
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              },
            ),
          ),
        // 当前帧
        Positioned(
          left: -offsetX,
          top: -offsetY,
          child: CachedNetworkImage(
            imageUrl: frameInfo.imageUrl,
            cacheManager: VideoshotApi.cacheManager,
            width: scaledSpriteWidth,
            height: scaledSpriteHeight,
            fit: BoxFit.fill,
            httpHeaders: const {
              'Referer': 'https://www.bilibili.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            imageBuilder: (context, imageProvider) {
              // 图片加载成功，更新缓存
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _lastLoadedFrame = frameInfo;
                    _lastLoadedUrl = frameInfo.imageUrl;
                  });
                }
              });
              return Image(image: imageProvider, fit: BoxFit.fill);
            },
            placeholder: (context, url) => Container(
              color: Colors.grey[900],
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.inactiveText,
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              width: displayWidth,
              height: displayHeight,
              color: Colors.grey[800],
              child: Icon(
                Icons.image_not_supported,
                color: AppColors.inactiveText,
                size: 32,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
