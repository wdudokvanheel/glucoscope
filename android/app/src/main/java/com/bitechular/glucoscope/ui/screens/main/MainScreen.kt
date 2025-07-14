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
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.components.indicator.Indicator
import com.bitechular.glucoscope.ui.screens.viewmodel.RealtimeDataSourceViewModel

@Composable
fun MainScreen(
    datasource: RealtimeDataSourceViewModel = hiltViewModel()
) {
    val prefs = PreferenceModel.current

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
            when (val state = datasource.dataSourceState.collectAsStateWithLifecycle().value) {
                DataSourceState.Loading -> LoadingScreen()
                is DataSourceState.Error -> {
                    Indicator(null)
                    ThemedGraph(emptyList())
                }

                is DataSourceState.Data -> {
                    Indicator(state.currentValue, lastUpdate = state.lastUpdate)
                    ThemedGraph(state.measurements)
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