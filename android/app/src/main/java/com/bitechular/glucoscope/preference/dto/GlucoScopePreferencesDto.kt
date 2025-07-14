package com.bitechular.glucoscope.preference.dto

import com.bitechular.glucoscope.data.model.RepositoryConfiguration
import kotlinx.serialization.Serializable

@Serializable
data class GlucoScopePreferencesDto(
    val repositoryConfiguration: RepositoryConfiguration? = null,
    val theme: ThemeDto = ThemeDto(),

    val graphMin: Double = 2.5,
    val graphMax: Double = 20.0,
    val lowThreshold: Double = 4.0,
    val highThreshold: Double = 7.0,
    val upperThreshold: Double = 10.0,
    val xAxisSteps: Int = 2,
    val yAxisLabels: List<Double> = listOf(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0),
)