package com.bitechular.glucoscope.ui.components.indicator

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.preference.PreferenceModel
import java.util.Locale

@Composable
fun SmallIndicator(currentValue: Double?) {
    val prefs = PreferenceModel.current
    val background = currentValue?.let {
        glucoseValueToColor(
            currentValue,
            graphMin = prefs.graphMin,
            graphMax = prefs.graphMax,
            lowThreshold = prefs.lowThreshold,
            highThreshold = prefs.highThreshold,
            upperThreshold = prefs.upperThreshold,
            lowColor = prefs.theme.lowColor,
            inRangeColor = prefs.theme.inRangeColor,
            highColor = prefs.theme.highColor,
            upperColor = prefs.theme.upperColor,
        )
    } ?: prefs.theme.inRangeColor
    Column(
        modifier = Modifier
            .padding(8.dp)
            .background(
                color = background,
                shape = RoundedCornerShape(8.dp)
            )
    ) {
        Box(
            Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        ) {
            Text(
                text = currentValue
                    ?.let { String.format(Locale.getDefault(), "%.1f", it) }
                    ?: "??",
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = prefs.theme.indicatorLabel,
                modifier = Modifier.align(Alignment.Center)
            )
        }
    }
}