package com.bitechular.glucoscope.data.datasource

import com.bitechular.glucoscope.data.model.DemoRepositoryConfiguration
import com.bitechular.glucoscope.data.model.GlucoScopeRepositoryConfiguration
import com.bitechular.glucoscope.data.model.NightscoutRepositoryConfiguration
import com.bitechular.glucoscope.data.model.RepositoryConfiguration
import com.bitechular.glucoscope.data.repository.DataSourceRepository
import com.bitechular.glucoscope.data.repository.DemoDataRepository
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

    suspend fun testConnection(configuration: RepositoryConfiguration): Boolean =
        toRepository(configuration).testConnection()

    fun toRepository(configuration: RepositoryConfiguration): DataSourceRepository =
        when (configuration) {
            is GlucoScopeRepositoryConfiguration ->
                GlucoScopeRepository(
                    configuration
                )

            is NightscoutRepositoryConfiguration ->
                NightscoutRepository(
                    configuration
                )

            is DemoRepositoryConfiguration ->
                DemoDataRepository()
        }


    fun setConfiguration(configuration: RepositoryConfiguration) {
        _datasource.value = toRepository(configuration)
    }
}