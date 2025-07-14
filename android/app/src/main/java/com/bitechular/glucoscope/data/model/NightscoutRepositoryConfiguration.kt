package com.bitechular.glucoscope.data.model

data class NightscoutRepositoryConfiguration(
    val url: String,
    val apiToken: String? = null
)
