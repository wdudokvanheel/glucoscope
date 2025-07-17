package com.bitechular.glucoscope.extensions

import com.bitechular.glucoscope.preference.GlucoScopeTheme
import kotlin.math.pow
import kotlin.math.sqrt

val GlucoScopeTheme.isLight: Boolean
    get() {
        val r = background.red
        val g = background.green
        val b = background.blue

        val distanceToWhite = sqrt((1 - r).pow(2) + (1 - g).pow(2) + (1 - b).pow(2))
        val distanceToBlack = sqrt(r.pow(2) + g.pow(2) + b.pow(2))

        return distanceToWhite < distanceToBlack
    }