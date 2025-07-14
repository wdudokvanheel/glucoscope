package com.bitechular.glucoscope.data.datasource

import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.ui.components.DataSourceService
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.shareIn

@OptIn(ExperimentalCoroutinesApi::class)
class RealtimeDataRepository(
    private val dataSourceService: DataSourceService,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO
) {

    val hours = MutableStateFlow(12)
    val window = MutableStateFlow(5)

    val measurements: Flow<List<GlucoseMeasurement>> =
        combine(
            dataSourceService.datasource,
            hours,
            window
        ) { ds, h, w -> Triple(ds, h, w) }
            .filter { it.first != null } // wait for a datasource
            .distinctUntilChanged() // only react on real changes
            .flatMapLatest { (ds, h, w) ->
                tickerFlow(5_000) // emits Unit every 5 s
                    .mapLatest { // restart on every tick
                        ds!!.getLatestEntries(h, w)
                    }
            }
            .flowOn(dispatcher) // network & JSON off main
            .shareIn(
                scope = CoroutineScope(SupervisorJob() + dispatcher),
                started = SharingStarted.Companion.WhileSubscribed(5_000),
                replay = 1
            )

    private fun tickerFlow(periodMillis: Long) = flow {
        while (true) {
            emit(Unit)
            delay(periodMillis)
        }
    }
}