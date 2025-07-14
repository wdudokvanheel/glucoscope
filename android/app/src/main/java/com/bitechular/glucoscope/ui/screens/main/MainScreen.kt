package com.bitechular.glucoscope.ui.screens.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.components.indicator.Indicator
import com.bitechular.glucoscope.ui.screens.viewmodel.RealtimeDataSourceViewModel

@Composable
fun MainScreen(
    datasource: RealtimeDataSourceViewModel = hiltViewModel()
) {
    val prefs = PreferenceModel.current
    val rtDataSource by datasource.uiState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = Modifier
            .fillMaxSize()
    ) { innerPadding ->
        Column(
            Modifier
                .background(prefs.theme.background)
                .padding(innerPadding)
                .fillMaxSize()
        ) {
            Indicator(rtDataSource.currentValue, null)
            ThemedGraph(rtDataSource.measurements, Modifier.fillMaxSize())
        }
    }
}