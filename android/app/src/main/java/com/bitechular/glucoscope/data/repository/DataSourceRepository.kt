package com.bitechular.glucoscope.data.repository

import com.bitechular.glucoscope.data.model.GlucoseMeasurement

interface DataSourceRepository {
    suspend fun getLatestEntries(hours: Int, window: Int): List<GlucoseMeasurement>
    suspend fun testConnection(): Boolean
}