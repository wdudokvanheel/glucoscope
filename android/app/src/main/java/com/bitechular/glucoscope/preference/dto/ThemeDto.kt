package com.bitechular.glucoscope.preference.dto

import kotlinx.serialization.Serializable

@Serializable
data class ThemeDto(
    val name: String = "Default Theme",
    val variant: String = "",
    val url: String = "",
    val background: String = "#000000",
    val surface: String = "#1A1A1C",
    val text: String = "#FFFFFF",
    val accent: String = "#40C8E0",
    val inRangeColor: String = "#00C853",
    val lowColor: String = "#FF006E",
    val highColor: String = "#FFD600",
    val upperColor: String = "#FF006E",
    val indicatorIcon: String = "#000000",
    val indicatorLabel: String = "#000000",
    val axisXLegendColor: String = "#555555",
    val axisYLegendColor: String = "#555555",
    val axisXGridLineColor: String = "#555555",
    val axisYGridLineColor: String = "#555555",
)