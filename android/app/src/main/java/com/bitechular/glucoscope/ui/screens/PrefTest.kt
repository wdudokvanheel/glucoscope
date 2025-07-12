package com.bitechular.glucoscope.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun PrefTest(modifier: Modifier) {
    val prefs = PreferenceModel.current

    Column(
        modifier = modifier
            .background(prefs.theme.background)
    ) {
        Text(
            "Hello " + prefs.username,
            modifier = Modifier.padding(16.dp)
        )

        Button(onClick = {
            prefs.username = "Zola"
            prefs.theme.background = Color(0xFF006600)
        }) {
            Text("CLICK ME")
        }
    }
}

