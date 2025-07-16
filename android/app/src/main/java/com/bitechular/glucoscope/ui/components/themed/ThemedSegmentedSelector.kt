package com.bitechular.glucoscope.ui.components.themed

import android.annotation.SuppressLint
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.extensions.atElevation
import com.bitechular.glucoscope.preference.PreferenceModel

@SuppressLint("UnusedBoxWithConstraintsScope")
@Composable
fun ThemedSegmentedSelector(
    options: List<String>,
    selected: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    tonalElevation: Dp = 3.dp,
    animationMillis: Int = 220
) {
    val prefs          = PreferenceModel.current
    val surface        = prefs.theme.surface
    val containerColor = surface.atElevation(tonalElevation)

    Surface(
        color          = containerColor,
        tonalElevation = tonalElevation,
        shape          = RoundedCornerShape(8.dp),
        modifier       = modifier
    ) {
        BoxWithConstraints(Modifier.height(32.dp)) {
            val density = LocalDensity.current
            val segmentWidthDp = remember(maxWidth) {
                with(density) { (maxWidth / options.size) }
            }

            val targetX = segmentWidthDp * selected
            val animX by animateDpAsState(
                targetValue = targetX,
                animationSpec = tween(durationMillis = animationMillis, easing = FastOutSlowInEasing)
            )

            Box(
                modifier = Modifier
                    .offset(x = animX)
                    .width(segmentWidthDp)
                    .fillMaxHeight()
                    .padding(2.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(prefs.theme.accent)
            )

            Row(Modifier.fillMaxSize()) {
                options.forEachIndexed { index, label ->
                    val isSelected   = index == selected
                    val textColor    = if (isSelected) prefs.theme.indicatorLabel else prefs.theme.text
                    val interaction  = remember { MutableInteractionSource() }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .padding(2.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .clickable(
                                interactionSource = interaction,
                                indication = null
                            ) { onSelect(index) },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(label, color = textColor)
                    }
                }
            }
        }
    }
}
