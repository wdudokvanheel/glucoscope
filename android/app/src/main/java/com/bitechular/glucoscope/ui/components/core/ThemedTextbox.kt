package com.bitechular.glucoscope.ui.components.core

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.LocalTextSelectionColors
import androidx.compose.foundation.text.selection.TextSelectionColors
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun <T> ThemedTextbox(
    value: T,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    textAlign: TextAlign = TextAlign.End,
    isPassword: Boolean = false
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
            onValueChange = onValueChange,
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            cursorBrush = SolidColor(prefs.theme.accent),
            visualTransformation = if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
            textStyle = TextStyle(
                color = prefs.theme.text,
                textAlign = textAlign
            ),
            modifier = modifier,
            decorationBox = { innerTextField ->
                Box(
                    modifier = Modifier
                        .background(
                            color = prefs.theme.background,
                            shape = RoundedCornerShape(8.dp)
                        )
                        .padding(8.dp)
                        .fillMaxWidth()
                ) {
                    if (value.toString().isEmpty()) {
                        Text(
                            text = placeholder,
                            style = TextStyle(
                                color = prefs.theme.text.copy(alpha = 0.5f),
                                textAlign = textAlign
                            ),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    innerTextField()
                }
            }
        )
    }
}
