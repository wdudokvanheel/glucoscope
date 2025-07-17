package com.bitechular.glucoscope.data.model

import kotlinx.serialization.Serializable

@Serializable
data class DemoRepositoryConfiguration(
    // Dummy value
    val demo: Boolean = true
) : RepositoryConfiguration
