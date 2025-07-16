package com.bitechular.glucoscope.ui.screens.main.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.hilt.navigation.compose.hiltViewModel
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.core.ThemedSegmentedSelector
import com.bitechular.glucoscope.ui.screens.main.model.DefaultGraphRanges
import com.bitechular.glucoscope.ui.screens.main.model.GraphRange
import com.bitechular.glucoscope.ui.screens.viewmodel.RealtimeDataSourceViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun GraphOverlayMenu(
    modifier: Modifier = Modifier,
    ranges: List<GraphRange> = DefaultGraphRanges,
    initialSelected: Int = 3,
    hideDelayMillis: Long = 3_000,
    datasource: RealtimeDataSourceViewModel = hiltViewModel(),
    content: @Composable () -> Unit
) {
    val prefs = PreferenceModel.current

    var showOverlay by remember { mutableStateOf(false) }
    var hideJob by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()

    var selectedIdx by remember { mutableIntStateOf(initialSelected) }

    fun revealOverlay() {
        showOverlay = true
        hideJob?.cancel()
        hideJob = scope.launch {
            delay(hideDelayMillis)
            showOverlay = false
            hideJob = null
        }
    }

    Box(
        modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(onPress = {
                    revealOverlay()
                    tryAwaitRelease()
                })
            }
    ) {
        content()

        // Transparent layer catches outside touches to hide the overlay again
        AnimatedVisibility(
            visible = showOverlay,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.matchParentSize()
        ) {
            Box(
                Modifier.clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() }
                ) {
                    hideJob?.cancel()
                    showOverlay = false
                    hideJob = null
                }
            )
        }

        AnimatedVisibility(
            visible = showOverlay,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 8.dp)
                .zIndex(1f)
        ) {
            val labels = ranges.map { "${it.hours}h" }

            ThemedSegmentedSelector(
                tonalElevation = 1.dp,
                options = labels,
                selected = selectedIdx,
                onSelect = { idx ->
                    selectedIdx = idx
                    val range = ranges[idx]
                    prefs.setGraphRange(range)
                    datasource.setRange(range)
                    revealOverlay()
                }
            )
        }
    }
}