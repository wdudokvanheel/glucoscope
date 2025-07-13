package com.bitechular.glucoscope.extensions

import androidx.compose.ui.graphics.Color

/**
 * Converts this Color to a hex string.
 * @param includeAlpha whether to include the alpha channel in the output (default true).
 * @return String in the form "#AARRGGBB" (if includeAlpha) or "#RRGGBB" (if not).
 */
fun Color.toHex(includeAlpha: Boolean = true): String {
    val a = (alpha * 255).toInt() and 0xFF
    val r = (red   * 255).toInt() and 0xFF
    val g = (green * 255).toInt() and 0xFF
    val b = (blue  * 255).toInt() and 0xFF

    return if (includeAlpha) {
        String.format("#%02X%02X%02X%02X", a, r, g, b)
    } else {
        String.format("#%02X%02X%02X", r, g, b)
    }
}

/**
 * Parses a hex color string and returns a Compose Color.
 * Supported formats:
 *  - "#RRGGBB"
 *  - "#AARRGGBB"
 *  - "RRGGBB"
 *  - "AARRGGBB"
 *
 * @throws IllegalArgumentException if the string is not in a supported format.
 */
fun String.toColor(): Color {
    // Remove leading '#' if present
    val hex = removePrefix("#")
    val rgba = when (hex.length) {
        6 -> { // RRGGBB
            val r = hex.substring(0, 2).toInt(16)
            val g = hex.substring(2, 4).toInt(16)
            val b = hex.substring(4, 6).toInt(16)
            listOf(255, r, g, b)
        }
        8 -> { // AARRGGBB
            val a = hex.substring(0, 2).toInt(16)
            val r = hex.substring(2, 4).toInt(16)
            val g = hex.substring(4, 6).toInt(16)
            val b = hex.substring(6, 8).toInt(16)
            listOf(a, r, g, b)
        }
        else -> throw IllegalArgumentException("Invalid color hex string: $this")
    }

    // Convert from 0–255 ints to 0f–1f floats
    return Color(
        red   = rgba[1] / 255f,
        green = rgba[2] / 255f,
        blue  = rgba[3] / 255f,
        alpha = rgba[0] / 255f
    )
}
