package com.lexpdf.lexpdf_app

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.StateListDrawable
import android.view.Menu
import android.widget.Button
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
