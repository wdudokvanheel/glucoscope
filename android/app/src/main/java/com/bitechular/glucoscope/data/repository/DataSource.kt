package com.bitechular.glucoscope.data.repository

import com.bitechular.glucoscope.data.model.GlucoseMeasurement

interface DataSource {
    suspend fun getCurrentValue(): Double
    suspend fun getLatestEntries(hours: Int, window: Int): List<GlucoseMeasurement>
    suspend fun testConnection(): Boolean
}