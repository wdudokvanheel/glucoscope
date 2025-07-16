package com.bitechular.glucoscope.ui.components

import android.annotation.SuppressLint
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.min

@Composable
@SuppressLint("UnusedBoxWithConstraintsScope")
fun SquareContainer(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    BoxWithConstraints(modifier) {
        val side: Dp = min(maxWidth, maxHeight)
        Box(
            modifier = Modifier.size(side),
            contentAlignment = Alignment.Center,
        ) {
            content()
        }
    }
}