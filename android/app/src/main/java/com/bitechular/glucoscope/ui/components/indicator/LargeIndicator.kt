package com.bitechular.glucoscope.ui.components.indicator

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.bitechular.glucoscope.ui.screens.AppNavigator
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun LargeIndicator(currentValue: Double?, lastUpdate: Date? = null) {
    val prefs = PreferenceModel.current
    val navigator = AppNavigator.current

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
            .fillMaxWidth()
            .fillMaxHeight(0.33f)
            .padding(bottom = 24.dp)
            .background(
                color = background,
                shape = RoundedCornerShape(8.dp)
            )
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
        ) {
            Text(
                text = currentValue
                    ?.let { String.format(Locale.getDefault(), "%.1f", it) }
                    ?: "??",
                fontSize = 72.sp,
                fontWeight = FontWeight.Bold,
                color = prefs.theme.indicatorLabel,
                modifier = Modifier.align(Alignment.Center)
            )

            SettingsButton(
                modifier = Modifier.align(Alignment.TopEnd),
                color = prefs.theme.indicatorIcon
            )

            lastUpdate?.let { date ->
                val formatted = SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)
                Text(
                    text = "Last updated $formatted",
                    fontSize = 12.sp,
                    color = prefs.theme.indicatorLabel.copy(alpha = 0.75f),
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(8.dp)
                )
            }
        }
    }
}