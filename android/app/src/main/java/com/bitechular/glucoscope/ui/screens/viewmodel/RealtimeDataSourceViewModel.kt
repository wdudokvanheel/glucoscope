package com.bitechular.glucoscope.ui.screens.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bitechular.glucoscope.data.datasource.RealtimeDataRepository
import com.bitechular.glucoscope.data.model.GlucoScopeRepositoryConfiguration
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.model.NightscoutRepositoryConfiguration
import com.bitechular.glucoscope.data.repository.GlucoScopeRepository
import com.bitechular.glucoscope.data.repository.NightscoutRepository
import com.bitechular.glucoscope.ui.components.DataSourceService
import dagger.hilt.android.lifecycle.HiltViewModel
import jakarta.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.util.Date
import kotlin.time.ExperimentalTime

@HiltViewModel
@OptIn(ExperimentalTime::class)
class RealtimeDataSourceViewModel @Inject constructor(
    private val repo: RealtimeDataRepository,
    private val dataService: DataSourceService

) : ViewModel() {

    data class UiState(
        val measurements: List<GlucoseMeasurement> = emptyList(),
        val currentValue: Double? = null,
        val lastUpdate: Date? = null
    )

    val uiState: StateFlow<UiState> = repo.measurements
        .map { list ->
            UiState(
                measurements = list,
                currentValue = list.lastOrNull()?.value,
                lastUpdate = Date()
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.Companion.WhileSubscribed(5_000),
            initialValue = UiState()
        )

    fun setHours(h: Int) {
        repo.hours.value = h
    }

    fun setWindow(w: Int) {
        repo.window.value = w
    }

    // TODO: Move to settings
    fun chooseGlucoscope(url: String, token: String?) {
        dataService.use(
            GlucoScopeRepository(GlucoScopeRepositoryConfiguration(url, token))
        )
    }

    fun chooseNightscout(url: String, token: String?) {
        dataService.use(
            NightscoutRepository(NightscoutRepositoryConfiguration(url, token))
        )
    }
}