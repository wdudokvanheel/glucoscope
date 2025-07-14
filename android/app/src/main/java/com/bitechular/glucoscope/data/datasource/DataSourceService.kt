package com.bitechular.glucoscope.data.datasource

import com.bitechular.glucoscope.data.model.GlucoScopeRepositoryConfiguration
import com.bitechular.glucoscope.data.model.NightscoutRepositoryConfiguration
import com.bitechular.glucoscope.data.model.RepositoryConfiguration
import com.bitechular.glucoscope.data.repository.DataSourceRepository
import com.bitechular.glucoscope.data.repository.GlucoScopeRepository
import com.bitechular.glucoscope.data.repository.NightscoutRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class DataSourceService {
    private val _datasource = MutableStateFlow<DataSourceRepository?>(null)
    val datasource: StateFlow<DataSourceRepository?> = _datasource

    fun use(source: DataSourceRepository) {
        _datasource.value = source
    }

    fun clear() {
        _datasource.value = null
    }

    fun setConfiguration(configuration: RepositoryConfiguration) {
        when (configuration) {
            is GlucoScopeRepositoryConfiguration -> _datasource.value =
                GlucoScopeRepository(
                    configuration
                )

            is NightscoutRepositoryConfiguration -> _datasource.value =
                NightscoutRepository(
                    configuration
                )
        }
    }
}