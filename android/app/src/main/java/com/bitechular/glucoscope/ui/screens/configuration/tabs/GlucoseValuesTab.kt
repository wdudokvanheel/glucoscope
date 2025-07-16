package com.bitechular.glucoscope.ui.screens.configuration.tabs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.selection.TextSelectionColors
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.components.themed.ThemedTextbox
import com.bitechular.glucoscope.ui.graphics.ThemedGlucoseTargetGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView


@Composable
fun GlucoseValuesTab() {
    val prefs = PreferenceModel.current

    ConfigurationTabView(
        graphic = { ThemedGlucoseTargetGraphic() },
    ) {
        ThemedSection(innerPadding = 8.dp) {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                GlucoseValueRow(
                    label = "Low",
                    value = prefs.lowThreshold,
                    onValueChange = { prefs.lowThreshold = it },
                )

                HorizontalDivider(thickness = 1.dp, color = prefs.theme.text.copy(alpha = 0.5f))

                GlucoseValueRow(
                    label = "High",
                    value = prefs.highThreshold,
                    onValueChange = { prefs.highThreshold = it },
                )

                HorizontalDivider(thickness = 1.dp, color = prefs.theme.text.copy(alpha = 0.5f))

                GlucoseValueRow(
                    label = "Very high",
                    value = prefs.upperThreshold,
                    onValueChange = { prefs.upperThreshold = it },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GlucoseValueRow(
    label: String,
    value: Double,
    onValueChange: (Double) -> Unit,
) {
    val prefs = PreferenceModel.current

    val customSelectionColors = TextSelectionColors(
        handleColor = prefs.theme.accent, backgroundColor = prefs.theme.accent.copy(alpha = 0.4f)
    )

    Row(
        modifier = Modifier.fillMaxWidth(),
//            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label, color = prefs.theme.text
        )
        ThemedTextbox(
            value = value, onValueChange = { new ->
                new.toDoubleOrNull()?.let(onValueChange)
            }, modifier = Modifier.width(64.dp)
        )
    }
}