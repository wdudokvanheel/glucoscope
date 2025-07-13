package com.bitechular.glucoscope.ui.screens.configuration

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun ConfigurationScreen() {
    val prefs = PreferenceModel.current

    Text("CONFIGURATION", color = prefs.theme.text)
}