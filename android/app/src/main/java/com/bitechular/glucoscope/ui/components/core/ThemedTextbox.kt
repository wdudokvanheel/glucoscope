package com.bitechular.glucoscope.ui.components.core

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.LocalTextSelectionColors
import androidx.compose.foundation.text.selection.TextSelectionColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun ThemedTextbox(
    value: Double,
    onValueChange: (Double) -> Unit,
    modifier: Modifier = Modifier
) {
    val prefs = PreferenceModel.current
    val textSelectionColors = TextSelectionColors(
        handleColor = prefs.theme.accent,
        backgroundColor = prefs.theme.accent.copy(alpha = 0.4f)
    )

    CompositionLocalProvider(
        LocalTextSelectionColors provides textSelectionColors
    ) {
        BasicTextField(
            value = value.toString(),
            onValueChange = { new ->
                new.toDoubleOrNull()?.let(onValueChange)
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            cursorBrush = SolidColor(prefs.theme.accent),
            modifier = modifier
                .background(
                    color = prefs.theme.background,
                    shape = RoundedCornerShape(8.dp)
                )
                .padding(8.dp),
            textStyle = TextStyle(
                color = prefs.theme.text,
                textAlign = TextAlign.End
            )
        )
    }
}