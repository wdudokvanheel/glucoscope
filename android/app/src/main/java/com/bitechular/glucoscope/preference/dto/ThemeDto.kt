package com.bitechular.glucoscope.preference.dto

import com.bitechular.glucoscope.extensions.toColor
import com.bitechular.glucoscope.extensions.toHex
import com.bitechular.glucoscope.preference.GlucoScopeTheme
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

fun ThemeDto.toTheme(): GlucoScopeTheme {
    val self = this

    return GlucoScopeTheme().apply {
        name = self.name
        url = self.url
        variant = self.variant
        background = self.background.toColor()
        surface = self.surface.toColor()
        text = self.text.toColor()
        accent = self.accent.toColor()
        inRangeColor = self.inRangeColor.toColor()
        lowColor = self.lowColor.toColor()
        highColor = self.highColor.toColor()
        upperColor = self.upperColor.toColor()
        indicatorIcon = self.indicatorIcon.toColor()
        indicatorLabel = self.indicatorLabel.toColor()
        axisXLegendColor = self.axisXLegendColor.toColor()
        axisYLegendColor = self.axisYLegendColor.toColor()
        axisXGridLineColor = self.axisXGridLineColor.toColor()
        axisYGridLineColor = self.axisYGridLineColor.toColor()
    }
}

fun ThemeDto.Companion.fromTheme(theme: GlucoScopeTheme): ThemeDto =
    ThemeDto(
        name = theme.name,
        variant = theme.variant,
        url = theme.url,
        background = theme.background.toHex(),
        surface = theme.surface.toHex(),
        text = theme.text.toHex(),
        accent = theme.accent.toHex(),
        inRangeColor = theme.inRangeColor.toHex(),
        lowColor = theme.lowColor.toHex(),
        highColor = theme.highColor.toHex(),
        upperColor = theme.upperColor.toHex(),
        indicatorIcon = theme.indicatorIcon.toHex(),
        indicatorLabel = theme.indicatorLabel.toHex(),
        axisXLegendColor = theme.axisXLegendColor.toHex(),
        axisYLegendColor = theme.axisYLegendColor.toHex(),
        axisXGridLineColor = theme.axisXGridLineColor.toHex(),
        axisYGridLineColor = theme.axisYGridLineColor.toHex()
    )