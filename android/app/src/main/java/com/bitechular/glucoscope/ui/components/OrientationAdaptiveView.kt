package com.bitechular.glucoscope.ui.components

import android.annotation.SuppressLint
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
// Don't care about what the API thinks the orientation is, only if the height exceeds the width
@SuppressLint("UnusedBoxWithConstraintsScope")
fun OrientationAdaptiveView(
    modifier: Modifier = Modifier,
    portrait: @Composable () -> Unit,
    landscape: @Composable () -> Unit
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        if (maxHeight > maxWidth) {
            portrait()
        } else {
            landscape()
        }
    }
}
