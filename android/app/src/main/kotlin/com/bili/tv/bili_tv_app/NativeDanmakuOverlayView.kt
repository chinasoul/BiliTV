package com.bili.tv.bili_tv_app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.Choreographer
import android.view.View
import kotlin.math.ceil
import kotlin.random.Random

class NativeDanmakuOverlayView(context: Context) : View(context), Choreographer.FrameCallback {
    private data class DanmakuItem(
        val text: String,
        val color: Int,
        val textWidth: Float,
        var trackY: Float,
        var bornAtMs: Long,
    )

    private val items = mutableListOf<DanmakuItem>()
    private val random = Random(SystemClock.elapsedRealtime().toInt())
    private var running = true

    private var opacity = 0.6f
    private var fontSizeSp = 17f
    private var areaRatio = 0.25f
    private var durationSec = 10f
    private var lineHeight = 1.6f
    private var hideScroll = false

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        strokeWidth = 0.8f
    }

    init {
        setWillNotDraw(false)
        setBackgroundColor(Color.TRANSPARENT)
        elevation = 10000f
        translationZ = 10000f
        bringToFront()
        Choreographer.getInstance().postFrameCallback(this)
    }

    fun updateOption(option: Map<String, Any?>) {
        opacity = (option["opacity"] as? Number)?.toFloat()?.coerceIn(0.1f, 1.0f) ?: opacity
        fontSizeSp = (option["fontSize"] as? Number)?.toFloat()?.coerceIn(8f, 64f) ?: fontSizeSp
        areaRatio = (option["area"] as? Number)?.toFloat()?.coerceIn(0.1f, 1.0f) ?: areaRatio
        durationSec = (option["duration"] as? Number)?.toFloat()?.coerceAtLeast(3f) ?: durationSec
        lineHeight = (option["lineHeight"] as? Number)?.toFloat()?.coerceIn(1.0f, 2.2f) ?: lineHeight
        hideScroll = option["hideScroll"] as? Boolean ?: hideScroll
        strokePaint.strokeWidth = ((option["strokeWidth"] as? Number)?.toFloat() ?: 0.8f).coerceIn(0f, 2.0f)
        invalidate()
    }

    fun addDanmaku(text: String, color: Int) {
        if (!running || hideScroll || width <= 0 || height <= 0 || text.isBlank()) return
        val textSizePx = fontSizeSp * resources.displayMetrics.scaledDensity
        paint.textSize = textSizePx
        strokePaint.textSize = textSizePx
        val textWidth = paint.measureText(text)
        val trackY = pickTrackY(textSizePx)
        items.add(
            DanmakuItem(
                text = text,
                color = color,
                textWidth = textWidth,
                trackY = trackY,
                bornAtMs = SystemClock.elapsedRealtime(),
            )
        )
        invalidate()
    }

    fun clearDanmaku() {
        items.clear()
        invalidate()
    }

    fun pauseDanmaku() {
        running = false
    }

    fun resumeDanmaku() {
        running = true
        invalidate()
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (running && items.isNotEmpty()) {
            invalidate()
        }
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (hideScroll || items.isEmpty() || width <= 0) return

        val now = SystemClock.elapsedRealtime()
        val alpha = (opacity * 255).toInt().coerceIn(20, 255)
        val textSizePx = fontSizeSp * resources.displayMetrics.scaledDensity
        paint.textSize = textSizePx
        strokePaint.textSize = textSizePx
        paint.alpha = alpha
        strokePaint.alpha = alpha

        val durationMs = (durationSec * 1000f).coerceAtLeast(1000f)
        val iterator = items.iterator()
        while (iterator.hasNext()) {
            val item = iterator.next()
            val elapsedMs = (now - item.bornAtMs).toFloat()
            val totalDistance = width + item.textWidth
            val speed = totalDistance / durationMs
            val x = width - elapsedMs * speed
            if (x + item.textWidth < 0f) {
                iterator.remove()
                continue
            }
            paint.color = item.color
            strokePaint.color = Color.BLACK
            if (strokePaint.strokeWidth > 0f) {
                canvas.drawText(item.text, x, item.trackY, strokePaint)
            }
            canvas.drawText(item.text, x, item.trackY, paint)
        }
    }

    private fun pickTrackY(textSizePx: Float): Float {
        val drawHeight = (height * areaRatio).coerceAtLeast(textSizePx * lineHeight)
        val rowHeight = (textSizePx * lineHeight).coerceAtLeast(1f)
        val tracks = ceil(drawHeight / rowHeight).toInt().coerceAtLeast(1)
        val trackIndex = random.nextInt(tracks)
        return (trackIndex + 1) * rowHeight
    }
}
