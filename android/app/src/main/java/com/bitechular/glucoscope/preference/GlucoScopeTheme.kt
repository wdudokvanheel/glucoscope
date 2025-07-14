package com.bitechular.glucoscope.preference

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

class GlucoScopeTheme() {
    var name by mutableStateOf("Default Theme")
    var variant by mutableStateOf("")
    var url by mutableStateOf("")
    var background by mutableStateOf(Color(0xFF000000))
    var surface by mutableStateOf(Color(0xFF1A1A1C))
    var text by mutableStateOf(Color(0xFFFFFFFF))
    var accent by mutableStateOf(Color(0xFF40C8E0))
    var inRangeColor by mutableStateOf(Color(0xFF00C853))
    var lowColor by mutableStateOf(Color(0xFFFF006E))
    var highColor by mutableStateOf(Color(0xFFFFD600))
    var upperColor by mutableStateOf(Color(0xFFFF006E))
    var indicatorIcon by mutableStateOf(Color(0xFF000000))
    var indicatorLabel by mutableStateOf(Color(0xFF000000))
    var axisXLegendColor by mutableStateOf(Color(0xFF555555))
    var axisYLegendColor by mutableStateOf(Color(0xFF555555))
    var axisXGridLineColor by mutableStateOf(Color(0xFF555555))
    var axisYGridLineColor by mutableStateOf(Color(0xFF555555))
}