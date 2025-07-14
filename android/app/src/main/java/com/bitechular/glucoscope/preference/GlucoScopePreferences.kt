package com.bitechular.glucoscope.preference

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bitechular.glucoscope.extensions.toColor
import com.bitechular.glucoscope.extensions.toHex
import com.bitechular.glucoscope.preference.dto.GlucoScopePreferencesDto
import com.bitechular.glucoscope.preference.dto.ThemeDto
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import jakarta.inject.Inject
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

@HiltViewModel
class GlucoScopePreferences @Inject constructor(
    @ApplicationContext context: Context
) : ViewModel() {
    var theme by mutableStateOf(GlucoScopeTheme())
    var graphMin by mutableDoubleStateOf(2.5)
    var graphMax by mutableDoubleStateOf(20.0)
    var lowThreshold by mutableDoubleStateOf(4.0)
    var highThreshold by mutableDoubleStateOf(7.0)
    var upperThreshold by mutableDoubleStateOf(10.0)
    var xAxisSteps by mutableIntStateOf(2)
    var yAxisLabels by mutableStateOf(listOf<Double>(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0))

    private val dataStore = context.settingsDataStore

    init {
        viewModelScope.launch {
            dataStore.data.firstOrNull()?.let(::applySettings)
        }

        // Persist automatically whenever ANY mutableState changes
        viewModelScope.launch {
            snapshotFlow { toSettings() }
                .distinctUntilChanged()
                .drop(1)
                .collect { new ->
                    dataStore.updateData { new }
                }
        }
    }

    private fun applySettings(s: GlucoScopePreferencesDto) {
        graphMin = s.graphMin
        graphMax = s.graphMax
        lowThreshold = s.lowThreshold
        highThreshold = s.highThreshold
        upperThreshold = s.upperThreshold
        xAxisSteps = s.xAxisSteps
        yAxisLabels = s.yAxisLabels
        theme.apply {
            name = s.theme.name
            url = s.theme.url
            variant = s.theme.variant
            background = s.theme.background.toColor()
            surface = s.theme.surface.toColor()
            accent = s.theme.accent.toColor()
            inRangeColor = s.theme.inRangeColor.toColor()
            lowColor = s.theme.lowColor.toColor()
            highColor = s.theme.highColor.toColor()
            upperColor = s.theme.upperColor.toColor()
            indicatorIcon = s.theme.indicatorIcon.toColor()
            indicatorLabel = s.theme.indicatorLabel.toColor()
            axisXLegendColor = s.theme.axisXLegendColor.toColor()
            axisYLegendColor = s.theme.axisYLegendColor.toColor()
            axisXGridLineColor = s.theme.axisXGridLineColor.toColor()
            axisYGridLineColor = s.theme.axisYGridLineColor.toColor()
        }
    }

    private fun toSettings() = GlucoScopePreferencesDto(
        graphMin = graphMin,
        graphMax = graphMax,
        lowThreshold = lowThreshold,
        highThreshold = highThreshold,
        upperThreshold = upperThreshold,
        xAxisSteps = xAxisSteps,
        yAxisLabels = yAxisLabels,
        theme = ThemeDto(
            name = theme.name,
            background = theme.background.toHex(),
            upperColor = theme.upperColor.toHex(),
            lowColor = theme.lowColor.toHex(),
            inRangeColor = theme.inRangeColor.toHex(),
            highColor = theme.highColor.toHex(),
            axisXLegendColor = theme.axisXLegendColor.toHex(),
            axisXGridLineColor = theme.axisXGridLineColor.toHex(),
        )
    )

}
