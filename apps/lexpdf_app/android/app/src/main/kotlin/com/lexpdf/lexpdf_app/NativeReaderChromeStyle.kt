package com.lexpdf.lexpdf_app

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.widget.Button

/** Presentation only: never changes reader geometry, input handlers or PDF colors. */
internal object NativeReaderChromeStyle {
    data class Palette(
        val surface: Int,
        val controlSurface: Int,
        val foreground: Int,
        val secondary: Int,
        val accent: Int,
    )

    fun palette(darkUi: Boolean): Palette {
        return if (darkUi) {
            Palette(
                surface = Color.rgb(34, 39, 49),
                controlSurface = Color.rgb(41, 49, 61),
                foreground = Color.rgb(237, 240, 245),
                secondary = Color.rgb(176, 186, 200),
                accent = Color.rgb(180, 207, 255),
            )
        } else {
            Palette(
                surface = Color.rgb(251, 252, 254),
                controlSurface = Color.rgb(241, 244, 248),
                foreground = Color.rgb(34, 42, 54),
                secondary = Color.rgb(89, 101, 119),
                accent = Color.rgb(36, 79, 146),
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
                roundedSurface(palette.controlSurface, radius),
                roundedSurface(Color.WHITE, radius),
            )
        button.setTextColor(
            ColorStateList(
                arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
                intArrayOf(palette.secondary, palette.foreground),
            ),
        )
        button.elevation = 0f
        button.stateListAnimator = null
        button.minimumWidth = minimumWidth
        button.minimumHeight = minimumHeight
        button.setPadding(paddingLeft, paddingTop, paddingRight, paddingBottom)
    }

    fun roundedSurface(color: Int, radius: Float): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(color)
        }
}
