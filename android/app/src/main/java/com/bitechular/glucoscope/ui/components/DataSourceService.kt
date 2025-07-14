package com.bitechular.glucoscope.ui.components

import com.bitechular.glucoscope.data.repository.DataSourceRepository
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
}
