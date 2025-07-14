package com.bitechular.glucoscope.ui.screens.configuration.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.GlucoScopeTheme

@Composable
fun ThemeSwatch(
    theme: GlucoScopeTheme,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .height(24.dp)
            .aspectRatio(2.5f)
            .clip(RoundedCornerShape(4.dp))
            .border(
                width = 3.dp,
                color = theme.background,
                shape = RoundedCornerShape(4.dp)
            )
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.spacedBy(0.dp)
        ) {
            listOf(
                theme.accent,
                theme.highColor,
                theme.upperColor,
                theme.inRangeColor
            ).forEach { color ->
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .background(color)
                )
            }
        }
    }
}
