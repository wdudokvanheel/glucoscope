package com.bitechular.glucoscope.ui.screens.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bitechular.glucoscope.data.datasource.DataSourceState
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.components.indicator.Indicator
import com.bitechular.glucoscope.ui.screens.main.components.GraphOverlayMenu
import com.bitechular.glucoscope.ui.screens.viewmodel.RealtimeDataSourceViewModel
import java.util.Date

@Composable
fun MainScreen(
    datasource: RealtimeDataSourceViewModel = hiltViewModel()
) {
    when (val state = datasource.dataSourceState.collectAsStateWithLifecycle().value) {
        DataSourceState.Loading -> LoadingScreen()
        is DataSourceState.Error -> {
            IndicatorAndGraph()
        }

        is DataSourceState.Data -> {
            IndicatorAndGraph(state.measurements, state.currentValue, state.lastUpdate)
        }
    }
}

@Composable
private fun IndicatorAndGraph(
    measurements: List<GlucoseMeasurement> = emptyList(),
    currentValue: Double? = null,
    lastUpdate: Date? = null,
) {
    val prefs = PreferenceModel.current
    Scaffold(
        Modifier.fillMaxSize()
    ) { inner ->
        Box(
            Modifier
                .fillMaxSize()
                .background(prefs.theme.background)
        ) {
            GraphOverlayMenu(
                modifier = Modifier
                    .padding(inner),
                datasource = hiltViewModel()
            ) {
                Column(Modifier.fillMaxSize()) {
                    Indicator(currentValue, lastUpdate)
                    ThemedGraph(measurements)
                }
            }
        }
    }
}


@Composable
fun LoadingScreen() {
    val prefs = PreferenceModel.current

    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        CircularProgressIndicator(color = prefs.theme.accent)
    }
}