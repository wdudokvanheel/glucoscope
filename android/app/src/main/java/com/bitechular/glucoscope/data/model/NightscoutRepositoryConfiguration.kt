package com.bitechular.glucoscope.data.model

import kotlinx.serialization.Serializable

@Serializable
data class NightscoutRepositoryConfiguration(
    val url: String,
    val apiToken: String? = null
) : RepositoryConfiguration
