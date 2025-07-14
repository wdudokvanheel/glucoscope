package com.bitechular.glucoscope.data.datasource

import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import java.util.Date

sealed interface DataSourceState {
    object Loading : DataSourceState

    data class Data(
        val measurements: List<GlucoseMeasurement>,
        val currentValue: Double?,
        val lastUpdate: Date
    ) : DataSourceState

    data class Error(val cause: Throwable) : DataSourceState
}