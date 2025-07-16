package com.bitechular.glucoscope.ui.screens.configuration.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.ui.components.OrientationAdaptiveView

@Composable
fun ConfigurationTabView(
    graphic: @Composable () -> Unit,
    content: @Composable () -> Unit
) {
    OrientationAdaptiveView(
        portrait = {
            Column(
                modifier = Modifier
                    .fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                graphic()
                content()
            }
        },
        landscape = {
            Row(
                modifier = Modifier.fillMaxSize()
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .weight(1f),
                    contentAlignment = Alignment.Center

                ) {
                    graphic()
                }
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .weight(2f),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    content()
                }
            }
        }
    )
}