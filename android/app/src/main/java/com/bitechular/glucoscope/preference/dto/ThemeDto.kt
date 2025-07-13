package com.bitechular.glucoscope.preference.dto

import kotlinx.serialization.Serializable

@Serializable
data class ThemeDto(
    val name: String = "Default Theme",
    val background: String = "#000000",
    val text: String = "#FFFFFF",
    val accent: String = "#40C8E0",
    val upperColor: String = "#FF006E",
    val lowColor: String = "#FF006E",
    val inRangeColor: String = "#00C853",
    val highColor: String = "#FFD600",
    val axisLegendColor: String = "#555555",
    val axisLinesColor: String = "#555555",
    val surface: String = "#1A1A1C",
    val indicatorIcon: String = "#000000",
    val indicatorLabel: String = "#000000",
)