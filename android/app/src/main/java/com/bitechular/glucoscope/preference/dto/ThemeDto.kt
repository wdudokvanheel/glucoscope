package com.bitechular.glucoscope.preference.dto

import kotlinx.serialization.Serializable

@Serializable
data class ThemeDto(
    val name: String = "Default Theme",
    val background: String = "#FF000000",
    val upperColor: String = "#FFFF006E",
    val lowColor: String = "#FFFF006E",
    val inRangeColor: String = "#FF00C853",
    val highColor: String = "#FFFFD600",
    val axisLegendColor: String = "#FF555555",
    val axisLinesColor: String = "#FF555555",
)