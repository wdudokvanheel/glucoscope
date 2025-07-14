package com.bitechular.glucoscope.extensions

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

fun Color.atElevation(elev: Dp): Color {
    val alpha = when {
        elev <= 1.dp -> 0.05f
        elev <= 3.dp -> 0.08f
        elev <= 6.dp -> 0.11f
        else -> 0.12f
    }
    val overlay = if (luminance() < 0.5f)
        Color.White.copy(alpha = alpha)
    else
        Color.Black.copy(alpha = alpha)

    return overlay.compositeOver(this)
}