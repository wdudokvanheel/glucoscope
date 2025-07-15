package com.bitechular.glucoscope.ui.screens.main.model

class GraphRange(
    val hours: Int = 0,
    val window: Int = 0
)

val DefaultGraphRanges: List<GraphRange> = listOf(
    GraphRange(hours = 24, window = 10),
    GraphRange(hours = 12, window = 5),
    GraphRange(hours = 9, window = 5),
    GraphRange(hours = 6, window = 5),
    GraphRange(hours = 3, window = 1)
)
