package com.bitechular.glucoscope.ui.components.themed

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel

@Composable
fun ThemedSection(
    modifier: Modifier = Modifier,
    innerPadding: Boolean = true,
    content: @Composable ColumnScope.() -> Unit
) {
    val prefs = PreferenceModel.current

    Surface(
        color = prefs.theme.surface,
        shape = RoundedCornerShape(12.dp),
        modifier = modifier
            .fillMaxWidth()
            .padding(16.dp),
    ) {
        Column(
            modifier = Modifier
                .padding(if (innerPadding) 16.dp else 0.dp),
            content = content
        )
    }

}