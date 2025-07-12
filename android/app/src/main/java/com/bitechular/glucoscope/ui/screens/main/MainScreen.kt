package com.bitechular.glucoscope.ui.screens.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.repository.DemoDataSource
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.screens.tests.ReactivePrefTest


@Composable
fun GlucoScopeApp() {
    val dataSource = DemoDataSource()

    val measurements by produceState(initialValue = emptyList<GlucoseMeasurement>(), key1 = Unit) {
        value = dataSource.getLatestEntries(9, 5)
    }
    val prefs = PreferenceModel.current

    Column(
        Modifier.background(prefs.theme.background)
    ) {
        Scaffold(
            modifier = Modifier
                .fillMaxSize()
        ) { innerPadding ->
            Column(
                Modifier
                    .background(prefs.theme.background)
                    .padding(innerPadding)
            ) {
                ReactivePrefTest()
                ThemedGraph(measurements, Modifier.fillMaxSize())
            }
        }
    }
}