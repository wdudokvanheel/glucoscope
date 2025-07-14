package com.bitechular.glucoscope.preference

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bitechular.glucoscope.data.model.RepositoryConfiguration
import com.bitechular.glucoscope.preference.dto.GlucoScopePreferencesDto
import com.bitechular.glucoscope.preference.dto.ThemeDto
import com.bitechular.glucoscope.preference.dto.fromTheme
import com.bitechular.glucoscope.preference.dto.toTheme
import com.bitechular.glucoscope.ui.components.DataSourceService
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import jakarta.inject.Inject
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

@HiltViewModel
class GlucoScopePreferences @Inject constructor(
    @ApplicationContext context: Context,
    private val dataSourceService: DataSourceService
) : ViewModel() {
    var repositoryConfiguration: RepositoryConfiguration? by mutableStateOf(null)
    var theme by mutableStateOf(GlucoScopeTheme())

    var graphMin by mutableDoubleStateOf(2.5)
    var graphMax by mutableDoubleStateOf(20.0)
    var lowThreshold by mutableDoubleStateOf(4.0)
    var highThreshold by mutableDoubleStateOf(7.0)
    var upperThreshold by mutableDoubleStateOf(10.0)
    var xAxisSteps by mutableIntStateOf(2)
    var yAxisLabels by mutableStateOf(listOf<Double>(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0))

    private val dataStore = context.settingsDataStore

    init {
        viewModelScope.launch {
            dataStore.data.firstOrNull()?.let(::applySettings)
        }

        viewModelScope.launch {
            snapshotFlow { toSettings() }
                .distinctUntilChanged()
                .drop(1)
                .collect { new ->
                    dataStore.updateData { new }
                }
        }
    }

    fun setRepositoryConfiguration(
        configuration: RepositoryConfiguration
    ) = viewModelScope.launch {
        dataStore.updateData { dto ->
            dto.copy(
                repositoryConfiguration =
                    configuration
            )
        }
        dataSourceService.setConfiguration(configuration)
        repositoryConfiguration = configuration
    }

    private fun applySettings(dto: GlucoScopePreferencesDto) {
        theme = dto.theme.toTheme()
        repositoryConfiguration = dto.repositoryConfiguration
        graphMin = dto.graphMin
        graphMax = dto.graphMax
        lowThreshold = dto.lowThreshold
        highThreshold = dto.highThreshold
        upperThreshold = dto.upperThreshold
        xAxisSteps = dto.xAxisSteps
        yAxisLabels = dto.yAxisLabels

        // Update datasource service with configuration (if available)
        repositoryConfiguration?.let { setRepositoryConfiguration(it) }
    }

    private fun toSettings() = GlucoScopePreferencesDto(
        repositoryConfiguration = repositoryConfiguration,
        theme = ThemeDto.fromTheme(theme),
        graphMin = graphMin,
        graphMax = graphMax,
        lowThreshold = lowThreshold,
        highThreshold = highThreshold,
        upperThreshold = upperThreshold,
        xAxisSteps = xAxisSteps,
        yAxisLabels = yAxisLabels
    )
}
