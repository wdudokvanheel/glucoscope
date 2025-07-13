package com.bitechular.glucoscope.ui.screens.main

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.repository.DemoDataSource
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.components.indicator.Indicator

@Composable
fun MainScreen() {
    // TODO Move this to RealTimeDataService
    val dataSource = DemoDataSource()

    val measurements by produceState(initialValue = emptyList<GlucoseMeasurement>(), key1 = Unit) {
        value = dataSource.getLatestEntries(9, 5)
    }

    val currentValue: Double? by produceState(initialValue = null, key1 = Unit) {
        value = dataSource.getCurrentValue()
    }

    Column {
//                ReactivePrefTest()
        Indicator(currentValue)
        ThemedGraph(measurements, Modifier.fillMaxSize())
    }
}