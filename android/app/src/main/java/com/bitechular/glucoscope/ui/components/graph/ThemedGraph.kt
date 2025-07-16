package com.bitechular.glucoscope.ui.components.graph

import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.main.model.GraphRange

@Composable
fun ThemedGraph(
    measurements: List<GlucoseMeasurement>,
    modifier: Modifier = Modifier,
    graphRange: GraphRange? = null
) {
    val prefs = PreferenceModel.current

    val range = graphRange ?: prefs.graphRange
    key(prefs.graphRange) {
        ColoredLineGraph(
            measurements = measurements,

            graphMin = prefs.graphMin,
            graphMax = prefs.graphMax,

            lowThreshold = prefs.lowThreshold,
            highThreshold = prefs.highThreshold,
            upperThreshold = prefs.upperThreshold,

            xAxisStep = range.axisStep,
            yAxisLabels = prefs.yAxisLabels,

            inRangeColor = prefs.theme.inRangeColor,
            lowColor = prefs.theme.lowColor,
            highColor = prefs.theme.highColor,
            upperColor = prefs.theme.upperColor,

            axisXLegendColor = prefs.theme.axisXLegendColor,
            axisYLegendColor = prefs.theme.axisXLegendColor,
            axisXGridLineColor = prefs.theme.axisXGridLineColor,
            axisYGridLineColor = prefs.theme.axisXGridLineColor,

            modifier = modifier
        )
    }
}