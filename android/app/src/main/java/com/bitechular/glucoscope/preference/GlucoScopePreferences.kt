package com.bitechular.glucoscope.preference

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import jakarta.inject.Inject

@HiltViewModel
class GlucoScopePreferences @Inject constructor() : ViewModel() {
    var username by mutableStateOf("Lumi")
    var theme by mutableStateOf(GlucoScopeTheme())
    var graphMin by mutableDoubleStateOf(2.5)
    var graphMax by mutableDoubleStateOf(20.0)
    var lowThreshold by mutableDoubleStateOf(3.0)
    var highThreshold by mutableDoubleStateOf(7.0)
    var upperThreshold by mutableDoubleStateOf(10.0)
    var xAxisSteps by mutableIntStateOf(2)
    var yAxisLabels by mutableStateOf(listOf<Double>(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0))
}

class GlucoScopeTheme() {
    var background by mutableStateOf(Color(0xFF000000))
    var upperColor by mutableStateOf(Color(0xFFFF006E))
    var lowColor by mutableStateOf(Color(0xFFFF006E))
    var inRangeColor by mutableStateOf(Color(0xFF00C853))
    var highColor by mutableStateOf(Color(0xFFFFD600))
    var axisLegendColor by mutableStateOf(Color(0xFF999999))
    var axisLinesColor by mutableStateOf(Color(0xFF999999))
}