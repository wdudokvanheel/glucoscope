package com.bitechular.glucoscope.ui.screens.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bitechular.glucoscope.data.datasource.DataSourceState
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.OrientationAdaptiveView
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.components.indicator.Indicator
import com.bitechular.glucoscope.ui.components.indicator.SettingsButton
import com.bitechular.glucoscope.ui.components.indicator.SmallIndicator
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

    Box(
        Modifier
            .background(prefs.theme.background)
            .fillMaxSize()
            .padding(WindowInsets.safeDrawing.asPaddingValues())
    ) {
        OrientationAdaptiveView(
            portrait = {
                Column(Modifier.fillMaxSize()) {
                    Indicator(currentValue, lastUpdate)
                    GraphOverlayMenu {
                        ThemedGraph(measurements)
                    }
                }
            },
            landscape = {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                ) {
                    GraphOverlayMenu {
                        ThemedGraph(measurements)
                    }
                    SmallIndicator(currentValue)

                    SettingsButton(
                        modifier = Modifier.align(Alignment.TopEnd),
                        color = prefs.theme.accent,
                    )
                }
            })
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