package com.bitechular.glucoscope.data

interface DataSource {
    suspend fun getLatestEntries(hours: Int, window: Int): List<GlucoseMeasurement>
    suspend fun testConnection(): Boolean
}