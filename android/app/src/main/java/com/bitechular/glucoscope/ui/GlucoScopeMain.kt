package com.bitechular.glucoscope.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.repository.DemoDataSource
import com.bitechular.glucoscope.preference.GlucoScopePreferences
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.screens.PrefTest


@Composable
fun GlucoScopeApp() {
    val preferences: GlucoScopePreferences = hiltViewModel()
    val dataSource = DemoDataSource()

    val measurements by produceState(initialValue = emptyList<GlucoseMeasurement>(), key1 = Unit) {
        value = dataSource.getLatestEntries(9, 5)
    }

    CompositionLocalProvider(PreferenceModel provides preferences) {
        Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
            Column(Modifier.padding(innerPadding)) {
                PrefTest()
                ThemedGraph(measurements, Modifier.fillMaxSize())
            }
        }
    }
}