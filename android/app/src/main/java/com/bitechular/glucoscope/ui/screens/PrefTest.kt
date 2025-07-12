package com.bitechular.glucoscope.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun PrefTest() {
    val prefs = PreferenceModel.current

    Column(
        Modifier
            .background(prefs.theme.background)
    ) {
        Text(
            "Hello " + prefs.username,
            modifier = Modifier.padding(16.dp)
        )

        Button(onClick = {
            prefs.username = "Zola"
            prefs.theme.lowColor = Color(0xFFFF00FF)
            prefs.theme.upperColor = Color(0xFFFF00FF)
            prefs.theme.highColor = Color(0xFFFF00FF)
            prefs.theme.inRangeColor = Color(0xFFFF00FF)
            prefs.theme.axisLinesColor = Color(0xFFFF00FF)
            prefs.theme.axisLegendColor = Color(0xFFFF00FF)
            prefs.yAxisLabels = listOf<Double>(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0)
            prefs.graphMin = 2.5
            prefs.graphMax = 15.0
            prefs.xAxisSteps = 1
        }) {
            Text("CLICK ME")
        }
    }
}

