package com.lexpdf.lexpdf_app

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.StateListDrawable
import android.view.Menu
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ReplacementSpan
import android.widget.Button
import android.widget.TextView
import kotlin.math.roundToInt

/** Presentation only: never changes reader geometry, input handlers or PDF colors. */
internal object NativeReaderChromeStyle {
    data class Palette(
        val surface: Int,
        val controlSurface: Int,
        val foreground: Int,
        val secondary: Int,
        val accent: Int,
        val selectedSurface: Int,
        val outline: Int,
    )

    fun palette(darkUi: Boolean): Palette {
        return if (darkUi) {
            Palette(
                surface = Color.rgb(34, 39, 49),
                controlSurface = Color.rgb(41, 49, 61),
                foreground = Color.rgb(237, 240, 245),
                secondary = Color.rgb(176, 186, 200),
                accent = Color.rgb(180, 207, 255),
                selectedSurface = Color.rgb(49, 69, 99),
                outline = Color.rgb(57, 67, 84),
            )
        } else {
            Palette(
                surface = Color.rgb(251, 252, 254),
                controlSurface = Color.rgb(241, 244, 248),
                foreground = Color.rgb(34, 42, 54),
                secondary = Color.rgb(89, 101, 119),
                accent = Color.rgb(36, 79, 146),
                selectedSurface = Color.rgb(230, 239, 252),
                outline = Color.rgb(220, 226, 233),
            )
        }
    }

    fun applyButton(button: Button, palette: Palette) {
        button.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        // Replacing an OEM drawable must not replace its padding or minimum
        // dimensions. The activity still owns all toolbar sizing and handlers.
        val paddingLeft = button.paddingLeft
        val paddingTop = button.paddingTop
        val paddingRight = button.paddingRight
        val paddingBottom = button.paddingBottom
        val minimumWidth = button.minimumWidth
        val minimumHeight = button.minimumHeight
        val radius = 7f * button.resources.displayMetrics.density
        val selectedSurface = roundedSurface(palette.selectedSurface, radius).apply {
            setStroke(
                button.resources.displayMetrics.density.roundToInt().coerceAtLeast(1),
                palette.outline,
            )
        }
        val controlStates = StateListDrawable().apply {
            addState(
                intArrayOf(-android.R.attr.state_enabled),
                roundedSurface(palette.controlSurface, radius),
            )
            addState(intArrayOf(android.R.attr.state_selected), selectedSurface)
            addState(intArrayOf(), roundedSurface(palette.controlSurface, radius))
        }
        val rippleColor =
            Color.argb(
                48,
                Color.red(palette.accent),
                Color.green(palette.accent),
                Color.blue(palette.accent),
            )

        button.backgroundTintList = null
        button.background =
            RippleDrawable(
                ColorStateList.valueOf(rippleColor),
                controlStates,
                roundedSurface(Color.WHITE, radius),
            )
        button.setTextColor(
            ColorStateList(
                arrayOf(
                    intArrayOf(-android.R.attr.state_enabled),
                    intArrayOf(android.R.attr.state_selected),
                    intArrayOf(),
                ),
                intArrayOf(palette.secondary, palette.accent, palette.foreground),
            ),
        )
        button.elevation = 0f
        button.stateListAnimator = null
        button.minimumWidth = minimumWidth
        button.minimumHeight = minimumHeight
        button.setPadding(paddingLeft, paddingTop, paddingRight, paddingBottom)
    }

    fun applyPageTypography(label: TextView) {
        label.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        label.fontFeatureSettings = "'tnum'"
    }

    fun applyControlIcon(button: Button, label: String, searchControls: Boolean = false) {
        val description = when (label) {
            "‹" -> if (searchControls) "Resultado anterior" else "Página anterior"
            "›" -> if (searchControls) "Próximo resultado" else "Próxima página"
            "−" -> "Diminuir zoom"
            "+" -> "Aumentar zoom"
            "⋮" -> "Mais opções"
            "⋯" -> "Opções de busca"
            "×" -> "Fechar busca"
            else -> return
        }
        // Keep the original label, line metrics and button geometry. Only its
        // painted glyph changes; TalkBack receives the full action name.
        button.contentDescription = description
        button.text = SpannableString(label).apply {
            setSpan(
                ControlIconSpan(label, 18f * button.resources.displayMetrics.density),
                0,
                length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
    }

    private class ControlIconSpan(private val glyph: String, private val size: Float) : ReplacementSpan() {
        override fun getSize(paint: Paint, text: CharSequence, start: Int, end: Int, fm: Paint.FontMetricsInt?): Int =
            size.roundToInt()

        override fun draw(canvas: Canvas, text: CharSequence, start: Int, end: Int, x: Float, top: Int, y: Int, bottom: Int, paint: Paint) {
            val metrics = paint.fontMetrics
            val centerY = y + (metrics.ascent + metrics.descent) / 2f
            val iconPaint = Paint(paint).apply {
                isAntiAlias = true
                style = Paint.Style.STROKE
                strokeWidth = 2f
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            val saveCount = canvas.save()
            canvas.translate(x, centerY - size / 2f)
            canvas.scale(size / 24f, size / 24f)
            when (glyph) {
                "‹", "›" -> {
                    val edge = if (glyph == "‹") 15f else 9f
                    val tip = if (glyph == "‹") 9f else 15f
                    val path = Path().apply {
                        moveTo(edge, 5f)
                        lineTo(tip, 12f)
                        lineTo(edge, 19f)
                    }
                    canvas.drawPath(path, iconPaint)
                }
                "−", "+" -> {
                    canvas.drawLine(5f, 12f, 19f, 12f, iconPaint)
                    if (glyph == "+") canvas.drawLine(12f, 5f, 12f, 19f, iconPaint)
                }
                "×" -> {
                    canvas.drawLine(6f, 6f, 18f, 18f, iconPaint)
                    canvas.drawLine(18f, 6f, 6f, 18f, iconPaint)
                }
                "⋮", "⋯" -> {
                    iconPaint.style = Paint.Style.FILL
                    for (position in floatArrayOf(5f, 12f, 19f)) {
                        val cx = if (glyph == "⋮") 12f else position
                        val cy = if (glyph == "⋮") position else 12f
                        canvas.drawCircle(cx, cy, 1.6f, iconPaint)
                    }
                }
            }
            canvas.restoreToCount(saveCount)
        }
    }

    fun markActiveTool(menu: Menu, activeTitle: String) {
        val toolTitles = setOf("Selecionar texto", "Caneta", "Marca-texto", "Borracha")
        for (index in 0 until menu.size()) {
            val item = menu.getItem(index)
            val title = item.title.toString()
            if (title in toolTitles) {
                item.isCheckable = true
                item.isChecked = title == activeTitle
            }
        }
    }

    fun roundedSurface(color: Int, radius: Float): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(color)
        }
}
