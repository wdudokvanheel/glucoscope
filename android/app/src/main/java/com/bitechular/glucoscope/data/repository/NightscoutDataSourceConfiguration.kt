package com.bitechular.glucoscope.data.repository

data class NightscoutDataSourceConfiguration(
    val url: String,
    val apiToken: String? = null
)
