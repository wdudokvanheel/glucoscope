package com.bitechular.glucoscope.preference

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

class GlucoScopeTheme() {
    var name by mutableStateOf("Default Theme")
    var background by mutableStateOf(Color(0xFF000000))
    var upperColor by mutableStateOf(Color(0xFFFF006E))
    var lowColor by mutableStateOf(Color(0xFFFF006E))
    var inRangeColor by mutableStateOf(Color(0xFF00C853))
    var highColor by mutableStateOf(Color(0xFFFFD600))
    var axisLegendColor by mutableStateOf(Color(0xFF555555))
    var axisLinesColor by mutableStateOf(Color(0xFF555555))
}