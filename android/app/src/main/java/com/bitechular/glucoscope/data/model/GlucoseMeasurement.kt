package com.bitechular.glucoscope.data.model

import kotlinx.serialization.Serializable

@Serializable
data class GlucoseMeasurement(
    val time: Double,
    val value: Double
)

internal fun Double.toMmol(): Double = this * 0.0555