package io.flutter.plugins.videoplayer.platformview;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.SystemClock;
import android.util.TypedValue;
import android.view.View;
import androidx.annotation.NonNull;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

final class DanmakuOverlayView extends View {
  private static final class DanmakuItem {
    final String text;
    final int color;
    final float width;
    final int trackIndex;
    final float y;
    long bornAtMs;

    DanmakuItem(String text, int color, float width, int trackIndex, float y, long bornAtMs) {
      this.text = text;
      this.color = color;
      this.width = width;
      this.trackIndex = trackIndex;
      this.y = y;
      this.bornAtMs = bornAtMs;
    }
  }

  private static final class TrackTail {
    float textWidth;
    long bornAtMs;
    float speed;

    TrackTail(float textWidth, long bornAtMs, float speed) {
      this.textWidth = textWidth;
      this.bornAtMs = bornAtMs;
      this.speed = speed;
    }
  }

  private final List<DanmakuItem> items = new ArrayList<>();
  private final List<TrackTail> trackTails = new ArrayList<>();
  private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
  private final Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

  private boolean running = true;
  private boolean hideScroll = false;
  private float opacity = 0.6f;
  private float fontSizeSp = 17f;
  private float areaRatio = 0.25f;
  private float durationSec = 10f;
  private float lineHeight = 1.6f;
  private long droppedByTrackBusy = 0;
  private long pauseStartMs = 0;

  DanmakuOverlayView(@NonNull Context context) {
    super(context);
    setWillNotDraw(false);
    setBackgroundColor(Color.TRANSPARENT);
    setClickable(false);
    setFocusable(false);

    textPaint.setStyle(Paint.Style.FILL);
    textPaint.setColor(Color.WHITE);

    strokePaint.setStyle(Paint.Style.STROKE);
    strokePaint.setColor(Color.BLACK);
    strokePaint.setStrokeWidth(0.8f);
  }

  void updateOption(
      double opacity,
      double fontSize,
      double area,
      double duration,
      boolean hideScroll,
      double strokeWidth,
      double lineHeight) {
    this.opacity = clamp((float) opacity, 0.0f, 1.0f);
    this.fontSizeSp = clamp((float) fontSize, 8.0f, 64.0f);
    this.areaRatio = clamp((float) area, 0.05f, 1.0f);
    this.durationSec = Math.max((float) duration, 3.0f);
    this.hideScroll = hideScroll;
    this.lineHeight = clamp((float) lineHeight, 1.0f, 2.2f);
    strokePaint.setStrokeWidth(clamp((float) strokeWidth, 0f, 2.5f));
    invalidate();
  }

  void addDanmaku(@NonNull String text, int color) {
    if (!running || hideScroll || text.isEmpty() || getWidth() <= 0 || getHeight() <= 0) {
      return;
    }

    final float textSizePx = spToPx(fontSizeSp);
    textPaint.setTextSize(textSizePx);
    strokePaint.setTextSize(textSizePx);

    final float rowHeight = Math.max(textSizePx * lineHeight, 1f);
    final int tracks = getTrackCount(rowHeight);
    ensureTrackStateSize(tracks);
    final long now = SystemClock.elapsedRealtime();
    final float width = textPaint.measureText(text);
    final float screenW = getWidth();
    final float durationMs = Math.max(durationSec * 1000.0f, 1000.0f);
    final float totalDistance = screenW + width;
    final float newSpeed = totalDistance / durationMs;
    final float minGapPx = Math.max(textSizePx * 1.0f, 42f);

    final int trackIndex = pickTrackByPosition(now, screenW, newSpeed, width, minGapPx);
    if (trackIndex < 0) {
      droppedByTrackBusy++;
      return;
    }

    final float y = (trackIndex + 1) * rowHeight;

    trackTails.set(trackIndex, new TrackTail(width, now, newSpeed));

    synchronized (items) {
      items.add(new DanmakuItem(text, color, width, trackIndex, y, now));
    }
    postInvalidateOnAnimation();
  }

  void clearDanmaku() {
    synchronized (items) {
      items.clear();
    }
    trackTails.clear();
    droppedByTrackBusy = 0;
    pauseStartMs = 0;
    invalidate();
  }

  void pauseDanmaku() {
    running = false;
    pauseStartMs = SystemClock.elapsedRealtime();
  }

  void resumeDanmaku() {
    if (pauseStartMs > 0) {
      final long pauseDuration = SystemClock.elapsedRealtime() - pauseStartMs;
      if (pauseDuration > 0) {
        synchronized (items) {
          for (DanmakuItem item : items) {
            item.bornAtMs += pauseDuration;
          }
        }
        for (int i = 0; i < trackTails.size(); i++) {
          final TrackTail tail = trackTails.get(i);
          if (tail != null) {
            tail.bornAtMs += pauseDuration;
          }
        }
      }
      pauseStartMs = 0;
    }
    running = true;
    postInvalidateOnAnimation();
  }

  @Override
  protected void onDraw(@NonNull Canvas canvas) {
    super.onDraw(canvas);
    if (hideScroll || getWidth() <= 0) {
      return;
    }

    final float textSizePx = spToPx(fontSizeSp);
    final float opacityScale = clamp(0.05f + 0.95f * opacity, 0.0f, 1.0f);
    textPaint.setTextSize(textSizePx);
    strokePaint.setTextSize(textSizePx);

    final float durationMs = Math.max(durationSec * 1000.0f, 1000.0f);
    final long now = SystemClock.elapsedRealtime();
    boolean hasAlive = false;

    synchronized (items) {
      final Iterator<DanmakuItem> it = items.iterator();
      while (it.hasNext()) {
        DanmakuItem item = it.next();
        float elapsedMs = now - item.bornAtMs;
        float totalDistance = getWidth() + item.width;
        float speed = totalDistance / durationMs;
        float x = getWidth() - elapsedMs * speed;
        if (x + item.width < 0f) {
          it.remove();
          continue;
        }
        hasAlive = true;
        final int fillColor = applyOpacity(item.color, opacityScale);
        textPaint.setColor(fillColor);
        final int strokeAlpha =
            Math.min(
                220,
                Math.max(
                    0,
                    (int)
                        (Color.alpha(fillColor)
                            * (opacityScale < 0.25f ? 0.0f : 0.45f))));
        strokePaint.setColor(Color.argb(strokeAlpha, 0, 0, 0));
        if (strokePaint.getStrokeWidth() > 0f) {
          canvas.drawText(item.text, x, item.y, strokePaint);
        }
        canvas.drawText(item.text, x, item.y, textPaint);
      }
    }

    if (running && hasAlive) {
      postInvalidateOnAnimation();
    }
  }

  private int getTrackCount(float rowHeight) {
    final float drawHeight = Math.max(getHeight() * areaRatio, rowHeight);
    return Math.max((int) Math.ceil(drawHeight / rowHeight), 1);
  }

  private void ensureTrackStateSize(int trackCount) {
    while (trackTails.size() < trackCount) {
      trackTails.add(null);
    }
    while (trackTails.size() > trackCount) {
      trackTails.remove(trackTails.size() - 1);
    }
  }

  /**
   * Returns the track index where the new danmaku can be placed, or -1 if all tracks are busy.
   * A track is available if:
   *   1) no tail recorded, OR
   *   2) the tail's right edge (tailX + tailWidth) has cleared the right edge of screen with gap, AND
   *   3) the new danmaku won't catch up with the tail before the tail exits.
   */
  private int pickTrackByPosition(long nowMs, float screenW, float newSpeed,
      float newWidth, float minGapPx) {
    int bestTrack = -1;
    float bestGap = -Float.MAX_VALUE;

    for (int i = 0; i < trackTails.size(); i++) {
      final TrackTail tail = trackTails.get(i);
      if (tail == null) {
        return i;
      }
      final float tailElapsed = nowMs - tail.bornAtMs;
      final float tailX = screenW - tailElapsed * tail.speed;
      final float tailRightEdge = tailX + tail.textWidth;
      final float gap = screenW - tailRightEdge;

      if (gap < minGapPx) {
        if (gap > bestGap) {
          bestGap = gap;
          bestTrack = i;
        }
        continue;
      }

      if (newSpeed > tail.speed) {
        final float tailTotalDist = screenW + tail.textWidth;
        final float tailDurationMs = tailTotalDist / Math.max(tail.speed, 0.001f);
        final float tailRemainingMs = tailDurationMs - tailElapsed;
        final float catchUpX = screenW - tailRemainingMs * newSpeed;
        if (catchUpX <= tailX - minGapPx) {
          return i;
        }
        if (gap > bestGap) {
          bestGap = gap;
          bestTrack = i;
        }
        continue;
      }

      return i;
    }

    return -1;
  }

  private static int applyOpacity(int color, float opacityScale) {
    final int sourceAlpha = Color.alpha(color);
    final int alpha = clampInt((int) Math.round(sourceAlpha * opacityScale), 0, 255);
    return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
  }

  private static int clampInt(int value, int min, int max) {
    return Math.max(min, Math.min(max, value));
  }

  private float spToPx(float sp) {
    return TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_SP, sp, getResources().getDisplayMetrics());
  }

  private static float clamp(float value, float min, float max) {
    return Math.max(min, Math.min(max, value));
  }
}
