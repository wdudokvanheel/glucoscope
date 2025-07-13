package com.bitechular.glucoscope.ui.screens.configuration.features

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.core.ThemedSection
import com.bitechular.glucoscope.ui.graphics.ThemedGlucoseTargetGraphic


@Composable
fun GlucoseValuesScreen() {
    val prefs = PreferenceModel.current

    Column(
        modifier = Modifier
            .fillMaxSize(),
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        ThemedGlucoseTargetGraphic()
        ThemedSection {
            Text("Low", color = prefs.theme.text)
        }
    }
}

