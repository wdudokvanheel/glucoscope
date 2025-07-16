package com.bitechular.glucoscope.ui.components.indicator

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import com.bitechular.glucoscope.extensions.linear
import com.bitechular.glucoscope.extensions.toSrgb
import kotlin.math.log10

/**
 * Maps a glucose *value* to the colour that the vertical line-gradient
 * in [ColoredLineGraph] would have at that height.
 */
fun glucoseValueToColor(
    value: Double,
    graphMin: Double = 2.5,
    graphMax: Double = 20.0,
    lowThreshold: Double = 4.0,
    highThreshold: Double = 7.0,
    upperThreshold: Double = 10.0,
    lowColor: Color = Color(0xFFFF006E),
    inRangeColor: Color = Color(0xFF00C853),
    highColor: Color = Color(0xFFFFD600),
    upperColor: Color = Color(0xFFFF006E),
): Color {
    require(value > 0) { "Value must be > 0." }
    require(graphMin > 0 && graphMax > graphMin)

    /* ---------- helper ---------- */

    fun frac(v: Double): Float {
        val span = log10(graphMax) - log10(graphMin)
        return ((log10(graphMax) - log10(v)) / span).toFloat()
    }

    /* ---------- band setup (identical to the shader) ---------- */

    val lowBand = lowThreshold * 0.04
    val highBand = highThreshold * 0.0214

    val positions = floatArrayOf(
        0f,
        frac(upperThreshold),
        frac(highThreshold),
        frac(highThreshold - highBand * 1.5),
        frac(lowThreshold + lowBand),
        frac(lowThreshold),
        frac(lowThreshold - lowBand),
        1f
    )

    // 50-50 mix in linear-light space, same as the gradient’s mid-stop
    val midLowColor = lerp(lowColor.linear(), inRangeColor.linear(), 0.5f).toSrgb()

    val colours = arrayOf(
        upperColor,
        upperColor,
        highColor,
        inRangeColor,
        inRangeColor,
        midLowColor,
        lowColor,
        lowColor
    )

    /* ---------- locate the segment for the given value ---------- */

    val f = frac(value).coerceIn(0f, 1f)

    var i = 0
    while (i < positions.lastIndex && f > positions[i + 1]) i++

    val p0 = positions[i]
    val p1 = positions[i + 1]
    val t = if (p1 == p0) 0f else (f - p0) / (p1 - p0)     // 0 → 1 within segment

    /* ---------- return the interpolated colour ---------- */
    return lerp(colours[i], colours[i + 1], t)
}
