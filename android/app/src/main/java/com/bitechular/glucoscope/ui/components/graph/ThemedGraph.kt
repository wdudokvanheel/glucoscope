package com.bitechular.glucoscope.ui.components.graph

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun ThemedGraph(
    measurements: List<GlucoseMeasurement>,
    modifier: Modifier
) {
    val prefs = PreferenceModel.current

    ColoredLineGraph(
        measurements = measurements,
        graphMin = prefs.graphMin,
        graphMax = prefs.graphMax,
        upperColor = prefs.theme.upperColor,
        lowColor = prefs.theme.lowColor,
        inRangeColor = prefs.theme.inRangeColor,
        highColor = prefs.theme.highColor,
        axisLabelColor = prefs.theme.axisLegendColor,
        axisLinesColor = prefs.theme.axisLinesColor,
        lowThreshold = prefs.lowThreshold,
        highThreshold = prefs.highThreshold,
        upperThreshold = prefs.upperThreshold,
        xAxisStep = prefs.xAxisSteps,
        yAxisLabels = prefs.yAxisLabels,
        modifier = modifier
    )
}