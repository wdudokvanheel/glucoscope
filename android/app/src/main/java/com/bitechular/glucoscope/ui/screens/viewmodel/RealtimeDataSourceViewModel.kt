package com.bitechular.glucoscope.ui.screens.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bitechular.glucoscope.data.datasource.DataSourceService
import com.bitechular.glucoscope.data.datasource.DataSourceState
import com.bitechular.glucoscope.data.datasource.RealtimeDataRepository
import com.bitechular.glucoscope.ui.screens.main.model.GraphRange
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
    val dataSourceState: StateFlow<DataSourceState> = repo.measurements
        .map { result ->
            result.fold(
                onSuccess = { list ->
                    DataSourceState.Data(
                        measurements = list,
                        currentValue = list.lastOrNull()?.value,
                        lastUpdate = Date()
                    )
                },
                onFailure = { err -> DataSourceState.Error(err) }
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = DataSourceState.Loading
        )

    fun setRange(range: GraphRange){
        repo.hours.value = range.hours
        repo.window.value = range.window
    }
}