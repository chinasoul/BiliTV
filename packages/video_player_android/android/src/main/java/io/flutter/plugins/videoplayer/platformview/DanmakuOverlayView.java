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
    final long bornAtMs;

    DanmakuItem(String text, int color, float width, int trackIndex, float y, long bornAtMs) {
      this.text = text;
      this.color = color;
      this.width = width;
      this.trackIndex = trackIndex;
      this.y = y;
      this.bornAtMs = bornAtMs;
    }
  }

  private final List<DanmakuItem> items = new ArrayList<>();
  private final List<Long> trackNextSpawnAtMs = new ArrayList<>();
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
    final int trackIndex = pickTrackIndex(now);
    final long readyAt = trackNextSpawnAtMs.get(trackIndex);
    // All tracks are busy: drop this item instead of forcing overlap.
    if (readyAt > now + 80L) {
      droppedByTrackBusy++;
      return;
    }

    final float width = textPaint.measureText(text);
    final float y = (trackIndex + 1) * rowHeight;
    final float durationMs = Math.max(durationSec * 1000.0f, 1000.0f);
    final float totalDistance = getWidth() + width;
    final float speed = totalDistance / durationMs;
    final float minGapPx = Math.max(textSizePx * 1.0f, 42f);
    final long nextSpawnAt = now + (long) Math.ceil((width + minGapPx) / Math.max(speed, 0.001f));
    trackNextSpawnAtMs.set(trackIndex, nextSpawnAt);

    synchronized (items) {
      items.add(new DanmakuItem(text, color, width, trackIndex, y, now));
    }
    postInvalidateOnAnimation();
  }

  void clearDanmaku() {
    synchronized (items) {
      items.clear();
    }
    trackNextSpawnAtMs.clear();
    droppedByTrackBusy = 0;
    invalidate();
  }

  void pauseDanmaku() {
    running = false;
  }

  void resumeDanmaku() {
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
    while (trackNextSpawnAtMs.size() < trackCount) {
      trackNextSpawnAtMs.add(0L);
    }
    while (trackNextSpawnAtMs.size() > trackCount) {
      trackNextSpawnAtMs.remove(trackNextSpawnAtMs.size() - 1);
    }
  }

  private int pickTrackIndex(long nowMs) {
    int best = 0;
    long bestReadyAt = Long.MAX_VALUE;
    for (int i = 0; i < trackNextSpawnAtMs.size(); i++) {
      final long readyAt = trackNextSpawnAtMs.get(i);
      if (readyAt <= nowMs) {
        return i;
      }
      if (readyAt < bestReadyAt) {
        bestReadyAt = readyAt;
        best = i;
      }
    }
    return best;
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
