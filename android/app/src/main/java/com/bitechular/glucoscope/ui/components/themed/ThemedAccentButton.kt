package com.bitechular.glucoscope.ui.components.themed

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun ThemedAccentButton(
    label: String,
    onClick: () -> Unit
) {
    val prefs = PreferenceModel.current

    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = prefs.theme.accent,
            contentColor = prefs.theme.text
        )
    ) {
        Text(
            text = label,
            fontSize = 18.sp
        )
    }
}
