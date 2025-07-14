package com.bitechular.glucoscope.data.model

import kotlinx.serialization.Serializable

@Serializable
data class GlucoScopeRepositoryConfiguration(
    val url: String,
    val apiToken: String?
) : RepositoryConfiguration