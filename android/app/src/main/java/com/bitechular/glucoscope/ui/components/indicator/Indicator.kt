package com.bitechular.glucoscope.ui.components.indicator

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.AppNavigator
import com.bitechular.glucoscope.ui.screens.Screen
import java.util.Date
import java.util.Locale

@Composable
fun Indicator(currentValue: Double?, lastUpdate: Date? = null) {
    val prefs = PreferenceModel.current
    val navigator = AppNavigator.current

    val background = currentValue?.let {
        valueToColor(
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
            .background(
                color = background,
                shape = RoundedCornerShape(16.dp)
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

            IconButton(
                onClick = {
                    navigator.navigate(Screen.Config.route)
                },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Menu,
                    contentDescription = "Menu",
                    tint = prefs.theme.indicatorIcon
                )
            }

            Text(
                text = "Last update: 15:00",
                fontSize = 12.sp,
                color = Color.Black,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
            )
        }
    }
}