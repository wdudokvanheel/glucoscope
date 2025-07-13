package com.bitechular.glucoscope.extensions

import androidx.compose.ui.graphics.Color
import kotlin.math.pow

fun Color.linear() = Color(
    red = red.pow(2.2f),
    green = green.pow(2.2f),
    blue = blue.pow(2.2f),
    alpha = alpha
)

fun Color.toSrgb() = Color(
    red = red.pow(1 / 2.2f),
    green = green.pow(1 / 2.2f),
    blue = blue.pow(1 / 2.2f),
    alpha = alpha
)
